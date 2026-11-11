#!/usr/bin/env bash
# Launch the TerraRepair-Bench full run on Fargate with AUTO-RESTART.
#
# Re-launches the task whenever it stops UNTIL the completion marker
# (run_complete.json) appears in S3. Because the container resumes from S3 and
# skips completed games, and exits 0 as a no-op once complete, this loop:
#   - recovers from a crashed/stopped task without losing work, and
#   - terminates cleanly when the run is finished.
#
# This is the "re-run loop" restart option from CONTAINER.md (no AWS Batch
# needed). Run AFTER deploy/setup.sh. This STARTS the ~$30 Bedrock experiment.
#
# Usage: bash deploy/run.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "${SCRIPT_DIR}/deploy.env" ]]; then
  echo "ERROR: ${SCRIPT_DIR}/deploy.env not found. Run deploy/setup.sh first." >&2
  exit 1
fi
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/deploy.env"

MARKER="s3://${RESULTS_BUCKET}/${S3_PREFIX}/run_complete.json"
MAX_LAUNCHES="${MAX_LAUNCHES:-10}"   # safety cap on restarts

echo "== TerraRepair-Bench run (auto-restart) =="
echo "  cluster=${CLUSTER} taskdef=${TASK_FAMILY} region=${REGION}"
echo "  completion marker: ${MARKER}"

launches=0
while true; do
  if aws s3 ls "${MARKER}" --region "${REGION}" >/dev/null 2>&1; then
    echo "[run] completion marker present -> run finished."
    break
  fi
  if (( launches >= MAX_LAUNCHES )); then
    echo "[run] hit MAX_LAUNCHES=${MAX_LAUNCHES} without completion; stopping. Investigate metrics.json / logs." >&2
    exit 1
  fi
  launches=$((launches + 1))
  echo "[run] launch #${launches}: run-task"
  TASK_ARN="$(aws ecs run-task \
    --cluster "${CLUSTER}" \
    --launch-type FARGATE \
    --task-definition "${TASK_FAMILY}" \
    --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_ID}],securityGroups=[${SG_ID}],assignPublicIp=ENABLED}" \
    --region "${REGION}" \
    --query 'tasks[0].taskArn' --output text)"
  if [[ -z "${TASK_ARN}" || "${TASK_ARN}" == "None" ]]; then
    echo "[run] run-task did not return a task ARN; retrying in 30s" >&2
    sleep 30
    continue
  fi
  echo "[run] task ${TASK_ARN} started; waiting for it to stop..."
  aws ecs wait tasks-stopped --cluster "${CLUSTER}" --tasks "${TASK_ARN}" --region "${REGION}" || true
  # Report why it stopped (exit code / reason) for troubleshooting.
  aws ecs describe-tasks --cluster "${CLUSTER}" --tasks "${TASK_ARN}" --region "${REGION}" \
    --query 'tasks[0].{stopCode:stopCode,stoppedReason:stoppedReason,containers:containers[0].{exitCode:exitCode,reason:reason}}' \
    --output json || true
  echo "[run] task stopped; re-checking completion marker..."
done

echo
echo "== run complete =="
echo "Fetch results:"
echo "  aws s3 sync s3://${RESULTS_BUCKET}/${S3_PREFIX} experiments/results/full_refresh_2026-09"
echo "Then analyze:"
echo "  python3 scripts/analyze_corrected.py --games experiments/results/full_refresh_2026-09/games --out experiments/results/full_refresh_2026-09"
echo
echo "Monitoring during a run (in another shell):"
echo "  aws s3 cp s3://${RESULTS_BUCKET}/${S3_PREFIX}/metrics.json - | python3 -m json.tool"
echo "  aws s3 ls s3://${RESULTS_BUCKET}/${S3_PREFIX}/games/ | wc -l"
