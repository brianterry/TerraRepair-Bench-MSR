"""
Retrieval-relevance ablation runner.

For each (target module, model, arm) runs the SAME scored repair pipeline as the
main experiment — repair_module -> ScannerStack.run_checked -> score_repair —
varying ONLY the few-shot retrieval arm:

  none        : no exemplars (reproduces the baseline prompt byte-for-byte)
  random      : K random hardened exemplars
  similarity  : top-K by Titan-embedding cosine
  oracle      : top-K by resource-type / finding-type overlap heuristic

Writes one per-game JSON per (module, model, arm) to
experiments/results/retrieval_ablation/games/<module>_<model>_<arm>.json.
Resumable (skips existing). Does NOT modify delta-scorer math.

Usage:
  python3 scripts/run_retrieval_ablation.py --models deepseek-r1,claude-sonnet-4-5,nova-pro \
      --arms none,random,similarity,oracle --k 2 --max-modules 5   # smoke
  (omit --max-modules for the full target set)
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

import boto3
from botocore.config import Config as BotoConfig

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from src.repair.repair_agent import repair_module  # noqa: E402
from src.scanning.scanner_normalizer import ScannerStack  # noqa: E402
from src.scoring.delta_scorer import score_repair  # noqa: E402
from src.utils.bedrock_client import BedrockClient, InvokeTimeout, ThrottlingError  # noqa: E402
from src.retrieval.retriever import Retriever, format_exemplars  # noqa: E402
from src.utils.repair_artifacts import write_repair_sidecars  # noqa: E402

SAMPLE = ROOT / "data" / "terrads_sample"
ABL = ROOT / "experiments/results/retrieval_ablation"


def _finding_to_dict(f):
    return {"tool": f.tool, "rule_id": f.rule_id, "title": f.title,
            "severity": f.severity, "resource_name": f.resource_name,
            "resource_type": f.resource_type, "file_path": f.file_path,
            "start_line": f.start_line, "end_line": f.end_line}


def _game_result_to_dict(g) -> dict:
    """Serialize a GameResult identically to the main runner (same fields), so
    ablation games are schema-compatible with report_final.py / analysis."""
    return {
        "module_id": g.module_id, "model_id": g.model_id,
        "findings_before": [_finding_to_dict(f) for f in g.findings_before],
        "findings_after": [_finding_to_dict(f) for f in g.findings_after],
        "target_count": g.target_count, "resolved_count": g.resolved_count,
        "introduced_count": g.introduced_count, "unchanged_count": g.unchanged_count,
        "repair_success_rate": g.repair_success_rate,
        "regression_rate": g.regression_rate, "net_delta": g.net_delta,
        "class_breakdown": g.class_breakdown, "repair_cost_usd": g.repair_cost_usd,
        "repair_tokens": g.repair_tokens, "hcl_valid": g.hcl_valid,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", required=True, help="comma-separated model ids")
    ap.add_argument("--arms", default="none,random,similarity,oracle")
    ap.add_argument("--k", type=int, default=2, help="exemplars per retrieval arm")
    ap.add_argument("--max-modules", type=int, default=None, help="cap targets (smoke)")
    ap.add_argument("--max-tokens", type=int, default=16384)
    ap.add_argument("--region", default="us-east-1")
    ap.add_argument("--draws", type=int, default=3,
                    help="replications per (module,model,arm) cell. Cell value is "
                         "the mean of the draws (computed at analysis time). Each "
                         "draw is a separate game file _d{N}.json. Default 3.")
    ap.add_argument("--concurrency", type=int, default=1,
                    help="parallel (module,model,arm,draw) units. Latency-bound; "
                         "4 is safe for all models' quotas on this account.")
    args = ap.parse_args()

    models = [m.strip() for m in args.models.split(",") if m.strip()]
    arms = [a.strip() for a in args.arms.split(",") if a.strip()]

    pool = json.loads((ABL / "hardened_pool.json").read_text())["module_ids"]
    targets = json.loads((ABL / "ablation_targets.json").read_text())["targets"]
    if args.max_modules:
        targets = targets[:args.max_modules]
    embeddings = json.loads((ABL / "embeddings_titan_v2.json").read_text())

    retriever = Retriever(SAMPLE, pool, embeddings)
    scanner = ScannerStack()
    bedrock = BedrockClient(region=args.region)

    games_dir = ABL / "games"
    games_dir.mkdir(parents=True, exist_ok=True)

    # Pre-scan each target ONCE to get pre-repair findings (shared across arms &
    # models). These define target_count and the oracle's finding-bearing types.
    print(f"pre-scanning {len(targets)} targets...")
    pre: dict[str, list] = {}
    for mid in targets:
        res = scanner.run_checked(str(SAMPLE / mid))
        pre[mid] = res.findings  # trust corpus membership; findings for scoring

    def run_cell(mid: str, model_id: str, arm: str, draw: int) -> str:
        """One (module,model,arm,draw) unit. Writes _d{draw}.json. Returns status.
        Each cell writes its OWN file -> safe to run in parallel threads."""
        gf = games_dir / f"{mid}_{model_id}_{arm}_d{draw}.json"
        if gf.exists():
            return "resumed"
        findings_before = pre[mid]
        finding_types = {f.resource_type for f in findings_before}
        if arm == "none":
            block, exemplars = "", []
        else:
            exemplars = retriever.select(arm, mid, finding_types, args.k)
            block = format_exemplars(SAMPLE, exemplars)
        try:
            result = repair_module(
                module_dir=str(SAMPLE / mid), findings=findings_before,
                model_id=model_id, bedrock_client=bedrock,
                max_tokens=args.max_tokens, exemplar_block=block,
            )
        except (ThrottlingError, InvokeTimeout) as e:
            print(f"[skip] {mid}/{model_id}/{arm}/d{draw}: {type(e).__name__}")
            return "skip"
        findings_after = []
        scan_failed = None
        if result.repaired_dir:
            try:
                after = scanner.run_checked(result.repaired_dir)
                findings_after = after.findings
                if not after.ok:
                    scan_failed = after.failures
            finally:
                shutil.rmtree(result.repaired_dir, ignore_errors=True)
        if scan_failed:
            print(f"[skip] {mid}/{model_id}/{arm}/d{draw}: post-scan failed {scan_failed}")
            return "scan_failed"
        game = score_repair(
            module_id=mid, model_id=model_id,
            findings_before=findings_before, findings_after=findings_after,
            repair_result=result,
        )
        gd = _game_result_to_dict(game)
        gd["retrieval_arm"] = arm
        gd["retrieved_exemplars"] = exemplars
        gd["exemplar_count"] = len(exemplars)
        gd["draw"] = draw
        # Persist the model output (sidecars BEFORE the game JSON resume marker).
        gd.update(write_repair_sidecars(gf, result))
        gf.write_text(json.dumps(gd, indent=2))
        print(f"{mid}/{model_id}/{arm}/d{draw} "
              f"RSR={game.repair_success_rate:.2f} RR={game.regression_rate:.2f} "
              f"hcl={game.hcl_valid}", flush=True)
        return "scored"

    # Full work list: every (module, model, arm, draw) unit.
    work = [(mid, model_id, arm, draw)
            for mid in targets
            for model_id in models
            for arm in arms
            for draw in range(1, args.draws + 1)]
    total = len(work)
    print(f"ablation work units: {total} "
          f"({len(targets)} modules x {len(models)} models x {len(arms)} arms "
          f"x {args.draws} draws)")

    concurrency = max(1, args.concurrency)
    if concurrency == 1:
        for mid, model_id, arm, draw in work:
            run_cell(mid, model_id, arm, draw)
    else:
        from concurrent.futures import ThreadPoolExecutor, as_completed
        print(f"[concurrency] {concurrency} parallel units")
        with ThreadPoolExecutor(max_workers=concurrency) as pool_ex:
            futs = [pool_ex.submit(run_cell, *w) for w in work]
            for fut in as_completed(futs):
                exc = fut.exception()
                if exc is not None:
                    print(f"[worker-error] {exc!r}", flush=True)

    print(f"\nablation games -> {games_dir}")


if __name__ == "__main__":
    main()
