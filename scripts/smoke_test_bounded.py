"""
Bounded, instrumented Phase-1 smoke test.

Same intent as smoke_test.py (prove the 10-model wiring on a small slice) but
hardened against the failure we hit: one slow/hanging model invocation blocking
the whole sequential run for 45+ minutes. Differences:

  * short per-call read timeout + fewer retries (fail fast, don't wedge)
  * per-(model,module) result written to disk IMMEDIATELY (incremental), so a
    timeout still leaves a usable partial PASS/FAIL table
  * live per-call stdout line (model, module, ok/err, seconds)
  * resumable: skips (model,module) pairs already recorded

REQUIRES live Bedrock + Trivy + Checkov. Writes to experiments/results/_smoke/.

Usage:
  export PATH="$HOME/Library/Python/3.9/bin:$PATH"
  python3 scripts/smoke_test_bounded.py \
    --config experiments/configs/full_refresh_2026.yaml \
    --region us-east-1 --n-modules 3 --read-timeout 90 --max-retries 1
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.repair.repair_agent import MODEL_COSTS, repair_module
from src.scanning.scanner_normalizer import ScannerStack
from src.scoring.corpus_filter import in_corpus
from src.utils import bedrock_client as bc
from src.utils.bedrock_client import SUPPORTED_MODELS, BedrockClient, ThrottlingError

REASONING = {"deepseek-r1", "qwen3-32b", "claude-sonnet-5", "deepseek-v3-2",
             "kimi-k2-5", "grok-4-6"}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--region", default="us-east-1")
    ap.add_argument("--n-modules", type=int, default=3)
    ap.add_argument("--read-timeout", type=int, default=90,
                    help="per-call Bedrock read timeout (s); fail fast")
    ap.add_argument("--max-retries", type=int, default=1,
                    help="throttle retry budget per call (small for smoke)")
    ap.add_argument("--max-tokens", type=int, default=1024,
                    help="cap output tokens for the SMOKE so calls finish fast. "
                         "A full repair needs the model's real ceiling; the "
                         "smoke only proves endpoint/route/parse, not a complete "
                         "repair, so a small cap is intentional.")
    ap.add_argument("--out", default="experiments/results/_smoke")
    ap.add_argument("--models", default=None,
                    help="CSV of model ids to restrict the smoke to (default: all in config)")
    args = ap.parse_args()

    config = yaml.safe_load(open(args.config))
    models = [m["id"] for m in config["models"]]
    if args.models:
        want = {m.strip() for m in args.models.split(",")}
        models = [m for m in models if m in want]
    corpus_dir = Path(config["corpus"]["dir"])
    out_dir = Path(args.out)
    (out_dir / "calls").mkdir(parents=True, exist_ok=True)

    scanner = ScannerStack()
    # Fail-fast client: short read timeout, single botocore attempt; our own
    # _with_retry budget is tiny for the smoke so one bad model can't wedge it.
    bedrock = BedrockClient(region=args.region, read_timeout=args.read_timeout)

    # small in-band slice
    slice_mods = []
    print("[smoke] building slice...", flush=True)
    for d in sorted(corpus_dir.iterdir()):
        if len(slice_mods) >= args.n_modules:
            break
        if not (d.is_dir() and list(d.glob("*.tf"))):
            continue
        scan = scanner.run_checked(str(d))
        if scan.ok and in_corpus(len({(f.rule_id, f.resource_name) for f in scan.findings})):
            slice_mods.append((str(d), scan.findings))
    print(f"[smoke] {len(slice_mods)} modules x {len(models)} models "
          f"= {len(slice_mods) * len(models)} calls\n", flush=True)

    def call_path(model_id: str, module_id: str) -> Path:
        return out_dir / "calls" / f"{module_id}__{model_id}.json"

    for model_id in models:
        for module_dir, findings_before in slice_mods:
            module_id = Path(module_dir).name
            cp = call_path(model_id, module_id)
            if cp.exists():
                continue  # resume
            rec = {"model": model_id, "module": module_id,
                   "bedrock_id": SUPPORTED_MODELS.get(model_id, "?")}
            t0 = time.monotonic()
            try:
                # tiny retry budget for smoke
                orig = bedrock._with_retry
                bedrock._with_retry = (
                    lambda mid, fn, **_: orig(mid, fn, max_attempts=args.max_retries + 1,
                                              base_delay=1.0)
                )
                result = repair_module(module_dir=module_dir, findings=findings_before,
                                       model_id=model_id, bedrock_client=bedrock,
                                       max_tokens=args.max_tokens)
                dt = time.monotonic() - t0
                after_ok = None
                if result.repaired_dir:
                    a = scanner.run_checked(result.repaired_dir)
                    after_ok = a.ok
                    shutil.rmtree(result.repaired_dir, ignore_errors=True)
                leak = (result.repaired_code and any(
                    t in result.repaired_code for t in ("<think>", "<thinking>", "<reasoning>")))
                rec.update({
                    "ok": True, "seconds": round(dt, 1),
                    "hcl_valid": result.hcl_valid,
                    "cost_usd": round(result.repair_cost_usd, 5),
                    "tokens": result.repair_prompt_tokens + result.repair_completion_tokens,
                    "think_leak": bool(leak) if model_id in REASONING else None,
                    "scanner_after_ok": after_ok,
                    "error": result.error,
                })
                print(f"  {model_id:<16} {module_id:<14} ok "
                      f"hcl={result.hcl_valid} {dt:5.1f}s ${result.repair_cost_usd:.4f}",
                      flush=True)
            except ThrottlingError as e:
                rec.update({"ok": False, "seconds": round(time.monotonic() - t0, 1),
                            "error": f"throttled: {e}"})
                print(f"  {model_id:<16} {module_id:<14} THROTTLED", flush=True)
            except Exception as e:  # noqa: BLE001
                rec.update({"ok": False, "seconds": round(time.monotonic() - t0, 1),
                            "error": f"{type(e).__name__}: {e}"})
                print(f"  {model_id:<16} {module_id:<14} ERR {type(e).__name__}: "
                      f"{str(e)[:80]}", flush=True)
            finally:
                bedrock._with_retry = orig
            cp.write_text(json.dumps(rec, indent=2))

    _summarize(out_dir, models)


def _summarize(out_dir: Path, models: list[str]) -> None:
    """Aggregate per-call records into the per-model PASS/FAIL table.
    Callable standalone after a partial run."""
    calls = [json.loads(p.read_text()) for p in (out_dir / "calls").glob("*.json")]
    by_model: dict[str, list[dict]] = {m: [] for m in models}
    for c in calls:
        by_model.setdefault(c["model"], []).append(c)

    print(f"\n{'model':<16}{'endpoint':>9}{'hcl':>6}{'think':>8}{'cost$':>9}{'scan':>6}{'calls':>7}")
    print("-" * 62)
    report = {}
    for m in models:
        cs = by_model.get(m, [])
        endpoint = any(c.get("ok") for c in cs)
        hcl = any(c.get("hcl_valid") for c in cs)
        leak = any(c.get("think_leak") for c in cs)
        cost = sum(c.get("cost_usd") or 0 for c in cs)
        scan_ok = any(c.get("scanner_after_ok") for c in cs)
        think = "-" if m not in REASONING else ("LEAK" if leak else "clean")
        def mk(b):
            return "PASS" if b else "FAIL"
        print(f"{m:<16}{mk(endpoint):>9}{mk(hcl):>6}{think:>8}{cost:>9.4f}"
              f"{mk(scan_ok):>6}{len(cs):>7}")
        report[m] = {"endpoint": endpoint, "hcl": hcl, "think": think,
                     "cost_usd": round(cost, 4), "scanner_ok": scan_ok,
                     "n_calls": len(cs),
                     "errors": [c["error"] for c in cs if c.get("error")][:3]}
    (out_dir / "smoke_report.json").write_text(json.dumps(report, indent=2))
    print(f"\nReport -> {out_dir / 'smoke_report.json'}")
    for m in models:
        if report[m]["errors"]:
            print(f"  {m} errors: {report[m]['errors']}")


if __name__ == "__main__":
    main()
