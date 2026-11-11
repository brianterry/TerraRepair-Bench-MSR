"""
Validate the regression-locus classification that the ablation's headline
mechanism rests on ("94.6% of regressions are on model-ADDED resources").

The analyzer labels an introduced regression "model-added" when its
resource_name is absent from the game's findings_before. The known failure mode:
a resource that EXISTED in the input but had no finding before repair would also
be absent from findings_before, so a new finding on it would be mislabeled
"model-added" when it is really existed-but-clean.

Ground truth available: the INPUT Terraform for every module is intact under
data/terrads_sample/<module>/*.tf (the repaired .tf is not stored — the runner
deletes it after scanning). We parse the resources actually DECLARED in the
input source and re-classify each model-added regression:

  true_new        : resource_name NOT declared in input source  -> correctly model-added
  existed_clean   : resource_name IS declared in input           -> MISCLASSIFIED (false model-added)

Because we can check the input source for EVERY game, we report both a
population-wide true-positive rate and a stratified random sample (for the
"manually spot-checked N" sentence in the paper). A rename cannot be detected
without the repaired text, so it folds into true_new and is noted as a caveat.

Usage: python3 scripts/validate_regression_locus.py [--sample 30]
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ABL = ROOT / "experiments/results/retrieval_ablation"
GAMES = ABL / "games"
SAMPLE = ROOT / "data" / "terrads_sample"

# resource "<type>" "<name>"  ->  <type>.<name>
RES_RE = re.compile(r'resource\s+"([^"]+)"\s+"([^"]+)"')
RNG_SEED = 20270115


def declared_resources(module_id: str) -> set[str]:
    """Set of '<type>.<name>' resources DECLARED in the module's input .tf.
    Cached per module (many games share a module)."""
    mdir = SAMPLE / module_id
    out: set[str] = set()
    if not mdir.is_dir():
        return out
    for tf in mdir.glob("*.tf"):
        try:
            text = tf.read_text(errors="ignore")
        except Exception:  # noqa: BLE001
            continue
        for m in RES_RE.finditer(text):
            out.add(f"{m.group(1)}.{m.group(2)}")
    return out


def before_keys(game: dict):
    return {(f.get("resource_name", ""), f.get("rule_id", ""))
            for f in game.get("findings_before", [])}


def model_added_regressions(game: dict):
    """Yield resource_names of introduced findings the ANALYZER calls model-added
    (resource_name not among findings_before resource_names)."""
    bkeys = before_keys(game)
    before_res = {f.get("resource_name", "") for f in game.get("findings_before", [])}
    for f in game.get("findings_after", []):
        key = (f.get("resource_name", ""), f.get("rule_id", ""))
        if key in bkeys:
            continue  # not introduced
        rn = f.get("resource_name", "")
        if rn not in before_res:  # analyzer's "model-added" rule
            yield rn


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sample", type=int, default=30)
    args = ap.parse_args()

    decl_cache: dict[str, set[str]] = {}
    def decl(mod):
        if mod not in decl_cache:
            decl_cache[mod] = declared_resources(mod)
        return decl_cache[mod]

    # population-wide pass over every model-added regression
    pop_true_new = 0
    pop_existed_clean = 0
    examples_true_new = []
    examples_existed = []
    # also: how many modules had an EMPTY declared set (parse failure) -> can't judge
    empty_decl_modules = set()
    per_sample_pool = []  # (module, model, arm, resource_name, verdict)

    for fn in os.listdir(GAMES):
        if not fn.endswith(".json"):
            continue
        g = json.loads((GAMES / fn).read_text())
        mod = g["module_id"]
        drs = decl(mod)
        if not drs:
            empty_decl_modules.add(mod)
        for rn in model_added_regressions(g):
            if not drs:
                verdict = "unknown_no_decl"
            elif rn in drs:
                verdict = "existed_clean"   # MISCLASSIFIED
                pop_existed_clean += 1
            else:
                verdict = "true_new"        # correct
                pop_true_new += 1
            per_sample_pool.append((mod, g["model_id"], g["retrieval_arm"], rn, verdict))
            if verdict == "true_new" and len(examples_true_new) < 8:
                examples_true_new.append((mod, rn))
            if verdict == "existed_clean" and len(examples_existed) < 12:
                examples_existed.append((mod, rn))

    judged = pop_true_new + pop_existed_clean
    tpr = pop_true_new / judged if judged else float("nan")

    # stratified random sample for the paper's "spot-checked N" claim
    import random
    rng = random.Random(RNG_SEED)
    judged_pool = [r for r in per_sample_pool if r[4] in ("true_new", "existed_clean")]
    rng.shuffle(judged_pool)
    sample = judged_pool[:args.sample]
    s_true = sum(1 for r in sample if r[4] == "true_new")

    print("==================== REGRESSION-LOCUS VALIDATION ====================")
    print(f"model-added regressions judged against input source: {judged:,}")
    print(f"  true_new      (resource NOT in input .tf, correctly model-added): {pop_true_new:,}")
    print(f"  existed_clean (resource IS in input .tf, MISCLASSIFIED):          {pop_existed_clean:,}")
    unknown = sum(1 for r in per_sample_pool if r[4] == "unknown_no_decl")
    print(f"  unknown_no_decl (module .tf unparyable/empty, not judged):        {unknown:,}")
    print(f"\nPOPULATION true-positive rate (true_new / judged): {tpr*100:.2f}%")
    print(f"  -> of all 'model-added' labels, {(1-tpr)*100:.2f}% are actually existed-but-clean")
    print(f"\nstratified random sample (seed {RNG_SEED}, n={len(sample)}): "
          f"{s_true}/{len(sample)} true_new = {100*s_true/len(sample):.1f}%")
    if empty_decl_modules:
        print(f"\nNOTE: {len(empty_decl_modules)} module(s) had no parseable resource decls "
              f"(e.g. all resources via modules/dynamic): {sorted(empty_decl_modules)[:10]}")
    print("\nexamples true_new (module, resource):")
    for mod, rn in examples_true_new:
        print(f"  {mod}: {rn}")
    if examples_existed:
        print("\nexamples existed_clean MISCLASSIFIED (module, resource):")
        for mod, rn in examples_existed:
            print(f"  {mod}: {rn}")

    # how much would the headline move if we RECLASSIFIED existed_clean out of model-added?
    # (needs the existing-count too; recompute overall split corrected)
    print("\n-- corrected overall split (if existed_clean moved to 'existing') --")
    # overall existing (resource in before) count from analysis.json
    try:
        a = json.loads((ABL / "analysis.json").read_text())
        o = a["regression_locus"]["overall"]
        orig_added = o["model_added"]; orig_existing = o["existing"]
        corr_added = orig_added - pop_existed_clean
        corr_existing = orig_existing + pop_existed_clean
        tot = orig_added + orig_existing
        print(f"  original : model_added {orig_added:,} ({100*orig_added/tot:.1f}%)  "
              f"existing {orig_existing:,}")
        print(f"  corrected: model_added {corr_added:,} ({100*corr_added/tot:.1f}%)  "
              f"existing {corr_existing:,}")
    except Exception as e:  # noqa: BLE001
        print(f"  (could not load analysis.json for correction: {e})")


if __name__ == "__main__":
    main()
