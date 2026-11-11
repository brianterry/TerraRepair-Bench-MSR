"""
Run trivy config against a directory and parse JSON output.
"""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path


class ScannerError(Exception):
    """Raised when trivy is not found, times out, or fails."""

    pass


# Default per-scan Trivy timeout in seconds. Raised from 60s to 180s after a
# full-run scan showed large modules (the same ones that stress model context
# windows) hitting the 60s cap and being dropped from the corpus as "scan
# failed" — a scanner-driven selection effect that skewed the corpus toward
# smaller modules. Overridable at runtime via TIMEOUT_ENV so the value can be
# tuned on the Fargate task without rebuilding the image.
DEFAULT_TRIVY_TIMEOUT = 180

# NOT "TRIVY_TIMEOUT": Trivy reads every TRIVY_<FLAG> env var as its own flag,
# and TRIVY_TIMEOUT is Trivy's --timeout (a Go duration). A unitless value such
# as "900" makes Trivy abort immediately, so the harness's knob must not share
# that name.
TIMEOUT_ENV = "TERRAREPAIR_TRIVY_TIMEOUT"


def _default_timeout() -> int:
    """Resolve the Trivy timeout from TIMEOUT_ENV, falling back to the default.

    A missing, empty, or non-integer/non-positive value falls back to
    DEFAULT_TRIVY_TIMEOUT so a bad env value can never silently disable the
    timeout or crash the scan.
    """
    raw = os.environ.get(TIMEOUT_ENV)
    if raw is None or not raw.strip():
        return DEFAULT_TRIVY_TIMEOUT
    try:
        val = int(raw)
    except ValueError:
        return DEFAULT_TRIVY_TIMEOUT
    return val if val > 0 else DEFAULT_TRIVY_TIMEOUT


def run_trivy(
    target_dir: str,
    severity: str = "LOW,MEDIUM,HIGH,CRITICAL",
    timeout: int | None = None,
) -> list[dict]:
    """
    Execute: trivy config --format json --severity {severity} --quiet {target_dir}
    Parse the Results[].Misconfigurations[] structure.
    Return list of normalized findings (raw dicts for normalizer).
    Raises ScannerError if trivy is not found, times out, exits non-zero, or
    produces no parseable JSON report.

    ``timeout`` defaults to ``TERRAREPAIR_TRIVY_TIMEOUT`` env (or
    ``DEFAULT_TRIVY_TIMEOUT``) when not passed explicitly; an explicit value
    always wins. The same value is passed to Trivy's own ``--timeout`` so the
    harness cap is the single effective limit (Trivy's default is 5m).
    """
    if timeout is None:
        timeout = _default_timeout()

    target = Path(target_dir)
    if not target.exists():
        return []

    cmd = [
        "trivy",
        "config",
        "--format",
        "json",
        "--severity",
        severity,
        "--quiet",
        "--timeout",
        f"{timeout}s",
        # Absolute path so the scan target is unambiguous regardless of the
        # process working directory. Previously a relative path was combined
        # with cwd=target.parent, which double-nested the path (e.g.
        # data/terrads_sample/data/terrads_sample/module_x), so Trivy scanned
        # nothing and silently returned zero findings — dropping the entire
        # Trivy half of the dual-scanner stack. See smoke-test finding.
        str(target.resolve()),
    ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except FileNotFoundError as e:
        raise ScannerError("trivy not found. Install with: brew install trivy") from e
    except subprocess.TimeoutExpired as e:
        raise ScannerError(f"trivy timed out after {timeout}s") from e

    # Trivy `config` exits 0 whether or not it finds misconfigurations (we never
    # pass --exit-code). Any non-zero exit is a FAILED scan. This used to accept
    # 1 as "findings found" (true for Checkov, not Trivy), which turned a fatal
    # Trivy error into "zero Trivy findings" -- i.e. every Trivy finding would
    # have scored as resolved.
    if result.returncode != 0:
        raise ScannerError(
            f"trivy exited {result.returncode}: {result.stderr.strip()[-500:]}")
    # A successful run always emits a JSON report; empty or unparseable output
    # is a failure, never "no findings".
    if not result.stdout.strip():
        raise ScannerError("trivy produced no output")
    try:
        raw = json.loads(result.stdout)
    except json.JSONDecodeError as e:
        raise ScannerError(f"trivy output is not valid JSON: {e}") from e
    findings = []
    for res in raw.get("Results", []):
        target_file = res.get("Target", "")
        for misconfig in res.get("Misconfigurations", []):
            m = dict(misconfig)
            m["Target"] = m.get("Target", target_file)
            findings.append(m)
    return findings
