# Canonical Corpus Definition — TerraRepair-Bench

This document defines the **one** corpus rule used across sampling, scoring, and
analysis, and reconciles the conflicting counts (194 vs 200 vs "180") that the
audit surfaced (see HARNESS_AUDIT.md, Finding A).

## The rule (paper §3.1)

A module is **in the corpus** iff its confirmed finding count is in the closed
interval **[3, 50]**:

- **≥ 3 findings** — drops near-trivial repair tasks.
- **≤ 50 findings** — excludes monolithic outliers ("Six modules exceeding 50
  findings were additionally excluded — one carried 215 findings alone").

This rule now lives in exactly one place: **`src/scoring/corpus_filter.py`**
(`MIN_FINDINGS = 3`, `MAX_FINDINGS = 50`, `in_corpus()`). Every consumer imports
it:

- `scripts/analyze.py --corpus-filter` (opt-in on the legacy analyzer)
- `scripts/analyze_corrected.py` (always applied in the corrected regeneration)
- `src/sampling/terrads_sampler.select_final_corpus` (enforces both bounds at
  sampling time; previously enforced only the lower bound)

## Finding-count basis

The count can be measured at two points; the **bounds are identical**, only the
source differs:

| Basis | Source | Used by |
|-------|--------|---------|
| Sampling-time | `metadata.json["findings_count"]` (raw scanner count when the corpus was built) | sampler; defines the paper's 194 |
| Scoring-time | `GameResult.target_count` = deduped `\|before_keys\|` on `(rule_id, resource_name)` | corrected regeneration from recorded games |

The scoring-time basis is used to regenerate tables because it is present for
every scored game, is model-independent (identical across all 6 models for a
given module — verified), and is the count that actually feeds RSR/RR/ND.

## Reconciling 194 vs 200 vs "180"

Empirical census of the recorded artifacts:

- **`data/terrads_sample/`** holds **200** modules with `metadata.json`. **All
  200** have `findings_count ≥ 3` (the sampler applied the lower bound).
  **Exactly 194** have `findings_count ∈ [3, 50]`; **exactly 6** exceed 50
  (`module_0072`=52, `0126`=54, `0128`=54, `0135`=76, `0151`=215, `0349`=71).
  → **This is the paper's 194**, and the 6 excluded match "one carried 215."
- **`experiments/results/full_180_game/games/`** holds **200 modules × 6 models
  = 1,200 game JSONs**. This scored set is **NOT** the paper's 194 corpus:
  - Only **149** modules are in **both** the paper's 194 **and** the scored set.
  - **45** of the paper's 194 corpus modules were **never scored** (no game
    JSON).
  - **51** scored modules are **outside** the paper's 194: **5** exceed 50
    findings (should have been excluded), and **46** have **no `metadata.json`
    at all** (e.g. `module_0068`, dir absent, scored with `target_count`=35).
- The experiment directory is named `full_180_game` — a **third** number that
  matches neither 194 nor 200. There is no artifact tying "180" to any actual
  module set; treat it as a stale label.

Applying the §3.1 filter to the **scored** data (`3 ≤ target_count ≤ 50`) keeps
**150** modules → 900 trials. That 150 = the 149 paper∩scored modules **plus
`module_0068`** (no metadata, but its scored `target_count`=35 lands in band).

### Canonical corpus for regeneration

Because no model inference is run in this session, the corrected tables are
regenerated over the **150 modules with `3 ≤ target_count ≤ 50`** that have
recorded data. This is the largest deterministically-defined, §3.1-compliant
subset of the recorded games.

> **Honest caveat:** this 150-module set is **not** identical to the paper's
> stated 194. Only 149 of the paper's corpus were ever scored; 45 have no
> recorded data and cannot be regenerated without new inference; and one
> additional module (`module_0068`) has recorded data but no sampling metadata.
> A fully paper-faithful re-run must (a) re-sample so all 194 are scored, and
> (b) drop `module_0068` (no provenance) or restore its `metadata.json`.

## For a clean future re-run

1. Build the corpus with `select_final_corpus(..., min_findings=3,
   max_findings=50, skip_manifest_path=...)` so both bounds are enforced and
   every rejected candidate is recorded.
2. Score **only** modules that pass `corpus_filter.in_corpus`, so the scored set
   and the corpus definition cannot drift apart.
3. Expect **194** modules / **1,164** trials if the same TerraDS snapshot and
   scanners are used; reconcile any deviation against the skip manifest.
