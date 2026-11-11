# TerraRepair-Bench — Methodology

This document describes how TerraRepair-Bench measures a language model's
ability to repair security misconfigurations in Terraform (HCL) infrastructure
code. It reflects the harness as implemented (see the `src/` modules cited
throughout), not an aspirational design. Where a detail affects fairness or
result validity, it is called out explicitly.

---

## 1. Task definition

Each evaluation unit is a **game**: one Terraform module repaired by one model.

Given a module with known security misconfigurations, the model is asked to
return repaired HCL that fixes the issues while preserving the module's
infrastructure intent. Repair quality is measured by re-scanning the model's
output with the same static analyzers and comparing the finding sets before and
after — a deterministic, judge-free comparison.

A run is the full cartesian product **corpus × models**: every module is
attempted by every model under identical inputs.

---

## 2. Corpus

### 2.1 Source

Modules are drawn from a TerraDS-derived sample of real-world Terraform modules
(`data/terrads_sample/`), each a directory of `.tf` files with a `metadata.json`.

### 2.2 Inclusion rule (single source of truth)

A module is **in the corpus** iff its confirmed finding count lies in the closed
interval **[3, 50]**, defined once in `src/scoring/corpus_filter.py`
(`MIN_FINDINGS = 3`, `MAX_FINDINGS = 50`, `in_corpus()`):

- **≥ 3 findings** — drops near-trivial repair tasks.
- **≤ 50 findings** — excludes monolithic outliers.

Sampling, scoring, and analysis all import this one function so the corpus
definition cannot drift between stages. (Historically the bound lived only in
the sampler and was not applied at scoring time; see `CORPUS.md` and
`HARNESS_AUDIT.md` "Finding A" for the full reconciliation of the earlier
194 / 200 / "180" count discrepancy.)

### 2.3 Corpus construction at run time

The runner (`scripts/run_experiment.py`) builds the corpus **at sampling time**,
not by post-hoc filtering:

1. Every candidate module directory containing `.tf` files is scanned once.
2. A module is admitted iff its **pre-repair** deduplicated finding count is
   in `[3, 50]`.
3. Admitted modules are written to `corpus_manifest.jsonl` (with finding count,
   source size, and estimated input tokens); rejected or unscannable candidates
   are written to `skip_manifest.jsonl` with a reason.

The corpus is therefore fully reproducible and every excluded candidate is
accounted for in the skip manifest.

---

## 3. Scanner stack

Two independent static analyzers are run and their findings merged
(`src/scanning/`):

| Scanner | Invocation | Pinned version |
|---------|------------|----------------|
| Trivy   | `trivy config --format json --severity LOW,MEDIUM,HIGH,CRITICAL --quiet <dir>` | 0.74.0 |
| Checkov | `checkov --directory <dir> --output json --quiet --framework terraform` | 3.3.20 |

Versions are pinned in the `Dockerfile` and recorded in each run's
`run_manifest.json` (`_scanner_versions()`), so a result set is tied to the exact
analyzer versions that produced it.

### 3.1 Finding normalization and deduplication

Raw scanner output is normalized into a common `Finding` record
(`scanner_normalizer.py`). A finding's identity is the pair **(rule_id,
resource_name)**. Findings sharing that pair — including the same issue reported
by both Trivy and Checkov, or duplicated within one scanner — are collapsed to a
single finding (`deduplicate_findings`, first occurrence kept). This dedup key is
the same pair used by the scorer (§4), so "one finding" means the same thing at
scan time and score time.

### 3.2 Loud scanner failures (no silent zeros)

A scan can *fail* (scanner crash, timeout, or not installed) as distinct from
*finding nothing*. `ScannerStack.run_checked` returns a `ScanResult` whose `ok`
flag is true only if **every** invoked scanner completed; failures are recorded
in `failures` and logged. This matters for the **post-repair** scan: an empty
finding set from a crashed scanner would otherwise look like a perfect repair.
Post-repair scan failures are logged to the skip manifest and the game is not
scored as a success.

