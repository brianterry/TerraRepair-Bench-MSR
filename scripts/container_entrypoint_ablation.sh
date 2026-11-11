#!/usr/bin/env bash
# Container entrypoint for the RETRIEVAL ABLATION runner.
#
# Mirrors container_entrypoint.sh (S3 resume-pull first, periodic sync-up,
# final sync on exit, idempotent completion marker), but runs
# run_retrieval_ablation.py over the pre-registered ablation grid.
#
# Fargate task storage is EPHEMERAL, so results must live in S3. This entrypoint:
#   1. Pulls existing ablation results from S3  -> RESUME across restarts
#      (the runner skips (module,model,arm,draw) games already present).
#   2. Background loop periodically syncs results UP to S3.
#   3. Runs the ablation.
#   4. Final sync on exit (success OR failure) via trap.
#
# Env vars:
#   RESULTS_S3_URI  (required for persistence) e.g. s3://bucket/terrarepair/retrieval_ablation
#   MODELS          comma-separated model ids (default = the 6-model pre-reg cohort)
#   ARMS            default none,random,similarity,oracle
#   DRAWS           replications per cell (default 3)
#   CONCURRENCY     parallel units (default 4)
#   MAX_TOKENS      output cap (default 16384)
#   MAX_MODULES     cap targets (set small for smoke; unset = full 192)
#   REGION          Bedrock region (default $AWS_REGION or us-east-1)
#   SYNC_INTERVAL   seconds between background syncs (default 120)
set -uo pipefail

REGION="${REGION:-${AWS_REGION:-us-east-1}}"
MODELS="${MODELS:-grok-4-6,claude-sonnet-5,deepseek-r1,claude-sonnet-4-5,kimi-k2-5,deepseek-v3-2}"
ARMS="${ARMS:-none,random,similarity,oracle}"
DRAWS="${DRAWS:-3}"
CONCURRENCY="${CONCURRENCY:-4}"
# 40000: grok-4-6 (and other verbose reasoning models) exhaust a 16384 output
# budget on reasoning and emit an empty answer. The per-model _MODEL_MAX_TOKENS
# clamp caps lower-ceiling models (deepseek-r1->32768, nova->10000, llama->8192),
# so a single 40000 nominal is correct for the whole cohort. Verified: grok
# succeeds at 40000 (used ~24k output tokens) where 16384 truncated it.
MAX_TOKENS="${MAX_TOKENS:-40000}"
SYNC_INTERVAL="${SYNC_INTERVAL:-120}"

LOCAL_RESULTS="experiments/results/retrieval_ablation"
mkdir -p "${LOCAL_RESULTS}/games"

# Shard id derived from the MODELS slice, so model-sharded containers each own a
# DISJOINT completion marker. Containers write disjoint game FILES already
# (filenames include the model id), so they share one games/ prefix safely; only
# the completion marker needs to be per-shard so one shard finishing does not
# make the others no-op on restart. Sanitize MODELS -> safe filename token.
SHARD_ID="$(printf '%s' "${MODELS}" | tr ',' '-' | tr -cd 'a-zA-Z0-9._-')"
MARKER="${LOCAL_RESULTS}/ablation_complete_${SHARD_ID}.json"
echo "[ablation] shard_id=${SHARD_ID}"

echo "[ablation] region=${REGION} draws=${DRAWS} concurrency=${CONCURRENCY}"
echo "[ablation] models=${MODELS}"
echo "[ablation] arms=${ARMS} max_tokens=${MAX_TOKENS} max_modules=${MAX_MODULES:-<all 192>}"
echo "[ablation] RESULTS_S3_URI=${RESULTS_S3_URI:-<unset: local-only>}"

sync_up() {
  if [[ -n "${RESULTS_S3_URI:-}" ]]; then
    aws s3 sync "${LOCAL_RESULTS}" "${RESULTS_S3_URI}" --only-show-errors \
      || echo "[ablation] WARN: sync-up failed"
  fi
}
sync_down() {
  if [[ -n "${RESULTS_S3_URI:-}" ]]; then
    echo "[ablation] pulling existing results from ${RESULTS_S3_URI} (resume)"
    aws s3 sync "${RESULTS_S3_URI}" "${LOCAL_RESULTS}" --only-show-errors \
      || echo "[ablation] WARN: initial sync-down failed (empty bucket or perms?)"
  fi
}

trap 'echo "[ablation] final sync on exit"; sync_up' EXIT

# 1. Resume.
sync_down

# 1b. Idempotency: if THIS SHARD already completed, no-op (safe auto-restart).
if [[ -f "${MARKER}" ]]; then
  echo "[ablation] ${MARKER} present -> this shard already finished; nothing to do."
  exit 0
fi

# 2. Background periodic sync-up.
if [[ -n "${RESULTS_S3_URI:-}" ]]; then
  ( while true; do sleep "${SYNC_INTERVAL}"; echo "[ablation $(date -u +%H:%M:%S)] periodic sync-up"; sync_up; done ) &
  SYNC_PID=$!
  trap 'echo "[ablation] final sync on exit"; kill ${SYNC_PID} 2>/dev/null; sync_up' EXIT
fi

# 3. Run the ablation.
CMD=(python3 scripts/run_retrieval_ablation.py
     --models "${MODELS}"
     --arms "${ARMS}"
     --draws "${DRAWS}"
     --concurrency "${CONCURRENCY}"
     --max-tokens "${MAX_TOKENS}"
     --region "${REGION}")
if [[ -n "${MAX_MODULES:-}" ]]; then
  CMD+=(--max-modules "${MAX_MODULES}")
fi

echo "[ablation] running: ${CMD[*]}"
"${CMD[@]}"
RC=$?
echo "[ablation] runner exited rc=${RC}"

# 4. Per-shard completion marker, written only on a clean exit, LAST (so a
# crashed/partial run never leaves it behind). Counts only THIS shard's games
# (files for the shard's models). The run is fully done when every shard's
# ablation_complete_<shard>.json exists in S3.
if [[ ${RC} -eq 0 ]]; then
  n=0
  IFS=',' read -ra _MS <<< "${MODELS}"
  for _m in "${_MS[@]}"; do
    c=$(ls "${LOCAL_RESULTS}/games" 2>/dev/null | grep -c "_${_m}_.*\.json$" || true)
    n=$((n + c))
  done
  python3 -c "import json,sys; json.dump({'completed':True,'shard':sys.argv[1],'models':sys.argv[2],'shard_games':int(sys.argv[3])}, open(sys.argv[4],'w'))" \
    "${SHARD_ID}" "${MODELS}" "${n}" "${MARKER}"
  echo "[ablation] wrote $(basename "${MARKER}") (${n} games for shard ${SHARD_ID})"
fi
exit ${RC}
