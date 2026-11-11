# TerraRepair-Bench — Harness Correctness Audit

**Scope:** read-and-verify audit of the 4-stage pipeline
(`src/sampling` → `src/scanning` → `src/repair` → `src/scoring`, driven by
`scripts/`) before a full experimental re-run. No pipeline logic was modified.
Deliverables are this document plus new tests under `tests/`.

**Method:** static reading of every pipeline module; cross-check against the
paper Methodology (§3–4, `paper.txt`); and a **read-only re-computation over all
1,200 recorded game JSONs** in `experiments/results/full_180_game/games/`
(harness: `tests/audit_recompute.py`, stdlib only, imports/modifies nothing).

**Verdict in one line:** the *scoring math is correct*, but the *published
numbers were computed over a corpus that contradicts the paper's own stated
filters*, and two scored games credit invalid output. The headline scientific
conclusion (reasoning models regress less) survives; specific Table 1 values do
not. **Do not re-baseline a new paper on the current recorded numbers without
re-running `analyze.py` over a corpus that matches §3.1.**

---

## Summary table

| # | Claim | Verdict | Impact |
|---|-------|---------|--------|
| 1 | Delta scoring correct (set-diff on `(rule_id, resource_name)`) | **PASS** | — |
| 2 | Scanner normalization faithful / key stable across versions | **CONCERN** | Re-run hazard |
| 3 | HCL-invalid ⇒ zero-resolved / zero-introduced | **FAIL (data)** | 9 games mis-scored |
| 4 | Completeness checker catches 57.7% of regressions | **PASS** | — |
| 5 | Determinism (temp-0, token clamps) + skips logged | **MIXED** | Skips not logged |
| A | Corpus matches paper (194 modules, ≥3 & ≤50 findings) | **FAIL** | **Flips a headline sign** |
| B | Severity-aware gating (G2/G3) sees all regressions | **CONCERN** | ~44% invisible |

Priorities are called out with 🔴 (would make a published number wrong),
🟠 (methodology/code disagreement), 🟡 (hygiene / re-run readiness).

---

## 🔴 FINDING A — Published results were computed on a corpus that violates the paper's own filters (highest priority)

**Paper §3.1 / §3.5:** corpus is **194 modules**, **1,164 trials**, mean **15.1**
findings/module; modules are retained only with **≥ 3 confirmed findings**, and
**6 modules with > 50 findings were excluded** ("one carried 215 findings
alone").

**What the recorded data actually is** (re-derived over
`experiments/results/full_180_game/games/`):

- **200 modules, 1,200 trials** (6 models × 200), not 194 / 1,164.
- **45 modules have `target_count < 3`** — including **modules with 0 findings**
  — despite the ≥3 rule.
- **5 modules have > 50 findings, and the 215-finding module the paper says was
  excluded is still present and scored.**
- Mean `target_count` = **12.3**, not 15.1.
- The experiment is named `full_180_game` yet contains 200 modules — a third
  distinct number.

`scripts/analyze.py` builds the published `results_summary.json` and Table 1–3
by taking `np.mean` of the stored `repair_success_rate` / `regression_rate` /
`net_delta` over **every** JSON in `games/`. It applies **no** corpus filter.
So Table 1 was computed over the unfiltered 200-module set.

**Why this is publication-critical — it flips a sign.** Re-running the exact same
averages after applying the paper's own `3 ≤ findings ≤ 50` filter (150 modules
in the recorded set):

| Model | ND (published, 200 mods) | ND (paper filter, 150 mods) |
|-------|--------------------------|------------------------------|
| claude-sonnet-4 | **+1.16** | **−0.73**  ← sign flip |
| deepseek-r1 | +7.11 | +8.05 |
| nova-pro | +3.00 | +2.83 |
| qwen3-32b | +1.45 | +1.13 |
| nova-lite | −0.94 | −1.48 |
| llama-3-3-70b | −1.67 | −2.25 |

The paper's §4.1 narrative — *"[Claude's] net delta of only +1.2, placing it
fourth"* — depends on the unfiltered corpus. Under the paper's stated filter,
Claude Sonnet 4 is **net-negative**. Neither corpus (200 nor the 150 that
survive the filter) equals the paper's stated **194**, so the exact set behind
the published numbers is currently unaccounted for.