Trivy's per-scan timeout is configurable via `TERRAREPAIR_TRIVY_TIMEOUT` (default 180s;
the name deliberately avoids `TRIVY_TIMEOUT`, which Trivy reads as its own
`--timeout` flag). Any non-zero Trivy exit, or a missing/unparseable JSON report,
is a scanner failure, never "zero findings".
It was raised from an earlier 60s after large modules — the same ones that
stress model context windows — were timing out and dropping from the corpus, a
scanner-driven selection effect. Modules that still exceed the timeout are
recorded as `pre-repair scan failed` in the skip manifest and excluded, and that
exclusion is reported rather than hidden.

---

## 4. Scoring (the core metric)

Scoring is **deterministic set arithmetic on finding identities** — there is no
LLM judge (`src/scoring/delta_scorer.py`). For one game:

Let `before` = the set of `(rule_id, resource_name)` pairs from the pre-repair
scan, and `after` = the same from the post-repair scan.

- **resolved** = `|before − after|` — findings present before but gone after.
- **introduced** = `|after − before|` — new findings the repair created.
- **unchanged** = `|before ∩ after|` — findings the repair left in place.
- **target_count** = `|before|`.

From these:

- **Repair Success Rate (RSR)** = `resolved / target_count`
- **Regression Rate (RR)** = `introduced / target_count`
- **Net Delta (ND)** = `resolved − introduced` (positive = net improvement)

RSR and RR are 0 when `target_count == 0` (guards division). This set-difference
math is the benchmark's primary scientific contribution and is held stable —
it is covered by a dedicated regression test suite (`tests/test_delta_scorer*`)
and is never altered when other parts of the harness change.

### 4.1 Vulnerability-class breakdown

Each finding is classified into one of four categories by keyword match against
`rule_id` + `title` (`classify_finding`), following the security triad:

- **access_control** — IAM, security groups, public access, policies
- **data_protection** — encryption, secrets, backups, versioning
- **observability** — logging, monitoring, audit trails
- **other** — anything unmatched

resolved / introduced / unchanged counts are reported per class, so a model's
strengths and weaknesses can be read by category, not just in aggregate.

### 4.2 Invalid HCL handling

If the model's output fails HCL validation, no repaired code is written and no
post-repair scan runs. Rather than treat the empty scan as "all resolved," the
scorer sets `after = before` — i.e. **nothing was fixed** — yielding RSR 0, RR 0,
ND 0 for that game. This attributes an unparseable repair to the model, as a
failure, not a success.

---

## 5. Model invocation

### 5.1 Prompt

Every model receives the **identical** prompt (`src/repair/repair_agent.py`,
`REPAIR_PROMPT`): the concatenated `.tf` source plus a formatted list of the
confirmed misconfigurations, with instructions to fix all of them, preserve
resource names and intent, add nothing extra, and return only HCL. Temperature
is 0.0 (deterministic) for models that accept it.

### 5.2 Dispatch paths

Models reach Bedrock through one of three request shapes, selected by model id
(`bedrock_client.py`, `_dispatch`):

- **Anthropic Messages** — Claude family.
- **Converse API** — Amazon Nova, Meta Llama, DeepSeek-R1, xAI Grok.
- **OpenAI-compatible `invoke_model`** — Qwen3, DeepSeek V3.2, Kimi K2.5.

All three return `(text, usage)` so the rest of the harness is
dispatch-agnostic. This is a deliberate fairness choice: models are grouped by
their **native API contract**, not given bespoke per-model logic, so no single
model gets special handling that could bias its results.

### 5.3 Reasoning-model response handling

Reasoning models return chain-of-thought in a content block **separate** from the
answer. On the Converse API that is a `reasoningContent` block (which, depending
on the SDK version, may surface as an opaque `SDK_UNKNOWN_MEMBER`). The extractor
(`_extract_converse_text`) returns **only** `text` blocks as the answer and never
treats reasoning as HCL, so a model's thinking cannot leak into — or be scored
as — its repair. Response text is then sanitized (`response_sanitizer.py`) to
strip `<think>`/`<thinking>`/`<reasoning>` wrappers and markdown fences before
HCL validation.

