"""
Main experiment runner. Runs all 1,200 games (6 models × 200 modules).

Usage: python scripts/run_experiment.py --config experiments/configs/full_experiment.yaml

For each module in the corpus:
  1. Run scanner stack on original code → findings_before
  2. For each model:
     a. Repair the module
     b. Run scanner stack on repaired code → findings_after
     c. Score the repair → GameResult
     d. Save to experiments/results/{experiment_id}/games/

Progress bar with ETA. Cost tracking per model.
Auto-resume: skip games where results/games/{module_id}_{model_id}.json exists.
"""

import argparse
import json
import os
import shutil
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

import yaml

# tqdm is optional: on a headless remote instance we emit line-based progress
# and a heartbeat instead of relying on a TTY progress bar.
try:
    from tqdm import tqdm
except Exception:  # noqa: BLE001
    tqdm = None

# Add project root
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.repair.repair_agent import repair_module
from src.scanning.scanner_normalizer import Finding, ScannerStack
from src.scoring.delta_scorer import GameResult, score_repair
from src.scoring.corpus_filter import MAX_FINDINGS, MIN_FINDINGS, in_corpus
from src.utils.bedrock_client import BedrockClient, InvokeTimeout, ThrottlingError
from src.utils.repair_artifacts import write_repair_sidecars

import logging
logger = logging.getLogger(__name__)


def _utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()


def _module_source_chars(module_dir: str) -> int:
    """Total characters across the module's .tf files (the repair prompt body)."""
    total = 0
    for tf in Path(module_dir).glob("*.tf"):
        try:
            total += len(tf.read_text())
        except Exception:  # noqa: BLE001
            pass
    return total


# Rough chars-per-token for English/HCL; used only for a size heuristic, not billing.
_CHARS_PER_TOKEN = 4


def _est_input_tokens(source_chars: int) -> int:
    return source_chars // _CHARS_PER_TOKEN


def _is_size_driven_failure(source_chars: int, max_tokens: int) -> bool:
    """Heuristic: a repair regenerates the whole module, so if the source alone
    already needs more OUTPUT tokens than max_tokens allows, an invalid-HCL
    result is almost certainly truncation/context-driven rather than a genuine
    repair-quality failure. Used to TAG the failure (option A keeps scoring at
    0/0/0); it does not change any score."""
    return _est_input_tokens(source_chars) > max_tokens


class RunMetrics:
    """Thread-safe run metrics for troubleshooting a long/expensive run.

    Categorizes every processed game as one of: scored (repair completed and
    was scored, valid or invalid HCL), throttled, timed_out, scan_failed,
    resumed (already existed), or size_note. Tracks per-model outcome counts
    and cumulative cost, plus overall progress + rate. Snapshotted to
    metrics.json periodically so a stalled or cost-runaway run is diagnosable
    without parsing raw logs.
    """

    def __init__(self, total: int, models: list[str], started_monotonic: float):
        import threading as _t
        self._lock = _t.Lock()
        self._total = total
        self._started = started_monotonic
        self._done = 0
        self._events: dict[str, int] = {
            "scored": 0, "scored_hcl_valid": 0, "scored_hcl_invalid": 0,
            "throttled": 0, "timed_out": 0, "scan_failed": 0,
            "resumed": 0, "size_driven": 0,
        }
        self._by_model: dict[str, dict] = {
            m: {"scored": 0, "hcl_valid": 0, "throttled": 0, "timed_out": 0,
                "scan_failed": 0, "resumed": 0, "size_driven": 0, "cost_usd": 0.0}
            for m in models
        }

    def record(self, model_id: str, event: str, *, hcl_valid: bool = False,
               size_driven: bool = False, cost_usd: float = 0.0) -> None:
        with self._lock:
            self._done += 1
            self._events[event] = self._events.get(event, 0) + 1
            bm = self._by_model.setdefault(model_id, {
                "scored": 0, "hcl_valid": 0, "throttled": 0, "timed_out": 0,
                "scan_failed": 0, "resumed": 0, "size_driven": 0, "cost_usd": 0.0})
            bm[event] = bm.get(event, 0) + 1
            bm["cost_usd"] += cost_usd
            if event == "scored":
                if hcl_valid:
                    self._events["scored_hcl_valid"] += 1
                    bm["hcl_valid"] += 1
                else:
                    self._events["scored_hcl_invalid"] += 1
            if size_driven:
                self._events["size_driven"] += 1
                bm["size_driven"] += 1

    def snapshot(self, now_monotonic: float) -> dict:
        with self._lock:
            elapsed = max(1e-6, now_monotonic - self._started)
            return {
                "ts": _utcnow(),
                "done": self._done,
                "total": self._total,
                "pct": round(self._done / self._total * 100, 1) if self._total else 0,
                "elapsed_sec": round(elapsed, 1),
                "games_per_min": round(self._done / elapsed * 60, 2),
                "events": dict(self._events),
                "total_cost_usd": round(
                    sum(m["cost_usd"] for m in self._by_model.values()), 4),
                "by_model": {k: {**v, "cost_usd": round(v["cost_usd"], 4)}
                             for k, v in self._by_model.items()},
            }


