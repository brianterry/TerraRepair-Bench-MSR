"""
READ-ONLY audit re-computation over recorded game JSONs.

Does NOT import or modify pipeline code. Re-derives per-model metrics two ways:
  (A) as-recorded  -- exactly the stored fields (what analyze.py averages, i.e. the paper)
  (B) paper-rule   -- applying paper 3.3: hcl_valid == False  =>  resolved=0, introduced=0,
                      net_delta=0, RSR=0, RR=0 (findings fully attributed to the model)

Also recomputes RSR/RR/ND from the raw findings_before/findings_after sets to check the
stored scalar fields are internally consistent with the (rule_id, resource_name) set-diff
definition, and re-derives the completeness-checker coverage %.

Run:  python3 tests/audit_recompute.py <games_dir> <completeness_analysis.json>
Prints a report to stdout. Writes nothing.
"""
from __future__ import annotations

import json
import statistics
import sys
from pathlib import Path


def key(f: dict) -> tuple[str, str]:
    return (f["rule_id"], f["resource_name"])


def recompute_from_sets(before: list[dict], after: list[dict]) -> dict:
    bk = {key(f) for f in before}
    ak = {key(f) for f in after}
    resolved = len(bk - ak)
    introduced = len(ak - bk)
    target = len(bk)
    return {
        "resolved": resolved,
        "introduced": introduced,
        "net_delta": resolved - introduced,
        "rsr": resolved / target if target else 0.0,
        "rr": introduced / target if target else 0.0,
        "target": target,
    }


