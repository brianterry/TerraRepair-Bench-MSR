"""
Analysis for the retrieval-relevance ablation (ECIR). Reads the per-game JSONs
written by run_retrieval_ablation.py and computes the six PRE-REGISTERED
analyses (see paper/PRE_REGISTRATION.md). Judge-free: every metric derives from
the deterministic delta-scorer set-diff already baked into each game file; this
script never recomputes that math, it only aggregates it.

Cell model (locked): each (module, model, arm) CELL value is the MEAN of its
available draws (n=3 nominal). The main run left 177 InvokeTimeout gaps, which
are arm-balanced; we treat missing draws as missing-at-random and average over
whatever draws landed. Completeness is reported so the reader sees the gaps.

Arms ladder: none < random < similarity < oracle.
  none       = closed-book lower bound
  random     = retrieval presence, no relevance
  similarity = Titan-embedding cosine relevance
  oracle     = resource/finding-type overlap upper bound (not inference-time)

Outputs a JSON blob (per-model + pooled arm metrics, dose-response, the primary
RR equivalence contrast with module-level bootstrap CI, the RSR-minus-RR
interaction contrast, the cross-model divergence read, the regression-locus
split, and the closed-book-vs-random presence test) to stdout and to
experiments/results/retrieval_ablation/analysis.json.

Usage: python3 scripts/analyze_retrieval_ablation.py
"""
from __future__ import annotations

import json
import os
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
ABL = ROOT / "experiments/results/retrieval_ablation"
GAMES = ABL / "games"

ARMS = ["none", "random", "similarity", "oracle"]
MODELS = ["grok-4-6", "claude-sonnet-5", "deepseek-r1",
          "claude-sonnet-4-5", "kimi-k2-5", "deepseek-v3-2"]
INDIFF = 0.05  # pre-registered equivalence indifference zone for the RR contrast
N_BOOT = 20000
RNG = np.random.default_rng(20270115)  # fixed seed -> reproducible CIs


# ---------- load ----------------------------------------------------------
def load_games() -> list[dict]:
    games = []
    for fn in os.listdir(GAMES):
        if not fn.endswith(".json"):
            continue
        try:
            games.append(json.loads((GAMES / fn).read_text()))
        except Exception as e:  # noqa: BLE001 - a corrupt file should be loud
            print(f"WARN: could not read {fn}: {e}", file=sys.stderr)
    return games


def _resource_names(findings: list[dict]) -> set[str]:
    return {f.get("resource_name", "") for f in findings}


def regression_locus(game: dict) -> tuple[int, int]:
    """Split a game's INTRODUCED findings into (model_added, existing_resource).

    An introduced finding on a resource_name NOT present in findings_before is a
    regression on a resource the model ADDED; one on a pre-existing resource_name
    is a single-knob regression on an EXISTING resource. Pre-reg analysis #5.
    """
    before_res = _resource_names(game.get("findings_before", []))
    before_keys = {(f.get("resource_name", ""), f.get("rule_id", ""))
                   for f in game.get("findings_before", [])}
    model_added = existing = 0
    for f in game.get("findings_after", []):
        key = (f.get("resource_name", ""), f.get("rule_id", ""))
        if key in before_keys:
            continue  # not introduced (was already there / unchanged)
        if f.get("resource_name", "") in before_res:
            existing += 1
        else:
            model_added += 1
    return model_added, existing


# ---------- cell aggregation ----------------------------------------------
def build_cells(games: list[dict]):
    """cell[(model,module,arm)] -> dict of mean metrics over available draws,
    plus summed regression-locus counts (counts summed, not averaged)."""
    bucket = defaultdict(list)
    locus = defaultdict(lambda: [0, 0])  # (model,module,arm) -> [added, existing]
    for g in games:
        key = (g["model_id"], g["module_id"], g["retrieval_arm"])
        bucket[key].append(g)
        ma, ex = regression_locus(g)
        locus[key][0] += ma
        locus[key][1] += ex
    cells = {}
    for key, gl in bucket.items():
        rsr = np.mean([g["repair_success_rate"] for g in gl])
        rr = np.mean([g["regression_rate"] for g in gl])
        nd = np.mean([g["net_delta"] for g in gl])
        cells[key] = {
            "rsr": float(rsr), "rr": float(rr), "net_delta": float(nd),
            "n_draws": len(gl),
            "reg_model_added": locus[key][0], "reg_existing": locus[key][1],
        }
    return cells


