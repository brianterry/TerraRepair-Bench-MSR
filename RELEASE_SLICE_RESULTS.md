# Release Slice Results — TerraRepair-Bench (MSR 2027 Data & Tool Showcase)

**Purpose of this file.** Single source of record for the `release_slice_2026-10` run
and its verification, written as context for drafting the MSR 2027 Data and Tool
Showcase paper (abstract due Nov 5, paper due Nov 10). Every number here was read
from the result files listed in the final section; nothing is estimated unless it
says so.

**What the release slice is.** A re-run of the 2026 refresh configuration (same
262-module corpus, same 10 models, same scanners, same scoring) whose purpose is to
ship each model's output as an artifact. Earlier runs scored the repaired Terraform
but never saved it. This run saves, per game, the exact repaired code that was
scanned and the model's raw response, and records a SHA-256 of the repaired file.

**Cite it as its own run.** Model outputs are nondeterministic on Bedrock even at
temperature 0 (in the smoke test, nova-lite went from invalid to valid HCL on 2 of 3
modules relative to the refresh). Per-game outcomes will not match the
`full_refresh_2026-09` run game-for-game, and per-model means differ somewhat from
`RESULTS_FOR_PAPER.md` Table 1. Do not mix the two runs' numbers in one table.

Scoring, the corpus filter, prompts, and the invalid-HCL rule were not changed. The
delta-scorer set-difference math is the same as in `RESULTS_FOR_PAPER.md`.

---

## 1. Run provenance

| Item | Value |
|---|---|
| Experiment name / config | `release_slice_2026-10` / `experiments/configs/release_slice_2026-10.yaml` (copy of the refresh config; only name and output folder changed) |
| Source commit | `3a9ae7fe40d96f7a62c4b1003eabff8e702fa6ae`, tree clean (`dirty: false`), recorded in `run_manifest.json` |
| Container image | `terrarepair-bench:release-3a9ae7f`, ECR digest `sha256:7381672d0b6bd1beb57783277b92ab63075e3480cdc0a059df05f958d1c8f8f1`, built from a clean git worktree with the commit baked in |
| Execution | AWS Fargate, us-east-1, task def `terrarepair-bench:2` (4 vCPU / 8 GB), one task, concurrency 4 |
| Scanners | Trivy 0.74.0, Checkov 3.3.20 (pinned in the image) |
| Timing | Harness started 2026-10-28T15:09:02Z, completed 2026-10-29T03:30:25Z (12.4 h; corpus scan of 400 candidates took the first ~31 min) |
| Output budget | `--max-tokens 40000`, clamped per model (table below) |
| Bedrock timeouts | read 900 s, invoke 900 s (the refresh used 300 / 420 s and lost 53 games to timeouts) |
| Temperature | 0.0, omitted for `claude-sonnet-5` and `grok-4-6`, which reject the parameter |
| Draws / retrieval | 1 draw, closed-book (no retrieval exemplars) |

Per-model invocation details (from `run_manifest.json` `model_details`):

| Model | Bedrock model id | Effective max tokens | Temperature sent |
|---|---|---:|:-:|
| claude-sonnet-5 | `global.anthropic.claude-sonnet-5` | 40,000 | no |
| grok-4-6 | `us.xai.grok-4.6` | 40,000 | no |
| claude-sonnet-4-5 | `us.anthropic.claude-sonnet-4-5-20250929-v1:0` | 40,000 | yes |
| deepseek-r1 | `us.deepseek.r1-v1:0` | 32,768 | yes |
| deepseek-v3-2 | `deepseek.v3.2` | 16,384 | yes |
| kimi-k2-5 | `moonshotai.kimi-k2.5` | 16,384 | yes |
| qwen3-32b | `qwen.qwen3-32b-v1:0` | 16,384 | yes |
| nova-pro | `us.amazon.nova-pro-v1:0` | 10,000 | yes |
| nova-lite | `us.amazon.nova-lite-v1:0` | 10,000 | yes |
| llama-3-3-70b | `us.meta.llama3-3-70b-instruct-v1:0` | 8,192 | yes |

`claude-sonnet-4` is excluded: it is marked Legacy on this Bedrock account and
invocations are refused.