def main() -> None:
    games_dir = Path(sys.argv[1])
    files = sorted(games_dir.glob("*.json"))
    games = [json.loads(f.read_text()) for f in files]
    print(f"Loaded {len(games)} game JSONs from {games_dir}")

    # ---- consistency: do stored scalar fields match set-diff recompute? ----
    mismatches = []
    hcl_invalid = []
    hcl_invalid_credited = []  # invalid HCL but stored resolved>0
    for f, g in zip(files, games):
        rc = recompute_from_sets(g["findings_before"], g["findings_after"])
        stored = (g["resolved_count"], g["introduced_count"], g["net_delta"])
        recomp = (rc["resolved"], rc["introduced"], rc["net_delta"])
        if stored != recomp:
            mismatches.append((f.name, stored, recomp))
        if not g.get("hcl_valid", True):
            hcl_invalid.append(g)
            if g["resolved_count"] > 0 or g["net_delta"] != 0:
                hcl_invalid_credited.append((f.name, g["model_id"], g["resolved_count"],
                                             g["introduced_count"], g["net_delta"],
                                             len(g["findings_after"])))

    print("\n== Stored-vs-recomputed (set-diff) consistency ==")
    print(f"  games where stored (resolved,introduced,net) != set-diff recompute: {len(mismatches)}")
    for name, s, r in mismatches[:10]:
        print(f"    {name}: stored={s} recompute={r}")

    print("\n== HCL validity ==")
    print(f"  hcl_valid == False games: {len(hcl_invalid)} ({len(hcl_invalid)/len(games)*100:.1f}%)")
    print(f"  of those, CREDITED (resolved>0 or net!=0) despite invalid HCL: {len(hcl_invalid_credited)}")
    for row in hcl_invalid_credited[:10]:
        print(f"    {row[0]} model={row[1]} resolved={row[2]} introduced={row[3]} net={row[4]} n_after={row[5]}")

    # ---- per-model means: as-recorded vs paper-rule ----
    by_model: dict[str, list[dict]] = {}
    for g in games:
        by_model.setdefault(g["model_id"], []).append(g)

    print("\n== Per-model means: AS-RECORDED (paper) vs PAPER-RULE (hcl invalid => 0) ==")
    hdr = f"  {'model':<16} {'n':>4} {'RSR_rec':>8} {'RSR_rule':>8} {'RR_rec':>7} {'RR_rule':>8} {'ND_rec':>7} {'ND_rule':>8} {'#inval':>6}"
    print(hdr)
    for mid in sorted(by_model):
        gs = by_model[mid]
        rsr_rec = statistics.mean(g["repair_success_rate"] for g in gs)
        rr_rec = statistics.mean(g["regression_rate"] for g in gs)
        nd_rec = statistics.mean(g["net_delta"] for g in gs)

        def rule_vals(g):
            if not g.get("hcl_valid", True):
                return 0.0, 0.0, 0
            return g["repair_success_rate"], g["regression_rate"], g["net_delta"]

        rsr_rule = statistics.mean(rule_vals(g)[0] for g in gs)
        rr_rule = statistics.mean(rule_vals(g)[1] for g in gs)
        nd_rule = statistics.mean(rule_vals(g)[2] for g in gs)
        n_inval = sum(1 for g in gs if not g.get("hcl_valid", True))
        print(f"  {mid:<16} {len(gs):>4} {rsr_rec:>8.3f} {rsr_rule:>8.3f} "
              f"{rr_rec:>7.3f} {rr_rule:>8.3f} {nd_rec:>+7.2f} {nd_rule:>+8.2f} {n_inval:>6}")

    # reasoning vs non-reasoning under both rules
    reasoning = {"deepseek-r1", "qwen3-32b"}
    for label, pred in [("AS-RECORDED", lambda g: g["regression_rate"]),
                        ("PAPER-RULE", lambda g: 0.0 if not g.get("hcl_valid", True) else g["regression_rate"])]:
        r = [pred(g) for g in games if g["model_id"] in reasoning]
        nr = [pred(g) for g in games if g["model_id"] not in reasoning]
        print(f"\n  [{label}] reasoning mean RR={statistics.mean(r):.3f} "
              f"non-reasoning mean RR={statistics.mean(nr):.3f} gap={statistics.mean(nr)-statistics.mean(r):.3f}")

    # ---- completeness coverage re-derivation (mirrors evaluate_coverage_on_games) ----
    RULE_MAPPING = {
        "RC-001": {"AWS-0094", "AWS-0093", "AWS-0091", "AWS-0087", "AWS-0086", "CKV2_AWS_6"},
        "RC-002": {"AWS-0104", "CKV_AWS_382"},
        "RC-003": {"AWS-0099", "AWS-0124", "CKV_AWS_23"},
        "RC-004": {"AWS-0065", "CKV_AWS_7"},
        "RC-005": {"AWS-0017", "CKV_AWS_158"},
        "RC-006": {"CKV_AWS_338", "CKV_AWS_66"},
        "RC-007": {"AWS-0132", "CKV_AWS_145"},
        "RC-008": {"AWS-0089"},
        "RC-009": {"AWS-0178"},
        "RC-010": {"CKV2_AWS_64"},
    }
    covered_rules = set().union(*RULE_MAPPING.values())
    total_reg = 0
    covered = 0
    # also test with AVD- prefix normalization
    covered_norm = 0
    def norm(rid: str) -> str:
        return rid[4:] if rid.startswith("AVD-") else rid
    for g in games:
        bk = {key(f) for f in g["findings_before"]}
        after_map = {key(f): f for f in g["findings_after"]}
        introduced_keys = set(after_map) - bk
        for k in introduced_keys:
            rid = after_map[k]["rule_id"]
            total_reg += 1
            if rid in covered_rules:
                covered += 1
            if norm(rid) in covered_rules:
                covered_norm += 1
    print("\n== Completeness coverage re-derivation ==")
    print(f"  total regressions: {total_reg}")
    print(f"  covered (exact, as code does): {covered} ({covered/total_reg*100:.2f}%)")
    print(f"  covered (AVD- prefix stripped): {covered_norm} ({covered_norm/total_reg*100:.2f}%)")

    if len(sys.argv) > 2:
        rec = json.loads(Path(sys.argv[2]).read_text())
        print(f"  recorded completeness_analysis.json: total={rec['total_regressions']} "
              f"covered={rec['covered_by_checker']} pct={rec['coverage_pct']:.2f}")

    # rule_id prefix census
    trivy_prefixes = {}
    for g in games:
        for f in g["findings_before"] + g["findings_after"]:
            rid = f["rule_id"]
            pre = rid.split("_")[0].split("-")[0] if rid else "EMPTY"
            trivy_prefixes[pre] = trivy_prefixes.get(pre, 0) + 1
    print("\n== rule_id prefix census (all findings) ==")
    for pre, cnt in sorted(trivy_prefixes.items(), key=lambda x: -x[1])[:12]:
        print(f"  {pre:<12} {cnt}")


if __name__ == "__main__":
    main()