**Evidence:** `tests/audit_recompute.py` (module counts, `<3` / `>50` census);
reproduce with:
```
python3 - <<'PY'
import json, glob, statistics
from collections import defaultdict
games=[json.load(open(f)) for f in glob.glob("experiments/results/full_180_game/games/*.json")]
tc={g["module_id"]:g["target_count"] for g in games}
print("modules:",len(tc),"<3:",sum(v<3 for v in tc.values()),">50:",sum(v>50 for v in tc.values()),
      "mean:",round(sum(tc.values())/len(tc),1))
PY
```

**Before re-running:** decide the canonical corpus, apply the §3.1 filter in a
single documented place (currently the filter lives only in
`select_final_corpus`, which was evidently not applied to the scored set), and
regenerate all tables. Reconcile 194 vs 200 vs "180".

---

## 🔴 CLAIM 3 — HCL-validation gating: FAIL (recorded data), PASS (current code)

**Paper §3.3:** responses that fail HCL validation are recorded as
`hcl_valid: False` and *"assigned zero resolved findings and zero introduced
regressions."*

**Current code (`delta_scorer.score_repair`) is correct:** when
`repair_result.hcl_valid` is false it sets `findings_after = list(findings_before)`,
forcing resolved = 0, introduced = 0, net = 0. Verified by
`tests/test_delta_scorer_audit.py::test_current_code_zero_credits_invalid_hcl`.

**But the recorded experiment data does not obey this rule.** Over the 1,200
JSONs:

- **74 games (6.2%) have `hcl_valid = false`.**
- **9 of them are credited with `resolved > 0` and positive `net_delta` while
  `findings_after = []`** — i.e. malformed output that made findings vanish was
  scored as a successful repair. Examples:
  - `module_0002_claude-sonnet-4.json`: `hcl_valid=false`, `resolved=8`,
    `net_delta=8`, `findings_after=[]`, `repair_success_rate=1.0`.
  - `module_0002_qwen3-32b.json`, `module_0021_qwen3-32b.json`: same shape, net 8.
  - `module_0006/0011 × claude/deepseek/qwen`: net 1 each.

This means the recorded games were produced by an **earlier scorer without the
guard**, and `analyze.py` simply averaged the stored fields, so the published
numbers include this bogus credit. The gate in `gating.py` cannot catch it
either: `GatingPolicy.evaluate` recomputes net delta from whatever
`findings_after` it is handed (empty), so it also credits the 8 as resolved
(`tests/test_gating_audit.py::test_gate_does_not_reapply_hcl_zeroing`).

**Impact is bounded but real and directional.** Re-scoring under the paper's rule
(invalid ⇒ 0/0/0):

| Model | ND recorded | ND paper-rule | #invalid |
|-------|-------------|---------------|----------|
| claude-sonnet-4 | +1.16 | +1.11 | 8 |
| deepseek-r1 | +7.11 | +7.10 | 10 |
| qwen3-32b | +1.45 | +1.36 | 8 |
| others | unchanged | unchanged | 14/21/13 |

Rankings and the reasoning-vs-non-reasoning gap (0.312) are unchanged by this
alone. **However this is not independent of Finding A** — the invalid-HCL games
are part of the same unfiltered set — so both corrections must be applied
together when regenerating tables.

**Evidence:** `tests/audit_recompute.py` "HCL validity" block;
`tests/test_delta_scorer_audit.py`, `tests/test_gating_audit.py`.

---

## ✅ CLAIM 1 — Delta scoring is correct: PASS

`delta_scorer.score_repair` computes the primary metrics exactly as the paper
§3.4 defines them, using set differences on the `(rule_id, resource_name)` key
(`_finding_key`):

- `resolved_count = |before_keys − after_keys|`
- `introduced_count = |after_keys − before_keys|`
- `unchanged_count = |before_keys ∩ after_keys|`
- `RSR = resolved / target`, `RR = introduced / target`, `ND = resolved −
  introduced`, all guarded against `target == 0`.

**Cross-check against recorded data:** for **all 1,200 games**, the stored
`(resolved_count, introduced_count, net_delta)` scalars **exactly match** an
independent set-diff recomputation from the stored `findings_before` /
`findings_after` (0 mismatches). Keying is exact: same rule on a different
resource, or same resource with a different rule, are treated as distinct
(`tests/test_delta_scorer_audit.py::test_keying_is_on_rule_id_AND_resource_name`).

