"""Unit tests for scripts/rescan_release.py (no scanners, no AWS)."""
from __future__ import annotations

import importlib.util
import json
import subprocess
import tarfile
from pathlib import Path

import pytest

from src.scanning.scanner_normalizer import Finding, ScanResult
from src.utils.repair_artifacts import sha256_hex

ROOT = Path(__file__).resolve().parent.parent


def _load():
    spec = importlib.util.spec_from_file_location(
        "rescan_release_mod", ROOT / "scripts" / "rescan_release.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


rr = _load()


def _f(rule, res, tool="checkov"):
    return Finding(tool=tool, rule_id=rule, title="t", severity="LOW",
                   resource_name=res, resource_type=res.split(".")[0],
                   file_path="main.tf", start_line=1, end_line=1)


def _fd(rule, res):
    return {"tool": "checkov", "rule_id": rule, "title": "t", "severity": "LOW",
            "resource_name": res, "resource_type": res.split(".")[0],
            "file_path": "main.tf", "start_line": 1, "end_line": 1}


class StubStack:
    """Returns a fixed ScanResult and records what it was asked to scan."""

    def __init__(self, findings=(), failures=None):
        self.result = ScanResult(findings=list(findings), failures=dict(failures or {}))
        self.scanned = []

    def run_checked(self, target_dir):
        p = Path(target_dir)
        self.scanned.append(sorted(x.name for x in p.iterdir()) if p.is_dir() else None)
        if p.is_dir() and (p / "main.tf").exists():
            self.last_code = (p / "main.tf").read_bytes()
        return self.result


def _game(tmp, stem="module_0001_nova-lite", code=b'resource "aws_s3_bucket" "b" {}\n',
          hcl_valid=True, after=(("CKV_AWS_1", "aws_s3_bucket.b"),), sha=None, sidecars=True):
    g = tmp / "games"
    g.mkdir(exist_ok=True)
    gj = g / f"{stem}.json"
    if sidecars:
        (g / f"{stem}.repaired.tf").write_bytes(code)
        (g / f"{stem}.raw.txt").write_text("raw")
    gj.write_text(json.dumps({
        "module_id": stem.split("_nova")[0], "model_id": "nova-lite", "hcl_valid": hcl_valid,
        "findings_before": [_fd("CKV_AWS_1", "aws_s3_bucket.b"), _fd("CKV_AWS_2", "aws_s3_bucket.b")],
        "findings_after": [_fd(r, n) for r, n in after],
        "repaired_code_path": f"{stem}.repaired.tf", "raw_response_path": f"{stem}.raw.txt",
        "repaired_code_sha256": sha or sha256_hex(code)}))
    return gj


# ----------------------------------------------------------- outcomes ---

def test_match_scans_saved_code_as_single_main_tf(tmp_path):
    gj = _game(tmp_path)
    stack = StubStack([_f("CKV_AWS_1", "aws_s3_bucket.b")])
    r = rr.check_game(stack, gj)
    assert r["outcome"] == "match" and r["n_findings"] == 1
    assert stack.scanned == [["main.tf"]]
    assert stack.last_code == b'resource "aws_s3_bucket" "b" {}\n'


def test_mismatch_reports_both_directions(tmp_path):
    gj = _game(tmp_path)
    r = rr.check_game(StubStack([_f("CKV_AWS_9", "aws_s3_bucket.b")]), gj)
    assert r["outcome"] == "mismatch"
    assert r["missing"] == [["CKV_AWS_1", "aws_s3_bucket.b"]]
    assert r["extra"] == [["CKV_AWS_9", "aws_s3_bucket.b"]]


def test_scanner_failure_is_never_a_match(tmp_path):
    gj = _game(tmp_path, after=())
    # Empty findings + a failure must NOT read as a clean match on an empty set.
    r = rr.check_game(StubStack([], {"trivy": "ScannerError: timed out"}), gj)
    assert r["outcome"] == "scanner_failure"
    assert r["failures"] == {"trivy": "ScannerError: timed out"}


def test_sha_mismatch_and_missing_sidecar(tmp_path):
    assert rr.check_game(StubStack(), _game(tmp_path, sha="0" * 64))["outcome"] == "sha_mismatch"
    gj = _game(tmp_path, stem="module_0002_nova-lite", sidecars=False)
    assert rr.check_game(StubStack(), gj)["outcome"] == "missing_sidecar"


def test_hcl_invalid_is_not_scanned(tmp_path):
    stack = StubStack()
    r = rr.check_game(stack, _game(tmp_path, hcl_valid=False))
    assert r["outcome"] == "skipped_hcl_invalid" and stack.scanned == []


def test_input_check(tmp_path):
    mod = tmp_path / "module_0001"
    mod.mkdir()
    (mod / "main.tf").write_text('module "v" {\n  source = "terraform-aws-modules/vpc/aws"\n}\n')
    rec = {("CKV_AWS_1", "aws_s3_bucket.b")}
    r = rr.check_input(StubStack([_f("CKV_AWS_1", "aws_s3_bucket.b")]), mod, rec)
    assert r["outcome"] == "match" and r["remote_modules"] == 1
    assert rr.check_input(StubStack([]), mod, rec)["outcome"] == "mismatch"


def test_remote_module_sources():
    text = '''
module "a" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"
}
module "b" { source = "./local" }
module "c" {
  source = "git::https://github.com/x/y.git?ref=v1"
}
module "d" { source = "../up" }
'''
    assert rr.remote_module_sources(text) == [
        "terraform-aws-modules/vpc/aws", "git::https://github.com/x/y.git?ref=v1"]


# ------------------------------------------------------------- main ---

def test_main_end_to_end_with_stub(tmp_path, monkeypatch):
    res = tmp_path / "results"
    res.mkdir()
    _game(res)                                                     # match
    _game(res, stem="module_0002_nova-lite", hcl_valid=False)      # skipped
    corpus = tmp_path / "corpus"
    for m in ("module_0001", "module_0002"):
        (corpus / m).mkdir(parents=True)
        (corpus / m / "main.tf").write_text("")
    stack = StubStack([_f("CKV_AWS_1", "aws_s3_bucket.b"), _f("CKV_AWS_2", "aws_s3_bucket.b")])
    # Inputs return before-findings (2); the valid game expects 1 -> the stub
    # gives 2 for the game too, so the game is a deliberate mismatch.
    monkeypatch.setattr(rr, "ScannerStack", lambda: stack)
    monkeypatch.setattr(rr, "_versions", lambda: {"trivy": "x", "checkov": "y"})
    out = tmp_path / "out"
    rc = rr.main(["--results", str(res), "--out", str(out), "--corpus-dir", str(corpus)])
    s = json.loads((out / "rescan_summary.json").read_text())
    assert rc == 1
    assert s["inputs"] == {"match": 2}
    assert s["games"] == {"mismatch": 1, "skipped_hcl_invalid": 1}
    lines = (out / "rescan_results.jsonl").read_text().splitlines()
    assert len(lines) == 4                                        # 2 inputs + 2 games


def test_only_remote_filters_inputs_and_games(tmp_path, monkeypatch):
    res = tmp_path / "results"
    res.mkdir()
    remote_code = b'module "v" {\n  source = "terraform-aws-modules/vpc/aws"\n}\n'
    _game(res, stem="module_0001_nova-lite", code=remote_code)       # remote -> checked
    _game(res, stem="module_0002_nova-lite")                         # local  -> skipped
    corpus = tmp_path / "corpus"
    (corpus / "module_0001").mkdir(parents=True)
    (corpus / "module_0001" / "main.tf").write_text(remote_code.decode())
    (corpus / "module_0002").mkdir(parents=True)
    (corpus / "module_0002" / "main.tf").write_text('resource "aws_s3_bucket" "b" {}\n')
    stack = StubStack([_f("CKV_AWS_1", "aws_s3_bucket.b"), _f("CKV_AWS_2", "aws_s3_bucket.b")])
    monkeypatch.setattr(rr, "ScannerStack", lambda: stack)
    monkeypatch.setattr(rr, "_versions", lambda: {})
    out = tmp_path / "out"
    rr.main(["--results", str(res), "--out", str(out), "--corpus-dir", str(corpus), "--only-remote"])
    rows = [json.loads(l) for l in (out / "rescan_results.jsonl").read_text().splitlines()]
    assert [(r["item"], r["module_id"]) for r in rows] == [("input", "module_0001"), ("game", "module_0001")]
    s = json.loads((out / "rescan_summary.json").read_text())
    assert s["only_remote"] is True and s["n_games_checked"] == 1


# ----------------------------------------------------------- capture ---

@pytest.mark.skipif(subprocess.run(["git", "--version"], capture_output=True).returncode != 0,
                    reason="git required")
def test_capture_records_module_commits_and_checks_digest(tmp_path, monkeypatch):
    tmpdir = tmp_path / "tmp"
    clone = tmpdir / ".aqua" / "cache" / "abc123"
    clone.mkdir(parents=True)
    (clone / "main.tf").write_text('resource "aws_s3_bucket" "x" {}\n')
    for cmd in (["init", "-q"], ["remote", "add", "origin", "https://github.com/x/terraform-aws-vpc"],
                ["add", "."], ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "m"]):
        subprocess.run(["git", *cmd], cwd=clone, check=True, capture_output=True)
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=clone, capture_output=True, text=True).stdout.strip()
    trivy_cache = tmp_path / "trivycache"
    (trivy_cache / "policy").mkdir(parents=True)
    (trivy_cache / "policy" / "metadata.json").write_text(json.dumps({"Digest": "sha256:feed"}))
    monkeypatch.setattr(rr.tempfile, "gettempdir", lambda: str(tmpdir))
    monkeypatch.setenv("TRIVY_CACHE_DIR", str(trivy_cache))

    out = tmp_path / "out"
    out.mkdir()
    man = rr.capture(out)
    assert man["modules"] == [{"cache_key": "abc123", "source_url": "https://github.com/x/terraform-aws-vpc",
                               "commit": head, "tf_files": 1}]
    assert man["checks_bundle"]["Digest"] == "sha256:feed"
    with tarfile.open(out / "trivy_module_cache.tar.gz") as t:
        assert ".aqua/cache/abc123/main.tf" in t.getnames()
    with tarfile.open(out / "trivy_checks_bundle.tar.gz") as t:
        assert "trivy/policy/metadata.json" in t.getnames()