### 5.4 Output token budget and per-model ceilings

**Each model is run at the maximum output budget it supports** (up to a 40K
nominal cap), clamped per model by `_MODEL_MAX_TOKENS` to that model's confirmed
Bedrock output ceiling. Confirmed ceilings (verified live, 2026-09-30): grok-4-6,
claude-sonnet-5, and claude-sonnet-4-5 accept ≥100K; deepseek-r1 caps at 32,768;
qwen3-32b / deepseek-v3-2 / kimi-k2-5 at 16,384; nova-pro / nova-lite at 10,000;
llama-3.3-70b at 8,192.

**Output ceiling is a characteristic of the model, not a choice of the harness.**
The harness gives every model the largest budget that model will accept; it does
not impose a uniform cap that would advantage or handicap any model. A model that
cannot emit a long repair (nova 10K, llama 8K) is exhibiting a real capability
limit, and the benchmark reports that limit rather than hiding it. We also report
each model's output ceiling alongside its scores (see §9 / `RESULTS_FOR_PAPER.md`)
so a reader can judge capacity against skill directly.

**The capacity difference does not drive the headline result.** Because output
ceilings differ, one might ask whether higher-capacity models score better simply
by being allowed more output. We test this directly (§8 / `HEADLINE_ANALYSIS.md`):
on the **capacity-controlled subset** — the 232 of 262 modules (89%) where *no*
model truncated or timed out — the per-model ranking is unchanged (each model
shifts ≤0.05 RSR), and the frontier models still lead on modules where the
lower-ceiling models had ample room. The frontier advantage is therefore repair
skill, not output budget.

### 5.5 Resilience

- **Throttling** — exponential backoff with jitter (`_with_retry`); exhausted
  retries raise `ThrottlingError`, logged to the skip manifest, never silently
  dropped.
- **Wall-clock cap** — each invocation runs under a hard timeout
  (`_call_with_wall_clock_cap`, default 420s) so a slow/streaming model cannot
  wedge a multi-hour run; a timeout is logged as `invoke timeout` and the game
  is skipped, not scored.
- **Temperature** — models that reject the `temperature` field are auto-detected
  and retried without it (`NO_TEMPERATURE_MODELS` + runtime fallback).

---

## 6. Cost accounting

Per-game cost is computed from token usage and per-model `(input, output)` rates
in `MODEL_COSTS` (USD per 1K tokens). Costs are aggregated per model and written
to `metrics.json` and `run_manifest.json`, so total and per-model spend are
auditable after every run.

---

## 7. Reproducibility and provenance

Every run writes, before any repair executes:

- `run_manifest.json` — corpus rule, candidate/corpus counts, model list,
  pinned scanner versions, temperature, concurrency, max-tokens.
- `corpus_manifest.jsonl` — every admitted module with its finding count and
  size.
- `skip_manifest.jsonl` — every excluded candidate and skipped game with a
  reason (out-of-band count, scan failure, throttle, timeout, size-driven).

On completion the runner writes `run_complete.json` **last**, so its presence is
an unambiguous "finished" signal (used to distinguish a completed run from a
crashed one on restart). Per-game results are individual JSON files under
`games/`, each fully self-describing (before/after findings, all metrics, cost,
tokens, `hcl_valid`, and `failure_metadata` when applicable).

### 7.1 Idempotent, resumable execution

Each game writes its own file and the runner skips games that already exist
(`if game_file.exists(): resume`). A run can therefore be interrupted and
resumed without recomputing finished games, and a **targeted re-run** (e.g. a
subset of models at a higher token budget) is achieved by deleting only the
specific game files to be recomputed and restricting the model set with
`--models`; all other games are left byte-for-byte intact. This makes partial
recovery cheap and keeps merged result sets internally consistent.

---

## 8. Known limitations and honest caveats

