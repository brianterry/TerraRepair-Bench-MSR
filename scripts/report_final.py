"""
Final paper-reporting generator (stdlib only).

Reads the recorded per-game JSONs and emits the locked-headline reporting:
  * per-model RSR / RR / NetDelta / output-ceiling / cost, ranked by NetDelta,
    over BOTH the full scored set and the capacity-controlled subset;
  * the capacity-control robustness result (ranking stable off the controlled
    subset => frontier advantage is skill, not output budget);
  * the retired reasoning-vs-non-reasoning note (negligible effect, d ~ -0.1).

This is a REPORTING tool. It does NOT touch the delta-scorer set-diff math and
does NOT run inference. It applies the same two already-decided corrections the
analyzer uses — HCL-invalid games score 0/0/0 (null model), and claude-sonnet-4
is excluded (Legacy access, not a repair result) — then adds the capacity
column + capacity-controlled subset the headline analysis established.

Every number traces to the game JSONs under --games.

Usage:
  python3 scripts/report_final.py --games <games_dir> --out <out_dir>
"""
from __future__ import annotations

import argparse
import glob
import json
import math
import os
import statistics
from pathlib import Path

# ---------------------------------------------------------------------------
# Fixed metadata (confirmed; see src/utils/bedrock_client._MODEL_MAX_TOKENS and
# the 2026-09-30 live maxTokens probes recorded in METHODOLOGY/HEADLINE_ANALYSIS)
# ---------------------------------------------------------------------------

EXCLUDED_MODELS = {"claude-sonnet-4"}  # Legacy on eval account: access errors, not repairs

# Confirmed per-model output-token ceiling (the model's true API limit). For
# grok/sonnet-5/sonnet-4-5 the API accepts >=100K; the run applied a lower
# nominal budget (40K recovery / 64K clamp) that still exceeded any observed
# need. For the rest the ceiling IS the applied budget (hard model limit).
OUTPUT_CEILING = {
    "grok-4-6": ">=100000",
    "claude-sonnet-5": ">=100000",
    "claude-sonnet-4-5": ">=100000",
    "deepseek-r1": "32768",
    "qwen3-32b": "16384",
    "deepseek-v3-2": "16384",
    "kimi-k2-5": "16384",
    "nova-pro": "10000",
    "nova-lite": "10000",
    "llama-3-3-70b": "8192",
}

# Applied nominal budget during the run (for the provenance footnote).
APPLIED_BUDGET = {
    "grok-4-6": 40000, "claude-sonnet-5": 40000, "deepseek-r1": 40000,
    "claude-sonnet-4-5": 40000,  # the four re-run/added models
    "nova-pro": 16384, "nova-lite": 16384, "llama-3-3-70b": 16384,
    "qwen3-32b": 16384, "deepseek-v3-2": 16384, "kimi-k2-5": 16384,
}

REASONING_MODELS = {
    "deepseek-r1", "qwen3-32b", "claude-sonnet-5",
    "deepseek-v3-2", "kimi-k2-5", "grok-4-6",
}


# ---------------------------------------------------------------------------
# Metric helpers (null-model HCL rule; no change to set-diff math)
# ---------------------------------------------------------------------------

def corrected(d: dict) -> tuple[float, float, float]:
    """(RSR, RR, NetDelta) under the §3.3 HCL rule: invalid HCL => 0/0/0."""
    if not d.get("hcl_valid", True):
        return 0.0, 0.0, 0.0
    return d["repair_success_rate"], d["regression_rate"], float(d["net_delta"])


def mean(xs: list[float]) -> float:
    return statistics.mean(xs) if xs else 0.0


def pstd(xs: list[float]) -> float:
    return statistics.pstdev(xs) if xs else 0.0


def _norm_cdf(x: float) -> float:
    return 0.5 * (1 + math.erf(x / math.sqrt(2)))


def ttest_p(a: list[float], b: list[float]) -> float:
    if len(a) < 2 or len(b) < 2:
        return float("nan")
    ma, mb = statistics.mean(a), statistics.mean(b)
    va, vb = statistics.variance(a), statistics.variance(b)
    na, nb = len(a), len(b)
    sp2 = ((na - 1) * va + (nb - 1) * vb) / (na + nb - 2)
    den = math.sqrt(sp2 * (1 / na + 1 / nb))
    if den == 0:
        return float("nan")
    t = (ma - mb) / den
    return 2 * (1 - _norm_cdf(abs(t)))


def cohens_d(a: list[float], b: list[float]) -> float:
    if len(a) < 2 or len(b) < 2:
        return 0.0
    va, vb = statistics.variance(a), statistics.variance(b)
    pooled = math.sqrt((va + vb) / 2)
    return (statistics.mean(a) - statistics.mean(b)) / pooled if pooled else 0.0


# ---------------------------------------------------------------------------
# Capacity control
# ---------------------------------------------------------------------------

def module_source_chars(games: list[dict]) -> dict[str, int]:
    """Prefer failure_metadata.source_chars; fall back to reading module dir."""
    chars: dict[str, int] = {}
    for g in games:
        fm = g.get("failure_metadata") or {}
        if fm.get("source_chars") and g["module_id"] not in chars:
            chars[g["module_id"]] = fm["source_chars"]
    for mid in {g["module_id"] for g in games}:
        if mid not in chars:
            tfs = glob.glob(f"data/terrads_sample/{mid}/*.tf")
            chars[mid] = sum(os.path.getsize(f) for f in tfs) if tfs else 0
    return chars


