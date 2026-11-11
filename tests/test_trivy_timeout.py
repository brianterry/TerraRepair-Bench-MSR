"""
Tests for the configurable Trivy scan timeout.

Context: a full-run corpus scan showed large modules hitting the old hardcoded
60s Trivy timeout and being dropped from the corpus as "scan failed". That is a
scanner-driven selection effect (it preferentially drops the large modules that
also stress model context windows), so the default was raised to 180s and made
overridable at runtime via the TERRAREPAIR_TRIVY_TIMEOUT env var (so the Fargate task can be
tuned without an image rebuild).

These tests pin:
  1. the default (no env)                -> DEFAULT_TRIVY_TIMEOUT (180)
  2. a valid env override                -> that value
  3. bad env values (empty/non-int/<=0)  -> fall back to the default
  4. an explicit timeout= argument       -> always wins over the env
  5. the resolved timeout is the value actually handed to subprocess.run

They use a fake subprocess so they run without Trivy installed and never spawn a
real scan. No scoring / set-diff code is touched.
"""
from __future__ import annotations

import shutil
import types

import pytest

import src.scanning.trivy_runner as tr
from src.scanning.trivy_runner import (DEFAULT_TRIVY_TIMEOUT, TIMEOUT_ENV, ScannerError,
                                       _default_timeout, run_trivy)


# --- _default_timeout: env resolution ------------------------------------

def test_default_timeout_no_env(monkeypatch):
    monkeypatch.delenv(TIMEOUT_ENV, raising=False)
    assert _default_timeout() == DEFAULT_TRIVY_TIMEOUT
    assert DEFAULT_TRIVY_TIMEOUT == 180


def test_default_timeout_valid_env(monkeypatch):
    monkeypatch.setenv(TIMEOUT_ENV, "300")
    assert _default_timeout() == 300


@pytest.mark.parametrize("bad", ["", "   ", "abc", "0", "-5", "12.5"])
def test_default_timeout_bad_env_falls_back(monkeypatch, bad):
    monkeypatch.setenv(TIMEOUT_ENV, bad)
    assert _default_timeout() == DEFAULT_TRIVY_TIMEOUT


# --- run_trivy: which timeout actually reaches subprocess.run -------------

class _FakeCompleted:
    returncode = 0
    stdout = "{}"
    stderr = ""


def _install_capturing_subprocess(monkeypatch):
    """Replace the module's subprocess with a fake that records run() kwargs."""
    captured = {}

    def fake_run(cmd, **kwargs):
        captured["cmd"] = cmd
        captured["timeout"] = kwargs.get("timeout")
        return _FakeCompleted()

    fake_subprocess = types.SimpleNamespace(
        run=fake_run,
        # run_trivy references these exception classes in its except clauses.
        TimeoutExpired=Exception,
    )
    monkeypatch.setattr(tr, "subprocess", fake_subprocess)
    return captured


def test_run_trivy_uses_env_timeout(monkeypatch, tmp_path):
    monkeypatch.setenv(TIMEOUT_ENV, "240")
    captured = _install_capturing_subprocess(monkeypatch)
    # tmp_path exists, so run_trivy proceeds to the subprocess call.
    run_trivy(str(tmp_path))
    assert captured["timeout"] == 240


def test_run_trivy_defaults_when_no_env(monkeypatch, tmp_path):
    monkeypatch.delenv(TIMEOUT_ENV, raising=False)
    captured = _install_capturing_subprocess(monkeypatch)
    run_trivy(str(tmp_path))
    assert captured["timeout"] == DEFAULT_TRIVY_TIMEOUT


def test_run_trivy_explicit_arg_overrides_env(monkeypatch, tmp_path):
    monkeypatch.setenv(TIMEOUT_ENV, "240")
    captured = _install_capturing_subprocess(monkeypatch)
    run_trivy(str(tmp_path), timeout=90)
    assert captured["timeout"] == 90, "explicit timeout= must win over the env var"


