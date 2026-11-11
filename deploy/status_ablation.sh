#!/usr/bin/env bash
# Read-only status for the sharded retrieval ablation run.
#
# Shows, without touching any state:
#   1. ECS task status for every terrarepair-ablation task (RUNNING + recently STOPPED).
#   2. Per-model game counts in S3 vs the expected 2304 (192 targets x 4 arms x 3 draws).
#   3. Which per-shard completion markers (ablation_complete_<shard>.json) exist.
#
# Safe to run any time; makes only list/describe/get calls. Does NOT launch,
# stop, or delete anything.
#
# Usage: bash deploy/status_ablation.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ablation.env"

PREFIX="s3://${RESULTS_BUCKET}/${S3_PREFIX}"
MODELS=(grok-4-6 claude-sonnet-5 deepseek-r1 claude-sonnet-4-5 kimi-k2-5 deepseek-v3-2)
# 192 targets x 4 arms x 3 draws
EXPECTED_PER_MODEL=2304

echo "== TerraRepair ABLATION status =="
echo "  account=${ACCOUNT_ID} cluster=${CLUSTER} family=${TASK_FAMILY}"
echo "  results=${PREFIX}"
echo

# ---- 1. ECS tasks --------------------------------------------------------
echo "-- ECS tasks (RUNNING + last 10 STOPPED) --"
RUNNING_ARNS="$(aws ecs list-tasks --cluster "${CLUSTER}" --family "${TASK_FAMILY}" \
  --desired-status RUNNING --region "${REGION}" --query 'taskArns' --output text 2>/dev/null)"
STOPPED_ARNS="$(aws ecs list-tasks --cluster "${CLUSTER}" --family "${TASK_FAMILY}" \
  --desired-status STOPPED --region "${REGION}" --query 'taskArns[:10]' --output text 2>/dev/null)"

ALL_ARNS="$(printf '%s %s' "${RUNNING_ARNS}" "${STOPPED_ARNS}" | tr '\t' ' ')"
ALL_ARNS="$(echo "${ALL_ARNS}" | sed 's/None//g' | xargs 2>/dev/null)"

if [[ -z "${ALL_ARNS}" ]]; then
  echo "  (no ablation tasks found)"
else
  # describe-tasks takes up to 100 arns; our run has <=4 + a few stopped.
  aws ecs describe-tasks --cluster "${CLUSTER}" --region "${REGION}" --tasks ${ALL_ARNS} \
    --query 'tasks[].{models:overrides.containerOverrides[0].environment[?name==`MODELS`]|[0].value,last:lastStatus,stopped:stoppedReason,exit:containers[0].exitCode}' \
    --output table 2>/dev/null \
    || echo "  (describe-tasks failed)"
fi
echo

# ---- 2. Per-model game counts in S3 -------------------------------------
echo "-- S3 game progress (per model, of ${EXPECTED_PER_MODEL} expected) --"
# One listing, bucketed locally. Game filenames: module_<id>_<model>_<arm>_d<n>.json
LISTING="$(aws s3 ls "${PREFIX}/games/" --region "${REGION}" 2>/dev/null | awk '{print $4}' | grep '\.json$' || true)"
TOTAL=0
for m in "${MODELS[@]}"; do
  # Anchor the model between "_<model>_" and one of the arm tokens, so e.g.
  # claude-sonnet-4-5 and claude-sonnet-5 do not cross-match.
  c=$(printf '%s\n' "${LISTING}" | grep -cE "_${m}_(none|random|similarity|oracle)_d[0-9]+\.json$" || true)
  pct=$(python3 -c "print(f'{100*$c/$EXPECTED_PER_MODEL:5.1f}')" 2>/dev/null || echo "  ?")
  printf "  %-20s %5d / %d  (%s%%)\n" "${m}" "${c}" "${EXPECTED_PER_MODEL}" "${pct}"
  TOTAL=$((TOTAL + c))
done
GRAND_EXPECTED=$((EXPECTED_PER_MODEL * ${#MODELS[@]}))
pct_all=$(python3 -c "print(f'{100*$TOTAL/$GRAND_EXPECTED:5.1f}')" 2>/dev/null || echo "  ?")
printf "  %-20s %5d / %d  (%s%%)\n" "TOTAL" "${TOTAL}" "${GRAND_EXPECTED}" "${pct_all}"
echo

# ---- 3. Completion markers ----------------------------------------------
echo "-- completion markers (run DONE when all 4 present) --"
MARKERS="$(aws s3 ls "${PREFIX}/" --region "${REGION}" 2>/dev/null | awk '{print $4}' | grep '^ablation_complete_.*\.json$' || true)"
if [[ -z "${MARKERS}" ]]; then
  echo "  (none yet)"
else
  printf '%s\n' "${MARKERS}" | sed 's/^/  [done] /'
fi
