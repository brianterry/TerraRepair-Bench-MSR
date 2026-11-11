"""
Corrected results regenerator (stdlib only — no numpy/scipy required).

Regenerates results_summary.json and Table 1/2/3 from EXISTING recorded game
JSONs, applying the two audit corrections:

  1. Corpus filter (§3.1)  — keep only modules with 3 <= target_count <= 50,
     via the single source of truth src/scoring/corpus_filter.py (Fix 1 /
     Finding A).

  2. HCL-invalid re-scoring — a game with hcl_valid == False is re-scored to
     resolved=0 / introduced=0 / net_delta=0 / RSR=0 / RR=0, regardless of the
     stored scalars. The recorded JSONs predate delta_scorer's guard and 9
     invalid-HCL games are mis-credited; here we recompute from the rule rather
     than trusting the stored fields (Fix 2 / Claim 3).

It does NOT modify delta_scorer's set-diff math and does NOT run any model
inference. Original result files are never touched; corrected outputs go to a
new directory (default experiments/results/full_corrected/).

Usage:
  python3 scripts/analyze_corrected.py \
      --games experiments/results/full_180_game/games \
      --out   experiments/results/full_corrected
"""
from __future__ import annotations

import argparse
import json
import math
import random
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.scoring.corpus_filter import MAX_FINDINGS, MIN_FINDINGS, in_corpus

# Reasoning vs non-reasoning split for Table 3. Updated for the 2026 cohort
# (was {"deepseek-r1","qwen3-32b"} for the original 6-model set). Classification
# metadata only — does NOT affect delta-scorer set-diff math; it only partitions
# models for the reasoning-gap comparison. Source: experiments/configs/
# full_refresh_2026.yaml "reasoning:" flags + MODEL_COHORT_2026.md.
REASONING_MODELS = {
    "deepseek-r1", "qwen3-32b",            # original reasoning anchors
    "claude-sonnet-5", "deepseek-v3-2",    # 2026 reasoning
    "kimi-k2-5", "grok-4-6",
}
# Models excluded from the comparison entirely (not a repair result):
#   claude-sonnet-4 — Legacy on the eval account, all games ResourceNotFound.
EXCLUDED_MODELS = {"claude-sonnet-4"}


# ---------------------------------------------------------------------------
# Correction 2: HCL-invalid re-scoring (does not touch delta_scorer math)
# ---------------------------------------------------------------------------

def corrected_metrics(game: dict) -> dict:
    """
    Return a game's metrics under the paper §3.3 HCL rule.

    For hcl_valid == False, force the null-model attribution (0 resolved,
    0 introduced, ND 0, RSR 0, RR 0). Otherwise use the stored scalars, which
    the audit verified are exactly the set-diff of the stored finding lists.
    """
    if not game.get("hcl_valid", True):
        return {
            "repair_success_rate": 0.0,
            "regression_rate": 0.0,
            "net_delta": 0,
            "resolved_count": 0,
            "introduced_count": 0,
            "hcl_zeroed": True,
        }
    return {
        "repair_success_rate": game["repair_success_rate"],
        "regression_rate": game["regression_rate"],
        "net_delta": game["net_delta"],
        "resolved_count": game["resolved_count"],
        "introduced_count": game["introduced_count"],
        "hcl_zeroed": False,
    }


# ---------------------------------------------------------------------------
# Stdlib stats helpers (replace numpy/scipy)
# ---------------------------------------------------------------------------

def bootstrap_ci(data: list[float], n_boot: int = 1000, ci: float = 0.95,
                 seed: int = 42) -> tuple[float, float]:
    if not data:
        return 0.0, 0.0
    rng = random.Random(seed)
    n = len(data)
    means = []
    for _ in range(n_boot):
        sample = [data[rng.randrange(n)] for _ in range(n)]
        means.append(sum(sample) / n)
    means.sort()
    lo = means[int((1 - ci) / 2 * n_boot)]
    hi = means[int((1 + ci) / 2 * n_boot) - 1]
    return lo, hi


