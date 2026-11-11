#!/usr/bin/env bash
# Container entrypoint for the TerraRepair-Bench runner.
#
# Fargate task storage is EPHEMERAL: when the task stops, /app/experiments/results
# is gone. So results must live in S3. This entrypoint:
#   1. Pulls any existing results from S3 first  -> enables RESUME across task
#      restarts (the runner auto-skips games already present).
#   2. Starts a background loop that periodically syncs results UP to S3, so a
#      crash/stop loses at most one sync interval of games.
#   3. Runs the experiment.
#   4. Does a FINAL sync on exit (success OR failure) via a trap, so partial
#      progress is always persisted.
#
# Configuration via environment variables:
#   RESULTS_S3_URI   (required for S3 persistence) e.g. s3://my-bucket/terrarepair/full_refresh_2026-09
#                    If unset, runs purely local (useful for the local smoke).
#   CONFIG           experiment YAML (default experiments/configs/full_refresh_2026.yaml)
#   REGION           AWS region for Bedrock (default $AWS_REGION or us-east-1)
#   CONCURRENCY      parallel repairs (default 4)
#   MAX_MODULES      cap corpus (set small for smoke; unset = full)
#   MAX_TOKENS       output token cap (default 16384; per-model clamp still applies)
#   MODELS           comma-separated model-id subset for a targeted re-run
#                    (unset = full cohort from the config)
#   SYNC_INTERVAL    seconds between background S3 syncs (default 120)
#   EXTRA_ARGS       any additional run_experiment.py flags
set -uo pipefail

CONFIG="${CONFIG:-experiments/configs/full_refresh_2026.yaml}"
REGION="${REGION:-${AWS_REGION:-us-east-1}}"
CONCURRENCY="${CONCURRENCY:-4}"
MAX_TOKENS="${MAX_TOKENS:-16384}"
SYNC_INTERVAL="${SYNC_INTERVAL:-120}"

# Derive the experiment name from the config so we know the local results dir.
EXP_NAME="$(python3 -c "import yaml,sys; print(yaml.safe_load(open('${CONFIG}'))['experiment']['name'])")"
OUTPUT_DIR="$(python3 -c "import yaml; c=yaml.safe_load(open('${CONFIG}')); print(c['output_dir'])")"
LOCAL_RESULTS="${OUTPUT_DIR}/${EXP_NAME}"
mkdir -p "${LOCAL_RESULTS}"

echo "[entrypoint] experiment=${EXP_NAME} region=${REGION} concurrency=${CONCURRENCY}"
echo "[entrypoint] local results dir=${LOCAL_RESULTS}"
echo "[entrypoint] RESULTS_S3_URI=${RESULTS_S3_URI:-<unset: local-only mode>}"

sync_down() {
  if [[ -n "${RESULTS_S3_URI:-}" ]]; then
    echo "[entrypoint] pulling existing results from ${RESULTS_S3_URI} (resume)"
    aws s3 sync "${RESULTS_S3_URI}" "${LOCAL_RESULTS}" --only-show-errors || \
      echo "[entrypoint] WARN: initial sync-down failed (bucket empty or perms?)"
  fi
}

sync_up() {
  if [[ -n "${RESULTS_S3_URI:-}" ]]; then
    aws s3 sync "${LOCAL_RESULTS}" "${RESULTS_S3_URI}" --only-show-errors || \
      echo "[entrypoint] WARN: sync-up failed"
  fi
}

# Final sync on ANY exit so partial progress is never lost.
trap 'echo "[entrypoint] final sync on exit"; sync_up' EXIT

# 1. Resume: pull whatever is already in S3.
sync_down

# 1b. Idempotency: if a previous run already completed (marker present), do NOT
# re-run. This makes an auto-restart safe — a restarter that fires after the run
# finished is a clean no-op instead of a duplicate (billable) run.
if [[ -f "${LOCAL_RESULTS}/run_complete.json" ]]; then
  echo "[entrypoint] run_complete.json present -> run already finished; nothing to do."
  echo "[entrypoint] $(cat "${LOCAL_RESULTS}/run_complete.json" | head -c 400)"
  exit 0
fi

# 2. Background periodic sync-up.
if [[ -n "${RESULTS_S3_URI:-}" ]]; then
  (
    while true; do
      sleep "${SYNC_INTERVAL}"
      echo "[entrypoint $(date -u +%H:%M:%S)] periodic sync-up"
      sync_up
    done
  ) &
  SYNC_PID=$!
  trap 'echo "[entrypoint] final sync on exit"; kill ${SYNC_PID} 2>/dev/null; sync_up' EXIT
fi

# 3. Build the run command.
CMD=(python3 scripts/run_experiment.py
     --config "${CONFIG}"
     --region "${REGION}"
     --concurrency "${CONCURRENCY}"
     --max-tokens "${MAX_TOKENS}")
if [[ -n "${MAX_MODULES:-}" ]]; then
  CMD+=(--max-modules "${MAX_MODULES}")
fi
# MODELS: comma-separated subset for targeted re-runs (e.g. recovering specific
# models at a larger MAX_TOKENS, or adding a new model). Unset = full cohort.
if [[ -n "${MODELS:-}" ]]; then
  CMD+=(--models "${MODELS}")
fi
if [[ -n "${EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  CMD+=(${EXTRA_ARGS})
fi

echo "[entrypoint] running: ${CMD[*]}"
"${CMD[@]}"
RC=$?
echo "[entrypoint] runner exited rc=${RC}"
exit ${RC}
