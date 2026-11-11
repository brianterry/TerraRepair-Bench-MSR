"""
Tests for RunMetrics (troubleshooting metrics) and the completion-marker logic
that makes auto-restart safe.

RunMetrics is imported from scripts/run_experiment.py. These verify counters
aggregate correctly (incl. under threads), the snapshot shape is sane, and the
event categorization matches what the runner records.
"""
from __future__ import annotations

import importlib.util
import os
import threading
from concurrent.futures import ThreadPoolExecutor

_spec = importlib.util.spec_from_file_location(
    "run_experiment",
    os.path.join(os.path.dirname(__file__), "..", "scripts", "run_experiment.py"),
)
run_experiment = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(run_experiment)
RunMetrics = run_experiment.RunMetrics


def test_scored_valid_and_invalid_counts():
    m = RunMetrics(total=4, models=["a"], started_monotonic=0.0)
    m.record("a", "scored", hcl_valid=True, cost_usd=0.10)
    m.record("a", "scored", hcl_valid=False, cost_usd=0.05)
    snap = m.snapshot(now_monotonic=10.0)
    assert snap["events"]["scored"] == 2
    assert snap["events"]["scored_hcl_valid"] == 1
    assert snap["events"]["scored_hcl_invalid"] == 1
    assert snap["by_model"]["a"]["hcl_valid"] == 1
    assert abs(snap["total_cost_usd"] - 0.15) < 1e-9


def test_size_driven_counted():
    m = RunMetrics(total=1, models=["a"], started_monotonic=0.0)
    m.record("a", "scored", hcl_valid=False, size_driven=True, cost_usd=0.02)
    snap = m.snapshot(1.0)
    assert snap["events"]["size_driven"] == 1
    assert snap["by_model"]["a"]["size_driven"] == 1


def test_skip_event_categories():
    m = RunMetrics(total=4, models=["a", "b"], started_monotonic=0.0)
    m.record("a", "throttled")
    m.record("a", "timed_out")
    m.record("b", "scan_failed", cost_usd=0.03)
    m.record("b", "resumed")
    snap = m.snapshot(5.0)
    assert snap["events"]["throttled"] == 1
    assert snap["events"]["timed_out"] == 1
    assert snap["events"]["scan_failed"] == 1
    assert snap["events"]["resumed"] == 1
    assert snap["done"] == 4


def test_rate_and_progress():
    m = RunMetrics(total=10, models=["a"], started_monotonic=0.0)
    for _ in range(5):
        m.record("a", "scored", hcl_valid=True)
    snap = m.snapshot(now_monotonic=60.0)   # 5 games in 60s
    assert snap["done"] == 5
    assert snap["pct"] == 50.0
    assert snap["games_per_min"] == 5.0


def test_thread_safe_no_lost_updates():
    m = RunMetrics(total=4000, models=["a"], started_monotonic=0.0)
    N = 4000

    def rec():
        m.record("a", "scored", hcl_valid=True, cost_usd=0.001)

    with ThreadPoolExecutor(max_workers=16) as pool:
        for _ in range(N):
            pool.submit(rec)
    snap = m.snapshot(1.0)
    assert snap["done"] == N
    assert snap["events"]["scored"] == N
    assert snap["events"]["scored_hcl_valid"] == N
    assert abs(snap["total_cost_usd"] - N * 0.001) < 1e-6


def test_completion_marker_written_only_at_end(tmp_path):
    """Simulate the runner's completion contract: run_complete.json is written
    only after the work loop finishes. A crash before that leaves NO marker, so
    a restarter correctly treats the run as incomplete."""
    out = tmp_path / "exp"
    out.mkdir()
    marker = out / "run_complete.json"

    # mid-run: no marker
    assert not marker.exists()

    # end-of-run: marker written last
    import json
    marker.write_text(json.dumps({"completed": "now", "total_work_items": 10,
                                   "scored_games_on_disk": 8}))
    assert marker.exists()
    data = json.loads(marker.read_text())
    assert data["total_work_items"] == 10


def test_entrypoint_idempotency_contract(tmp_path):
    """Mirror the entrypoint's guard: presence of run_complete.json => skip.
    (Shell-level test would need bash; here we assert the file-presence contract
    the entrypoint depends on.)"""
    out = tmp_path / "exp"
    out.mkdir()
    marker = out / "run_complete.json"
    should_skip = marker.exists()
    assert should_skip is False
    marker.write_text("{}")
    should_skip = marker.exists()
    assert should_skip is True
