"""
Phase-1 smoke test: prove the 10-model wiring holds on a SMALL slice before
committing to the ~3-day full run.

Runs 5-10 modules x all 10 models, single-pass, temperature 0, into a throwaway
dir (experiments/results/_smoke/). For each model it reports the PASS/FAIL
columns the refresh spec asks for:

  endpoint  - did the Bedrock endpoint resolve (correct CRIS prefix / access)?
  hcl       - did at least one repair parse as valid HCL?
  think     - was a thinking delimiter stripped when present (reasoning models)?
  cost      - is a real (non-default) MODEL_COSTS entry producing $/module > 0?
  scanner   - did BOTH scanners run (not silently fail) on at least one scan?

REQUIRES a live environment: AWS Bedrock credentials + region, and Trivy +
Checkov installed. It cannot run offline; run it on the remote instance. The
offline-checkable parts of the wiring are covered by tests/test_model_wiring_2026.py.

Usage:
  python3 scripts/smoke_test.py --config experiments/configs/full_refresh_2026.yaml \
      --region us-east-1 --n-modules 8
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from collections import defaultdict
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.repair.repair_agent import MODEL_COSTS, repair_module
from src.scanning.scanner_normalizer import ScannerStack
from src.scoring.corpus_filter import in_corpus
from src.utils.bedrock_client import SUPPORTED_MODELS, BedrockClient, ThrottlingError

REASONING = {"deepseek-r1", "qwen3-32b", "claude-sonnet-5", "deepseek-v3-2",
             "kimi-k2-5", "grok-4-6"}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--region", default="us-east-1")
    ap.add_argument("--n-modules", type=int, default=8)
    ap.add_argument("--out", default="experiments/results/_smoke")
    args = ap.parse_args()

    config = yaml.safe_load(open(args.config))
    models = [m["id"] for m in config["models"]]
    corpus_dir = Path(config["corpus"]["dir"])
    out_dir = Path(args.out)
    if out_dir.exists():
        shutil.rmtree(out_dir)
    (out_dir / "games").mkdir(parents=True, exist_ok=True)

    scanner = ScannerStack()
    bedrock = BedrockClient(region=args.region)

    # Build a small in-band slice.
    slice_mods = []
    for d in sorted(corpus_dir.iterdir()):
        if len(slice_mods) >= args.n_modules:
            break
        if not (d.is_dir() and list(d.glob("*.tf"))):
            continue
        scan = scanner.run_checked(str(d))
        if not scan.ok:
            continue
        n = len({(f.rule_id, f.resource_name) for f in scan.findings})
        if in_corpus(n):
            slice_mods.append((str(d), scan.findings, scan.ok))

    print(f"[smoke] {len(slice_mods)} modules x {len(models)} models\n")

    # Per-model accumulators for the PASS/FAIL table.
    stat = {m: {"endpoint": False, "hcl": False, "think": None, "cost": 0.0,
                "scanner_ok": False, "errors": []} for m in models}

    for module_dir, findings_before, before_ok in slice_mods:
        module_id = Path(module_dir).name
        for model_id in models:
            try:
                result = repair_module(
                    module_dir=module_dir, findings=findings_before,
                    model_id=model_id, bedrock_client=bedrock,
                )
                stat[model_id]["endpoint"] = True  # a response came back
                stat[model_id]["cost"] += result.repair_cost_usd
                if result.hcl_valid:
                    stat[model_id]["hcl"] = True
                # thinking-strip check: if the raw response carried a reasoning
                # block, the sanitized repaired_code must not contain it.
                if model_id in REASONING and result.repaired_code:
                    had = any(t in (result.repaired_code or "")
                              for t in ("<think>", "<thinking>", "<reasoning>"))
                    stat[model_id]["think"] = "LEAK" if had else "clean"
                if result.repaired_dir:
                    after = scanner.run_checked(result.repaired_dir)
                    if after.ok:
                        stat[model_id]["scanner_ok"] = True
                    shutil.rmtree(result.repaired_dir, ignore_errors=True)
            except ThrottlingError as e:
                stat[model_id]["errors"].append(f"throttled: {e}")
            except Exception as e:  # noqa: BLE001
                stat[model_id]["errors"].append(f"{type(e).__name__}: {e}")

    # Also record whether the pre-repair scanner ran on the slice at all.
    scanner_ran = any(ok for _, _, ok in slice_mods)

    # ---- PASS/FAIL table ----
    def mark(b: bool) -> str:
        return "PASS" if b else "FAIL"

    print(f"{'model':<18}{'endpoint':>9}{'hcl':>6}{'think':>8}{'cost$':>9}{'scanner':>9}")
    print("-" * 60)
    all_pass = True
    report = {}
    for m in models:
        s = stat[m]
        cost_ok = s["cost"] > 0 and MODEL_COSTS.get(m) not in (None, )
        think_col = "-" if s["think"] is None else s["think"]
        row_ok = s["endpoint"] and s["hcl"] and cost_ok and (s["scanner_ok"] or scanner_ran) \
            and s["think"] != "LEAK"
        all_pass = all_pass and row_ok
        print(f"{m:<18}{mark(s['endpoint']):>9}{mark(s['hcl']):>6}{think_col:>8}"
              f"{s['cost']:>9.4f}{mark(s['scanner_ok']):>9}")
        report[m] = {
            "endpoint": s["endpoint"], "hcl_valid_seen": s["hcl"],
            "thinking": think_col, "cost_usd": round(s["cost"], 4),
            "scanner_ok": s["scanner_ok"], "row_pass": row_ok,
            "bedrock_id": SUPPORTED_MODELS.get(m, "?"),
            "errors": s["errors"][:3],
        }

    (out_dir / "smoke_report.json").write_text(json.dumps({
        "n_modules": len(slice_mods), "models": models,
        "scanner_ran": scanner_ran, "all_pass": all_pass, "per_model": report,
    }, indent=2))
    print("\n" + ("ALL MODELS PASS" if all_pass else "SOME MODELS FAILED — see errors below"))
    for m in models:
        if report[m]["errors"]:
            print(f"  {m}: {report[m]['errors']}")
    print(f"\nReport -> {out_dir / 'smoke_report.json'}")
    sys.exit(0 if all_pass else 1)


if __name__ == "__main__":
    main()