**Minor CONCERN (does not affect primary metrics):**

- 🟡 `class_breakdown` (Table 2 category counts) iterates `findings_before` /
  `findings_after` as **lists**, not the deduped key sets. If the same
  `(rule_id, resource_name)` arrives from both scanners and survives into the
  scored lists, category tallies can double-count it, whereas RSR/RR/ND count it
  once. Table 2 totals may therefore be slightly inflated relative to the
  primary metrics. Low severity; flag only because Table 2 is a published table.
- 🟠 **Paper wording bug (not a code bug):** §3.4 says *"Net delta is the
  absolute difference between resolved and introduced findings."* The code uses
  the **signed** difference (`resolved − introduced`), which is what produces the
  reported negative net deltas (Nova Lite −0.9, Llama −1.7). "absolute" should be
  "signed" in the paper.

---

## 🟠 CLAIM 2 — Scanner normalization: PASS within a run, CONCERN across versions

**Within a single run, normalization is faithful.** `deduplicate_findings` keys
on `(resource_name, rule_id)`, keeps the first occurrence, and drops nothing
else; cross-scanner duplicates collapse to one while distinct findings survive
(`tests/test_scanner_normalizer_audit.py`). No silent drop or double-count in the
dedup path.

**Two concerns for the re-run:**

- 🔴/🟠 **The `(rule_id, resource_name)` key is NOT stable across Trivy
  versions.** `normalize_trivy_findings` stores `item["ID"]` **verbatim**. The
  recorded corpus contains bare IDs like `AWS-0104` (census: 67 distinct Trivy
  IDs, **none** `AVD-`-prefixed). Modern Trivy `config` emits IDs as
  `AVD-AWS-0104`. A re-run with current Trivy will therefore produce a different
  key for the *same* misconfiguration
  (`tests/test_scanner_normalizer_audit.py::test_trivy_id_stored_verbatim_modern_prefix`).
  Consequences on re-run: (a) any comparison against the recorded corpus breaks;
  (b) **the completeness checker's `RULE_MAPPING` — which uses bare `AWS-xxxx` —
  would match ~0 Trivy rules**, silently collapsing its coverage (see Claim 4).
  Delta scoring *within* a re-run stays internally consistent (before/after use
  the same scanner), so this corrupts cross-run and completeness comparisons, not
  the intra-run RSR/RR.
- 🟡 **Silent scanner failure = "clean".** `ScannerStack.run` wraps each scanner
  in `except Exception: pass`. If Trivy or Checkov crashes, times out, or is not
  installed, that scanner contributes **zero findings** with no log. A post-repair
  scan that silently fails looks like a perfect repair (all findings resolved).
  Combined with Claim 5's silent skips, a scanner outage during a re-run could
  inflate resolution rates invisibly.

---

## ✅ CLAIM 4 — Completeness checker "57.7%": PASS (reproduced exactly)

`completeness_checker.evaluate_coverage_on_games` computes, per game,
`introduced = after_keys − before_keys`, then counts a regression as "covered"
if its `rule_id` is in `ALL_COVERED_SCANNER_RULES` (the union of `RULE_MAPPING`).

**Re-derived independently over all 1,200 games:**

- total regressions = **7,206**
- covered = **4,161**
- coverage = **57.74%**

This matches `completeness_analysis.json` (`total_regressions: 7206`,
`covered_by_checker: 4161`, `coverage_pct: 57.7435…`) to the digit. **The 57.7%
claim reproduces.**

**Caveats to record:**

- 🟡 The number is a **pattern-overlap upper bound**, not a validated catch rate:
  it counts a regression as "caught" if its rule id is in a mapped set, without
  running the regex checker on the actual repaired HCL. The docstring's "catches
  57.7%" should be read as "57.7% of regressions fall into rule families the
  checker targets."
- 🔴 **Version-fragile (ties to Claim 2):** `RULE_MAPPING` mixes Checkov ids
  (`CKV_AWS_7`) with **bare** Trivy ids (`AWS-0094`). It reproduces 57.7% here
  only because the recorded corpus stored bare Trivy ids. On a re-run producing
  `AVD-AWS-0094`, every Trivy branch of the mapping misses and coverage would
  drop sharply. `norm()`-stripping the `AVD-` prefix in the audit harness leaves
  57.74% unchanged **on this data**, confirming the recorded ids are already bare.

