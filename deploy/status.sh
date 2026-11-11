#!/usr/bin/env bash
# READ-ONLY status for the TerraRepair-Bench Fargate run.
#
# Consolidates every signal into one view. Makes NO changes: only S3 reads
# (cp/ls) and ECS describe/list calls. Safe to run repeatedly during a run.
#
# What it reports:
#   1. Completion   -> is run_complete.json present in S3? (the authoritative
#                      "done" marker; written last by run_experiment.py)
#   2. Progress     -> metrics.json snapshot: done/total, %, games/min,
#                      cumulative cost, event + per-model breakdown
#   3. Games count  -> objects under games/ in S3 (independent cross-check of
#                      metrics.done; lags by up to one container sync interval)
#   4. Skips        -> tail of skip_manifest.jsonl (out-of-band / unscannable /
#                      size-driven modules)
#   5. ECS tasks    -> live/last task state for the family (RUNNING? why STOPPED?)
#
# Usage:
#   bash deploy/status.sh            # full status
#   bash deploy/status.sh --watch    # refresh every 30s (Ctrl-C to stop)
#   SKIP_TAIL=20 bash deploy/status.sh   # show last 20 skip entries (default 10)
#
# Notes:
#   - metrics.json / games count reflect the LAST container sync-up, so they can
#     be up to SYNC_INTERVAL (default 120s) stale mid-run. The "ts" field in the
#     metrics snapshot tells you how fresh it is.
#   - Requires deploy.env (from deploy/setup.sh), aws CLI, and python3 for
#     pretty-printing (falls back to raw JSON if python3 is missing).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "${SCRIPT_DIR}/deploy.env" ]]; then
  echo "ERROR: ${SCRIPT_DIR}/deploy.env not found. Run deploy/setup.sh first." >&2
  exit 1
fi
# An S3_PREFIX set by the caller wins over deploy.env, so the same script can
# report on any run under the bucket, e.g.
#   S3_PREFIX=terrarepair/release_slice_2026-10 bash deploy/status.sh
_S3_PREFIX_OVERRIDE="${S3_PREFIX:-}"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/deploy.env"
if [[ -n "${_S3_PREFIX_OVERRIDE}" ]]; then
  S3_PREFIX="${_S3_PREFIX_OVERRIDE}"
fi

SKIP_TAIL="${SKIP_TAIL:-10}"
S3_BASE="s3://${RESULTS_BUCKET}/${S3_PREFIX}"

have_python() { command -v python3 >/dev/null 2>&1; }

hr() { printf '%s\n' "------------------------------------------------------------"; }