# ---------- bootstrap helpers ---------------------------------------------
def module_bootstrap_ci(per_module_vals: np.ndarray, n_boot=N_BOOT, alpha=0.05):
    """Module-level (cluster) bootstrap of the mean. Resamples MODULES, which
    respects the within-module pairing / ICC the pre-reg power pin relies on."""
    vals = np.asarray(per_module_vals, dtype=float)
    vals = vals[~np.isnan(vals)]
    if len(vals) == 0:
        return (float("nan"), float("nan"), float("nan"))
    means = np.empty(n_boot)
    n = len(vals)
    for b in range(n_boot):
        idx = RNG.integers(0, n, n)
        means[b] = vals[idx].mean()
    lo, hi = np.percentile(means, [100 * alpha / 2, 100 * (1 - alpha / 2)])
    return (float(vals.mean()), float(lo), float(hi))


# ---------- per-model / pooled arm metrics --------------------------------
def arm_metrics(cells, models):
    """Mean RSR/RR/NetD per arm over the given models, with module-level CIs.
    Per-arm per-module value = mean over the included models' cells for that
    (module,arm) so bootstrap resamples modules, not model*module pseudo-reps."""
    # modules present
    modules = sorted({k[1] for k in cells})
    out = {}
    for arm in ARMS:
        rsr_m, rr_m, nd_m = [], [], []
        for mod in modules:
            rs = [cells[(mdl, mod, arm)]["rsr"] for mdl in models
                  if (mdl, mod, arm) in cells]
            rr = [cells[(mdl, mod, arm)]["rr"] for mdl in models
                  if (mdl, mod, arm) in cells]
            nd = [cells[(mdl, mod, arm)]["net_delta"] for mdl in models
                  if (mdl, mod, arm) in cells]
            if rs:
                rsr_m.append(np.mean(rs)); rr_m.append(np.mean(rr)); nd_m.append(np.mean(nd))
        out[arm] = {
            "rsr": module_bootstrap_ci(np.array(rsr_m)),
            "rr": module_bootstrap_ci(np.array(rr_m)),
            "net_delta": module_bootstrap_ci(np.array(nd_m)),
            "n_modules": len(rsr_m),
        }
    return out


# ---------- primary RR equivalence contrast (oracle vs random) ------------
def rr_equivalence_contrast(cells, models):
    """Pre-reg primary #1. Per module (pooled over models): oracle RR = min arm
    RR across the retrieval arms is NOT what pre-reg says — pre-reg defines, per
    module: oracle = oracle-arm RR, random = random-arm RR, paired difference
    (oracle - random). Negative => oracle reduces regressions. 95% module
    bootstrap CI vs +-INDIFF."""
    modules = sorted({k[1] for k in cells})
    diffs = []
    for mod in modules:
        orc = [cells[(mdl, mod, "oracle")]["rr"] for mdl in models
               if (mdl, mod, "oracle") in cells]
        rnd = [cells[(mdl, mod, "random")]["rr"] for mdl in models
               if (mdl, mod, "random") in cells]
        if orc and rnd:
            diffs.append(np.mean(orc) - np.mean(rnd))
    mean, lo, hi = module_bootstrap_ci(np.array(diffs))
    # equivalence: CI entirely within +-INDIFF  => flat (divergence/null branch)
    equivalent = (lo > -INDIFF) and (hi < INDIFF)
    # directional help: hi < 0 => oracle significantly reduces RR
    helps = hi < 0
    hurts = lo > 0
    return {"mean": mean, "ci": [lo, hi], "n_modules": len(diffs),
            "indifference": INDIFF, "equivalent_within_zone": equivalent,
            "oracle_reduces_rr": helps, "oracle_increases_rr": hurts}


# ---------- RSR dose-response ladder --------------------------------------
def rsr_dose_response(cells, models):
    """Pre-reg primary #2. Mean RSR per arm (module-bootstrap) + monotonicity
    check none<=random<=similarity<=oracle and the oracle-none paired lift."""
    am = arm_metrics(cells, models)
    means = [am[a]["rsr"][0] for a in ARMS]
    monotone = all(means[i] <= means[i + 1] + 1e-9 for i in range(len(means) - 1))
    # paired oracle-none lift per module
    modules = sorted({k[1] for k in cells})
    lift = []
    for mod in modules:
        orc = [cells[(mdl, mod, "oracle")]["rsr"] for mdl in models if (mdl, mod, "oracle") in cells]
        non = [cells[(mdl, mod, "none")]["rsr"] for mdl in models if (mdl, mod, "none") in cells]
        if orc and non:
            lift.append(np.mean(orc) - np.mean(non))
    return {"arm_means": dict(zip(ARMS, means)), "monotone": monotone,
            "oracle_minus_none_lift": module_bootstrap_ci(np.array(lift))}