---

## 🟠 CLAIM 5 — Determinism & skip logging: MIXED

**PASS — determinism knobs are wired correctly:**

- `repair_agent.repair_module` calls `bedrock_client.invoke(..., temperature=0.0)`
  and the default is 0.0 throughout.
- Per-model output-token clamps exist in
  `bedrock_client._MODEL_MAX_TOKENS` (claude 64000, nova-pro/lite 10000, llama
  8192, deepseek/qwen 16384) and are applied via
  `max_tokens = min(max_tokens, model_limit)`. This matches §3.5's "Nova and Llama
  impose lower output token ceilings — 10,000 and 8,192."

**FAIL — the "~9% skipped due to repo churn" claim is not reproducible from any
code artifact:**

- `terrads_sampler.clone_and_extract_module` raises `FileNotFoundError` when a
  module path has moved/been deleted, and `select_final_corpus` swallows it with
  `except Exception: continue`. **No counter, no log line, no manifest** of what
  was skipped or why.
- `run_experiment.py`'s auto-resume also silently `continue`s on any existing
  game file.
- There is no record in the repo that ties "9%" to an actual skip count. The
  claim may be true, but it is **not evidenced** and cannot be re-derived. A
  re-run should emit a skip manifest (module id, reason) so this number is
  auditable.

🟡 **Determinism caveat worth stating in the paper:** temperature 0 reduces but
does not guarantee bit-identical Bedrock output across dates/regions/model minor
versions. The benchmark cannot claim exact reproducibility of model text, only of
*scoring given fixed findings*.

---

## 🟠 FINDING B — Severity-aware gating (G2/G3) is blind to ~44% of regressions

`GatingPolicy` (G2 = no CRITICAL, G3 = no HIGH) keys off `Finding.severity ==
"CRITICAL"/"HIGH"`. But **Checkov findings normalize to `UNKNOWN`**:
open-source Checkov `failed_checks` carry no severity, and
`normalize_checkov_findings` defaults to `UNKNOWN`
(`tests/test_scanner_normalizer_audit.py::test_checkov_without_severity_normalizes_to_unknown`).

Over the recorded regressions: **3,190 of 7,206 (44.3%) come from Checkov, and
0 of them carry CRITICAL or HIGH.** So G2/G3 can only ever act on Trivy
regressions. A repair that introduces a Checkov-detected critical misconfiguration
passes G2 and G3 unchecked
(`tests/test_gating_audit.py::test_g2_g3_blind_to_checkov_regressions`).