- **HCL validity is structural, not full `terraform validate`.** `is_valid_hcl`
  checks balanced braces and the presence of real HCL block types; it does not
  run the Terraform CLI. It catches gross malformations (prose, truncated
  output, wrong language) but is not a full parser.
- **Classification is keyword-based.** The four vulnerability classes come from
  keyword matching, first-match-wins. It is a coarse lens for per-class trends,
  not an authoritative taxonomy.
- **Output-capacity limits are model-dependent.** Models with small hard output
  ceilings (nova, llama) cannot emit very long repairs; their failures on large
  modules are capability limits, reported separately from budget-truncation.
- **Model access.** A model that is Legacy-blocked or otherwise inaccessible on
  the evaluation account produces access errors, not repair results, and is
  excluded from the comparison (documented, not scored as 0).
- **Scanner coverage bounds ground truth.** "Findings" means what Trivy 0.74.0 +
  Checkov 3.3.20 detect at the pinned severities; a real misconfiguration the
  scanners miss is invisible to the metric, on both sides of the repair.
- **Wall-clock timeouts on the largest modules.** Each invocation runs under a
  420s hard cap (§5.5). A small number of oversized modules (e.g. module_0240 at
  ~187K source chars, module_0002 at ~126K, module_0333 at ~142K) exceed this
  cap when a model must read tens of thousands of input tokens and generate a
  large repair, so they time out and are not scored. These timeouts are
  **symmetric across models** — the same oversized modules time out for every
  model — so they do not bias cross-model comparison; they are a size/time
  limitation, reported here rather than hidden. (The corpus rule bounds *finding
  count* at ≤50 but does not bound *source size*; these are the source-size
  outliers.) Raising the cap would recover some but not all of them, with
  diminishing returns.
- **Each model at its own maximum supported budget.** Every model is run at the
  largest output budget it accepts, up to a 40K nominal cap (§5.4). In practice
  the high-ceiling models (grok-4-6, claude-sonnet-5, claude-sonnet-4-5) ran at
  40K and the others at their lower ceilings (deepseek-r1 32,768; qwen /
  deepseek-v3-2 / kimi 16,384; nova 10,000; llama 8,192). This is not a uniform
  cap and not an unfairness — it is each model operating at its own capacity,
  which the results table reports explicitly (output-ceiling column). The
  capacity-controlled analysis (§5.4, `HEADLINE_ANALYSIS.md`) confirms the model
  ranking is unchanged on the 232/262 modules where no model was capacity-bound,
  so the comparison reflects skill, not budget. A uniform-budget re-run of the
  lower-ceiling models would not change this: they would re-clamp to the same
  hard ceilings and reproduce their current output.