# ---------- interaction contrast: RSR effect minus RR effect --------------
def interaction_contrast(cells, models):
    """Pre-reg #3. Per module: (oracle-none RSR gain) - (none-oracle RR change
    i.e. the RR 'protection'). We register the magnitude asymmetry: does
    relevance move RSR more than it moves RR? Report both effects and their
    paired difference with a module bootstrap CI."""
    modules = sorted({k[1] for k in cells})
    rsr_eff, rr_eff, inter = [], [], []
    for mod in modules:
        def arm_mean(arm, metric):
            vs = [cells[(mdl, mod, arm)][metric] for mdl in models if (mdl, mod, arm) in cells]
            return np.mean(vs) if vs else np.nan
        ro, rn = arm_mean("oracle", "rsr"), arm_mean("none", "rsr")
        rro, rrn = arm_mean("oracle", "rr"), arm_mean("none", "rr")
        if np.isnan([ro, rn, rro, rrn]).any():
            continue
        e_rsr = ro - rn           # + => relevance improves repair
        e_rr = rrn - rro          # + => relevance reduces regressions (protection)
        rsr_eff.append(e_rsr); rr_eff.append(e_rr); inter.append(e_rsr - e_rr)
    return {"rsr_effect": module_bootstrap_ci(np.array(rsr_eff)),
            "rr_protection_effect": module_bootstrap_ci(np.array(rr_eff)),
            "interaction_rsr_minus_rr": module_bootstrap_ci(np.array(inter))}


# ---------- closed-book vs random (presence, not relevance) ---------------
def presence_contrast(cells, models):
    """Pre-reg #6. random - none, per module, both metrics. Isolates the effect
    of retrieval PRESENCE (random exemplars) before relevance enters."""
    modules = sorted({k[1] for k in cells})
    d_rsr, d_rr = [], []
    for mod in modules:
        def am(arm, metric):
            vs = [cells[(mdl, mod, arm)][metric] for mdl in models if (mdl, mod, arm) in cells]
            return np.mean(vs) if vs else np.nan
        rn, nn = am("random", "rsr"), am("none", "rsr")
        rrn, rnn = am("random", "rr"), am("none", "rr")
        if not np.isnan([rn, nn, rrn, rnn]).any():
            d_rsr.append(rn - nn); d_rr.append(rrn - rnn)
    return {"random_minus_none_rsr": module_bootstrap_ci(np.array(d_rsr)),
            "random_minus_none_rr": module_bootstrap_ci(np.array(d_rr))}


# ---------- regression-locus split ----------------------------------------
def locus_split(games):
    """Pre-reg #5. Of all INTRODUCED regressions, what fraction are on
    model-added resources vs existing resources, overall and per arm?"""
    tot = defaultdict(lambda: [0, 0])  # arm -> [added, existing]
    for g in games:
        ma, ex = regression_locus(g)
        tot[g["retrieval_arm"]][0] += ma
        tot[g["retrieval_arm"]][1] += ex
    allp = [sum(v[0] for v in tot.values()), sum(v[1] for v in tot.values())]
    def frac(added, existing):
        t = added + existing
        return {"model_added": added, "existing": existing,
                "pct_model_added": (added / t if t else float("nan"))}
    return {"overall": frac(*allp),
            "by_arm": {a: frac(*tot[a]) for a in ARMS if a in tot}}


# ---------- completeness ---------------------------------------------------
def completeness(cells):
    per_model_arm = defaultdict(lambda: defaultdict(int))
    for (mdl, mod, arm) in cells:
        per_model_arm[mdl][arm] += 1
    modules = sorted({k[1] for k in cells})
    exp = len(modules)
    return {"n_modules": exp,
            "per_model_arm_cells": {m: dict(per_model_arm[m]) for m in MODELS},
            "note": f"expected {exp} (module,arm) cells per (model,arm); "
                    f"a cell exists if >=1 of its 3 draws landed"}


def fmt_ci(t):
    m, lo, hi = t
    return f"{m:+.4f} [{lo:+.4f}, {hi:+.4f}]"