The severity distribution across all findings is: `UNKNOWN` 23,469 (all Checkov),
Trivy `HIGH` 1,492 / `LOW` 1,067 / `MEDIUM` 776 / `CRITICAL` 681. If the gating
policies feature in any published claim, they are half-sighted. (Gating is
applied by the side script `scripts/gated_repair.py`; if it is not part of the
paper's headline results, this is a CONCERN rather than a FAIL.)

---

## Other issues (🟡 hygiene / minor)

- **`bedrock_client` vs paper model id mismatch.** Paper §3.5 lists Qwen as
  `us.qwen.qwen3-32b-v1:0` (with `us.` inference-profile prefix). Both
  `SUPPORTED_MODELS` and `experiments/configs/full_experiment.yaml` use
  `qwen.qwen3-32b-v1:0` (no `us.`). One is wrong; reconcile before re-run or the
  Qwen invocation will fail / hit a different endpoint than documented.
- **`scripts/gated_repair.py` dead code + wrong effective-RSR.** `mean_rsr` is
  computed then never used; and effective RSR is computed as
  `sum(eff_resolved)/count(eff_resolved)` — a mean of raw **counts**, not a rate,
  so it is not comparable to the RSR reported elsewhere. Side script only; does
  not affect `results_summary.json`.
- **`is_valid_hcl` is a heuristic, not a parser.** It checks brace balance and
  keyword presence. The paper §3.3 says "using an HCL parser." Malformed-but-
  brace-balanced output can pass. Low impact given Claim 3's bounded effect, but
  the paper overstates the check.
- **`sanitize_repair_response` can raise `ValueError` ("too short", "refused")
  that `repair_module` catches and turns into `success=False`.** That path is
  handled, but the `< 50 char` and refusal-phrase heuristics could misclassify a
  legitimately tiny valid repair as a refusal. Edge case; note for re-run QA.

---

## Re-run readiness for a new Bedrock model cohort

**Adding current Bedrock models is mostly config, with two small code touch-points.**

*Config only (no code):* add each model to `experiments/configs/full_experiment.yaml`
under `models:`. The runner iterates `config["models"]` generically.

*Requires code edits in `src/utils/bedrock_client.py`:*
1. `SUPPORTED_MODELS` — add the friendly-id → Bedrock-id mapping.
2. `_MODEL_MAX_TOKENS` — add the new model's output ceiling (else it silently
   falls back to the caller's `max_tokens`, risking validation errors).
3. Routing: `invoke` dispatches by substring (`"claude"` → Claude body,
   `_INVOKE_MODEL_IDS = {"qwen"}` → raw invoke, else Converse). A new model whose
   API shape differs (e.g. a new Anthropic/InvokeModel schema, or a model needing
   `invoke_model` rather than Converse) needs a new branch and possibly a new
   `_invoke_*` method.
4. `src/repair/repair_agent.py::MODEL_COSTS` — add per-1K token prices, or cost
   tracking silently defaults to `(0.001, 0.001)` and reports wrong `$/module`.
5. `src/utils/response_sanitizer.py` — reasoning models with new "thinking"
   delimiters (the current code special-cases only DeepSeek `<think>`) may need a
   new strip rule, or their HCL will fail validation.

**Also required before a clean re-run (independent of model cohort):**
- Pin Trivy and Checkov versions (Claim 2 key stability); if using modern Trivy,
  either strip the `AVD-` prefix at normalization or update `RULE_MAPPING` and any
  corpus comparisons.
- Apply the §3.1 corpus filter in one documented place and reconcile the 194 /
  200 / "180" discrepancy (Finding A).
- Add skip/skip-reason logging to the sampler and runner (Claim 5).
- Confirm the HCL-gating guard now in `score_repair` is the code path used to
  score (Claim 3), and regenerate `results_summary.json` from scratch.

---

## Tests added (this audit)

All under `tests/`, stdlib + pytest only, no pipeline code modified. Full suite
(new + pre-existing) passes: **28 passed**.

- `tests/test_delta_scorer_audit.py` — hand-built before/after sets with known
  RSR/RR/ND; exact-keying; RR>1 legitimacy; divide-by-zero guard; and the
  current-code HCL zeroing vs the recorded-data divergence.
- `tests/test_scanner_normalizer_audit.py` — Trivy `AVD-` prefix key instability;
  Checkov `UNKNOWN` severity; dedup keeps distinct / collapses cross-scanner dupes
  / never drops same-rule-different-resource.
- `tests/test_gating_audit.py` — G1 net rule; G2 rejects CRITICAL; G2/G3 blind to
  Checkov/UNKNOWN regressions; gate does not re-apply HCL zeroing.
- `tests/audit_recompute.py` — **read-only** data harness that re-derives all of
  the above statistics from `experiments/results/full_180_game/`. Run:
  `python3 tests/audit_recompute.py experiments/results/full_180_game/games experiments/results/full_180_game/completeness_analysis.json`

---

## Bottom line for the re-run decision

- The **metric engine is trustworthy**: set-diff scoring is exact and reproduces
  the recorded scalars perfectly, and the 57.7% completeness figure reproduces.
- The **published aggregate numbers are not re-run-ready as-is**: they were
  averaged over a 200-module corpus that violates the paper's ≥3 / ≤50 filter and
  includes 9 invalid-HCL games credited as successes. Correcting to the paper's
  stated corpus **flips Claude Sonnet 4's net delta negative**, so at least one
  Table 1 value and its §4.1 narrative would change.
- The **central conclusion** (reasoning models regress far less; gap ≈ 0.31) is
  robust to the HCL-gating correction and is not driven by the mis-scored games.
- Before building a new paper on this harness: fix the corpus definition, pin
  scanner versions (Trivy id prefix), add skip logging, confirm the gating guard
  is on the scoring path, and regenerate every table from `analyze.py`.
