"""
Release-slice provenance: the saved model output is the artifact that was scored.

Each game JSON written by scripts/run_experiment.py and
scripts/run_retrieval_ablation.py now has sidecars:

  <stem>.repaired.tf   sanitized repaired code (exactly the text scanned)
  <stem>.raw.txt       raw model response before sanitization

plus ``repaired_code_path``, ``raw_response_path`` and ``repaired_code_sha256``
in the JSON.

Tests here:
  * Unit (no AWS, no scanners): raw_response is threaded through RepairResult,
    including for refusals that sanitize_repair_response rejects; sidecars and
    sha256 are written correctly.
  * End-to-end offline (real Trivy + Checkov, stubbed model): run the runner's
    repair -> scan -> score -> persist path on a real corpus module, then
    RESCAN the saved .repaired.tf and assert the finding identities
    (rule_id, resource_name) equal the game's findings_after.
  * Results-tree rescan (real scanners): for every hcl_valid game with
    sidecars under $RESCAN_RESULTS_DIR (default
    experiments/results/release_slice_2026-10), verify sha256 and rescan.
    Skipped when the directory has no sidecar games.
"""
from __future__ import annotations

import importlib.util
import json
import os
import shutil
import tempfile
from pathlib import Path

import pytest

from src.repair.repair_agent import RepairResult, repair_module
from src.utils.repair_artifacts import sha256_hex, write_repair_sidecars

ROOT = Path(__file__).resolve().parent.parent
SAMPLE = ROOT / "data" / "terrads_sample"
DEFAULT_RESULTS = ROOT / "experiments" / "results" / "release_slice_2026-10"

_HAVE_SCANNERS = bool(shutil.which("trivy") and shutil.which("checkov"))
needs_scanners = pytest.mark.skipif(
    not _HAVE_SCANNERS, reason="trivy and checkov must be on PATH")


# ---------------------------------------------------------------- helpers ---

class _StubBedrock:
    """Returns a canned response; records nothing, needs no AWS."""

    def __init__(self, text: str):
        self.text = text

    def invoke(self, model_id, prompt, max_tokens, temperature):
        return self.text, {"input_tokens": 10, "output_tokens": 20}