- **Reasoning vs non-reasoning is not a reported finding (2026 cohort).** The
  regression-rate difference between reasoning and non-reasoning models is
  negligible (Cohen's d ≈ −0.11) and driven by model composition, not reasoning
  capability — per-model RR interleaves across the two groups. We report RR as a
  per-model property and do not claim a reasoning effect for this cohort. (It was
  a strong effect on the earlier cohort; see `HEADLINE_ANALYSIS.md` §3.)

---

## 9. Metric summary

| Metric | Definition | Direction |
|--------|------------|-----------|
| Repair Success Rate (RSR) | resolved / target | higher better |
| Regression Rate (RR) | introduced / target | lower better |
| Net Delta (ND) | resolved − introduced | higher better (positive = improvement) |
| HCL valid | repair parsed as structural HCL | higher better |

All are computed by deterministic set difference on `(rule_id, resource_name)`
finding identities, with no model-judge in the loop.

---

## 10. Experimental setup

### 10.1 Model cohort

The 2026 evaluation cohort is 10 models spanning non-reasoning and
reasoning/agentic families, invoked on AWS Bedrock (`us-east-1`). Bedrock model
ids use cross-region inference (CRIS) profiles where required.

| Model | Bedrock id | API path | Reasoning | Cost $/1K (in, out) |
|-------|-----------|----------|-----------|---------------------|
| claude-sonnet-4-5 | `us.anthropic.claude-sonnet-4-5-20250929-v1:0` | Anthropic Messages | no | (0.003, 0.015) |
| nova-pro | `us.amazon.nova-pro-v1:0` | Converse | no | (0.001, 0.001) |
| nova-lite | `us.amazon.nova-lite-v1:0` | Converse | no | (0.0001, 0.0002) |
| llama-3-3-70b | `us.meta.llama3-3-70b-instruct-v1:0` | Converse | no | (0.0008, 0.0008) |
| deepseek-r1 | `us.deepseek.r1-v1:0` | Converse | yes | (0.0014, 0.0028) |
| qwen3-32b | `qwen.qwen3-32b-v1:0` | OpenAI-compatible | yes | (0.0004, 0.0004) |
| claude-sonnet-5 | `global.anthropic.claude-sonnet-5` | Anthropic Messages | yes | (0.002, 0.010) |
| deepseek-v3-2 | `deepseek.v3.2` | OpenAI-compatible | yes | (0.00074, 0.00222) |
| kimi-k2-5 | `moonshotai.kimi-k2.5` | OpenAI-compatible | yes | (0.00060, 0.00250) |
| grok-4-6 | `us.xai.grok-4.6` | Converse | yes | (0.002, 0.006) |

**Cohort notes.**
- **claude-sonnet-4-5 replaces claude-sonnet-4.** The originally-planned
  claude-sonnet-4 anchor is Legacy on the evaluation account (invocations return
  `ResourceNotFoundException`), so it produced access errors rather than repairs
  and is excluded from the comparison. It was replaced by claude-sonnet-4-5 —
  same Sonnet tier, one minor generation up — which is the accessible, current
  form of the intended anchor.
- Model ids and per-token prices were confirmed against the Bedrock console at
  wiring time; see `MODEL_COHORT_2026.md` for sourcing.

### 10.2 Inference parameters

- **Temperature:** 0.0 (deterministic) for models that accept it; omitted for
  models that reject the field (Claude Sonnet 5, Grok 4.6), detected and
  handled automatically.
- **Output token budget:** nominal `--max-tokens` per run, clamped per model to
  its confirmed Bedrock ceiling (§5.4). The current evaluation uses a **40,000**
  nominal budget so verbose reasoning models are not truncated mid-answer;
  models with lower hard ceilings (deepseek-r1 32,768; nova 10,000; llama 8,192)
  are clamped to those.
- **Single pass:** one repair attempt per (module, model); no multi-sample or
  best-of-N.

### 10.3 Execution environment

Runs execute in a portable container (`Dockerfile`) that pins the analyzer stack
(Trivy 0.74.0, Checkov 3.3.20) and Python dependencies (including a pinned
`boto3`/`botocore` so Bedrock response handling is reproducible). The same image
runs locally (smoke) and on AWS Fargate (full run).

- **Compute:** AWS Fargate task, 1 vCPU / 4 GB, `linux/amd64`.
- **Concurrency:** 4 parallel (module, model) repairs by default. Repairs are
  latency-bound (minutes each) and request rate stays well under Bedrock quota,
  so parallelism is throughput, not a correctness variable — the serial and
  concurrent paths produce identical per-game results (each game is independent
  and writes its own file under lock-free isolation).
- **Result persistence:** the container syncs results to S3 periodically and on
  exit, and resumes from S3 on restart, so an interrupted task loses at most one
  sync interval of games and never recomputes finished ones (§7.1).

### 10.4 Analysis

Final tables (RSR, RR, ND, HCL-valid rate; overall and per vulnerability class)
are produced by the analysis scripts over the completed `games/` set, applying
the §2.2 corpus filter so the analyzed set and the corpus definition cannot
drift. Failure modes (out-of-band, scan failure, throttle, timeout, size-driven,
model-access) are read from the skip manifest and reported alongside the
headline metrics rather than folded silently into them.
