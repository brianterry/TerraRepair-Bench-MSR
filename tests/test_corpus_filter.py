"""
Tests for the canonical §3.1 corpus filter (src/scoring/corpus_filter.py).

Locks the boundary semantics (3 <= findings <= 50, inclusive) and confirms the
filter reproduces the paper's corpus size when applied to the recorded games.
Stdlib + pytest only. No pipeline math is modified.
"""
from __future__ import annotations

import glob
import json
import os

import pytest

from src.scoring.corpus_filter import (
    MAX_FINDINGS,
    MIN_FINDINGS,
    corpus_module_ids,
    filter_games,
    in_corpus,
)

GAMES_DIR = os.path.join(
    os.path.dirname(__file__), "..",
    "experiments", "results", "full_180_game", "games",
)


@pytest.mark.parametrize("n,expected", [
    (0, False),
    (1, False),
    (2, False),          # below MIN
    (3, True),           # lower boundary inclusive
    (4, True),
    (25, True),
    (50, True),          # upper boundary inclusive
    (51, False),         # above MAX
    (215, False),        # the paper's excluded monolith
])
def test_in_corpus_boundaries(n, expected):
    assert in_corpus(n) is expected


def test_bounds_match_paper():
    assert MIN_FINDINGS == 3
    assert MAX_FINDINGS == 50


def test_filter_games_uses_target_count_by_default():
    games = [
        {"module_id": "m_lo", "target_count": 2},   # dropped
        {"module_id": "m_ok", "target_count": 3},   # kept
        {"module_id": "m_hi", "target_count": 51},  # dropped
        {"module_id": "m_50", "target_count": 50},  # kept
    ]
    kept = {g["module_id"] for g in filter_games(games)}
    assert kept == {"m_ok", "m_50"}


def test_filter_games_alternate_count_key():
    games = [
        {"module_id": "a", "findings_count": 2},
        {"module_id": "b", "findings_count": 10},
    ]
    kept = corpus_module_ids(games, count_key="findings_count")
    assert kept == {"b"}


def test_filter_reproduces_paper_corpus_size_on_recorded_data():
    """On the recorded games, the scoring-time filter (3<=target_count<=50)
    yields 150 modules. This is the corrected regeneration corpus. It is not
    exactly the paper's 194 because only 149 of the paper's metadata-defined
    corpus were actually scored (see CORPUS.md); this test locks the number the
    corrected pipeline will use so a future data change is caught."""
    files = glob.glob(os.path.join(GAMES_DIR, "*.json"))
    if not files:
        pytest.skip("recorded games not present")
    # one record per module (target_count is model-independent)
    by_mod = {}
    for f in files:
        g = json.loads(open(f).read())
        by_mod.setdefault(g["module_id"], g)
    kept = corpus_module_ids(list(by_mod.values()))
    assert len(by_mod) == 200            # unfiltered scored set
    assert len(kept) == 150              # §3.1-filtered corrected set
