"""
Audit tests for delta_scorer.py — the paper's core metric.

These tests hand-construct before/after finding sets with KNOWN expected
RSR / RR / ND and confirm score_repair reproduces them, plus lock in the
exact-keying and HCL-gating behavior of the CURRENT code.

They document (via test names) two audit findings:
  - CLAIM 1 (delta scoring)  : PASS — set-diff on (rule_id, resource_name).
  - CLAIM 3 (HCL gating)     : the CURRENT code zero-credits invalid HCL, but
                               the RECORDED experiment data does not (see
                               test_hcl_invalid_* and HARNESS_AUDIT.md).

No pipeline code is modified. Stdlib + pytest only.
"""
from __future__ import annotations

from unittest.mock import MagicMock

from src.scanning.scanner_normalizer import Finding
from src.scoring.delta_scorer import score_repair


def mk(rule_id: str, resource_name: str, severity: str = "HIGH", title: str = "") -> Finding:
    return Finding(
        tool="trivy",
        rule_id=rule_id,
        title=title,
        severity=severity,
        resource_name=resource_name,
        resource_type=resource_name.split(".")[0],
        file_path="main.tf",
        start_line=1,
        end_line=2,
    )


def repair(hcl_valid: bool = True):
    r = MagicMock()
    r.success = True
    r.hcl_valid = hcl_valid
    r.repair_cost_usd = 0.01
    r.repair_prompt_tokens = 10
    r.repair_completion_tokens = 5
    return r


# ---------------------------------------------------------------------------
# CLAIM 1: resolved = before \ after, introduced = after \ before, exact keying
# ---------------------------------------------------------------------------

def test_known_rsr_rr_nd_partial():
    """Hand-computed: 3 before, resolve 2, introduce 1.
    resolved=2, introduced=1, target=3 -> RSR=2/3, RR=1/3, ND=+1."""
    before = [mk("AWS-0086", "aws_s3_bucket.a"),
              mk("AWS-0087", "aws_s3_bucket.a"),
              mk("CKV_AWS_23", "aws_security_group.b")]
    after = [mk("CKV_AWS_23", "aws_security_group.b"),   # unchanged
             mk("AWS-0104", "aws_security_group.c")]      # introduced
    g = score_repair("m", "model", before, after, repair())
    assert g.resolved_count == 2
    assert g.introduced_count == 1
    assert g.unchanged_count == 1
    assert g.target_count == 3
    assert abs(g.repair_success_rate - 2 / 3) < 1e-9
    assert abs(g.regression_rate - 1 / 3) < 1e-9
    assert g.net_delta == 1


def test_keying_is_on_rule_id_AND_resource_name():
    """Same rule_id on a different resource is NOT the same finding; same
    resource with a different rule_id is NOT the same finding. Both must be
    treated as distinct keys (exact pair matching)."""
    before = [mk("AWS-0086", "aws_s3_bucket.a")]
    # after: same rule, different resource + same resource, different rule
    after = [mk("AWS-0086", "aws_s3_bucket.b"),
             mk("AWS-0099", "aws_s3_bucket.a")]
    g = score_repair("m", "model", before, after, repair())
    # the one before-finding is gone (resolved); both after-findings are new
    assert g.resolved_count == 1
    assert g.introduced_count == 2
    assert g.net_delta == -1


def test_regression_rate_can_exceed_one():
    """RR normalizes introduced against |before|, so RR>1 is legitimate when a
    repair introduces more new findings than existed. Matches paper Table 1
    (Claude RR=0.88, and >1.0 per-module cases exist)."""
    before = [mk("AWS-0086", "aws_s3_bucket.a")]
    after = [mk("AWS-0086", "aws_s3_bucket.a"),          # unchanged
             mk("AWS-0104", "aws_security_group.x"),
             mk("AWS-0104", "aws_security_group.y"),
             mk("AWS-0104", "aws_security_group.z")]
    g = score_repair("m", "model", before, after, repair())
    assert g.resolved_count == 0
    assert g.introduced_count == 3
    assert g.target_count == 1
    assert g.regression_rate == 3.0
    assert g.net_delta == -3


def test_empty_before_no_divide_by_zero():
    before = []
    after = [mk("AWS-0104", "aws_security_group.x")]
    g = score_repair("m", "model", before, after, repair())
    assert g.target_count == 0
    assert g.repair_success_rate == 0.0
    assert g.regression_rate == 0.0        # guarded, not a crash
    assert g.introduced_count == 1
    assert g.net_delta == -1


def test_duplicate_keys_collapse_in_primary_metrics():
    """Cross-scanner duplicate (same rule_id+resource, different tool) counts
    once in the set-diff primary metrics."""
    before = [mk("AWS-0086", "aws_s3_bucket.a"),
              Finding("checkov", "AWS-0086", "", "HIGH", "aws_s3_bucket.a",
                      "aws_s3_bucket", "main.tf", 1, 2)]
    after = []
    g = score_repair("m", "model", before, after, repair())
    assert g.target_count == 1
    assert g.resolved_count == 1


# ---------------------------------------------------------------------------
# CLAIM 3: HCL gating in the CURRENT code
# ---------------------------------------------------------------------------

def test_current_code_zero_credits_invalid_hcl():
    """The CURRENT score_repair sets findings_after = findings_before when
    hcl_valid is False, yielding resolved=0 / introduced=0 / ND=0.
    (This is the paper's stated §3.3 rule.)"""
    before = [mk("AWS-0086", "aws_s3_bucket.a"),
              mk("AWS-0087", "aws_s3_bucket.a")]
    after: list[Finding] = []          # scanner saw nothing (malformed HCL)
    g = score_repair("m", "model", before, after, repair(hcl_valid=False))
    assert g.hcl_valid is False
    assert g.resolved_count == 0        # NOT credited despite empty after
    assert g.introduced_count == 0
    assert g.net_delta == 0
    assert g.repair_success_rate == 0.0


def test_recorded_data_contradicts_current_gating():
    """AUDIT EVIDENCE: the recorded experiment JSONs were produced BEFORE the
    guard above existed. This reproduces the recorded (buggy) shape — an
    invalid-HCL game credited with full resolution — to show it is exactly
    what the current code prevents. Marks CLAIM 3 as a data-integrity FAIL,
    documented in HARNESS_AUDIT.md.

    We demonstrate the divergence explicitly: with the current guard, empty
    'after' + invalid HCL scores 0; the recorded module_0002_claude-sonnet-4
    stored net_delta=8. The two disagree."""
    before = [mk(f"R{i}", f"aws_x.n{i}") for i in range(8)]
    after: list[Finding] = []
    g = score_repair("m", "model", before, after, repair(hcl_valid=False))
    current_net = g.net_delta
    recorded_net = 8   # value stored in the recorded JSON for this shape
    assert current_net == 0
    assert current_net != recorded_net   # divergence is real
