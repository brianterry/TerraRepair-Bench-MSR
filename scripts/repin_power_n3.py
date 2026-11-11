"""
Re-pin the paired oracle-vs-random RR power under OBSERVED per-cell generation
noise and the n=3 replication scheme. Arithmetic only — no inference.

Two independent variance sources add in the paired per-module difference d_i:

  (1) BETWEEN-MODULE paired variance  — the module-to-module spread of the
      oracle-random RR difference, from the correlation-aware pin
      (/tmp/paired_power_final.json, 6-model). This is the structural term that
      the ±0.032 pin captured, measured on the recorded refresh games (effectively
      1 draw/cell but on the FULL 6-model data where module-level pairing already
      cancels shared difficulty).
  (2) PER-CELL GENERATION NOISE — new, from the Phase-1 smoke: repeated/independent
      generations of the SAME (module,model,arm) differ (temp-0 nondeterminism).
      Averaging n=3 draws per cell shrinks this by 1/sqrt(3) in SD. It enters the
      paired difference through BOTH arms (oracle cell + random cell), so it adds
      as 2 * (cell_noise_var / n) under independence of the two arms' draws.

Re-pinned half-width (per-module paired diff, then /sqrt(n_modules)):
    sd_d_effective = sqrt( sd_between^2  +  2 * sd_cell^2 / n_draws )
    half_width     = 1.96 * sd_d_effective / sqrt(n_modules)

We report RR (the primary divergence contrast). n_modules = 192 (retrievable set,
the primary ablation target), vs the 232 of the original pin.
"""
from __future__ import annotations

import glob
import json
import math
import statistics
from collections import defaultdict

SMOKE = "experiments/results/retrieval_ablation/games"
PIN = "/tmp/paired_power_final.json"
N_DRAWS = 3
N_MODULES_PRIMARY = 192
N_MODULES_PIN = 232
THRESHOLD = 0.05


def load_smoke():
    rows = []
    for fp in glob.glob(f"{SMOKE}/*.json"):
        d = json.load(open(fp))
        rows.append((d["module_id"], d["model_id"], d["retrieval_arm"],
                     d["repair_success_rate"], d["regression_rate"]))
    return rows


def per_cell_noise_sd(rows):
    """Estimate per-cell generation SD per model for RSR and RR.

    The smoke has 1 draw per (module,model,arm), so we cannot take a direct
    within-cell SD from it alone. We use the ACROSS-ARM spread within a
    (module,model) as an UPPER-BOUND proxy for generation noise (it bundles any
    true arm effect + noise; since the smoke shows no coherent arm effect and
    even reversed orderings, the spread is noise-dominated). We also fold in the
    determinism probe (deepseek-r1 RR 0.00<->0.50 on module_0008; 4-repeat
    module_0008: claude sd=0.00, nova-pro RSR sd=0.054 RR sd=0.0).

    Returns dict model -> (sd_rsr, sd_rr), plus a pooled conservative value.
    """
    by_cell = defaultdict(lambda: {"rsr": {}, "rr": {}})
    for mid, model, arm, rsr, rr in rows:
        by_cell[(mid, model)]["rsr"][arm] = rsr
        by_cell[(mid, model)]["rr"][arm] = rr

    # per (module,model) across-arm SD, then average within model
    model_rsr_sds = defaultdict(list)
    model_rr_sds = defaultdict(list)
    for (mid, model), v in by_cell.items():
        rs = list(v["rsr"].values())
        rr = list(v["rr"].values())
        if len(rs) >= 2:
            model_rsr_sds[model].append(statistics.pstdev(rs))
            model_rr_sds[model].append(statistics.pstdev(rr))
    out = {}
    for model in model_rsr_sds:
        out[model] = (statistics.mean(model_rsr_sds[model]),
                      statistics.mean(model_rr_sds[model]))
    return out