## 2. Corpus

- 400 candidate modules from `data/terrads_sample` were scanned at sampling time;
  **262** fall in the corpus band (3 ≤ pre-repair findings ≤ 50) and form the corpus.
- 138 candidates were out of band and are logged in `skip_manifest.jsonl`. No
  candidate was dropped for a scanner failure.
- The 262-module set is identical to the `full_refresh_2026-09` corpus.

## 3. Run outcome

2,620 work items (262 modules × 10 models); **2,614 scored**.

| Model | Games | HCL-valid | HCL-invalid | Invoke timeout | Throttled (dropped) | Cost, in-code prices (USD) |
|---|---:|---:|---:|---:|---:|---:|
| claude-sonnet-4-5 | 262 | 259 | 3 | 0 | 0 | 30.24 |
| claude-sonnet-5 | 258 | 245 | 13 | 0 | 4 | 37.45 |
| deepseek-r1 | 262 | 259 | 3 | 0 | 0 | 9.58 |
| deepseek-v3-2 | 262 | 247 | 15 | 0 | 0 | 3.93 |
| grok-4-6 | 260 | 231 | 29 | 2 | 0 | 35.34 |
| kimi-k2-5 | 262 | 249 | 13 | 0 | 0 | 3.96 |
| llama-3-3-70b | 262 | 235 | 27 | 0 | 0 | 1.96 |
| nova-lite | 262 | 217 | 45 | 0 | 0 | 0.41 |
| nova-pro | 262 | 236 | 26 | 0 | 0 | 2.75 |
| qwen3-32b | 262 | 242 | 20 | 0 | 0 | 0.82 |
| **Total** | **2,614** | **2,420** | **194** | **2** | **4** | **126.45** |

- The 6 unscored items are 4 `claude-sonnet-5` games dropped after 6 retries on
  Bedrock `ServiceUnavailableException`, and 2 `grok-4-6` games that exceeded the
  900 s invoke cap. All 6 are logged in `skip_manifest.jsonl`.
- HCL-invalid games are scored 0/0/0 under the existing rule. They include **8**
  size-driven failures, one each for 8 models, all on `module_0240` (~46.8K
  estimated input tokens, above the 40K budget). nova-pro and llama-3-3-70b returned
  valid HCL on that module, so it is not a failure for them. qwen3-32b has 14 further
  games (15 including `module_0240`) rejected by Bedrock because the prompt exceeds
  its 32K context window.

### Per-model score means (this run)

Per-game means over scored games; HCL-invalid games count as 0/0/0. RSR = resolved /
target; RR = introduced / target; Net Δ = resolved − introduced. Ranked by Net Δ.
These are new numbers for this run, not the refresh's Table 1.

| Model | n | RSR | RR | Net Δ | HCL-valid % |
|---|---:|---:|---:|---:|---:|
| claude-sonnet-5 | 258 | 0.848 | 0.192 | 10.36 | 95.0 |
| deepseek-r1 | 262 | 0.791 | 0.191 | 10.28 | 98.9 |
| grok-4-6 | 260 | 0.866 | 0.223 | 9.85 | 88.8 |
| kimi-k2-5 | 262 | 0.733 | 0.266 | 8.08 | 95.0 |
| deepseek-v3-2 | 262 | 0.666 | 0.286 | 6.75 | 94.3 |
| nova-pro | 262 | 0.518 | 0.141 | 6.74 | 90.1 |
| claude-sonnet-4-5 | 262 | 0.769 | 0.490 | 6.26 | 98.9 |
| qwen3-32b | 262 | 0.478 | 0.169 | 6.03 | 92.4 |
| nova-lite | 262 | 0.385 | 0.103 | 4.95 | 82.8 |
| llama-3-3-70b | 262 | 0.560 | 0.336 | 4.73 | 89.7 |

No confidence intervals have been computed for these means yet.

### Cost

- **Bedrock + Fargate for the run: about $144.6** (AWS Cost Explorer, still flagged
  *estimated* when read): Bedrock $141.89 (Claude Sonnet 5 $37.45, Claude Sonnet 4.5
  $33.25, all other models $71.19), ECS/Fargate $2.56, S3 and other $0.12.
