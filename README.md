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

For a repair, let B be the pre-repair findings and A the post-repair findings, each identified by (rule_id, resource_name).

1. **Repair success rate (RSR):** resolved over target, |B \ A| / |B|.
2. **Regression rate (RR):** introduced over target, |A \ B| / |B|. It can exceed 1 when a repair introduces more findings than it targeted.
3. **Net delta:** resolved minus introduced.

Matching is deterministic. No language model is in the scoring loop. A repair that is not valid HCL is scored as no change (A = B).

## Models

The released slice covers ten models, all invoked through Amazon Bedrock with one draw each.

| Model | Reasoning |
|---|---|
| Claude Sonnet 4.5 | No |
| Claude Sonnet 5 | Yes |
| DeepSeek-R1 | Yes |
| DeepSeek V3.2 | Yes |
| Grok 4.6 | Yes |
| Kimi K2.5 | Yes |
| Llama 3.3 70B | No |
| Nova Lite | No |
| Nova Pro | No |
| Qwen3 32B | Yes |

Temperature is 0 for every model that accepts it. Claude Sonnet 5 and Grok 4.6 do not, so their outputs are not deterministic. Exact Bedrock model IDs are in `experiments/configs/release_slice_2026-10.yaml` and in each run's `run_manifest.json`.

## Quick Start

Using the released data needs no AWS account and no model calls.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Reproduce the paper's comparisons from the released games
python3 scripts/bootstrap_ci.py

# Rescan the released artifacts with the pinned scanners (Trivy 0.74.0, Checkov 3.3.20)
docker build -t terrarepair-bench:latest .
python3 scripts/rescan_release.py --results experiments/results/release_slice_2026-10
```

Running new repairs needs AWS credentials with Amazon Bedrock access. Run the smoke configuration first, then the full one:

```bash
python3 scripts/run_experiment.py --config experiments/configs/release_slice_2026-10_smoke.yaml
python3 scripts/run_experiment.py --config experiments/configs/release_slice_2026-10.yaml --max-tokens 40000
```

`CONTAINER.md` describes running the same image on AWS Fargate. The deploy files use `<ACCOUNT_ID>` as a placeholder for your AWS account.

The corpus in `data/terrads_sample/` was drawn from TerraDS v1 with `scripts/sample_terrads.py`. Re-sampling needs `TerraDS.sqlite` from [Zenodo record 14217386](https://zenodo.org/records/14217386). Use the released corpus to reproduce the paper.

## Environment

Copy `.env.example` to `.env` and set:

- `AWS_REGION`, `AWS_PROFILE` (or credentials), needed only for new model runs
- `TERRADS_SQLITE_PATH`, needed only for re-sampling
- `CORPUS_DIR`, defaults to `data/terrads_sample`

## Citation

Cite the archived release, DOI [10.5281/zenodo.24115285](https://doi.org/10.5281/zenodo.24115285). `CITATION.cff` has the full entry.