def main():
    games = load_games()
    print(f"loaded {len(games)} games", file=sys.stderr)
    cells = build_cells(games)
    models_present = [m for m in MODELS if any(k[0] == m for k in cells)]

    result = {
        "n_games": len(games),
        "models": models_present,
        "completeness": completeness(cells),
        "pooled_arm_metrics": arm_metrics(cells, models_present),
        "per_model_arm_metrics": {m: arm_metrics(cells, [m]) for m in models_present},
        "primary_rr_equivalence": rr_equivalence_contrast(cells, models_present),
        "primary_rsr_dose_response": rsr_dose_response(cells, models_present),
        "interaction": interaction_contrast(cells, models_present),
        "presence_contrast": presence_contrast(cells, models_present),
        "regression_locus": locus_split(games),
        "per_model_rr_equivalence": {
            m: rr_equivalence_contrast(cells, [m]) for m in models_present},
        "per_model_rsr_dose": {
            m: rsr_dose_response(cells, [m]) for m in models_present},
    }

    (ABL / "analysis.json").write_text(json.dumps(result, indent=2))

    # ---- human-readable summary to stdout ----
    print("\n==================== RETRIEVAL ABLATION ANALYSIS ====================")
    c = result["completeness"]
    print(f"games={len(games)}  modules={c['n_modules']}  models={len(models_present)}")
    print("\n-- pooled arm metrics (module-bootstrap 95% CI) --")
    pam = result["pooled_arm_metrics"]
    print(f"{'arm':11s} {'RSR':>26s} {'RR':>26s} {'NetDelta':>26s}")
    for a in ARMS:
        print(f"{a:11s} {fmt_ci(pam[a]['rsr']):>26s} {fmt_ci(pam[a]['rr']):>26s} "
              f"{fmt_ci(pam[a]['net_delta']):>26s}")

    dr = result["primary_rsr_dose_response"]
    print(f"\n-- RSR dose-response -- monotone={dr['monotone']}")
    print("   arm means:", {k: round(v, 4) for k, v in dr["arm_means"].items()})
    print("   oracle-none lift:", fmt_ci(dr["oracle_minus_none_lift"]))

    rr = result["primary_rr_equivalence"]
    print(f"\n-- PRIMARY: oracle-random RR contrast (indifference +-{INDIFF}) --")
    print(f"   mean paired diff = {fmt_ci((rr['mean'], *rr['ci']))}")
    print(f"   equivalent within zone = {rr['equivalent_within_zone']}  "
          f"oracle_reduces_rr = {rr['oracle_reduces_rr']}  "
          f"oracle_increases_rr = {rr['oracle_increases_rr']}")

    it = result["interaction"]
    print("\n-- interaction (RSR effect vs RR protection) --")
    print("   RSR effect (oracle-none):      ", fmt_ci(it["rsr_effect"]))
    print("   RR protection (none-oracle RR):", fmt_ci(it["rr_protection_effect"]))
    print("   interaction (RSR - RR):        ", fmt_ci(it["interaction_rsr_minus_rr"]))

    pc = result["presence_contrast"]
    print("\n-- presence (random - none) --")
    print("   RSR:", fmt_ci(pc["random_minus_none_rsr"]),
          "  RR:", fmt_ci(pc["random_minus_none_rr"]))

    rl = result["regression_locus"]
    print("\n-- regression locus (of introduced regressions) --")
    o = rl["overall"]
    print(f"   overall: {o['pct_model_added']*100:.1f}% model-added "
          f"({o['model_added']} added / {o['existing']} existing)")

    print("\n-- per-model RSR dose-response (monotone?) + oracle-none lift --")
    for m in models_present:
        d = result["per_model_rsr_dose"][m]
        print(f"   {m:20s} monotone={str(d['monotone']):5s} "
              f"means={{" + ", ".join(f'{k}:{v:.2f}' for k,v in d['arm_means'].items()) + "}}"
              f"  lift={fmt_ci(d['oracle_minus_none_lift'])}")

    print("\n-- per-model oracle-random RR contrast --")
    for m in models_present:
        e = result["per_model_rr_equivalence"][m]
        print(f"   {m:20s} {fmt_ci((e['mean'], *e['ci'])):>26s} "
              f"equiv={e['equivalent_within_zone']} reduces={e['oracle_reduces_rr']}")

    print(f"\nwrote {ABL/'analysis.json'}")


if __name__ == "__main__":
    main()
