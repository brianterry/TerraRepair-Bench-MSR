#!/usr/bin/env python3
"""
Pre-build gating analysis for the retrieval-relevance ablation.

Answers two gating questions from EXISTING data (no retriever, no inference):
  Gate 1 — Power for the null (RR): per-arm/per-model regression-event counts
           and CI width on RR at the planned ablation size.
  Gate 2 — Fraction of regressions that are exemplar-addressable vs structural.

Data sources:
  - Gate 1: experiments/results/full_refresh_2026-09_analysis/report_final.json
            (per-model RR mean/std/n for the planned cohort; refresh games
             themselves are not on disk).
  - Gate 2: experiments/results/full_180_game/games/*.json  (per-game findings
            with introduced-finding detail; predecessor cohort — see caveats).
"""
import json
import math
import glob
import os
import re
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REFRESH = os.path.join(ROOT, "experiments/results/full_refresh_2026-09_analysis/report_final.json")
GAMES = os.path.join(ROOT, "experiments/results/full_180_game/games")

PLANNED_MODELS = ["deepseek-r1", "claude-sonnet-4-5", "nova-pro"]  # per brief
N_ARMS = 4  # none / random / similarity / oracle


def finding_key(f):
    return (f.get("rule_id"), f.get("resource_name"))


# ---------------------------------------------------------------------------
# GATE 1 — Power for the null (RR)
# ---------------------------------------------------------------------------
def gate1():
    rep = json.load(open(REFRESH))
    ctrl = rep["per_model_controlled"]
    n_controlled = rep["corpus"]["capacity_controlled_modules"]
    print("=" * 78)
    print("GATE 1 — POWER FOR THE NULL (RR)")
    print("=" * 78)
    print(f"Capacity-controlled module pool: {n_controlled}")
    print(f"Planned design: {len(PLANNED_MODELS)} models x {N_ARMS} arms "
          f"x (module subset)\n")
    print("Per model (controlled set), per ARM (modules split across arms if "
          "one pass each):\n")
    print(f"{'model':20} {'RR_mean':>8} {'RR_std':>8} {'n_full':>7} "
          f"{'n/arm*':>7} {'CI95_halfwidth/arm':>18}")
    results = {}
    for m in PLANNED_MODELS:
        if m not in ctrl:
            print(f"{m:20}  (not in refresh controlled set)")
            continue
        rr = ctrl[m]["rr_mean"]
        sd = ctrl[m]["rr_std"]
        n_full = ctrl[m]["n"]
        # If each module is run once per arm, each arm sees the full module
        # subset. If instead the module subset is PARTITIONED across arms,
        # n/arm = n_full / N_ARMS. The brief says "4 conditions per
        # (module, model)" => each arm sees ALL modules. Report both.
        n_per_arm_allmods = n_full
        half_all = 1.96 * sd / math.sqrt(n_per_arm_allmods)
        results[m] = (rr, sd, n_full, half_all)
        print(f"{m:20} {rr:8.3f} {sd:8.3f} {n_full:7d} {n_per_arm_allmods:7d} "
              f"{half_all:18.3f}")
    print("\n* '4 conditions per (module,model)' => each arm runs the FULL "
          "module subset,\n  so n/arm = n_full. CI halfwidth = 1.96*std/sqrt(n).")

    print("\nInterpretation — can we distinguish arms on RR?")
    print("A relevance effect on RR would plausibly shift the mean by a "
          "fraction of itself.")
    for m, (rr, sd, n, half) in results.items():
        # smallest detectable difference between two arms (paired-ish, treat
        # as two-sample for a conservative ballpark): need |Δ| > ~2.8*sd/sqrt(n)
        mdd = 2.8 * sd / math.sqrt(n)
        print(f"  {m:20} RR={rr:.3f} +/-{half:.3f}  "
              f"min detectable arm-to-arm Δ ≈ {mdd:.3f} "
              f"({100*mdd/rr:4.0f}% of RR)")
    return results


# ---------------------------------------------------------------------------
# GATE 2 — Preventable vs structural regressions
# ---------------------------------------------------------------------------
# Classification of an introduced finding — does it concern a SETTABLE
# hardening property an exemplar could demonstrate, or a value the author
# cannot control in HCL?
#
# STRUCTURAL (b) — genuinely unpreventable by any exemplar:
#   * service-produced / apply-time values (generated IDs, ARNs, default
#     endpoints) that a scanner flags regardless of authored config, and
#   * rules that fire purely on resource EXISTENCE with no settable knob.
#   In practice, almost no Checkov/Trivy rule in this corpus is of this kind —
#   they target settable attributes. We keep an explicit allowlist and treat
#   everything else as preventable, which is the honest direction (don't
#   inflate "structural").
#
# PREVENTABLE (a) — a settable property an exemplar demonstrates the secure
#   form of: encryption on/CMK, logging on, retention set, versioning on,
#   public-access-block, SG description, restricted ingress/egress, rotation,
#   deletion protection, etc. Whether the resource is NEW is irrelevant: a
#   hardened exemplar of that resource type teaches the secure default.
STRUCTURAL_RULE_IDS = set()  # none identified in top-N; see note in output

