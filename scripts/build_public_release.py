#!/usr/bin/env python3
"""Build the public release tree for TerraRepair-Bench in a separate folder.

Copies only what RELEASE_CONTENTS.md lists as included, keeps only the 262
admitted corpus modules, and replaces the AWS account ID with a placeholder.
Nothing in this repository is modified.

Usage (from the repo root):
  python3 scripts/build_public_release.py ../TerraRepair-Bench-public
"""
import json, os, re, shutil, sys
from pathlib import Path

SRC = Path(__file__).resolve().parent.parent
ACCOUNT = "<ACCOUNT_ID>"
PLACEHOLDER = "<ACCOUNT_ID>"

TOP_FILES = [
    "README.md", "LICENSE", "CITATION.cff", ".zenodo.json", "THIRD_PARTY_LICENSES.md",
    "RELEASE_CONTENTS.md", "CORPUS.md", "CONTAINER.md", "RELEASE_SLICE_RESULTS.md",
    "HARNESS_AUDIT.md", "METHODOLOGY.md", "Dockerfile", ".dockerignore", ".gitignore",
    "requirements.txt", "pyproject.toml", ".env.example",
]
TOP_DIRS = ["src", "scripts", "tests", "LICENSES"]
DEPLOY_SKIP = re.compile(r"(\.env$|\.rendered\.json$)")
CONFIGS = ["release_slice_2026-10.yaml", "release_slice_2026-10_smoke.yaml"]
RESULTS = [
    "release_slice_2026-10", "release_slice_2026-10_rescan",
    "release_slice_2026-10_offline2_full", "release_slice_2026-10_offline2_nogit",
]
EXTRA_DATA = ["terrads_provenance.csv", "terrads_provenance_verification.json"]
IGNORE = shutil.ignore_patterns("__pycache__", "*.pyc", ".DS_Store", ".pytest_cache")
TEXT_EXT = {".py", ".md", ".json", ".jsonl", ".yaml", ".yml", ".sh", ".txt", ".toml", ".cfg", ".csv", ""}


def scrub(root: Path) -> list[str]:
    changed = []
    for p in root.rglob("*"):
        if not p.is_file() or p.suffix not in TEXT_EXT or p.suffix == ".tf":
            continue
        try:
            t = p.read_text()
        except UnicodeDecodeError:
            continue
        if ACCOUNT in t:
            p.write_text(t.replace(ACCOUNT, PLACEHOLDER))
            changed.append(str(p.relative_to(root)))
    return changed


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out = Path(sys.argv[1]).resolve()
    if out.exists():
        sys.exit(f"{out} already exists; remove it or pick another path")
    if SRC in out.parents or out == SRC:
        sys.exit("output must be outside this repository")
    out.mkdir(parents=True)

    for f in TOP_FILES:
        if (SRC / f).exists():
            shutil.copy2(SRC / f, out / f)
    for d in TOP_DIRS:
        if (SRC / d).exists():
            shutil.copytree(SRC / d, out / d, ignore=IGNORE)
    (out / "deploy").mkdir()
    for p in (SRC / "deploy").iterdir():
        if p.is_file() and not DEPLOY_SKIP.search(p.name):
            shutil.copy2(p, out / "deploy" / p.name)
    (out / "experiments/configs").mkdir(parents=True)
    for c in CONFIGS:
        shutil.copy2(SRC / "experiments/configs" / c, out / "experiments/configs" / c)
    for r in RESULTS:
        shutil.copytree(SRC / "experiments/results" / r, out / "experiments/results" / r, ignore=IGNORE)

    manifest = SRC / "experiments/results/release_slice_2026-10/corpus_manifest.jsonl"
    admitted = [json.loads(l)["module_id"] for l in manifest.open()]
    for m in admitted:
        shutil.copytree(SRC / "data/terrads_sample" / m, out / "data/terrads_sample" / m, ignore=IGNORE)
    for f in EXTRA_DATA:
        shutil.copy2(SRC / "data" / f, out / "data" / f)

    changed = scrub(out)
    left = [str(p.relative_to(out)) for p in out.rglob("*")
            if p.is_file() and p.suffix != ".tf" and ACCOUNT in p.read_bytes().decode("utf-8", "ignore")]
    n_files = sum(1 for p in out.rglob("*") if p.is_file())
    size = sum(p.stat().st_size for p in out.rglob("*") if p.is_file())
    print(f"built {out}: {n_files} files, {size/1e6:.1f} MB, {len(admitted)} corpus modules")
    print(f"account ID replaced in {len(changed)} files")
    if left:
        sys.exit(f"account ID still present in: {left}")


if __name__ == "__main__":
    main()
