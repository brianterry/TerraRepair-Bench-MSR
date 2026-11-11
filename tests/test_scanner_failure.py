"""
Fix 4: a crashed scanner must be LOUD and DISTINGUISHABLE from a clean scan.

Before the fix, ScannerStack.run swallowed scanner exceptions with
`except: pass` and returned [], so a crashed post-repair scan was scored as a
perfect repair. These tests confirm failures are recorded, logged, and
separable from a genuinely empty result. Stdlib + pytest only.
"""
from __future__ import annotations

import logging

import pytest

from src.scanning.scanner_normalizer import (
    ScannerFailure,
    ScannerStack,
)


def _ok_empty(_dir):
    return []


def _ok_one_trivy(_dir):
    return [{
        "ID": "AVD-AWS-0086", "Title": "t", "Severity": "LOW", "Target": "main.tf",
        "CauseMetadata": {"Resource": "aws_s3_bucket.a", "StartLine": 1, "EndLine": 2},
    }]


def _boom(_dir):
    raise RuntimeError("trivy not installed")


def test_clean_scan_is_ok_and_empty():
    stack = ScannerStack(trivy_runner=_ok_empty, checkov_runner=_ok_empty)
    res = stack.run_checked("/tmp/x")
    assert res.ok is True
    assert res.findings == []
    assert res.failures == {}


def test_failed_scan_is_not_ok_and_records_reason():
    stack = ScannerStack(trivy_runner=_boom, checkov_runner=_ok_empty)
    res = stack.run_checked("/tmp/x")
    assert res.ok is False                      # DISTINCT from a clean empty scan
    assert "trivy" in res.failures
    assert "RuntimeError" in res.failures["trivy"]
    # checkov still ran
    assert res.findings == []


def test_clean_empty_vs_failed_empty_are_distinguishable():
    clean = ScannerStack(_ok_empty, _ok_empty).run_checked("/tmp/x")
    failed = ScannerStack(_boom, _ok_empty).run_checked("/tmp/x")
    assert clean.findings == failed.findings == []   # same findings list...
    assert clean.ok != failed.ok                      # ...but ok differs


def test_failure_is_logged(caplog):
    stack = ScannerStack(trivy_runner=_boom, checkov_runner=_ok_empty)
    with caplog.at_level(logging.ERROR):
        stack.run_checked("/tmp/x")
    assert any("scanner" in r.message and "trivy" in r.message
               for r in caplog.records)


def test_run_strict_raises_on_failure():
    stack = ScannerStack(trivy_runner=_boom, checkov_runner=_ok_empty)
    with pytest.raises(ScannerFailure):
        stack.run("/tmp/x", strict=True)


def test_run_nonstrict_best_effort_still_returns_partial():
    """Non-strict run returns whatever succeeded (checkov here) — but the
    failure was logged and is visible via run_checked, not silently dropped."""
    stack = ScannerStack(trivy_runner=_boom, checkov_runner=_ok_one_trivy)
    # checkov runner returns a trivy-shaped dict just to yield one finding;
    # the point is a non-empty partial result without raising.
    findings = stack.run("/tmp/x", strict=False)
    assert isinstance(findings, list)