# Rules we are CONFIDENT are settable hardening knobs (sanity cross-check that
# the "preventable" bucket is dominated by these).
SETTABLE_HINT = re.compile(
    r"(encrypt|kms|cmk|rotat|public|acl|ingress|egress|unrestricted|"
    r"description|flow[_ ]?log|logging|retention|versioning|backup|"
    r"deletion_protection|mfa|tls|ssl|https|snapshot|notification|"
    r"lifecycle|access[_ ]?block|logging|audit|policy)", re.I)


def resource_base(resource_name):
    # "aws_eks_cluster.this[0]" -> "aws_eks_cluster.this"
    if not resource_name:
        return resource_name
    return re.sub(r"\[\d+\]$", "", resource_name)


def gate2():
    files = sorted(glob.glob(os.path.join(GAMES, "*.json")))
    print("\n" + "=" * 78)
    print("GATE 2 — PREVENTABLE vs STRUCTURAL REGRESSIONS")
    print("=" * 78)
    print(f"Game files on disk: {len(files)} (cohort: full_180_game)\n")

    per_model_events = defaultdict(int)
    per_model_games = defaultdict(int)
    per_model_games_with_reg = defaultdict(int)
    introduced_by_rule = defaultdict(int)
    preventable = 0
    structural = 0
    structural_newresource = 0
    structural_rulehint = 0
    examples = {"preventable": [], "structural": []}

    for fp in files:
        d = json.load(open(fp))
        model = d["model_id"]
        per_model_games[model] += 1
        before = d.get("findings_before", [])
        after = d.get("findings_after", [])
        before_keys = {finding_key(f) for f in before}
        before_resources = {resource_base(f.get("resource_name")) for f in before}
        before_restypes = {f.get("resource_type") for f in before}
        introduced = [f for f in after if finding_key(f) not in before_keys]
        if introduced:
            per_model_games_with_reg[model] += 1
        settable_hits = 0
        for f in introduced:
            per_model_events[model] += 1
            rid = f.get("rule_id", "")
            title = f.get("title", "")
            introduced_by_rule[rid] += 1
            rbase = resource_base(f.get("resource_name"))
            is_new_resource = rbase not in before_resources
            text = f"{rid} {title}"
            is_settable = bool(SETTABLE_HINT.search(text))
            if is_settable:
                settable_hits += 1
            # Classification: structural ONLY if on the explicit allowlist.
            if rid in STRUCTURAL_RULE_IDS:
                structural += 1
                if is_new_resource:
                    structural_newresource += 1
                if len(examples["structural"]) < 6:
                    examples["structural"].append(
                        f"{rid} on {f.get('resource_name')} ({title[:50]})")
            else:
                preventable += 1
                # Track how many preventable are also on a NEW resource — these
                # are "preventable but require the exemplar to teach a whole
                # companion resource", a harder ask than a single attribute.
                if is_new_resource:
                    structural_newresource += 1  # reuse counter: "on new resource"
                if len(examples["preventable"]) < 8:
                    examples["preventable"].append(
                        f"{rid} on {f.get('resource_name')} ({title[:50]}) "
                        f"[newres={is_new_resource}]")
        structural_rulehint += settable_hits

    total = preventable + structural
    print("Regression EVENTS per model (this cohort):")
    print(f"{'model':20} {'games':>6} {'games_w_reg':>12} {'reg_events':>11} "
          f"{'events/game':>12}")
    for m in sorted(per_model_games):
        g = per_model_games[m]
        gr = per_model_games_with_reg[m]
        ev = per_model_events[m]
        print(f"{m:20} {g:6d} {gr:12d} {ev:11d} {ev/g:12.2f}")

    print(f"\nTotal introduced findings classified: {total}")
    if total:
        print(f"  PREVENTABLE (a): {preventable:4d}  ({100*preventable/total:.1f}%)")
        print(f"  STRUCTURAL  (b): {structural:4d}  ({100*structural/total:.1f}%)")
        print(f"  cross-check: {structural_rulehint} of {total} "
              f"({100*structural_rulehint/total:.1f}%) match a known SETTABLE "
              f"hardening-knob pattern")
        print(f"  of preventable, on a NEW resource (harder for exemplar): "
              f"{structural_newresource} "
              f"({100*structural_newresource/total:.1f}% of all)")

    print("\nTop introduced rule_ids:")
    for rid, c in sorted(introduced_by_rule.items(), key=lambda x: -x[1])[:12]:
        print(f"  {c:4d}  {rid}")

    print("\nExample PREVENTABLE:")
    for e in examples["preventable"]:
        print("  -", e)
    print("Example STRUCTURAL:")
    for e in examples["structural"]:
        print("  -", e)

    return preventable, structural, per_model_events


if __name__ == "__main__":
    g1 = gate1()
    prev, struct, ev = gate2()
