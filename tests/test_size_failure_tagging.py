"""
Tests for option-A oversized-template handling in run_experiment.

Scoring is unchanged (oversized/failed repairs stay 0/0/0, attributed to the
model). What these test are the pure helpers that TAG a size-driven failure and
record size metadata, enabling the paper §3.5 "reported separately" cut.
"""
from __future__ import annotations

import importlib.util
import os

_spec = importlib.util.spec_from_file_location(
    "run_experiment",
    os.path.join(os.path.dirname(__file__), "..", "scripts", "run_experiment.py"),
)
run_experiment = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(run_experiment)


def test_est_input_tokens():
    assert run_experiment._est_input_tokens(4000) == 1000
    assert run_experiment._est_input_tokens(0) == 0


def test_size_driven_failure_true_for_large_module():
    # 100k chars ~= 25k tokens > 16384 max_tokens -> size-driven
    assert run_experiment._is_size_driven_failure(100_000, 16384) is True


def test_size_driven_failure_false_for_small_module():
    # 8k chars ~= 2k tokens, well under 16384 -> NOT size-driven
    assert run_experiment._is_size_driven_failure(8_000, 16384) is False


def test_size_driven_boundary():
    # exactly at the boundary: est tokens == max_tokens is NOT > max, so False
    chars = 16384 * run_experiment._CHARS_PER_TOKEN
    assert run_experiment._is_size_driven_failure(chars, 16384) is False
    assert run_experiment._is_size_driven_failure(chars + 4, 16384) is True


def test_module_source_chars(tmp_path):
    (tmp_path / "main.tf").write_text('resource "x" "y" {}\n')   # 20 chars
    (tmp_path / "vars.tf").write_text('variable "v" {}\n')       # 16 chars
    (tmp_path / "readme.md").write_text("ignored, not .tf")
    n = run_experiment._module_source_chars(str(tmp_path))
    assert n == len('resource "x" "y" {}\n') + len('variable "v" {}\n')
