#!/usr/bin/env python3
"""Paired bootstrap confidence intervals for a TerraRepair-Bench run.

Reproduces the per-model CIs and pairwise comparisons reported for
release_slice_2026-10. Stdlib only (no numpy/scipy needed).

Method
  - Unit of resampling: module. Modules are resampled with replacement and the
    SAME resample is applied to every model (paired bootstrap), because every
    model repaired the same corpus.
  - Only modules scored by ALL models are used (drops throttled/timed-out games).
  - Invalid HCL counts as a failed repair: net_delta = 0, repair rate = 0,
    zero resolved/introduced. (Modeling choice; see --exclude-invalid.)
  - Regression % is pooled: 100 * sum(introduced) / sum(target) over modules.
  - 95% percentile intervals. p-values are two-sided bootstrap sign tests.
    No multiple-comparison correction is applied.

Usage
  python scripts/bootstrap_ci.py
  python scripts/bootstrap_ci.py --run release_slice_2026-10 --B 5000 --seed 42
  python scripts/bootstrap_ci.py --pairs claude-sonnet-5:deepseek-r1 grok-4-6:kimi-k2-5
  python scripts/bootstrap_ci.py --json out.json
"""
import argparse
import glob
import json
import os
import random
import sys
from collections import defaultdict

METRICS = ("nd", "rsr", "regr", "rr", "anyreg")
LABELS = {"nd": "net delta", "rsr": "repair rate", "regr": "pooled regression %", "rr": "mean regression rate", "anyreg": "share of games with any regression"}


def load(run_dir, exclude_invalid):
    data = defaultdict(dict)
    files = glob.glob(os.path.join(run_dir, "games", "*.json"))
    if not files:
        sys.exit(f"no game files under {run_dir}/games")
    for f in files:
        with open(f) as fh:
            d = json.load(fh)
        valid = d.get("hcl_valid", True)
        if exclude_invalid and not valid:
            continue
        data[d["model_id"]][d["module_id"]] = {
            "nd": d["net_delta"] if valid else 0.0,
            "rsr": d["repair_success_rate"] if valid else 0.0,
            "rr": d["regression_rate"] if valid else 0.0,
            "intro": d["introduced_count"] if valid else 0,
            "tgt": d["target_count"],
            "anyreg": 1 if (valid and d["introduced_count"] > 0) else 0,
        }
    return data


def stat(data, model, mods, key):
    rows = [data[model][m] for m in mods]
    if key == "regr":
        tgt = sum(r["tgt"] for r in rows)
        return 100.0 * sum(r["intro"] for r in rows) / max(tgt, 1)
    return sum(r[key] for r in rows) / len(rows)


def pct_ci(values, alpha=0.05):
    s = sorted(values)
    n = len(s)
    return s[int((alpha / 2) * n)], s[int((1 - alpha / 2) * n) - 1]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--run", default="release_slice_2026-10")
    ap.add_argument("--results", default=os.path.join(os.path.dirname(__file__), "..", "experiments", "results"))
    ap.add_argument("--B", type=int, default=5000)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--exclude-invalid", action="store_true",
                    help="drop invalid-HCL games instead of scoring them as failed repairs")
    ap.add_argument("--pairs", nargs="*", default=None,
                    help="model pairs A:B for net-delta comparisons (default: adjacent pairs in the top 4)")
    ap.add_argument("--json", default=None, help="write all results to this JSON file")
    args = ap.parse_args()

    data = load(os.path.join(args.results, args.run), args.exclude_invalid)
    models = sorted(data)
    common = sorted(set.intersection(*[set(data[m]) for m in models]))
    n = len(common)

    rng = random.Random(args.seed)
    resamples = [[common[rng.randrange(n)] for _ in range(n)] for _ in range(args.B)]

    per_model = {}
    for m in models:
        per_model[m] = {}
        for k in METRICS:
            point = stat(data, m, common, k)
            lo, hi = pct_ci([stat(data, m, r, k) for r in resamples])
            per_model[m][k] = {"point": point, "lo": lo, "hi": hi}

    order = sorted(models, key=lambda m: -per_model[m]["nd"]["point"])

    if args.pairs:
        pairs = [tuple(p.split(":", 1)) for p in args.pairs]
    else:
        pairs = [(order[0], order[1]), (order[0], order[2]), (order[1], order[2]), (order[2], order[3])]

    comparisons = []
    for a, b in pairs:
        if a not in data or b not in data:
            sys.exit(f"unknown model in pair {a}:{b}; known: {', '.join(models)}")
        point = stat(data, a, common, "nd") - stat(data, b, common, "nd")
        diffs = [stat(data, a, r, "nd") - stat(data, b, r, "nd") for r in resamples]
        lo, hi = pct_ci(diffs)
        p = 2 * min(sum(x <= 0 for x in diffs), sum(x >= 0 for x in diffs)) / args.B
        comparisons.append({"a": a, "b": b, "metric": "nd", "diff": point, "lo": lo, "hi": hi,
                            "p": min(p, 1.0), "significant": lo > 0 or hi < 0})

    # The model with the highest regression rate vs the next two, under both
    # definitions: pooled (sum introduced / sum target) and mean per game
    # (the RR column of the paper's per-model table).
    for metric in ("regr", "rr"):
        ranked = sorted(models, key=lambda m: -per_model[m][metric]["point"])
        a = ranked[0]
        for b in ranked[1:3]:
            point = stat(data, a, common, metric) - stat(data, b, common, metric)
            diffs = [stat(data, a, r, metric) - stat(data, b, r, metric) for r in resamples]
            lo, hi = pct_ci(diffs)
            comparisons.append({"a": a, "b": b, "metric": metric, "diff": point, "lo": lo, "hi": hi,
                                "significant": lo > 0 or hi < 0})

    invalid_mode = "excluded" if args.exclude_invalid else "scored as failed repair"
    print(f"run={args.run}  modules={n}  B={args.B}  seed={args.seed}  invalid HCL: {invalid_mode}\n")
    print(f"{'model':18}{'net delta [95% CI]':>24}{'repair rate [95% CI]':>26}{'regr % [95% CI]':>22}")
    for m in order:
        r = per_model[m]
        print(f"{m:18}"
              f"{r['nd']['point']:7.2f} [{r['nd']['lo']:5.2f},{r['nd']['hi']:5.2f}]    "
              f"{r['rsr']['point']:6.3f} [{r['rsr']['lo']:.3f},{r['rsr']['hi']:.3f}]   "
              f"{r['regr']['point']:5.1f} [{r['regr']['lo']:4.1f},{r['regr']['hi']:4.1f}]")
    print("\nPaired differences:")
    for c in comparisons:
        unit = " pts" if c["metric"] == "regr" else ""
        fmt = "+.3f" if c["metric"] == "rr" else "+.2f"
        ptxt = f"  p~{c['p']:.3f}" if "p" in c else ""
        print(f"  [{LABELS[c['metric']]}] {c['a']} - {c['b']}: {c['diff']:{fmt}}{unit} "
              f"[{c['lo']:{fmt}},{c['hi']:{fmt}}]{ptxt}  {'SIG' if c['significant'] else 'n.s.'}")

    if args.json:
        with open(args.json, "w") as fh:
            json.dump({"run": args.run, "modules": n, "B": args.B, "seed": args.seed,
                       "invalid_hcl": invalid_mode, "per_model": per_model,
                       "comparisons": comparisons}, fh, indent=2)
        print(f"\nwrote {args.json}")


if __name__ == "__main__":
    main()