def _scanner_versions() -> dict:
    """Record exact scanner versions in the run manifest (audit: pin scanners)."""
    versions = {}
    for name, cmd in (("trivy", ["trivy", "--version"]),
                      ("checkov", ["checkov", "--version"])):
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            versions[name] = (out.stdout or out.stderr).strip().splitlines()[0] if (out.stdout or out.stderr) else "unknown"
        except Exception as e:  # noqa: BLE001
            versions[name] = f"UNAVAILABLE: {type(e).__name__}"
    return versions


def _git_provenance() -> dict:
    """Commit + dirty-tree marker for the run manifest. A dirty tree is
    recorded (with a hash of the tracked diff) rather than hidden, so a run
    made from uncommitted code is identifiable."""
    import hashlib

    root = Path(__file__).resolve().parent.parent

    def git(*a):
        return subprocess.run(["git", *a], cwd=root, capture_output=True,
                              text=True, timeout=30).stdout

    try:
        commit = git("rev-parse", "HEAD").strip()
        if commit:
            diff = git("-P", "diff", "HEAD")
            status = git("status", "--porcelain", "--untracked-files=no").strip()
            return {
                "source": "git",
                "commit": commit,
                "dirty": bool(status),
                "tracked_diff_sha256": hashlib.sha256(diff.encode()).hexdigest() if diff else None,
            }
    except Exception:  # noqa: BLE001 - fall through to the baked-in values
        pass
    # No usable git checkout (the container image excludes .git). Use the
    # commit baked in at image build time (Dockerfile ARG -> ENV). If that is
    # absent too, say so explicitly rather than reporting a clean tree.
    baked = os.environ.get("TERRAREPAIR_GIT_COMMIT", "").strip()
    if baked:
        dirty_raw = os.environ.get("TERRAREPAIR_GIT_DIRTY", "").strip().lower()
        dirty = {"true": True, "false": False}.get(dirty_raw, "unknown")
        return {
            "source": "image_build_arg",
            "commit": baked,
            "dirty": dirty,
            "tracked_diff_sha256": None,
        }
    return {"source": "unavailable", "commit": "unknown", "dirty": "unknown"}


def _model_provenance(model_ids: list[str], max_tokens: int) -> dict:
    """The Bedrock id actually invoked (BedrockClient resolves friendly ids via
    SUPPORTED_MODELS; the YAML's bedrock_model_id is informational only), the
    effective output budget after the per-model clamp, and whether temperature
    is sent."""
    from src.utils import bedrock_client as bc
    return {
        mid: {
            "bedrock_model_id": bc.SUPPORTED_MODELS.get(mid, mid),
            "effective_max_tokens": min(max_tokens, bc._MODEL_MAX_TOKENS.get(mid, max_tokens)),
            "temperature_sent": mid not in bc.NO_TEMPERATURE_MODELS,
        }
        for mid in model_ids
    }