- The harness's in-code prices total $126.45; actual Bedrock spend for the
  non-Claude models came in about $12 higher, and Sonnet 4.5 about $3 higher.
  Claude Sonnet 5 matched exactly.
- Verification rescans (Section 5) added roughly **$1.50** of Fargate compute. This
  is an estimate from task hours, not from billing data.

## 4. What each game ships

For a game `<module>_<model>.json` the release contains:

| File | Contents |
|---|---|
| `<stem>.json` | Game record: findings before/after, counts, RSR/RR/Net Δ, cost, `hcl_valid`, plus `repaired_code_path`, `raw_response_path`, `repaired_code_sha256` |
| `<stem>.repaired.tf` | The sanitized repaired code, byte-for-byte the text written to `main.tf` and scanned. Empty when the model refused or the call failed. For HCL-invalid games it is the text that failed validation and was not scanned. |
| `<stem>.raw.txt` | The raw model response before sanitization (including reasoning blocks / code fences). Empty if the invocation itself failed. |

Paths in the JSON are bare filenames (relative), so the tree can be moved.
`run_manifest.json` records the commit, scanner versions, per-model Bedrock ids,
clamped budgets, temperature handling, and the Bedrock timeouts.

Counts: 2,614 `.repaired.tf` and 2,614 `.raw.txt`; none missing; **0 SHA-256
mismatches**.

## 5. Verification

### 5.1 Online rescan (all items, network available as in the run)

`scripts/rescan_release.py`, run on Fargate (task def `terrarepair-rescan:1`, image
built from commit `d9a1da7`), 2026-10-30 00:56–03:51 UTC. For each item it rescans
exactly as the harness scanned (repaired code written alone as `main.tf` in a fresh
directory; inputs scanned as their module directory) and compares the set of
`(rule_id, resource_name)` finding identities. It records an outcome per item and
never stops at the first problem.

| Items | Compared against | Checked | Match | Mismatch | Scanner failure |
|---|---|---:|---:|---:|---:|
| Corpus inputs | recorded `findings_before` | 262 | **262** | 0 | 0 |
| — of which reference remote modules | | 93 | 93 | 0 | 0 |
| HCL-valid games | recorded `findings_after` | 2,420 | **2,420** | 0 | 0 |
| — of which reference remote modules | | 785 | 785 | 0 | 0 |

The 194 HCL-invalid games are not scanned by design (their `findings_after` equals
`findings_before` under the scoring rule). Every model's valid games matched.

### 5.2 Offline rescan from the captured bundle (Trivy network blocked)

Two Fargate tasks (task def `terrarepair-rescan-offline:2`, commit `30e4c44`),
2026-10-30 16:41–18:19 UTC, rescanned only the items that reference remote modules,
with Trivy's network access blocked and the captured module cache and rule bundle
restored:

| Variant | Module cache restored | Inputs | Valid games | Mismatch / failure |
|---|---|---:|---:|---:|
| full | 484 entries with git history (2.7 GB on disk; 2.4 GB archive) | **93 / 93** | **785 / 785** | 0 / 0 |
| nogit | same 484 entries, `.git` stripped (479 MB on disk; **146 MB archive**) | **93 / 93** | **785 / 785** | 0 / 0 |

- **Negative control.** Before restoring the bundle, each task scanned
  `module_0045_claude-sonnet-5` with an empty cache and the network blocked. Trivy
  downloaded nothing and the recorded finding `AWS-0028` (located inside a
  downloaded module) disappeared, which proves the block was effective.
- Trivy's rule-bundle refresh was disabled (`TRIVY_SKIP_CHECK_UPDATE=true`); the
  bundle digest was unchanged after the run.
- Conclusion: **the 146 MB `nogit` archive plus the rule bundle is sufficient to
  reproduce every Trivy finding offline.** That is the archive to ship.
- Network blocking used the uppercase `HTTPS_PROXY`/`HTTP_PROXY` variables pointed
  at a dead local port, which Trivy and git honor and Checkov does not. Checkov kept
  network access, as during the run (see 6.3 for why).