def welch_or_pooled_ttest(a: list[float], b: list[float]) -> float:
    """Two-sample t-test p-value (pooled-variance, two-sided) via a normal
    approximation for the p-value. Sufficient for reporting an order of
    magnitude; the audit's headline does not hinge on the exact p."""
    if len(a) < 2 or len(b) < 2:
        return float("nan")
    ma, mb = statistics.mean(a), statistics.mean(b)
    va, vb = statistics.variance(a), statistics.variance(b)
    na, nb = len(a), len(b)
    sp2 = ((na - 1) * va + (nb - 1) * vb) / (na + nb - 2)
    denom = math.sqrt(sp2 * (1 / na + 1 / nb))
    if denom == 0:
        return float("nan")
    t = (ma - mb) / denom
    # two-sided p via survival function of standard normal (large-df approx)
    p = 2 * (1 - _norm_cdf(abs(t)))
    return p


def cohens_d(a: list[float], b: list[float]) -> float:
    if len(a) < 2 or len(b) < 2:
        return 0.0
    va, vb = statistics.variance(a), statistics.variance(b)
    pooled = math.sqrt((va + vb) / 2)
    if pooled == 0:
        return 0.0
    return (statistics.mean(a) - statistics.mean(b)) / pooled


def _norm_cdf(x: float) -> float:
    return 0.5 * (1 + math.erf(x / math.sqrt(2)))


