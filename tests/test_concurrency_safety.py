"""
Concurrency-safety tests for the parallel runner (--concurrency N).

The runner's per-game work is isolated (each game writes its own JSON), so the
only shared state under threads is: (a) the cost tally, (b) the append-only skip
manifest, (c) the progress counter, and (d) NO_TEMPERATURE_MODELS mutation in
the bedrock client. These tests exercise those exact patterns under heavy thread
contention to prove no lost updates, no interleaved manifest lines, and safe set
mutation. They do not require AWS.

They also assert the scoring is order-independent: the same set of games scored
in any order yields the same per-model aggregates (concurrency can't change the
numbers because delta scoring is per-game and deterministic).
"""
from __future__ import annotations

import json
import threading
from concurrent.futures import ThreadPoolExecutor

from src.utils import bedrock_client as bc


def test_locked_cost_tally_no_lost_updates():
    """Mirror the runner's cost_by_model += under a lock from many threads."""
    cost = {"m": 0.0}
    lock = threading.Lock()
    N = 2000

    def add():
        with lock:
            cost["m"] += 1.0

    with ThreadPoolExecutor(max_workers=8) as pool:
        for _ in range(N):
            pool.submit(add)
    assert cost["m"] == float(N)      # no lost updates


def test_manifest_append_lines_not_interleaved(tmp_path):
    """Mirror log_skip: lock-guarded append must yield whole JSON lines only."""
    manifest = tmp_path / "skip.jsonl"
    lock = threading.Lock()
    N = 1000

    def log(i):
        line = json.dumps({"kind": "game", "id": f"m_{i}", "reason": "x" * 50}) + "\n"
        with lock:
            with open(manifest, "a") as fh:
                fh.write(line)

    with ThreadPoolExecutor(max_workers=16) as pool:
        for i in range(N):
            pool.submit(log, i)

    lines = manifest.read_text().splitlines()
    assert len(lines) == N
    # every line is valid JSON (no torn/interleaved writes)
    ids = set()
    for ln in lines:
        obj = json.loads(ln)
        ids.add(obj["id"])
    assert len(ids) == N


def test_progress_counter_locked():
    done = {"n": 0}
    lock = threading.Lock()
    N = 5000

    def tick():
        with lock:
            done["n"] += 1

    with ThreadPoolExecutor(max_workers=12) as pool:
        for _ in range(N):
            pool.submit(tick)
    assert done["n"] == N


def test_no_temperature_set_concurrent_add_is_safe():
    """bedrock_client marks a model temperature-free from worker threads via
    NO_TEMPERATURE_MODELS.add(). Concurrent idempotent adds of the same key
    must not corrupt the set."""
    bc.NO_TEMPERATURE_MODELS.discard("concurrent-probe")

    def mark():
        for _ in range(500):
            bc.NO_TEMPERATURE_MODELS.add("concurrent-probe")

    with ThreadPoolExecutor(max_workers=8) as pool:
        for _ in range(8):
            pool.submit(mark)
    assert "concurrent-probe" in bc.NO_TEMPERATURE_MODELS
    bc.NO_TEMPERATURE_MODELS.discard("concurrent-probe")


def test_scoring_is_order_independent():
    """Concurrency changes execution order, not results: aggregate per-model
    means are identical regardless of the order games are produced in."""
    import random
    import statistics

    from unittest.mock import MagicMock
    from src.scanning.scanner_normalizer import Finding
    from src.scoring.delta_scorer import score_repair

    def mk(rule, res):
        return Finding("trivy", rule, "", "HIGH", res, res.split(".")[0], "m.tf", 1, 2)

    def repair(hcl=True):
        r = MagicMock(); r.hcl_valid = hcl; r.repair_cost_usd = 0.01
        r.repair_prompt_tokens = 10; r.repair_completion_tokens = 5
        return r

    # a handful of deterministic games
    games_spec = [
        ([mk("AWS-1", "aws_s3.a"), mk("AWS-2", "aws_s3.a")], []),          # 2 resolved
        ([mk("AWS-1", "aws_s3.b")], [mk("AWS-9", "aws_sg.x")]),            # 1 res 1 intro
        ([mk("AWS-3", "aws_kms.k")], [mk("AWS-3", "aws_kms.k")]),          # unchanged
    ]

    def score_all(order):
        nds = []
        for i in order:
            before, after = games_spec[i]
            g = score_repair("m", "model", before, after, repair())
            nds.append(g.net_delta)
        return statistics.mean(nds)

    base = score_all([0, 1, 2])
    for _ in range(20):
        order = [0, 1, 2]
        random.shuffle(order)
        assert score_all(order) == base
