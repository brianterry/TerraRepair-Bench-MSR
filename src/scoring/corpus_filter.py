"""
Canonical corpus filter — the SINGLE source of truth for paper §3.1.

The paper (Methodology §3.1) defines the evaluation corpus as Terraform
modules whose confirmed finding count is in the closed interval [3, 50]:

  * modules with fewer than 3 findings are near-trivial repair tasks and are
    dropped ("only modules yielding at least three confirmed findings are
    retained");
  * modules with more than 50 findings are excluded as monolithic outliers
    ("Six modules exceeding 50 findings were additionally excluded — one
    carried 215 findings alone").

This module centralizes that rule so that sampling, scoring, and analysis all
apply the *same* definition. Prior to this, the filter lived only in
`terrads_sampler.select_final_corpus` (which was not applied when the recorded
games were scored), so `analyze.py` averaged over an unfiltered 200-module set.
See HARNESS_AUDIT.md "Finding A" and CORPUS.md for the full reconciliation of
the 194 / 200 / "180" discrepancy.

Finding-count basis
-------------------
`in_corpus(finding_count)` takes a single integer count. Two bases exist in the
repo and BOTH must be filtered with this same function:

  * sampling time  — `metadata.json["findings_count"]` (raw scanner count at
    corpus construction; this is the basis that yields the paper's 194).
  * scoring time   — `GameResult.target_count`, i.e. the deduplicated
    ``|before_keys|`` on ``(rule_id, resource_name)``. This is the basis used
    when regenerating tables from recorded game JSONs, because it is present
    for every scored module and is what actually feeds the metrics.

The bounds are identical regardless of basis; only the count source differs.
"""
from __future__ import annotations

# Paper §3.1 bounds (inclusive on both ends).
MIN_FINDINGS = 3
MAX_FINDINGS = 50


def in_corpus(finding_count: int) -> bool:
    """Return True iff a module's finding count satisfies §3.1: 3 <= n <= 50."""
    return MIN_FINDINGS <= finding_count <= MAX_FINDINGS


def filter_games(games: list[dict], count_key: str = "target_count") -> list[dict]:
    """
    Keep only the game records whose module is in the §3.1 corpus.

    Args:
        games: list of game dicts (each has ``count_key`` and ``module_id``).
        count_key: the field holding the module's finding count. Defaults to
            ``target_count`` (the scoring-time deduplicated basis).

    Returns:
        The subset of ``games`` whose ``count_key`` is in [3, 50].
    """
    return [g for g in games if in_corpus(g[count_key])]


def corpus_module_ids(games: list[dict], count_key: str = "target_count") -> set[str]:
    """Return the set of module_ids that pass the §3.1 filter."""
    return {g["module_id"] for g in filter_games(games, count_key)}
