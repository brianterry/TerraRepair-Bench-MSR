#!/usr/bin/env bash
# Backfill the InvokeTimeout gaps left by the main sharded run.
#
# The main run finished with 13,647 / 13,824 games; 177 cells were skipped on
# Bedrock InvokeTimeout (grok 163, claude-sonnet-5 2, deepseek-v3-2 12). This
# relaunches ONLY the shards that have gaps. The runner is resume-safe
# (if gf.exists(): return "resumed"), so each task recomputes ONLY its missing
# games and skips the thousands already present.
#
# Two changes vs the main launch, to actually close the gaps rather than hit the
# same wall:
#   - BEDROCK_INVOKE_TIMEOUT=900  (up from the 420s default; grok at 40K tokens
#     under load exceeded 420s). Needs the rebuilt image that reads this env.
#   - grok shard runs at concurrency 4 (down from 8) to cut per-call contention,
#     the dominant driver of grok's timeouts. The cheap/fast shard stays at 8.
#
# The two already-complete shards (deepseek-r1+claude-sonnet-4-5, and kimi which
# is 100%) are intentionally NOT relaunched; kimi rides along in the
# deepseek-v3-2 shard and its present games are skipped.
#
# Markers must be deleted BEFORE running this (otherwise each shard no-ops on its
# existing ablation_complete_<shard>.json). On clean exit each relaunched shard
# rewrites its marker.
#
# Usage: bash deploy/run_ablation_backfill.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ablation.env"

INVOKE_TIMEOUT="${BEDROCK_INVOKE_TIMEOUT:-900}"
PREFIX="s3://${RESULTS_BUCKET}/${S3_PREFIX}"

# shard spec: "MODELS|CONCURRENCY" — only the gap shards.
SHARDS=(
  "grok-4-6|4"
  "claude-sonnet-5|8"
  "kimi-k2-5,deepseek-v3-2|8"
)

echo "== TerraRepair ABLATION backfill launch =="
echo "  account=${ACCOUNT_ID} cluster=${CLUSTER} family=${TASK_FAMILY}"
echo "  results=${PREFIX}  invoke_timeout=${INVOKE_TIMEOUT}s  shards=${#SHARDS[@]}"
echo

# Pre-flight: refuse to double-launch.
RUNNING="$(aws ecs list-tasks --cluster "${CLUSTER}" --family "${TASK_FAMILY}" \
  --desired-status RUNNING --region "${REGION}" --query 'taskArns' --output text 2>/dev/null)"
if [[ -n "${RUNNING}" && "${RUNNING}" != "None" ]]; then
  echo "ERROR: ablation task(s) already RUNNING for ${TASK_FAMILY}:" >&2
  echo "  ${RUNNING}" >&2
  echo "Stop them first or let them finish. Not launching." >&2
  exit 1
fi

# Pre-flight: refuse if markers still present (would make shards no-op).
MARKERS="$(aws s3 ls "${PREFIX}/" --region "${REGION}" 2>/dev/null | grep -c 'ablation_complete_' || true)"
if [[ "${MARKERS}" -gt 0 ]]; then
  echo "ERROR: ${MARKERS} completion marker(s) still present; delete them first" >&2
  echo "  (shards no-op while their ablation_complete_<shard>.json exists)." >&2
  exit 1
fi

for SPEC in "${SHARDS[@]}"; do
  MODELS="${SPEC%%|*}"
  CONC="${SPEC##*|}"
  OVERRIDES="$(python3 -c "
import json,sys
print(json.dumps({'containerOverrides':[{'name':'runner','environment':[
  {'name':'MODELS','value':sys.argv[1]},
  {'name':'CONCURRENCY','value':sys.argv[2]},
  {'name':'BEDROCK_INVOKE_TIMEOUT','value':sys.argv[3]},
]}]}))" "${MODELS}" "${CONC}" "${INVOKE_TIMEOUT}")"
  ARN="$(aws ecs run-task \
    --cluster "${CLUSTER}" --launch-type FARGATE --task-definition "${TASK_FAMILY}" \
    --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_ID}],securityGroups=[${SG_ID}],assignPublicIp=ENABLED}" \
    --overrides "${OVERRIDES}" --region "${REGION}" \
    --query 'tasks[0].taskArn' --output text 2>&1)"
  echo "[backfill] MODELS=${MODELS} conc=${CONC}"
  echo "           task=${ARN}"
done

echo
echo "== launched ${#SHARDS[@]} backfill shard tasks =="
echo "Each recomputes ONLY its missing games (resume-safe). Done when all its"
echo "markers reappear and status_ablation.sh shows the per-model counts at 2304."
