#!/usr/bin/env bash
# Launch the retrieval ablation as 4 MODEL-SHARDED Fargate tasks in parallel.
#
# Each shard runs a disjoint set of models over the SAME 192 targets x 4 arms x
# 3 draws, writing to the SAME S3 games/ prefix. Because game filenames include
# the model id, shards write DISJOINT files -> no collision, no distributed lock
# needed. Each shard owns a per-shard completion marker
# (ablation_complete_<shard>.json), so one shard finishing never makes another
# no-op on restart. The run is DONE when all 4 shard markers exist.
#
# Shards (slow models get their own container so wall-clock ~= slowest shard):
#   1: grok-4-6                         (slowest, verbose reasoning @ 40K)
#   2: claude-sonnet-5                  (slow)
#   3: deepseek-r1, claude-sonnet-4-5   (medium)
#   4: kimi-k2-5, deepseek-v3-2         (fast, cheap)
#
# Concurrency 8 per shard. Quotas on this account support it (sonnet-5 10k RPM,
# nova 500, etc.); deepseek-r1's 200k TPM is the tightest and is self-limited by
# its share of one shard at conc 8. This STARTS the ~$1,155 billable run.
#
# Usage: bash deploy/run_ablation_sharded.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ablation.env"

CONCURRENCY="${CONCURRENCY:-8}"
PREFIX="s3://${RESULTS_BUCKET}/${S3_PREFIX}"

SHARDS=(
  "grok-4-6"
  "claude-sonnet-5"
  "deepseek-r1,claude-sonnet-4-5"
  "kimi-k2-5,deepseek-v3-2"
)

echo "== TerraRepair ABLATION sharded launch =="
echo "  account=${ACCOUNT_ID} cluster=${CLUSTER} family=${TASK_FAMILY}"
echo "  results=${PREFIX}  concurrency=${CONCURRENCY}/shard  shards=${#SHARDS[@]}"
echo

# Pre-flight: refuse to double-launch. If any ablation task is already RUNNING
# for this family, stop — avoids the duplicate-task spend problem.
RUNNING="$(aws ecs list-tasks --cluster "${CLUSTER}" --family "${TASK_FAMILY}" \
  --desired-status RUNNING --region "${REGION}" --query 'taskArns' --output text 2>/dev/null)"
if [[ -n "${RUNNING}" && "${RUNNING}" != "None" ]]; then
  echo "ERROR: ablation task(s) already RUNNING for ${TASK_FAMILY}:" >&2
  echo "  ${RUNNING}" >&2
  echo "Stop them first (aws ecs stop-task) or let them finish. Not launching." >&2
  exit 1
fi

for MODELS in "${SHARDS[@]}"; do
  OVERRIDES="$(python3 -c "
import json,sys
print(json.dumps({'containerOverrides':[{'name':'runner','environment':[
  {'name':'MODELS','value':sys.argv[1]},
  {'name':'CONCURRENCY','value':sys.argv[2]},
]}]}))" "${MODELS}" "${CONCURRENCY}")"
  ARN="$(aws ecs run-task \
    --cluster "${CLUSTER}" --launch-type FARGATE --task-definition "${TASK_FAMILY}" \
    --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_ID}],securityGroups=[${SG_ID}],assignPublicIp=ENABLED}" \
    --overrides "${OVERRIDES}" --region "${REGION}" \
    --query 'tasks[0].taskArn' --output text 2>&1)"
  echo "[shard] MODELS=${MODELS}"
  echo "        task=${ARN}"
done

echo
echo "== launched ${#SHARDS[@]} shard tasks =="
echo "Monitor:  bash deploy/status_ablation.sh   (or watch the S3 prefix / CloudWatch)"
echo "Done when all 4 ablation_complete_<shard>.json markers exist under:"
echo "  ${PREFIX}/"
