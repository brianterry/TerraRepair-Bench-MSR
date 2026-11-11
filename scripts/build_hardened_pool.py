"""
Build the hardened-exemplar pool and the restricted ablation target set
(Option C) for the retrieval-relevance ablation. Reporting/analysis only — reads
the recorded corpus-construction scan (skip_manifest.jsonl) and the module .tf
sources; runs NO scanners and NO inference.

Clean threshold (documented):
  A module is HARDENED iff it scanned to ZERO deduplicated (rule_id,
  resource_name) findings under the pinned dual stack (Trivy 0.74.0 + Checkov
  3.3.20) during the 2026-09 corpus construction. These are recorded in
  full_refresh_2026-09/skip_manifest.jsonl as "finding count 0 outside [3,50]".
  No near-clean (>=1 finding) modules are admitted: an exemplar that itself
  carries a finding is not a clean "securely-configured" example.

Target set (Option C):
  The ablation targets are the capacity-controlled modules (232) RESTRICTED to
  those with >= 1 resource type present in the hardened pool — i.e. modules for
  which relevance-based retrieval can operate at all. Controlled targets with no
  pool-covered resource type are EXCLUDED and listed, so the relevance-vs-utility
  question is tested only where relevance is operable.

Outputs (to experiments/results/retrieval_ablation/):
  hardened_pool.json        - {threshold, module_ids, resource_types}
  ablation_targets.json     - {targets, excluded_no_overlap, source}
"""
from __future__ import annotations

import glob
import json
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SAMPLE = ROOT / "data" / "terrads_sample"
SKIP = ROOT / "experiments/results/full_refresh_2026-09/skip_manifest.jsonl"
CONTROLLED = "/tmp/controlled_mods.json"
OUT = ROOT / "experiments/results/retrieval_ablation"

_RES = re.compile(r'resource\s+"([a-z0-9_]+)"')


def resource_types(module_id: str) -> set[str]:
    s: set[str] = set()
    for f in glob.glob(str(SAMPLE / module_id / "*.tf")):
        try:
            s.update(_RES.findall(Path(f).read_text(errors="ignore")))
        except OSError:
            pass
    return s


def clean_pool() -> list[str]:
    """0-finding modules from the recorded corpus-construction scan, present on disk."""
    by_mod: dict[str, int] = {}
    for line in SKIP.read_text().splitlines():
        if not line.strip():
            continue
        d = json.loads(line)
        m = re.search(r"finding count (\d+)", d.get("reason", ""))
        if m:
            by_mod[d["id"]] = int(m.group(1))  # consistent across dup lines (verified)
    clean = [mid for mid, n in by_mod.items() if n == 0]
    return sorted(
        mid for mid in clean
        if (SAMPLE / mid).is_dir() and glob.glob(str(SAMPLE / mid / "*.tf"))
    )


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    pool = clean_pool()
    pool_types: set[str] = set()
    pool_type_by_mod = {}
    for mid in pool:
        rt = resource_types(mid)
        pool_type_by_mod[mid] = sorted(rt)
        pool_types |= rt

    controlled = json.load(open(CONTROLLED))
    targets, excluded = [], []
    for mid in sorted(controlled):
        if resource_types(mid) & pool_types:
            targets.append(mid)
        else:
            excluded.append(mid)

    (OUT / "hardened_pool.json").write_text(json.dumps({
        "clean_threshold": "0 deduplicated (rule_id,resource_name) findings under "
                           "Trivy 0.74.0 + Checkov 3.3.20 (2026-09 corpus scan)",
        "source": "full_refresh_2026-09/skip_manifest.jsonl (finding count 0)",
        "n_modules": len(pool),
        "module_ids": pool,
        "n_distinct_resource_types": len(pool_types),
        "resource_types_by_module": pool_type_by_mod,
    }, indent=2))

    (OUT / "ablation_targets.json").write_text(json.dumps({
        "policy": "Option C: capacity-controlled modules restricted to those with "
                  ">=1 resource type present in the hardened pool",
        "n_controlled": len(controlled),
        "n_targets": len(targets),
        "n_excluded_no_overlap": len(excluded),
        "targets": targets,
        "excluded_no_overlap": excluded,
    }, indent=2))

    print(f"hardened pool: {len(pool)} modules, {len(pool_types)} distinct resource types")
    print(f"ablation targets (Option C): {len(targets)} / {len(controlled)} controlled "
          f"({len(excluded)} excluded for no pool overlap)")
    print(f"wrote {OUT}/hardened_pool.json and ablation_targets.json")


if __name__ == "__main__":
    main()
