# TerraRepair-Bench

A research benchmark that measures how well large language models repair security misconfigurations in real-world Terraform Infrastructure-as-Code.

**Research question:** When LLMs are used to repair scanner-confirmed Terraform security misconfigurations, do they successfully eliminate the target vulnerability, and at what rate do they introduce new ones?

## Released slice (MSR 2027 Data and Tool Showcase)

The released slice is one complete run of the harness: 262 Terraform modules from TerraDS v1, repaired once by each of ten foundation models, for 2,614 scored games. It lives in `experiments/results/release_slice_2026-10/`.

Each game is a JSON record plus two sidecar files that share its stem:

| File | Content |
|---|---|
| `<stem>.json` | findings before and after, set-difference counts, rates, cost, and the SHA-256 of the scanned code |
| `<stem>.repaired.tf` | the exact code that was written to disk and scanned |
| `<stem>.raw.txt` | the model's response before sanitizing |

The run directory also holds `run_manifest.json` (commit, scanner versions, model identifiers), `corpus_manifest.jsonl` (admitted modules), and `skip_manifest.jsonl` (every rejected candidate and unscored repair, with a reason).

### Verify the release

The rescan checks every sidecar's hash and rescans every valid repair with the pinned scanners. No model is called.

```bash
docker build -t terrarepair-bench:latest .
python3 scripts/rescan_release.py --results experiments/results/release_slice_2026-10
```

The archived rescan results are in `experiments/results/release_slice_2026-10_rescan/`. The two `_offline2_*` directories repeat the remote-module rescan with Trivy's network access blocked.

### Reproduce the paper's comparisons

```bash
python3 scripts/bootstrap_ci.py
```

This runs a paired bootstrap over the modules every model completed (5,000 resamples, seed 42, invalid HCL scored as no change) and prints the per-model intervals and pairwise comparisons reported in the paper.

### Licenses

The harness code is MIT-licensed (see `LICENSE`). The scores, findings, and manifests are released under CC BY 4.0. The Terraform files in `data/terrads_sample/` and the `.repaired.tf` sidecars are modified copies of public repositories collected by TerraDS. Each keeps its source repository's license, which is not covered by the CC BY 4.0 data license. Most are Apache-2.0 or MIT. 21 modules come from MPL-2.0, GPL-3.0, or AGPL-3.0 repositories. `THIRD_PARTY_LICENSES.md` lists every module's repository and license, and `data/terrads_provenance.csv` gives the verified source commit. Pipeline icons are Uicons by Flaticon.

## Prior Work

- **Low et al. (2024)** — "Repairing Infrastructure-as-Code using Large Language Models" (IEEE SecDev 2024). Evaluated GPT-3.5 and GPT-4 on synthetic vulnerable codebases. This benchmark extends their work with real-world repos, reasoning models, full automation, and regression measurement.
- **TerraDS (Bühler et al., MSR 2025)** — 62,406 real-world Terraform repositories. [Zenodo](https://zenodo.org/records/14217386). The released slice uses 262 modules with 3 to 50 confirmed scanner findings.

## Primary Metrics

1. **Repair success rate** — Fraction of target findings resolved (same rule_id + resource_name no longer flagged).
2. **Regression rate** — Fraction of target findings for which new findings were introduced.
3. **Net delta** — resolved_count − introduced_count (positive = improvement).

Matching is deterministic on (rule_id, resource_name) pairs. No LLM judge.

## Models

| Model | Type |
|-------|------|
| Claude 3.5 Sonnet | Non-reasoning |
| Nova Pro | Non-reasoning |
| Nova Lite | Non-reasoning |
| Llama 3.3 70B | Non-reasoning |
| DeepSeek-R1 | Reasoning |
| Qwen3-32B | Reasoning |

All models via AWS Bedrock. Temperature 0.0 for deterministic repair.

## Quick Start

```bash
# Create and activate a virtual environment
python3 -m venv .venv
source .venv/bin/activate   # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Install external tools
brew install trivy
pip install checkov

# Download TerraDS (SQLite + archive)
# Place TerraDS.sqlite in a known path

# Sample 200 modules
python scripts/sample_terrads.py --sqlite /path/to/TerraDS.sqlite --output data/terrads_sample

# Run experiment (6 models × 200 modules)
python scripts/run_experiment.py --config experiments/configs/full_experiment.yaml

# Analyze results
python scripts/analyze.py --results experiments/results/full_180_game/
```

## Environment

Copy `.env.example` to `.env` and set:

- `AWS_REGION`, `AWS_PROFILE` (or credentials)
- `TERRADS_SQLITE_PATH`
- `CORPUS_DIR`

## Target Venue

[RAID 2026](https://raid2026.org/) — International Symposium on Research in Attacks, Intrusions and Defenses (April 16, 2026 deadline).
