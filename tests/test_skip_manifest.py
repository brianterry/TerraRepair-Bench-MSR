"""
Fix 5: skips are recorded with a reason, not silently dropped.

Covers the sampler's select_final_corpus skip manifest. (The runner
scripts/run_experiment.py writes an analogous skip_manifest.jsonl; that path is
exercised end-to-end only with live scanners/Bedrock, so here we test the
sampler's manifest which is unit-testable with injected scanners.)

Stdlib + pytest only.
"""
from __future__ import annotations

import json

import src.sampling.terrads_sampler as sampler


def test_select_final_corpus_writes_skip_manifest(tmp_path, monkeypatch):
    # Fake scanners: finding count is encoded in the directory name.
    #   dir "m_low"  -> 1 finding  (below min -> skip)
    #   dir "m_ok"   -> 5 findings (kept)
    #   dir "m_high" -> 60 findings (above max -> skip)
    #   dir "m_boom" -> raises (scan failed -> skip)
    def fake_trivy(d):
        if d.endswith("m_boom"):
            raise RuntimeError("trivy exploded")
        return []

    def fake_checkov(d):
        counts = {"m_low": 1, "m_ok": 5, "m_high": 60}
        n = counts.get(d.split("/")[-1], 0)
        return [
            {"check_id": f"CKV_AWS_{i}", "check_name": "x", "file_path": "/main.tf",
             "resource": f"aws_s3_bucket.b{i}", "file_line_range": [1, 2]}
            for i in range(n)
        ]

    monkeypatch.setattr("src.scanning.trivy_runner.run_trivy", fake_trivy)
    monkeypatch.setattr("src.scanning.checkov_runner.run_checkov", fake_checkov)

    manifest = tmp_path / "skips.jsonl"
    candidates = ["/c/m_low", "/c/m_ok", "/c/m_high", "/c/m_boom"]
    selected = sampler.select_final_corpus(
        candidates, min_findings=3, max_findings=50,
        skip_manifest_path=str(manifest),
    )

    assert selected == ["/c/m_ok"]                 # only the in-band module kept
    assert manifest.exists()
    rows = [json.loads(line) for line in manifest.read_text().splitlines()]
    reasons = {r["id"]: r["reason"] for r in rows}
    assert len(rows) == 3                           # low, high, boom all recorded
    assert "below min findings" in reasons["/c/m_low"]
    assert "above max findings" in reasons["/c/m_high"]
    assert "scan failed" in reasons["/c/m_boom"]
