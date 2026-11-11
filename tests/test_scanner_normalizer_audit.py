"""
Audit tests for scanner_normalizer.py.

Locks in the audit findings for CLAIM 2 (faithful normalization):
  - dedup drops nothing and never double-counts within a run  (PASS)
  - the (rule_id, resource_name) key is NOT stable across Trivy versions,
    because normalize_trivy_findings stores the raw scanner ID verbatim
    (modern Trivy emits 'AVD-AWS-xxxx', the recorded corpus used 'AWS-xxxx')
  - Checkov OSS findings carry no severity, so they normalize to 'UNKNOWN'
    (this is what makes severity-aware gating blind to ~44% of regressions;
    see test_gating_audit.py)

No pipeline code is modified. Stdlib + pytest only.
"""
from __future__ import annotations

from src.scanning.scanner_normalizer import (
    Finding,
    deduplicate_findings,
    normalize_checkov_findings,
    normalize_trivy_findings,
)


# ---------------------------------------------------------------------------
# Key stability across Trivy versions
# ---------------------------------------------------------------------------

def test_trivy_id_canonicalized_across_versions():
    """FIX (audit Claim 2): the normalizer now canonicalizes Trivy ids by
    stripping the leading 'AVD-' prefix, so modern Trivy ('AVD-AWS-0086') and
    the legacy/recorded form ('AWS-0086') collapse to the SAME key. This makes
    the (rule_id, resource_name) key stable across Trivy versions."""
    modern = normalize_trivy_findings([{
        "ID": "AVD-AWS-0086",
        "Title": "S3 versioning",
        "Severity": "LOW",
        "Target": "main.tf",
        "CauseMetadata": {"Resource": "aws_s3_bucket.a", "StartLine": 1, "EndLine": 2},
    }])[0]
    legacy = normalize_trivy_findings([{
        "ID": "AWS-0086",
        "Title": "S3 versioning",
        "Severity": "LOW",
        "Target": "main.tf",
        "CauseMetadata": {"Resource": "aws_s3_bucket.a", "StartLine": 1, "EndLine": 2},
    }])[0]
    # Same misconfiguration, same resource — keys now MATCH after canonicalization.
    assert modern.rule_id == "AWS-0086"
    assert legacy.rule_id == "AWS-0086"
    assert (modern.rule_id, modern.resource_name) == (legacy.rule_id, legacy.resource_name)


def test_checkov_id_not_canonicalized():
    """Checkov ids must be left intact by canonicalization (only 'AVD-' strips)."""
    from src.scanning.scanner_normalizer import canonicalize_rule_id
    assert canonicalize_rule_id("CKV_AWS_19") == "CKV_AWS_19"
    assert canonicalize_rule_id("CKV2_AWS_6") == "CKV2_AWS_6"
    assert canonicalize_rule_id("AVD-AWS-0104") == "AWS-0104"
    assert canonicalize_rule_id("AWS-0104") == "AWS-0104"


# ---------------------------------------------------------------------------
# Checkov severity is UNKNOWN in OSS output
# ---------------------------------------------------------------------------

def test_checkov_without_severity_normalizes_to_unknown():
    """OSS Checkov failed_checks have no 'severity' field; the normalizer
    defaults to UNKNOWN. Gating keys off CRITICAL/HIGH, so these are invisible
    to G2/G3."""
    f = normalize_checkov_findings([{
        "check_id": "CKV_AWS_18",
        "check_name": "Ensure S3 access logging",
        "file_path": "/main.tf",
        "resource": "aws_s3_bucket.a",
        "file_line_range": [1, 5],
        # no 'severity' key, no nested check.severity
    }])[0]
    assert f.severity == "UNKNOWN"


def test_checkov_with_explicit_severity_preserved():
    f = normalize_checkov_findings([{
        "check_id": "CKV_AWS_18",
        "check_name": "x",
        "severity": "high",
        "file_path": "/main.tf",
        "resource": "aws_s3_bucket.a",
        "file_line_range": [1, 5],
    }])[0]
    assert f.severity == "HIGH"


# ---------------------------------------------------------------------------
# Dedup: nothing silently dropped, no double count
# ---------------------------------------------------------------------------

def test_dedup_keeps_distinct_and_collapses_exact_dupes():
    trivy = normalize_trivy_findings([{
        "ID": "AWS-0086", "Title": "t", "Severity": "LOW", "Target": "main.tf",
        "CauseMetadata": {"Resource": "aws_s3_bucket.a", "StartLine": 1, "EndLine": 2},
    }])
    checkov = normalize_checkov_findings([
        {"check_id": "AWS-0086", "check_name": "c", "file_path": "/main.tf",
         "resource": "aws_s3_bucket.a", "file_line_range": [1, 2]},   # cross-scanner dup
        {"check_id": "CKV_AWS_23", "check_name": "c2", "file_path": "/main.tf",
         "resource": "aws_security_group.b", "file_line_range": [3, 4]},  # distinct
    ])
    deduped = deduplicate_findings(trivy + checkov)
    keys = {(f.rule_id, f.resource_name) for f in deduped}
    assert keys == {("AWS-0086", "aws_s3_bucket.a"), ("CKV_AWS_23", "aws_security_group.b")}
    assert len(deduped) == 2                 # the cross-scanner dup collapsed to one
    # first occurrence (trivy) is kept
    kept = [f for f in deduped if f.rule_id == "AWS-0086"][0]
    assert kept.tool == "trivy"


def test_dedup_does_not_drop_same_rule_different_resource():
    findings = [
        Finding("trivy", "AWS-0104", "", "HIGH", "aws_security_group.a", "aws_security_group", "", 1, 2),
        Finding("trivy", "AWS-0104", "", "HIGH", "aws_security_group.b", "aws_security_group", "", 1, 2),
    ]
    assert len(deduplicate_findings(findings)) == 2