report() {
  echo "=========================================================="
  echo " TerraRepair-Bench status   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "   bucket : ${S3_BASE}"
  echo "   cluster: ${CLUSTER}   family: ${TASK_FAMILY}   region: ${REGION}"
  echo "=========================================================="

  # ---- 1. Completion marker -------------------------------------------------
  hr
  echo "[1] Completion"
  if aws s3 ls "${S3_BASE}/run_complete.json" --region "${REGION}" >/dev/null 2>&1; then
    echo "  STATUS: COMPLETE (run_complete.json present)"
    marker="$(aws s3 cp "${S3_BASE}/run_complete.json" - --region "${REGION}" 2>/dev/null)"
    if have_python && [[ -n "${marker}" ]]; then
      printf '%s' "${marker}" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    print("  (could not parse run_complete.json)"); sys.exit()
m=d.get("metrics",{})
ev=m.get("events",{})
scored=d.get("scored_games", ev.get("scored","?"))
cost=m.get("total_cost_usd","?")
ts=m.get("ts", d.get("ts","?"))
print("  scored_games : {}".format(scored))
print("  total_cost   : ${}".format(cost))
print("  finished_ts  : {}".format(ts))
'
    fi
  else
    echo "  STATUS: NOT COMPLETE (no run_complete.json yet)"
  fi

  # ---- 2. Progress (metrics.json) ------------------------------------------
  hr
  echo "[2] Progress (metrics.json — last container sync-up)"
  metrics="$(aws s3 cp "${S3_BASE}/metrics.json" - --region "${REGION}" 2>/dev/null)"
  if [[ -z "${metrics}" ]]; then
    echo "  (no metrics.json yet — run may not have started syncing)"
  elif have_python; then
    printf '%s' "${metrics}" | python3 -c '
import json,sys
d=json.load(sys.stdin)
print("  snapshot_ts  : {}".format(d.get("ts","?")))
print("  progress     : {}/{}  ({}%)".format(d.get("done",0), d.get("total",0), d.get("pct",0)))
print("  rate         : {} games/min   elapsed {}s".format(d.get("games_per_min",0), d.get("elapsed_sec",0)))
print("  total_cost   : ${}".format(d.get("total_cost_usd",0)))
ev=d.get("events",{})
if ev:
    print("  events       : " + "  ".join("{}={}".format(k,v) for k,v in ev.items() if v))
bm=d.get("by_model",{})
if bm:
    print("  by_model     :")
    for mid,s in bm.items():
        print("    {:<24} scored={:>3} hcl_valid={:>3} throttled={:>2} timed_out={:>2} size={:>2} cost=${}".format(
              mid, s.get("scored",0), s.get("hcl_valid",0), s.get("throttled",0),
              s.get("timed_out",0), s.get("size_driven",0), s.get("cost_usd",0)))
'
  else
    echo "  (python3 not found — raw metrics.json:)"
    printf '%s\n' "${metrics}"
  fi

  # ---- 3. Games count (independent cross-check) -----------------------------
  hr
  echo "[3] Games written to S3 (independent of metrics.done)"
  games_count="$(aws s3 ls "${S3_BASE}/games/" --region "${REGION}" 2>/dev/null | grep -c '\.json$' || true)"
  echo "  game result objects: ${games_count:-0}"
  echo "  (lags metrics/done by up to one container sync interval)"

  # ---- 4. Skips -------------------------------------------------------------
  hr
  echo "[4] Skip manifest (last ${SKIP_TAIL} entries)"
  skips="$(aws s3 cp "${S3_BASE}/skip_manifest.jsonl" - --region "${REGION}" 2>/dev/null)"
  if [[ -z "${skips}" ]]; then
    echo "  (no skip_manifest.jsonl / no skips recorded)"
  else
    total_skips="$(printf '%s\n' "${skips}" | grep -c . || true)"
    echo "  total skip entries: ${total_skips}"
    printf '%s\n' "${skips}" | tail -n "${SKIP_TAIL}" | sed 's/^/    /'
  fi

  # ---- 5. ECS task state ----------------------------------------------------
  hr
  echo "[5] ECS tasks (family=${TASK_FAMILY})"
  running="$(aws ecs list-tasks --cluster "${CLUSTER}" --family "${TASK_FAMILY}" \
             --desired-status RUNNING --region "${REGION}" \
             --query 'taskArns' --output text 2>/dev/null || true)"
  if [[ -n "${running}" && "${running}" != "None" ]]; then
    echo "  RUNNING tasks:"
    aws ecs describe-tasks --cluster "${CLUSTER}" --tasks ${running} --region "${REGION}" \
      --query 'tasks[].{task:taskArn,lastStatus:lastStatus,health:healthStatus,started:startedAt}' \
      --output table 2>/dev/null || echo "    (describe-tasks failed)"
  else
    echo "  no RUNNING tasks. Most recent STOPPED task:"
    stopped="$(aws ecs list-tasks --cluster "${CLUSTER}" --family "${TASK_FAMILY}" \
               --desired-status STOPPED --region "${REGION}" \
               --query 'taskArns[0]' --output text 2>/dev/null || true)"
    if [[ -n "${stopped}" && "${stopped}" != "None" ]]; then
      aws ecs describe-tasks --cluster "${CLUSTER}" --tasks "${stopped}" --region "${REGION}" \
        --query 'tasks[0].{lastStatus:lastStatus,stopCode:stopCode,stoppedReason:stoppedReason,exitCode:containers[0].exitCode,containerReason:containers[0].reason,stoppedAt:stoppedAt}' \
        --output json 2>/dev/null | sed 's/^/    /' || echo "    (describe-tasks failed)"
    else
      echo "    (no tasks found for this family — run never launched?)"
    fi
  fi
  hr
}

if [[ "${1:-}" == "--watch" ]]; then
  while true; do
    clear
    report
    echo
    echo "(watch mode: refreshing in 30s — Ctrl-C to stop)"
    sleep 30
  done
else
  report
fi