def main():
    rows = load_smoke()
    noise = per_cell_noise_sd(rows)

    print("=== observed per-cell noise proxy (across-arm SD within module,model) ===")
    print(f"{'model':<18}{'RSR sd':>9}{'RR sd':>9}")
    for m, (srsr, srr) in sorted(noise.items()):
        print(f"{m:<18}{srsr:>9.3f}{srr:>9.3f}")

    # Pooled per-cell RR noise across the 6-model cohort. The smoke has 3 models;
    # use the mean of their RR SDs as the representative per-cell RR noise, and
    # also a CONSERVATIVE (max) variant since nova-pro/deepseek-r1 are volatile.
    rr_sds = [srr for (_, srr) in noise.values()]
    sd_cell_rr_mean = statistics.mean(rr_sds)
    sd_cell_rr_max = max(rr_sds)

    # Between-module structural SD of the paired diff, from the 6-model pin.
    pin = json.load(open(PIN))["6-model controlled"]
    hw_pin = pin["hw_normal"]          # 0.032 on n=232 stable cells
    n_pin = pin["n"]                   # 232
    sd_between = hw_pin * math.sqrt(n_pin) / 1.96   # recover per-module sd_d

    print(f"\n=== structural (between-module) paired-diff SD from pin ===")
    print(f"  pin half-width {hw_pin:.4f} on n={n_pin} -> sd_between(d) = {sd_between:.4f}")

    def repin(sd_cell_rr, n_draws, n_modules, label):
        # per-cell noise enters the paired diff via BOTH arms: 2 * var_cell/n
        sd_d_eff = math.sqrt(sd_between**2 + 2 * (sd_cell_rr**2) / n_draws)
        hw = 1.96 * sd_d_eff / math.sqrt(n_modules)
        margin = THRESHOLD - hw
        print(f"\n[{label}] sd_cell_RR={sd_cell_rr:.3f} n_draws={n_draws} "
              f"n_modules={n_modules}")
        print(f"  sd_d_effective = {sd_d_eff:.4f}  (vs structural {sd_between:.4f})")
        print(f"  re-pinned 95% half-width = +-{hw:.4f}")
        print(f"  vs +-0.05 threshold: margin {margin:+.4f}  "
              f"-> {'CLEARS' if hw < THRESHOLD else 'FAILS'}")
        return hw, margin

    print("\n================ RE-PINNED POWER (RR paired contrast) ================")
    # primary: n=3 draws, 192 modules, mean-noise and conservative-max-noise
    hw3_mean, m3_mean = repin(sd_cell_rr_mean, 3, N_MODULES_PRIMARY, "n=3, 192 mod, mean noise")
    hw3_max, m3_max = repin(sd_cell_rr_max, 3, N_MODULES_PRIMARY, "n=3, 192 mod, CONSERVATIVE max noise")
    # reference points
    repin(sd_cell_rr_mean, 1, N_MODULES_PRIMARY, "n=1, 192 mod, mean noise (what n=1 would give)")
    repin(sd_cell_rr_max, 5, N_MODULES_PRIMARY, "n=5, 192 mod, CONSERVATIVE max noise")

    # how many modules if n=3 conservative is borderline?
    if hw3_max >= THRESHOLD:
        sd_d_eff = math.sqrt(sd_between**2 + 2 * (sd_cell_rr_max**2) / 3)
        n_need = math.ceil((1.96 * sd_d_eff / THRESHOLD) ** 2)
        print(f"\n  [conservative] modules needed at n=3 for hw<=0.05: {n_need}")

    out = {
        "noise_by_model": {m: {"rsr_sd": s[0], "rr_sd": s[1]} for m, s in noise.items()},
        "sd_cell_rr_mean": sd_cell_rr_mean, "sd_cell_rr_max": sd_cell_rr_max,
        "sd_between_d": sd_between,
        "repin_n3_192_mean_hw": hw3_mean, "repin_n3_192_mean_margin": m3_mean,
        "repin_n3_192_max_hw": hw3_max, "repin_n3_192_max_margin": m3_max,
        "threshold": THRESHOLD,
        "original_pin_hw": hw_pin, "original_pin_n": n_pin,
    }
    json.dump(out, open("/tmp/repin_n3.json", "w"), indent=2)
    print("\nwrote /tmp/repin_n3.json")


if __name__ == "__main__":
    main()
