"""
Final correlation-aware power calculation for the oracle-vs-random paired RR
contrast. Reporting/analysis only — reads recorded game JSONs, no inference,
no change to delta-scorer math.

Design (locks the experiment size):
  * Unit of analysis = MODULE. For each module, over the arm set, define
      oracle_i = best (min) RR among arms on module i
      random_i = mean RR among arms on module i
      d_i      = oracle_i - random_i        (one value per module)
  * The paired difference is ONE number per module, so there is NO shared-arm
    pseudo-replication: n = number of modules, full stop. The arm count enters
    only by shaping oracle/random (reducing per-module variance), not by
    inflating N. This is the correlation-aware fix to the earlier naive
    effective-N = modules x pairs (which double-counted shared arms).

Half-width is estimated THREE ways so the number is not method-dependent:
  (A) paired normal-approx:        hw = 1.96 * sd(d) / sqrt(n)
  (B) module-level bootstrap CI:   resample modules with replacement; respects
      the real (non-normal, min-of-k) sampling distribution of mean(d).
  (C) variance-components check:   decompose arm RR into module (shared) vs
      residual to confirm pairing cancels the shared component.

min-of-k selection bias: the in-sample oracle (best arm chosen on the same data
it is scored on) is optimistic. (D) reports a CROSS-FITTED oracle — the oracle
arm is chosen on a random half of modules and evaluated on the other half — so
the reported contrast is not inflated by selection-on-the-same-data.
"""
from __future__ import annotations

import glob
import json
import math

import numpy as np

RNG = np.random.default_rng(42)
EXCLUDED = {"claude-sonnet-4"}

# The 6 models that already have refresh data (recovery trio + new anchor +
# the two OpenAI-path reasoning models), i.e. the proposed 6-model cohort.
SIX = ["grok-4-6", "claude-sonnet-5", "deepseek-r1",
       "claude-sonnet-4-5", "kimi-k2-5", "deepseek-v3-2"]
THREE = ["grok-4-6", "claude-sonnet-5", "deepseek-r1"]


def load_rr():
    rr = {}
    for fp in glob.glob("/tmp/final_games/*.json"):
        d = json.loads(open(fp).read())
        m = d["model_id"]
        if m in EXCLUDED:
            continue
        v = 0.0 if not d.get("hcl_valid", True) else d["regression_rate"]
        rr.setdefault(d["module_id"], {})[m] = v
    return rr


def build_matrix(rr, arms, modules):
    """rows = modules (with all arms present), cols = arms. Returns (M, mods)."""
    rows, kept = [], []
    for mid in modules:
        if all(a in rr[mid] for a in arms):
            rows.append([rr[mid][a] for a in arms]); kept.append(mid)
    return np.array(rows), kept


def paired_d(M):
    """One paired diff per module: oracle(min) - random(mean) across arm cols."""
    return M.min(axis=1) - M.mean(axis=1)


def hw_normal(d):
    n = len(d)
    return 1.96 * d.std(ddof=1) / math.sqrt(n)


def hw_bootstrap(d, nboot=20000):
    n = len(d)
    means = np.array([RNG.choice(d, n, replace=True).mean() for _ in range(nboot)])
    lo, hi = np.percentile(means, [2.5, 97.5])
    return (hi - lo) / 2, means.mean()


def variance_components(M):
    """Decompose arm RR into module (shared) + residual. ICC = shared fraction;
    the paired contrast cancels the shared (module) component."""
    grand = M.mean()
    mod_means = M.mean(axis=1)
    n_mod, n_arm = M.shape
    ss_between = n_arm * ((mod_means - grand) ** 2).sum()
    ss_within = ((M - mod_means[:, None]) ** 2).sum()
    ms_between = ss_between / (n_mod - 1)
    ms_within = ss_within / (n_mod * (n_arm - 1))
    var_module = max(0.0, (ms_between - ms_within) / n_arm)
    var_resid = ms_within
    icc = var_module / (var_module + var_resid) if (var_module + var_resid) else 0.0
    return icc, var_module, var_resid


def crossfit_oracle(M, nrep=2000):
    """Debiased oracle: choose oracle arm on a random half of modules, evaluate
    on the held-out half. Returns mean(d) and its half-width across repeats, so
    the oracle advantage is NOT inflated by selection-on-the-same-data."""
    n = M.shape[0]
    ds = []
    for _ in range(nrep):
        idx = RNG.permutation(n)
        a, b = idx[:n // 2], idx[n // 2:]
        oracle_arm = M[a].mean(axis=0).argmin()   # pick best arm on split A
        d_b = M[b, oracle_arm] - M[b].mean(axis=1)  # evaluate on split B
        ds.append(d_b.mean())
    ds = np.array(ds)
    return ds.mean(), ds.std()


def report(label, arms, rr, modules):
    M, kept = build_matrix(rr, arms, modules)
    n = len(kept)
    d = paired_d(M)
    md = d.mean()
    hwA = hw_normal(d)
    hwB, bmean = hw_bootstrap(d)
    icc, vm, vr = variance_components(M)
    cf_mean, cf_sd = crossfit_oracle(M)
    print(f"\n=== {label}: {len(arms)} arms x {n} modules ===")
    print(f"  mean paired d (oracle-random) = {md:.4f}   (bootstrap mean {bmean:.4f})")
    print(f"  (A) normal-approx half-width   = +-{hwA:.4f}")
    print(f"  (B) bootstrap    half-width    = +-{hwB:.4f}")
    print(f"  (C) ICC (shared module var frac)= {icc:.3f}  "
          f"[var_module={vm:.4f} var_resid={vr:.4f}] -> pairing cancels the shared part")
    print(f"  (D) cross-fitted oracle d      = {cf_mean:.4f} +- {1.96*cf_sd:.4f} "
          f"(debiased; not selection-inflated)")
    clears = max(hwA, hwB) < 0.05
    print(f"  --> clears +-0.05? {'YES' if clears else 'NO/BORDERLINE'} "
          f"(worst-of-A/B half-width {max(hwA,hwB):.4f}; margin {0.05-max(hwA,hwB):+.4f})")
    return {"n": n, "mean_d": md, "hw_normal": hwA, "hw_boot": hwB,
            "icc": icc, "crossfit_d": cf_mean, "crossfit_hw": 1.96 * cf_sd,
            "clears_05": clears}


def modules_needed(d, target=0.05):
    sd = d.std(ddof=1)
    return math.ceil((1.96 * sd / target) ** 2)


if __name__ == "__main__":
    rr = load_rr()
    controlled = set(json.load(open("/tmp/controlled_mods.json")))
    out = {}
    out["6-model controlled"] = report("6-MODEL (controlled)", SIX, rr, controlled)
    out["3-model controlled"] = report("3-MODEL (controlled)", THREE, rr, controlled)

    # modules needed at 6 arms to hit +-0.05 (normal approx), from observed sd(d)
    M6, _ = build_matrix(rr, SIX, controlled)
    d6 = paired_d(M6)
    print(f"\nmodules needed (6-arm, normal approx) for hw<=0.05: "
          f"{modules_needed(d6)} (have {len(d6)})")
    def _clean(o):
        if isinstance(o, dict):
            return {k: _clean(v) for k, v in o.items()}
        if isinstance(o, (np.bool_,)):
            return bool(o)
        if isinstance(o, (np.integer,)):
            return int(o)
        if isinstance(o, (np.floating,)):
            return float(o)
        return o
    json.dump(_clean(out), open("/tmp/paired_power_final.json", "w"), indent=2)
    print("\nwrote /tmp/paired_power_final.json")
