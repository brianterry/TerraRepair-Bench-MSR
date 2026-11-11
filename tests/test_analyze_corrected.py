"""
Tests for the corrected regenerator (scripts/analyze_corrected.py).

Confirms Fix 2: the regeneration re-derives scores under the paper §3.3 HCL
rule (invalid HCL => 0/0/0) rather than trusting the stored scalars, which for
the recorded data are mis-credited for 9 games.

Also confirms the corpus filter (Fix 1) is applied in the regeneration path.
Stdlib + pytest only. delta_scorer math untouched.
"""
from __future__ import annotations

import importlib.util
import os

import pytest

_SPEC = importlib.util.spec_from_file_location(
    "analyze_corrected",
    os.path.join(os.path.dirname(__file__), "..", "scripts", "analyze_corrected.py"),
)
analyze_corrected = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(analyze_corrected)


def test_invalid_hcl_game_is_rezeroed_even_if_stored_scalars_credit_it():
    """The recorded shape: hcl_valid False but stored resolved=8/net=8 (bug).
    The regenerator must ignore the stored scalars and return 0/0/0."""
    game = {
        "module_id": "module_0002",
        "model_id": "claude-sonnet-4",
        "hcl_valid": False,
        "repair_success_rate": 1.0,   # mis-credited in the recorded JSON
        "regression_rate": 0.0,
        "net_delta": 8,
        "resolved_count": 8,
        "introduced_count": 0,
    }
    cm = analyze_corrected.corrected_metrics(game)
    assert cm["hcl_zeroed"] is True
    assert cm["repair_success_rate"] == 0.0
    assert cm["regression_rate"] == 0.0
    assert cm["net_delta"] == 0
    assert cm["resolved_count"] == 0
    assert cm["introduced_count"] == 0


def test_valid_hcl_game_keeps_verified_stored_scalars():
    game = {
        "module_id": "m", "model_id": "x", "hcl_valid": True,
        "repair_success_rate": 0.5, "regression_rate": 0.25,
        "net_delta": 2, "resolved_count": 3, "introduced_count": 1,
    }
    cm = analyze_corrected.corrected_metrics(game)
    assert cm["hcl_zeroed"] is False
    assert cm["net_delta"] == 2
    assert cm["repair_success_rate"] == 0.5


def test_missing_hcl_valid_defaults_to_valid():
    """A record without hcl_valid is treated as valid (no silent zeroing)."""
    game = {"module_id": "m", "model_id": "x",
            "repair_success_rate": 0.5, "regression_rate": 0.0,
            "net_delta": 1, "resolved_count": 1, "introduced_count": 0}
    cm = analyze_corrected.corrected_metrics(game)
    assert cm["hcl_zeroed"] is False
    assert cm["net_delta"] == 1