def _finding_to_dict(f: Finding) -> dict:
    return {
        "tool": f.tool,
        "rule_id": f.rule_id,
        "title": f.title,
        "severity": f.severity,
        "resource_name": f.resource_name,
        "resource_type": f.resource_type,
        "file_path": f.file_path,
        "start_line": f.start_line,
        "end_line": f.end_line,
    }


def _game_result_to_dict(g: GameResult) -> dict:
    return {
        "module_id": g.module_id,
        "model_id": g.model_id,
        "findings_before": [_finding_to_dict(f) for f in g.findings_before],
        "findings_after": [_finding_to_dict(f) for f in g.findings_after],
        "target_count": g.target_count,
        "resolved_count": g.resolved_count,
        "introduced_count": g.introduced_count,
        "unchanged_count": g.unchanged_count,
        "repair_success_rate": g.repair_success_rate,
        "regression_rate": g.regression_rate,
        "net_delta": g.net_delta,
        "class_breakdown": g.class_breakdown,
        "repair_cost_usd": g.repair_cost_usd,
        "repair_tokens": g.repair_tokens,
        "hcl_valid": g.hcl_valid,
    }


def filter_models(models: list[dict], models_csv: str) -> list[dict]:
    """Restrict the config's model list to a requested comma-separated subset.

    Used for targeted re-runs (e.g. recovering specific models at a larger
    --max-tokens, or adding a single new model). Preserves the config order of
    the kept models. Raises SystemExit on an unknown id so a typo can't silently
    run the wrong (or empty) set.
    """
    requested = [m.strip() for m in models_csv.split(",") if m.strip()]
    available = {m["id"] for m in models}
    unknown = [r for r in requested if r not in available]
    if unknown:
        raise SystemExit(
            f"--models contains ids not in the config: {unknown}. "
            f"Available: {sorted(available)}"
        )
    return [m for m in models if m["id"] in requested]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, help="Path to experiment YAML")
    parser.add_argument("--region", default="us-east-1", help="AWS region for Bedrock")
    parser.add_argument("--max-modules", type=int, default=None,
                        help="Override corpus cap (e.g. small slice for smoke test)")
    parser.add_argument("--heartbeat-secs", type=int, default=300,
                        help="Emit a heartbeat line at least this often")
    parser.add_argument("--concurrency", type=int, default=1,
                        help="Number of (module,model) repairs to run in "
                             "parallel. Default 1 = the verified serial path. "
                             "Full-module repairs are latency-bound (minutes "
                             "each) and request-rate stays far under quota, so "
                             "4-6 is safe on this account and ~Nx faster.")
    parser.add_argument("--max-tokens", type=int, default=16384,
                        help="Max output tokens per repair. Clamped down per "
                             "model by _MODEL_MAX_TOKENS. Bounds worst-case "
                             "generation latency; keep high enough to fit a "
                             "full repaired module (default 16384).")
    parser.add_argument("--models", default=None,
                        help="Comma-separated model ids to restrict the run to "
                             "(subset of the config's models). Used for targeted "
                             "re-runs, e.g. recovering specific models at a "
                             "larger --max-tokens. Combined with the existing "
                             "game-file resume guard, only missing (module,model) "
                             "games for these models are re-attempted; all other "
                             "models' existing games are left untouched. Unknown "
                             "ids error out (typo guard).")
    args = parser.parse_args()

    with open(args.config) as f:
        config = yaml.safe_load(f)

    exp_name = config["experiment"]["name"]
    corpus_dir = Path(config["corpus"]["dir"])
    max_modules = args.max_modules or config["corpus"].get("max_modules", 200)
    output_dir = Path(config["output_dir"]) / exp_name
    games_dir = output_dir / "games"
    games_dir.mkdir(parents=True, exist_ok=True)

    models = config["models"]
    if args.models:
        models = filter_models(models, args.models)
        print(f"[models] restricted to {[m['id'] for m in models]} (via --models)")
    scanner_stack = ScannerStack()
    bedrock = BedrockClient(region=args.region)

    # Manifests (written BEFORE any repair runs, so the run is reproducible
    # even if it is interrupted): skip log, corpus manifest, run manifest.
    skip_manifest = output_dir / "skip_manifest.jsonl"
    corpus_manifest_path = output_dir / "corpus_manifest.jsonl"
    run_manifest_path = output_dir / "run_manifest.json"

    skip_lock = threading.Lock()

    def log_skip(kind: str, ident: str, reason: str) -> None:
        # Guard the append so concurrent workers don't interleave partial lines.
        line = json.dumps({"kind": kind, "id": ident, "reason": reason,
                           "ts": _utcnow()}) + "\n"
        with skip_lock:
            with open(skip_manifest, "a") as fh:
                fh.write(line)

    # ------------------------------------------------------------------
    # Corpus construction AT SAMPLING TIME (audit Finding A / CORPUS.md):
    # a module is in the corpus iff its pre-repair finding count is in
    # [MIN_FINDINGS, MAX_FINDINGS]. Every candidate is scanned once here; those
    # in-band are kept (with findings cached for scoring), those out-of-band or
    # unscannable are logged to the skip manifest. The corpus is thus defined
    # up front, not by post-hoc filtering of scored games.
    # ------------------------------------------------------------------
    candidate_dirs = sorted(
        str(d) for d in corpus_dir.iterdir()
        if d.is_dir() and list(d.glob("*.tf"))
    )
    corpus: list[tuple[str, list, int]] = []   # (module_dir, findings_before, source_chars)
    n_candidates = 0
    for module_dir in candidate_dirs:
        if len(corpus) >= max_modules:
            break
        n_candidates += 1
        module_id = Path(module_dir).name
        before_scan = scanner_stack.run_checked(module_dir)
        if not before_scan.ok:
            log_skip("candidate", module_id,
                     f"pre-repair scan failed: {before_scan.failures}")
            continue
        n = len({(f.rule_id, f.resource_name) for f in before_scan.findings})
        if not in_corpus(n):
            log_skip("candidate", module_id,
                     f"finding count {n} outside [{MIN_FINDINGS},{MAX_FINDINGS}]")
            continue
        source_chars = _module_source_chars(module_dir)
        corpus.append((module_dir, before_scan.findings, source_chars))
        with open(corpus_manifest_path, "a") as fh:
            fh.write(json.dumps({
                "module_id": module_id, "module_dir": module_dir,
                "finding_count": n,
                "source_chars": source_chars,
                "est_input_tokens": _est_input_tokens(source_chars),
                "ts": _utcnow(),
            }) + "\n")

    # Run manifest (provenance for the whole run).
    run_manifest = {
        "experiment": exp_name,
        "started": _utcnow(),
        "region": args.region,
        "corpus_rule": {"min_findings": MIN_FINDINGS, "max_findings": MAX_FINDINGS},
        "candidates_scanned": n_candidates,
        "corpus_size": len(corpus),
        "models": [m["id"] for m in models],
        "model_details": _model_provenance([m["id"] for m in models], args.max_tokens),
        "git": _git_provenance(),
        "scanner_versions": _scanner_versions(),
        "temperature": 0.0,
        "concurrency": max(1, args.concurrency),
        "max_tokens": args.max_tokens,
        # Effective Bedrock timeouts as resolved by the client (env
        # BEDROCK_READ_TIMEOUT / BEDROCK_INVOKE_TIMEOUT, else 300/420 defaults).
        "bedrock_timeouts_s": {
            "read_timeout": bedrock.read_timeout,
            "invoke_timeout": bedrock.invoke_timeout,
        },
    }
    run_manifest_path.write_text(json.dumps(run_manifest, indent=2))
    print(f"[corpus] {len(corpus)} modules in band / {n_candidates} candidates scanned "
          f"(rule: {MIN_FINDINGS}<=findings<={MAX_FINDINGS})")
    print(f"[scanners] {run_manifest['scanner_versions']}")

    total = len(corpus) * len(models)
    cost_by_model = {m["id"]: 0.0 for m in models}
    done = 0
    started_monotonic = time.monotonic()
    last_heartbeat = started_monotonic
    pbar = tqdm(total=total, desc=exp_name, unit="game") if tqdm else None

    # Structured metrics for troubleshooting (snapshotted to metrics.json).
    metrics = RunMetrics(total, [m["id"] for m in models], started_monotonic)
    metrics_path = output_dir / "metrics.json"

    def write_metrics() -> None:
        try:
            metrics_path.write_text(json.dumps(metrics.snapshot(time.monotonic()), indent=2))
        except Exception as e:  # noqa: BLE001 - metrics must never break the run
            logger.warning("metrics write failed: %s", e)

    # Locks guarding shared mutable state when concurrency > 1. With
    # concurrency == 1 they are uncontended and the behavior is identical to
    # the verified serial path. Each game writes its OWN json file, so game
    # output needs no lock; only the aggregates and append-only manifests do.
    progress_lock = threading.Lock()
    cost_lock = threading.Lock()

    def tick(n: int = 1) -> None:
        nonlocal done, last_heartbeat
        with progress_lock:
            done += n
            if pbar:
                pbar.update(n)
            now = time.monotonic()
            if now - last_heartbeat >= args.heartbeat_secs:
                last_heartbeat = now
                print(f"[heartbeat {_utcnow()}] {done}/{total} games "
                      f"({done / total * 100:.1f}%)", flush=True)
                write_metrics()

    def run_one(module_dir: str, findings_before, model_id: str,
                source_chars: int = 0) -> None:
        """Repair -> scan -> score one (module, model). Isolated per game;
        safe to run in a worker thread. Mutates only lock-guarded aggregates."""
        module_id = Path(module_dir).name
        game_file = games_dir / f"{module_id}_{model_id}.json"
        if game_file.exists():
            # Auto-resume: already scored in a prior (possibly interrupted)
            # invocation. Counted for progress, not logged as a genuine skip.
            metrics.record(model_id, "resumed")
            tick(1)
            return

        try:
            result = repair_module(
                module_dir=module_dir,
                findings=findings_before,
                model_id=model_id,
                bedrock_client=bedrock,
                max_tokens=args.max_tokens,
            )
        except ThrottlingError as e:
            log_skip("game", f"{module_id}_{model_id}", f"throttled: {e}")
            metrics.record(model_id, "throttled")
            tick(1)
            return
        except InvokeTimeout as e:
            log_skip("game", f"{module_id}_{model_id}", f"invoke timeout: {e}")
            metrics.record(model_id, "timed_out")
            tick(1)
            return

        with cost_lock:
            cost_by_model[model_id] += result.repair_cost_usd

        # Scan repaired code. run_checked so a crashed post-repair scanner is
        # NOT mistaken for a clean (all-resolved) repair.
        findings_after = []
        scan_failed = None
        if result.repaired_dir:
            try:
                after_scan = scanner_stack.run_checked(result.repaired_dir)
                findings_after = after_scan.findings
                if not after_scan.ok:
                    scan_failed = after_scan.failures
            finally:
                if result.repaired_dir and Path(result.repaired_dir).exists():
                    shutil.rmtree(result.repaired_dir, ignore_errors=True)

        if scan_failed:
            log_skip("game", f"{module_id}_{model_id}",
                     f"post-repair scan failed: {scan_failed}")
            metrics.record(model_id, "scan_failed", cost_usd=result.repair_cost_usd)
            tick(1)
            return

        game = score_repair(
            module_id=module_id,
            model_id=model_id,
            findings_before=findings_before,
            findings_after=findings_after,
            repair_result=result,
        )
        game_dict = _game_result_to_dict(game)
        # Option A: keep 0/0/0 scoring for oversized/failed repairs, but TAG a
        # size-driven HCL failure so it can be reported separately (paper §3.5)
        # without changing any score. A failure is size-driven when the module
        # source alone already needs more output tokens than max_tokens allows.
        size_driven = False
        if not game.hcl_valid:
            size_driven = _is_size_driven_failure(source_chars, args.max_tokens)
            game_dict["failure_metadata"] = {
                "source_chars": source_chars,
                "est_input_tokens": _est_input_tokens(source_chars),
                "max_tokens": args.max_tokens,
                "size_driven_failure": size_driven,
                "repair_error": result.error,
            }
            if size_driven:
                log_skip("size_note", f"{module_id}_{model_id}",
                         f"size-driven HCL failure: {source_chars} chars "
                         f"(~{_est_input_tokens(source_chars)} tok) > max_tokens "
                         f"{args.max_tokens}; scored 0/0/0 to model per option A")
        # Persist the model output (sidecars written BEFORE the game JSON,
        # which is the resume marker). Paths are relative to games_dir.
        game_dict.update(write_repair_sidecars(game_file, result))
        game_file.write_text(json.dumps(game_dict, indent=2))
        metrics.record(model_id, "scored", hcl_valid=game.hcl_valid,
                       size_driven=size_driven, cost_usd=result.repair_cost_usd)
        tick(1)

    # Build the full (module, model) work list.
    work = [
        (module_dir, findings_before, model_cfg["id"], source_chars)
        for module_dir, findings_before, source_chars in corpus
        for model_cfg in models
    ]

    concurrency = max(1, args.concurrency)
    if concurrency == 1:
        for module_dir, findings_before, model_id, source_chars in work:
            run_one(module_dir, findings_before, model_id, source_chars)
    else:
        print(f"[concurrency] running {concurrency} repairs in parallel")
        with ThreadPoolExecutor(max_workers=concurrency) as pool:
            futures = [
                pool.submit(run_one, md, fb, mid, sc) for md, fb, mid, sc in work
            ]
            for fut in as_completed(futures):
                # Surface unexpected exceptions (repair_module handles its own;
                # this catches programming errors so they aren't swallowed).
                exc = fut.exception()
                if exc is not None:
                    logger.error("worker raised: %r", exc)

    if pbar:
        pbar.close()

    # Final metrics snapshot.
    write_metrics()

    # Finalize run manifest with completion time + cost.
    run_manifest["completed"] = _utcnow()
    run_manifest["cost_by_model"] = {mid: round(c, 4) for mid, c in cost_by_model.items()}
    run_manifest_path.write_text(json.dumps(run_manifest, indent=2))

    # COMPLETION SIGNAL. Reaching this line means the work loop finished every
    # (module, model) item without the process dying — i.e. the run is DONE.
    # A restarter (AWS Batch / re-run loop) checks for this marker to decide
    # "finished, do not restart" vs "crashed, restart". Written LAST so a
    # partial/crashed run never leaves it behind.
    scored_games = len(list(games_dir.glob("*.json")))
    completion = {
        "experiment": exp_name,
        "completed": _utcnow(),
        "total_work_items": total,
        "scored_games_on_disk": scored_games,
        "repaired_tf_sidecars_on_disk": len(list(games_dir.glob("*.repaired.tf"))),
        "raw_txt_sidecars_on_disk": len(list(games_dir.glob("*.raw.txt"))),
        "metrics": metrics.snapshot(time.monotonic()),
    }
    (output_dir / "run_complete.json").write_text(json.dumps(completion, indent=2))

    print("\nCost by model:")
    for mid, cost in cost_by_model.items():
        print(f"  {mid}: ${cost:.4f}")
    if skip_manifest.exists():
        n_skips = sum(1 for _ in open(skip_manifest))
        print(f"\nSkip manifest: {n_skips} entries -> {skip_manifest}")
    print(f"Corpus manifest: {len(corpus)} modules -> {corpus_manifest_path}")
    print(f"Run manifest -> {run_manifest_path}")
    print(f"Metrics -> {metrics_path}")
    print(f"COMPLETE marker -> {output_dir / 'run_complete.json'} "
          f"({scored_games} games scored)")


if __name__ == "__main__":
    main()
