# Release contents (MSR 2027 artifact)

What goes into the public repository and the Zenodo archive, and what stays out.

## Included

| Path | Size | Why |
|---|---|---|
| `src/`, `scripts/`, `tests/`, `deploy/`, `Dockerfile`, `requirements.txt` | <1 MB | The harness and the container with pinned scanners |
| `experiments/configs/release_slice_2026-10*.yaml` | small | Configuration used for the released slice |
| `experiments/results/release_slice_2026-10/` | 108 MB | The released slice: 2,614 games with sidecars and the three manifests |
| `experiments/results/release_slice_2026-10_rescan/` | 0.7 MB | Rescan results and capture manifest |
| `experiments/results/release_slice_2026-10_offline2_full/`, `..._offline2_nogit/` | 0.4 MB | Offline remote-module rescans |
| `data/terrads_sample/` (the 262 admitted modules only) | ~7 MB | Corpus inputs; needed to rescan `findings_before` |
| `CORPUS.md`, `CONTAINER.md`, `RELEASE_SLICE_RESULTS.md`, `HARNESS_AUDIT.md` | small | Method and audit notes |
| `LICENSE`, `CITATION.cff`, `.zenodo.json`, `THIRD_PARTY_LICENSES.md` | small | Licensing and citation |

**Zenodo archive only (not git):** the Trivy module cache (484 module copies, about 146 MB) and the Trivy checks bundle, which the paper says the archive adds for offline rescans. These are not in the repo tree today; they come from the rescan capture step.

## Excluded

| Path | Why |
|---|---|
| `experiments/results/full_180_game/` | Earlier run; its scored set does not match the paper's corpus rule (see `CORPUS.md`) |
| `experiments/results/full_refresh_2026-09*`, `full_corrected/` | Earlier runs, already gitignored; not described in the MSR paper |
| `experiments/results/prompt_ablation/`, `retrieval_ablation/` | Belong to other papers, one under review |
| `data/terrads_corpus/` | Superseded duplicate of the corpus inputs |
| `data/poc_resolve_diff/` | 1.8 GB scratch tree, already gitignored |
| `data/terrads_sample/` modules not in the corpus manifest | Rejected candidates; only the 262 admitted modules are released |
| `paper/` drafts, briefs, and other venues' sources | Not part of the artifact |
| `.env`, `deploy/*.env`, `deploy/*.rendered.json` | Account-specific, already gitignored |

## Before publishing

1. Check the git history for secrets or account IDs before making the repo public.
2. Confirm `THIRD_PARTY_LICENSES.md` covers every released module. Leave out any module whose license cannot be confirmed.
3. Fill `TODO-REPOSITORY-URL` and `TODO-ZENODO-DOI` in `CITATION.cff`.