def _load_runner():
    spec = importlib.util.spec_from_file_location(
        "run_experiment_mod", ROOT / "scripts" / "run_experiment.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _identities(findings) -> set[tuple[str, str]]:
    out = set()
    for f in findings:
        if isinstance(f, dict):
            out.add((f["rule_id"], f["resource_name"]))
        else:
            out.add((f.rule_id, f.resource_name))
    return out


def rescan_game(game_json: Path, stack=None) -> tuple[set, set]:
    """Rescan a game's saved .repaired.tf exactly as the runner scanned it
    (single main.tf in a fresh temp dir). Returns (expected, actual) identity
    sets. Fails loudly on scanner errors or a sha256 mismatch."""
    from src.scanning.scanner_normalizer import ScannerStack

    game = json.loads(game_json.read_text())
    tf = game_json.parent / game["repaired_code_path"]
    data = tf.read_bytes()
    assert sha256_hex(data) == game["repaired_code_sha256"], f"sha256 mismatch: {tf}"

    stack = stack or ScannerStack()
    tmp = tempfile.mkdtemp()
    try:
        (Path(tmp) / "main.tf").write_bytes(data)
        res = stack.run_checked(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    assert res.ok, f"rescan scanner failure for {game_json.name}: {res.failures}"
    return _identities(game["findings_after"]), _identities(res.findings)


def _smallest_corpus_module() -> Path:
    """A small, real in-corpus module (keeps the scanner run fast)."""
    manifest = ROOT / "experiments/results/full_refresh_2026-09/corpus_manifest.jsonl"
    rows = [json.loads(line) for line in manifest.read_text().splitlines() if line.strip()]
    rows.sort(key=lambda r: r["source_chars"])
    for r in rows:
        d = ROOT / r["module_dir"]
        if d.is_dir():
            return d
    pytest.skip("no corpus module available on disk")


# ------------------------------------------------------------- unit tests ---

def test_repair_result_raw_response_defaults_empty():
    r = RepairResult(
        model_id="m", module_id="x", original_code="", repaired_code="",
        repaired_dir=None, repair_prompt_tokens=0, repair_completion_tokens=0,
        repair_cost_usd=0.0, success=False, hcl_valid=False, error=None)
    assert r.raw_response == ""


def test_raw_response_is_pre_sanitization(tmp_path):
    mod = tmp_path / "module_x"
    mod.mkdir()
    (mod / "main.tf").write_text('resource "aws_s3_bucket" "b" {\n  bucket = "x"\n}\n')
    hcl = 'resource "aws_s3_bucket" "b" {\n  bucket = "x"\n  acl    = "private"\n}'
    raw = f"<think>reasoning here</think>\nHere is the repaired code:\n```hcl\n{hcl}\n```\n"
    res = repair_module(str(mod), [], "nova-lite", _StubBedrock(raw))
    try:
        assert res.raw_response == raw                 # untouched model text
        assert res.repaired_code == hcl                # sanitized
        assert "<think>" not in res.repaired_code
        if res.repaired_dir:
            scanned = (Path(res.repaired_dir) / "main.tf").read_bytes()
            assert scanned == res.repaired_code.encode("utf-8")
    finally:
        if res.repaired_dir:
            shutil.rmtree(res.repaired_dir, ignore_errors=True)


def test_raw_response_survives_sanitizer_rejection(tmp_path):
    mod = tmp_path / "module_y"
    mod.mkdir()
    (mod / "main.tf").write_text('resource "aws_s3_bucket" "b" {}\n')
    raw = "I cannot help with modifying this infrastructure code, sorry about that."
    res = repair_module(str(mod), [], "nova-lite", _StubBedrock(raw))
    assert res.success is False and res.repaired_code == ""
    assert res.raw_response == raw                     # not lost on refusal


def test_write_repair_sidecars(tmp_path):
    game_file = tmp_path / "module_0001_nova-lite.json"
    r = RepairResult(
        model_id="nova-lite", module_id="module_0001", original_code="o",
        repaired_code='resource "a" "b" {}  # é', repaired_dir=None,
        repair_prompt_tokens=1, repair_completion_tokens=1, repair_cost_usd=0.0,
        success=True, hcl_valid=True, error=None, raw_response="```hcl\nraw\n```")
    fields = write_repair_sidecars(game_file, r)
    assert fields["repaired_code_path"] == "module_0001_nova-lite.repaired.tf"
    assert fields["raw_response_path"] == "module_0001_nova-lite.raw.txt"
    tf = tmp_path / fields["repaired_code_path"]
    assert tf.read_bytes() == r.repaired_code.encode("utf-8")
    assert (tmp_path / fields["raw_response_path"]).read_text("utf-8") == r.raw_response
    assert fields["repaired_code_sha256"] == sha256_hex(tf.read_bytes())
    # Paths are relative (bare filenames), never absolute.
    assert not Path(fields["repaired_code_path"]).is_absolute()


def test_ablation_stem_keeps_arm_and_draw(tmp_path):
    gf = tmp_path / "module_0001_nova-pro_oracle_d2.json"
    r = RepairResult("nova-pro", "module_0001", "", "", None, 0, 0, 0.0,
                     False, False, "err")
    fields = write_repair_sidecars(gf, r)
    assert fields["repaired_code_path"] == "module_0001_nova-pro_oracle_d2.repaired.tf"
    assert fields["repaired_code_sha256"] == sha256_hex(b"")


def test_git_provenance_in_this_environment():
    """Host checkout -> live git. Container image (no .git) -> the baked
    build-arg commit. Either way the commit must be a real 40-char sha."""
    prov = _load_runner()._git_provenance()
    if (ROOT / ".git").exists():
        assert prov["source"] == "git"
    else:
        baked = os.environ.get("TERRAREPAIR_GIT_COMMIT", "")
        if not baked:
            pytest.skip("no git checkout and no baked commit in this environment")
        assert prov["source"] == "image_build_arg"
        assert prov["commit"] == baked
    assert len(prov["commit"]) == 40


def test_git_provenance_falls_back_to_baked_commit(monkeypatch):
    """In the container there is no .git: use the build-arg commit, and never
    report a clean tree when the dirty flag is unknown."""
    runner = _load_runner()

    class _NoGit:
        stdout = ""
    monkeypatch.setattr(runner.subprocess, "run", lambda *a, **k: _NoGit())

    monkeypatch.setenv("TERRAREPAIR_GIT_COMMIT", "a" * 40)
    monkeypatch.setenv("TERRAREPAIR_GIT_DIRTY", "false")
    prov = runner._git_provenance()
    assert prov == {"source": "image_build_arg", "commit": "a" * 40,
                    "dirty": False, "tracked_diff_sha256": None}

    monkeypatch.setenv("TERRAREPAIR_GIT_DIRTY", "")
    assert runner._git_provenance()["dirty"] == "unknown"

    monkeypatch.delenv("TERRAREPAIR_GIT_COMMIT")
    assert runner._git_provenance() == {
        "source": "unavailable", "commit": "unknown", "dirty": "unknown"}


# ----------------------------------------------- end-to-end offline rescan ---

@needs_scanners
def test_end_to_end_saved_artifact_is_what_was_scored(tmp_path):
    """Drive the runner's own repair -> scan -> score -> serialize -> persist
    path with a stubbed model, then rescan the saved sidecar."""
    from src.scanning.scanner_normalizer import ScannerStack
    from src.scoring.delta_scorer import score_repair

    runner = _load_runner()
    module_dir = _smallest_corpus_module()
    stack = ScannerStack()
    before = stack.run_checked(str(module_dir))
    assert before.ok, before.failures

    original = "\n\n".join(p.read_text() for p in sorted(module_dir.glob("*.tf")))
    raw = f"<think>x</think>\n```hcl\n{original}\n```"
    result = repair_module(str(module_dir), before.findings, "nova-lite", _StubBedrock(raw))
    assert result.hcl_valid, result.error

    try:
        after = stack.run_checked(result.repaired_dir)
        assert after.ok, after.failures
    finally:
        shutil.rmtree(result.repaired_dir, ignore_errors=True)

    game = score_repair(module_dir.name, "nova-lite", before.findings,
                        after.findings, result)
    gd = runner._game_result_to_dict(game)
    game_file = tmp_path / f"{module_dir.name}_nova-lite.json"
    gd.update(write_repair_sidecars(game_file, result))
    game_file.write_text(json.dumps(gd, indent=2))

    assert (tmp_path / gd["raw_response_path"]).read_text("utf-8") == raw
    expected, actual = rescan_game(game_file, stack)
    assert expected == actual


# ------------------------------------------------ results-tree rescan ---

def _sidecar_games(root: Path) -> list[Path]:
    if not root.is_dir():
        return []
    out = []
    for p in sorted(root.rglob("*.json")):
        try:
            g = json.loads(p.read_text())
        except Exception:  # noqa: BLE001 - manifests etc.
            continue
        if isinstance(g, dict) and "repaired_code_path" in g and "findings_after" in g:
            out.append(p)
    return out


@needs_scanners
def test_rescan_results_tree():
    # Opt-in: a full release tree takes hours to rescan, so the offline suite
    # must not pick it up just because results are synced locally.
    # For a full, non-aborting report use scripts/rescan_release.py.
    if not os.environ.get("RESCAN_RESULTS_DIR"):
        pytest.skip("set RESCAN_RESULTS_DIR to rescan a results tree "
                    f"(e.g. {DEFAULT_RESULTS.relative_to(ROOT)})")
    root = Path(os.environ["RESCAN_RESULTS_DIR"])
    games = _sidecar_games(root)
    if not games:
        pytest.skip(f"no sidecar games under {root}")

    from src.scanning.scanner_normalizer import ScannerStack
    stack = ScannerStack()
    mismatches, checked = [], 0
    for gf in games:
        g = json.loads(gf.read_text())
        # Both sidecars must exist and the sha must match for EVERY game.
        assert (gf.parent / g["raw_response_path"]).exists(), gf
        tf = gf.parent / g["repaired_code_path"]
        assert sha256_hex(tf.read_bytes()) == g["repaired_code_sha256"], gf
        if not g["hcl_valid"]:
            continue  # not scanned by design (findings_after := findings_before)
        expected, actual = rescan_game(gf, stack)
        checked += 1
        if expected != actual:
            mismatches.append((gf.name, sorted(expected ^ actual)))
    assert not mismatches, mismatches
    assert checked > 0, "no hcl_valid games to rescan"