def pstd(data: list[float]) -> float:
    return statistics.pstdev(data) if len(data) >= 1 else 0.0


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def load_games(games_dir: Path) -> list[dict]:
    return [json.loads(f.read_text()) for f in sorted(games_dir.glob("*.json"))]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--games", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--no-corpus-filter", action="store_true",
                    help="skip §3.1 filter (for A/B comparison only)")
    args = ap.parse_args()

    games_dir = Path(args.games)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    all_games = load_games(games_dir)

    # Exclude models that are not a repair result (e.g. Legacy-blocked access).
    # Done BEFORE corpus/HCL corrections so excluded models never enter any
    # table or the reasoning split. Count what we drop for provenance.
    n_before_exclude = len(all_games)
    excluded_counts: dict[str, int] = {}
    kept_games = []
    for g in all_games:
        mid = g.get("model_id")
        if mid in EXCLUDED_MODELS:
            excluded_counts[mid] = excluded_counts.get(mid, 0) + 1
        else:
            kept_games.append(g)
    all_games = kept_games

    # Correction 1: corpus filter (single source of truth)
    if args.no_corpus_filter:
        games = all_games
    else:
        games = [g for g in all_games if in_corpus(g["target_count"])]

    kept_modules = sorted({g["module_id"] for g in games})
    dropped_modules = sorted({g["module_id"] for g in all_games} - set(kept_modules))
    hcl_zeroed_games = []

    by_model: dict[str, list[dict]] = {}
    for g in games:
        by_model.setdefault(g["model_id"], []).append(g)

    summary: dict[str, dict] = {}
    for model_id, mgames in sorted(by_model.items()):
        rsr, rr, nd = [], [], []
        for g in mgames:
            cm = corrected_metrics(g)
            if cm["hcl_zeroed"] and (g["resolved_count"] or g["net_delta"]):
                hcl_zeroed_games.append(f"{g['module_id']}_{g['model_id']}")
            rsr.append(cm["repair_success_rate"])
            rr.append(cm["regression_rate"])
            nd.append(float(cm["net_delta"]))
        summary[model_id] = {
            "n": len(mgames),
            "repair_success_rate_mean": statistics.mean(rsr),
            "repair_success_rate_std": pstd(rsr),
            "repair_success_rate_ci": list(bootstrap_ci(rsr)),
            "regression_rate_mean": statistics.mean(rr),
            "regression_rate_std": pstd(rr),
            "regression_rate_ci": list(bootstrap_ci(rr)),
            "net_delta_mean": statistics.mean(nd),
            "net_delta_std": pstd(nd),
            "net_delta_ci": list(bootstrap_ci(nd)),
            "total_cost_usd": sum(g["repair_cost_usd"] for g in mgames),
        }

    (out_dir / "results_summary.json").write_text(json.dumps(summary, indent=2))

    # provenance / corpus manifest for this regeneration
    (out_dir / "corpus_manifest.json").write_text(json.dumps({
        "corpus_filter": {"min_findings": MIN_FINDINGS, "max_findings": MAX_FINDINGS,
                          "applied": not args.no_corpus_filter,
                          "basis": "scored target_count (deduped |before_keys|)"},
        "modules_before_filter": len({g["module_id"] for g in all_games}),
        "modules_after_filter": len(kept_modules),
        "trials_after_filter": len(games),
        "dropped_modules": dropped_modules,
        "hcl_invalid_games_rezeroed": sorted(hcl_zeroed_games),
        "hcl_rule": "hcl_valid==False => resolved=0/introduced=0/net=0/RSR=0/RR=0",
        "excluded_models": {m: excluded_counts.get(m, 0) for m in sorted(EXCLUDED_MODELS)},
        "excluded_models_reason": "not a repair result (e.g. Legacy access-blocked)",
        "games_before_model_exclude": n_before_exclude,
        "reasoning_models": sorted(REASONING_MODELS),
    }, indent=2))

    # Table 1
    t1 = [r"\begin{tabular}{lccc}", r"\toprule",
          r"Model & Repair Success Rate & Regression Rate & Net $\Delta$ \\", r"\midrule"]
    for mid, s in summary.items():
        t1.append(f"{mid} & {s['repair_success_rate_mean']:.2f} $\\pm$ {s['repair_success_rate_std']:.2f} & "
                  f"{s['regression_rate_mean']:.2f} $\\pm$ {s['regression_rate_std']:.2f} & "
                  f"{s['net_delta_mean']:.1f} $\\pm$ {s['net_delta_std']:.1f} \\\\")
    t1 += [r"\bottomrule", r"\end{tabular}"]
    (out_dir / "table1_main_results.tex").write_text("\n".join(t1))

    # Table 2: class breakdown (aggregate; unchanged games contribute stored breakdown,
    # invalid-HCL games contribute nothing under the null-model rule)
    class_totals: dict[str, dict] = {}
    for g in games:
        if not g.get("hcl_valid", True):
            continue  # null model: no resolved/introduced/unchanged credited
        for cls, counts in g.get("class_breakdown", {}).items():
            ct = class_totals.setdefault(cls, {"resolved": 0, "introduced": 0, "unchanged": 0})
            for k, v in counts.items():
                ct[k] += v
    t2 = [r"\begin{tabular}{lccc}", r"\toprule",
          r"Class & Resolved & Introduced & Unchanged \\", r"\midrule"]
    for cls, c in class_totals.items():
        t2.append(f"{cls} & {c['resolved']} & {c['introduced']} & {c['unchanged']} \\\\")
    t2 += [r"\bottomrule", r"\end{tabular}"]
    (out_dir / "table2_class_breakdown.tex").write_text("\n".join(t2))

    # Table 3: reasoning vs non-reasoning (corrected RR)
    r_rr, nr_rr = [], []
    for g in games:
        rr_val = corrected_metrics(g)["regression_rate"]
        (r_rr if g["model_id"] in REASONING_MODELS else nr_rr).append(rr_val)
    p = welch_or_pooled_ttest(r_rr, nr_rr)
    d = cohens_d(r_rr, nr_rr)
    t3 = [r"\begin{tabular}{lc}", r"\toprule", r"Metric & Value \\", r"\midrule",
          f"Reasoning mean regression rate & {statistics.mean(r_rr):.2f} \\\\",
          f"Non-reasoning mean regression rate & {statistics.mean(nr_rr):.2f} \\\\",
          f"Two-sample $t$-test $p$-value & {p:.4f} \\\\",
          f"Cohen's $d$ & {d:.2f} \\\\", r"\bottomrule", r"\end{tabular}"]
    (out_dir / "table3_reasoning_comparison.tex").write_text("\n".join(t3))

    print(f"Corrected results written to {out_dir}")
    if excluded_counts:
        print(f"  excluded models (not scored): {excluded_counts}")
    print(f"  modules: {len({g['module_id'] for g in all_games})} -> {len(kept_modules)} "
          f"(filter applied: {not args.no_corpus_filter})")
    print(f"  trials:  {len(all_games)} -> {len(games)}")
    print(f"  invalid-HCL games re-zeroed (were mis-credited): {len(hcl_zeroed_games)}")
    print(f"  reasoning RR={statistics.mean(r_rr):.3f}  non-reasoning RR={statistics.mean(nr_rr):.3f}")


if __name__ == "__main__":
    main()
