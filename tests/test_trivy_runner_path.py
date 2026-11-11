"""
Regression test for the Trivy path-doubling bug found during the 2026 smoke prep.

run_trivy previously passed a relative target path together with
cwd=target.parent, which nested the path (data/x/data/x/module) so Trivy
scanned nothing and silently returned zero findings — dropping the whole Trivy
half of the dual-scanner stack while still exiting cleanly (so run_checked
reported ok=True with only Checkov findings).

This test proves run_trivy resolves the target to an absolute path and returns
findings on a module known to have Trivy misconfigurations. It SKIPS when Trivy
is not installed (dev laptop / CI without the scanner), so the suite stays green
offline, but it FAILS loudly if the path bug ever returns where Trivy exists.
"""
from __future__ import annotations

import os
import shutil
import subprocess

import pytest

from src.scanning.trivy_runner import run_trivy

_MODULE = os.path.join(
    os.path.dirname(__file__), "..", "data", "terrads_sample", "module_0002"
)

trivy_missing = shutil.which("trivy") is None


@pytest.mark.skipif(trivy_missing, reason="trivy not installed")
def test_run_trivy_finds_misconfigs_from_any_cwd():
    if not os.path.isdir(_MODULE):
        pytest.skip("sample module not present")

    # Raw ground truth: run trivy directly (correct cwd) and count misconfigs.
    import json
    raw = subprocess.run(
        ["trivy", "config", "--format", "json", "--severity",
         "LOW,MEDIUM,HIGH,CRITICAL", "--quiet", os.path.abspath(_MODULE)],
        capture_output=True, text=True, timeout=120,
    )
    ground_truth = 0
    if raw.stdout:
        doc = json.loads(raw.stdout)
        ground_truth = sum(len(r.get("Misconfigurations", []))
                           for r in doc.get("Results", []))
    if ground_truth == 0:
        pytest.skip("this module has no trivy misconfigs in the installed version")

    # run_trivy must recover the same findings (path resolved absolutely),
    # not silently return zero due to a cwd/path mismatch.
    findings = run_trivy(_MODULE)
    assert len(findings) > 0, "run_trivy returned 0 while raw trivy found misconfigs"
    assert len(findings) == ground_truth