## 6. Network dependencies of the scores (disclose these)

The released code alone is not the only input to a score. Three things are fetched
over the network at scan time.

### 6.1 Remote Terraform modules (Trivy) — captured

- Trivy's `config` scan downloads every remote module a file references (Terraform
  Registry and git sources) and also scans the downloaded module code.
- Scope in this run: **785 of 2,420 HCL-valid games (32.4%)** and **93 of 262 corpus
  inputs** reference at least one remote module, across all 10 models.
- **111** games have a recorded Trivy finding located inside a downloaded module
  (not in the released `main.tf`).
- Released as: `trivy_module_cache_nogit.tar.gz` (146 MB) plus
  `capture_manifest.json` listing all **484** cache entries: **155** repositories,
  **354** distinct (repository, commit) pairs, 26,258 `.tf` files. 8 entries come from
  non-git sources and have no commit recorded.
- Restore: extract the archive into the temp directory Trivy uses (`$TMPDIR`, by
  default `/tmp`, giving `/tmp/.aqua/cache`), extract the rule bundle into
  `~/.cache`, then scan with network access blocked and `TRIVY_SKIP_CHECK_UPDATE=true`.

### 6.2 Trivy rule bundle — captured

- Trivy downloads its checks bundle at scan time from the floating tag
  `mirror.gcr.io/aquasec/trivy-checks:2`; the run manifest records only the Trivy
  binary version, not the bundle.
- The bundle captured by the rescan has digest
  `sha256:b591e9190cff4aa4e385b1a25bccfd9ecf178d3c77fd194e1410b7ce7e1df058`. A
  bundle downloaded on the development machine on 2026-10-28 13:37 UTC (before the
  run started) has the same digest, and the rescan's copy (downloaded 2026-10-30
  00:56 UTC, after the run ended) does too. So the run almost certainly used this
  bundle; it was not recorded directly.
- Released as `trivy_checks_bundle.tar.gz` (~200 KB).

### 6.3 Checkov vendor run configuration — NOT capturable

- At startup Checkov fetches a "public run config" from the Bridgecrew / Prisma Cloud
  API (`get_public_run_config`). When the fetch succeeds, as it did during the run and
  the online rescan, some checks do not fire; when it fails, they do.
- Observed: blocking only that fetch on the 93 remote-module inputs added findings on
  3 of them (`CKV_AWS_111` on all three; also `CKV_AWS_38`, `CKV_AWS_39`,
  `CKV_AWS_58` on `module_0400`). Running Checkov online with `--skip-download`
  produces the same extra findings.
- The effect on the other 169 inputs and on the games was **not measured**.
- Checkov has no option to load that configuration from a file, so it cannot be
  shipped. Checkov results therefore assume the vendor service is reachable and that
  its configuration has not changed since the run.

### 6.4 Silent module-load failures (residual limitation)

If Trivy cannot download a referenced module, it logs an error but still exits 0 and
drops that module's findings. The harness cannot detect this. It did not affect this
release: the online rescan reproduced every recorded finding. The offline negative
control (6.1) is an example of the behavior.

## 7. Harness bugs found and fixed during verification

Both are fixed in commit `b1fedff`, with regression tests.

1. **Environment-variable collision.** The harness read its Trivy subprocess timeout
   from `TRIVY_TIMEOUT`, but Trivy reads that variable as its own `--timeout` flag (a
   Go duration). A unitless value such as `900` made Trivy abort immediately. The
   harness now reads `TERRAREPAIR_TRIVY_TIMEOUT` and passes the cap to Trivy's
   `--timeout` explicitly. **Impact on recorded runs: none.** No registered task
   definition (`terrarepair-bench:1/2`, `terrarepair-ablation:1/2`) ever set
   `TRIVY_TIMEOUT`.