def capacity_controlled_modules(games: list[dict], cohort: set[str]) -> tuple[set[str], set[str]]:
    """A module is capacity-controlled iff NO cohort model (a) had a size-driven
    failure on it, or (b) is missing a game for it (wall-clock timeout). Returns
    (controlled, pressured)."""
    all_mods = {g["module_id"] for g in games}
    present: dict[str, set[str]] = {m: set() for m in cohort}
    sizedriven: dict[str, set[str]] = {m: set() for m in cohort}
    for g in games:
        m = g["model_id"]
        if m not in cohort:
            continue
        present[m].add(g["module_id"])
        fm = g.get("failure_metadata") or {}
        if fm.get("size_driven_failure"):
            sizedriven[m].add(g["module_id"])
    pressured = set()
    for mid in all_mods:
        for m in cohort:
            if mid in sizedriven[m] or mid not in present[m]:
                pressured.add(mid)
                break
    return all_mods - pressured, pressured


# ---------------------------------------------------------------------------

def per_model(games: list[dict], subset: set[str] | None = None) -> dict[str, dict]:
    agg: dict[str, dict] = {}
    for g in games:
        m = g["model_id"]
        if m in EXCLUDED_MODELS:
            continue
        if subset is not None and g["module_id"] not in subset:
            continue
        rsr, rr, nd = corrected(g)
        a = agg.setdefault(m, {"rsr": [], "rr": [], "nd": [], "cost": 0.0})
        a["rsr"].append(rsr)
        a["rr"].append(rr)
        a["nd"].append(nd)
        a["cost"] += g.get("repair_cost_usd", 0.0)
    out = {}
    for m, a in agg.items():
        out[m] = {
            "n": len(a["rsr"]),
            "rsr_mean": mean(a["rsr"]), "rsr_std": pstd(a["rsr"]),
            "rr_mean": mean(a["rr"]), "rr_std": pstd(a["rr"]),
            "nd_mean": mean(a["nd"]), "nd_std": pstd(a["nd"]),
            "cost_usd": round(a["cost"], 2),
            "output_ceiling": OUTPUT_CEILING.get(m, "?"),
            "applied_budget": APPLIED_BUDGET.get(m, "?"),
        }
    return out


def reasoning_split(games: list[dict], subset: set[str] | None = None):
    r, nr = [], []
    for g in games:
        m = g["model_id"]
        if m in EXCLUDED_MODELS:
            continue
        if subset is not None and g["module_id"] not in subset:
            continue
        _, rr, _ = corrected(g)
        (r if m in REASONING_MODELS else nr).append(rr)
    return {
        "reasoning_rr": mean(r), "reasoning_n": len(r),
        "non_reasoning_rr": mean(nr), "non_reasoning_n": len(nr),
        "gap": mean(nr) - mean(r),
        "p_value": ttest_p(r, nr),
        "cohens_d": cohens_d(r, nr),
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--games", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    games = [json.loads(Path(f).read_text())
             for f in sorted(glob.glob(f"{args.games}/*.json"))]
    cohort = {g["model_id"] for g in games} - EXCLUDED_MODELS

    controlled, pressured = capacity_controlled_modules(games, cohort)
    chars = module_source_chars(games)

    full = per_model(games)
    ctrl = per_model(games, subset=controlled)
    reason_full = reasoning_split(games)
    reason_ctrl = reasoning_split(games, subset=controlled)

    report = {
        "corpus": {
            "total_modules": len({g["module_id"] for g in games}),
            "capacity_controlled_modules": len(controlled),
            "pressured_modules": len(pressured),
            "controlled_median_chars": sorted(chars[m] for m in controlled)[len(controlled) // 2],
            "pressured_median_chars": (sorted(chars[m] for m in pressured)[len(pressured) // 2]
                                       if pressured else 0),
        },
        "excluded_models": sorted(EXCLUDED_MODELS),
        "per_model_full": full,
        "per_model_controlled": ctrl,
        "reasoning_full": reason_full,
        "reasoning_controlled": reason_ctrl,
    }
    (out_dir / "report_final.json").write_text(json.dumps(report, indent=2))

    # LaTeX main table (ranked by NetDelta on the full set).
    order = sorted(full, key=lambda m: -full[m]["nd_mean"])
    tex = [r"\begin{tabular}{lccccr}", r"\toprule",
           r"Model & RSR & RR & Net $\Delta$ & Out. ceiling & Cost (\$) \\",
           r"\midrule"]
    for m in order:
        s = full[m]
        tex.append(f"{m} & {s['rsr_mean']:.2f} & {s['rr_mean']:.2f} & "
                   f"{s['nd_mean']:.1f} & {s['output_ceiling']} & {s['cost_usd']:.2f} \\\\")
    tex += [r"\bottomrule", r"\end{tabular}"]
    (out_dir / "table_main_results.tex").write_text("\n".join(tex))

    print(f"Final report written to {out_dir}")
    print(f"  modules {report['corpus']['total_modules']} -> controlled {len(controlled)}")
    print(f"  reasoning gap full d={reason_full['cohens_d']:.3f} / controlled d={reason_ctrl['cohens_d']:.3f}")


if __name__ == "__main__":
    main()
