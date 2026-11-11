"""
Audit tests for gating.py.

Documents CLAIM 3 / gating behavior:
  - G1/G2/G3 net-delta and severity logic on well-formed findings (PASS)
  - severity-aware gates are BLIND to Checkov regressions, because Checkov
    findings normalize to severity 'UNKNOWN' (never CRITICAL/HIGH). A repair
    that introduces a Checkov-detected misconfig passes G2 and G3 unchecked.
  - GatingPolicy.evaluate recomputes net_delta from the findings it is given;
    it does NOT re-apply the HCL-invalid zeroing. On the recorded data, an
    invalid-HCL game with findings_after=[] is scored as all-resolved by the
    gate — i.e. the gate trusts upstream and cannot catch the CLAIM-3 defect.

No pipeline code is modified. Stdlib + pytest only.
"""
from __future__ import annotations

from src.scanning.scanner_normalizer import Finding
from src.scoring.gating import GateLevel, GatingPolicy


def mk(rule_id: str, resource_name: str, severity: str) -> Finding:
    return Finding("trivy", rule_id, "", severity, resource_name,
                   resource_name.split(".")[0], "main.tf", 1, 2)


def test_g1_accepts_net_positive_rejects_negative():
    p = GatingPolicy(GateLevel.G1)
    before = [mk("AWS-0086", "aws_s3_bucket.a", "HIGH"),
              mk("AWS-0087", "aws_s3_bucket.a", "HIGH")]
    after = [mk("AWS-0104", "aws_security_group.x", "HIGH")]  # 2 resolved, 1 introduced
    assert p.evaluate(before, after).accepted is True         # net +1
    # net-negative
    after2 = [mk("AWS-0104", "aws_security_group.x", "HIGH"),
              mk("AWS-0105", "aws_security_group.y", "HIGH"),
              mk("AWS-0106", "aws_security_group.z", "HIGH")]  # 2 resolved, 3 introduced
    assert p.evaluate(before, after2).accepted is False       # net -1


def test_g2_rejects_critical_regression():
    p = GatingPolicy(GateLevel.G2)
    before = [mk("AWS-0086", "aws_s3_bucket.a", "HIGH"),
              mk("AWS-0087", "aws_s3_bucket.a", "HIGH"),
              mk("AWS-0088", "aws_s3_bucket.a", "HIGH")]
    # net +2 but one CRITICAL introduced -> G2 rejects
    after = [mk("AWS-0999", "aws_kms_key.k", "CRITICAL")]
    d = p.evaluate(before, after)
    assert d.critical_introduced == 1
    assert d.accepted is False


def test_g2_g3_blind_to_checkov_regressions():
    """A repair that resolves nothing and introduces a Checkov-detected issue
    (severity UNKNOWN) has net_delta 0 and zero CRITICAL/HIGH as far as the
    gate can see. G2 accepts it. This is the severity-blindness finding:
    ~44% of the corpus's regressions are Checkov/UNKNOWN and cannot be gated."""
    before = [mk("AWS-0086", "aws_s3_bucket.a", "HIGH")]
    after = [
        mk("AWS-0086", "aws_s3_bucket.a", "HIGH"),                 # unchanged
        Finding("checkov", "CKV_AWS_18", "", "UNKNOWN",           # introduced, UNKNOWN sev
                "aws_s3_bucket.a", "aws_s3_bucket", "main.tf", 1, 2),
    ]
    d = GatingPolicy(GateLevel.G2).evaluate(before, after)
    assert d.critical_introduced == 0
    assert d.high_introduced == 0
    # net_delta = 0 resolved - 1 introduced = -1 -> G1 net rule rejects on net,
    # but the SEVERITY tier adds nothing: a Checkov CRITICAL is indistinguishable
    # from a Checkov LOW. Show that if the model also resolves one, severity is ignored:
    before2 = [mk("AWS-0086", "aws_s3_bucket.a", "HIGH"),
               mk("AWS-0087", "aws_s3_bucket.b", "HIGH")]
    after2 = [
        Finding("checkov", "CKV_AWS_18", "", "UNKNOWN",
                "aws_s3_bucket.a", "aws_s3_bucket", "main.tf", 1, 2),  # introduced
    ]
    d2 = GatingPolicy(GateLevel.G3).evaluate(before2, after2)
    # 2 resolved, 1 introduced, net +1; introduced sev UNKNOWN -> G3 accepts
    assert d2.net_delta == 1
    assert d2.critical_introduced == 0 and d2.high_introduced == 0
    assert d2.accepted is True   # a possibly-critical Checkov regression slips through


def test_gate_does_not_reapply_hcl_zeroing():
    """The gate trusts the findings it is handed. Given the RECORDED shape of an
    invalid-HCL game (findings_after=[]), it scores full resolution and accepts.
    The gate therefore cannot catch the CLAIM-3 upstream defect."""
    before = [mk(f"R{i}", f"aws_x.n{i}", "HIGH") for i in range(8)]
    after: list[Finding] = []            # exactly what the recorded invalid-HCL game stored
    d = GatingPolicy(GateLevel.G2).evaluate(before, after)
    assert d.net_delta == 8              # gate credits all 8 as resolved
    assert d.accepted is True