2. **Trivy failures recorded as zero findings.** The wrapper accepted exit code 1 as
   "findings found" (Checkov's convention). Trivy exits 0 whether or not it finds
   misconfigurations and 1 only on a fatal error, so a fatal Trivy run was parsed as
   zero Trivy findings with no error; in scoring, every Trivy finding would have
   counted as resolved. Any non-zero exit, empty output, or invalid JSON now raises a
   scanner failure. **Impact on the release slice: none** (the online rescan used the
   fixed wrapper and found no discrepancies). **Impact on `full_refresh_2026-09` and
   `retrieval_ablation`: not checked.** They used the same wrapper.

Neither fix changes behavior for scans that succeed.

## 8. What the paper can and cannot claim

Supported:
- Every game ships its repaired code and raw response; all 2,614 sidecars match
  their recorded SHA-256.
- Rescanning the shipped code with the pinned image reproduces the recorded finding
  identities exactly for all 2,420 HCL-valid games and all 262 corpus inputs.
- With the shipped module bundle and rule bundle, all Trivy findings for the 878
  remote-module items reproduce exactly with Trivy offline.

Not supported — do not claim:
- "Every score can be reproduced from the released files alone." Checkov needs its
  vendor service (6.3).
- "The scores are independent of external services."
- Anything about the refresh or ablation runs being verified by this process.
- Confidence intervals for the Section 3 means (none computed).

### Suggested paragraph (verified against the numbers above)

> **Artifact verification.** Each game ships the model's repaired Terraform and raw
> response; the game record holds the SHA-256 of the repaired file. We rescanned every
> artifact with the experiment's container image and pinned scanners (Trivy 0.74.0,
> Checkov 3.3.20). All 2,614 sidecars match their recorded hashes, and all 2,420
> HCL-valid repairs and all 262 corpus inputs reproduce their recorded finding
> identities exactly. Trivy also scans the contents of remote Terraform modules a file
> references, and does so for 32.4% of valid games. We therefore release the module
> copies Trivy fetched (with source commits) and its rule bundle. With Trivy's network
> access blocked, all 878 remote-module items again reproduce exactly from these
> files. Checkov retrieves a vendor-hosted run configuration at scan time that affects
> which checks apply; it cannot be pinned, so Checkov findings assume that service is
> reachable.

## 9. Where everything is

Local (repo-relative):

| Path | Contents |
|---|---|
| `experiments/results/release_slice_2026-10/` | The release: `games/` (2,614 × JSON + `.repaired.tf` + `.raw.txt`), `run_manifest.json`, `run_complete.json`, `metrics.json`, `corpus_manifest.jsonl`, `skip_manifest.jsonl` |
| `experiments/results/release_slice_2026-10/_smoke/` | 6-game smoke run (3 modules × nova-lite, qwen3-32b) |
| `experiments/results/release_slice_2026-10_rescan/` | Online rescan: `rescan_summary.json`, `rescan_results.jsonl`, `capture_manifest.json` |
| `experiments/results/release_slice_2026-10_offline2_full/`, `…_offline2_nogit/` | Offline rescans: summaries, per-item results, negative control, bundle digest after run |
| `scripts/rescan_release.py` | The verification tool (`--capture`, `--only-remote`) |
| `tests/test_repair_artifacts.py`, `tests/test_rescan_release.py`, `tests/test_trivy_timeout.py` | Tests for sidecars, the rescan tool, and the Trivy fixes |

S3 (`s3://terrarepair-bench-results-<ACCOUNT_ID>/terrarepair/`):

| Prefix | Contents |
|---|---|
| `release_slice_2026-10/` | The release results (source of the local copy) |
| `release_slice_2026-10_rescan/` | Online rescan report, `trivy_module_cache.tar.gz` (2.4 GB, with git history), `trivy_checks_bundle.tar.gz`, `capture_manifest.json` |
| `release_slice_2026-10_offline2_nogit/` | `trivy_module_cache_nogit.tar.gz` (**146 MB — the archive to ship**) and the offline report |
| `release_slice_2026-10_offline_full/`, `…_offline_nogit/` | Superseded first offline attempt (it blocked Checkov's network by mistake and produced spurious extra Checkov findings). Not results; safe to delete. |

Commits (local `main`, not pushed): `da5b0ab` sidecars + manifest provenance;
`59ea6e0`, `3a9ae7f` commit provenance inside the container; `b1fedff` Trivy
fail-loud + env rename; `d9a1da7` rescan tool; `30e4c44` `--only-remote`.
