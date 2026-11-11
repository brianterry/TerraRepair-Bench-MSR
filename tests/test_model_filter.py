"""
Tests for run_experiment.filter_models — the --models subset filter used for
targeted re-runs (recovering specific models at a higher token budget, or
adding a single new model) while leaving other models' existing games untouched.
"""
from __future__ import annotations

import importlib.util
import os

import pytest

_spec = importlib.util.spec_from_file_location(
    "run_experiment",
    os.path.join(os.path.dirname(__file__), "..", "scripts", "run_experiment.py"),
)
run_experiment = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(run_experiment)
filter_models = run_experiment.filter_models

MODELS = [
    {"id": "claude-sonnet-4-5"},
    {"id": "grok-4-6"},
    {"id": "claude-sonnet-5"},
    {"id": "deepseek-r1"},
    {"id": "nova-pro"},
]


def test_single_model():
    out = filter_models(MODELS, "grok-4-6")
    assert [m["id"] for m in out] == ["grok-4-6"]


def test_subset_preserves_config_order():
    # requested order differs from config order; config order must win
    out = filter_models(MODELS, "claude-sonnet-5,grok-4-6")
    assert [m["id"] for m in out] == ["grok-4-6", "claude-sonnet-5"]


def test_recovery_trio():
    out = filter_models(MODELS, "grok-4-6,claude-sonnet-5,deepseek-r1")
    assert {m["id"] for m in out} == {"grok-4-6", "claude-sonnet-5", "deepseek-r1"}


def test_whitespace_and_empty_tokens_ignored():
    out = filter_models(MODELS, " grok-4-6 , , claude-sonnet-5 ")
    assert {m["id"] for m in out} == {"grok-4-6", "claude-sonnet-5"}


def test_unknown_id_raises():
    with pytest.raises(SystemExit) as e:
        filter_models(MODELS, "grok-4-6,typo-model")
    assert "typo-model" in str(e.value)


def test_all_unknown_raises():
    with pytest.raises(SystemExit):
        filter_models(MODELS, "nope")