def test_run_trivy_passes_cap_to_trivys_own_timeout(monkeypatch, tmp_path):
    """Trivy's internal --timeout (default 5m) must not undercut the harness cap."""
    monkeypatch.setenv(TIMEOUT_ENV, "900")
    captured = _install_capturing_subprocess(monkeypatch)
    run_trivy(str(tmp_path))
    i = captured["cmd"].index("--timeout")
    assert captured["cmd"][i + 1] == "900s"


def test_harness_ignores_trivys_own_env_name(monkeypatch):
    """TRIVY_TIMEOUT is Trivy's own --timeout flag; the harness must not read it
    (a unitless value there makes Trivy abort)."""
    monkeypatch.delenv(TIMEOUT_ENV, raising=False)
    monkeypatch.setenv("TRIVY_TIMEOUT", "900")
    assert TIMEOUT_ENV != "TRIVY_TIMEOUT"
    assert _default_timeout() == DEFAULT_TRIVY_TIMEOUT


# --- run_trivy: failures must be loud, never "zero findings" ---------------

def _install_result(monkeypatch, returncode, stdout, stderr=""):
    done = types.SimpleNamespace(returncode=returncode, stdout=stdout, stderr=stderr)
    monkeypatch.setattr(tr, "subprocess", types.SimpleNamespace(
        run=lambda cmd, **kw: done, TimeoutExpired=Exception))


def test_nonzero_exit_is_a_failure_not_zero_findings(monkeypatch, tmp_path):
    # Trivy exits 1 on a FATAL error (it exits 0 when it finds misconfigs).
    # This used to be accepted as "findings found" with empty output -> [].
    _install_result(monkeypatch, 1, "", "FATAL Fatal error run error: scan failed")
    with pytest.raises(ScannerError, match="exited 1"):
        run_trivy(str(tmp_path))


def test_empty_output_is_a_failure(monkeypatch, tmp_path):
    _install_result(monkeypatch, 0, "   ")
    with pytest.raises(ScannerError, match="no output"):
        run_trivy(str(tmp_path))


def test_invalid_json_is_a_failure(monkeypatch, tmp_path):
    _install_result(monkeypatch, 0, "{not json")
    with pytest.raises(ScannerError, match="not valid JSON"):
        run_trivy(str(tmp_path))


def test_clean_report_is_zero_findings(monkeypatch, tmp_path):
    _install_result(monkeypatch, 0, '{"SchemaVersion": 2, "Results": []}')
    assert run_trivy(str(tmp_path)) == []


def test_findings_parsed(monkeypatch, tmp_path):
    report = ('{"Results": [{"Target": "main.tf", "Misconfigurations": '
              '[{"ID": "AWS-0086", "CauseMetadata": {"Resource": "aws_s3_bucket.b"}}]}]}')
    _install_result(monkeypatch, 0, report)
    out = run_trivy(str(tmp_path))
    assert [m["ID"] for m in out] == ["AWS-0086"] and out[0]["Target"] == "main.tf"


@pytest.mark.skipif(shutil.which("trivy") is None, reason="trivy not on PATH")
def test_real_trivy_fatal_raises_and_clean_scan_parses(monkeypatch, tmp_path):
    """Against the real binary:
      * a Trivy FATAL (rc=1, empty stdout -- forced here with an invalid
        severity) must raise, not read as zero findings;
      * a stray TRIVY_TIMEOUT in the environment (Trivy's own flag; a unitless
        value used to make it abort) is overridden by the explicit --timeout;
      * a clean file returns [] without error."""
    (tmp_path / "main.tf").write_text("locals { a = 1 }\n")
    monkeypatch.delenv(TIMEOUT_ENV, raising=False)
    with pytest.raises(ScannerError, match="exited 1"):
        run_trivy(str(tmp_path), severity="BOGUS")
    monkeypatch.setenv("TRIVY_TIMEOUT", "1")
    assert run_trivy(str(tmp_path)) == []
    monkeypatch.delenv("TRIVY_TIMEOUT")
    assert run_trivy(str(tmp_path)) == []
