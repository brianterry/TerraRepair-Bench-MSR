"""
Verify where each corpus module in data/terrads_sample came from in TerraDS v1.

data/terrads_sample/module_N was written by scripts/sample_terrads.py from
candidate index N of query_candidate_modules(min_resource_types=4, min_stars=5,
provider="aws", limit=1000): the loop names each output dir module_{i:04d}
from the candidate index, and failed clones still consume an index.

That query orders only by StarCount, so the order of equal-star rows is not
defined by SQL. The mapping is therefore verified by content, not assumed:

  * clone each candidate repository (blobless: full commit/tree history, file
    contents fetched only on demand);
  * compare the module's local *.tf files with the *.tf files in the
    candidate's module path, by git blob hash, at these commits in order:
      1. the LatestCommitSha stored in TerraDS,
      2. the repository's current default-branch HEAD,
      3. every other commit that touched the path (HEAD history, then all refs).
    sample_terrads.py cloned HEAD at sampling time (after 2026-03-18), so the
    matching commit may be any of these;
  * if names match but a hash differs, fetch the blob and compare with line
    endings normalized (the sampler's read_text/write_text converted CRLF->LF).

Outcomes per module:
  exact     identical set of *.tf names and identical contents at one commit
  partial   some overlap (names and/or identical files) but never exact
  no_match  no overlap at any commit, path never existed, or clone failed

Only "exact" modules are treated as resolved.

Usage:
  python3 scripts/verify_terrads_provenance.py --sqlite data/external/TerraDS.sqlite \
      --out data/terrads_provenance_verification.json
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from src.sampling.terrads_sampler import query_candidate_modules  # noqa: E402

GIT_ENV = {**os.environ, "GIT_TERMINAL_PROMPT": "0", "GIT_ASKPASS": "/bin/echo"}


def git(repo: Path, *args, check=True, binary=False, timeout=600):
    r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True,
                       env=GIT_ENV, timeout=timeout)
    if check and r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args[:3])}: {r.stderr.decode(errors='replace')[-300:]}")
    return r.stdout if binary else r.stdout.decode(errors="replace")


def blob_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def norm(data: bytes) -> bytes:
    return data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")


def local_files(module_dir: Path) -> dict[str, bytes]:
    return {p.name: p.read_bytes() for p in sorted(module_dir.glob("*.tf")) if p.is_file()}


def tree_tf(repo: Path, commit: str, path: str) -> dict[str, tuple[str, str]] | None:
    """*.tf blobs directly in <path> at <commit>: name -> (mode, sha). None if
    the path does not exist there."""
    spec = commit if path in ("", ".") else f"{commit}:{path.strip('/')}"
    r = subprocess.run(["git", "-C", str(repo), "ls-tree", spec], capture_output=True, env=GIT_ENV)
    if r.returncode != 0:
        return None
    out = {}
    for line in r.stdout.decode(errors="replace").splitlines():
        meta, name = line.split("\t", 1)
        mode, typ, sha = meta.split()
        if typ == "blob" and name.endswith(".tf"):
            out[name] = (mode, sha)
    return out


def _fetch(repo: Path, sha: str, blob_cache: dict) -> bytes | None:
    if sha not in blob_cache:
        try:
            blob_cache[sha] = git(repo, "cat-file", "-p", sha, binary=True)
        except RuntimeError:
            blob_cache[sha] = None      # unfetchable on demand: cannot confirm
    return blob_cache[sha]


def resolve_symlink(repo: Path, commit: str, path: str, name: str, link_sha: str,
                    blob_cache: dict, depth: int = 0) -> str | None:
    """Follow a symlink blob to the blob it points to within <commit>'s tree.
    Returns the target blob sha, or None if it cannot be resolved inside the repo."""
    target = _fetch(repo, link_sha, blob_cache)
    if target is None or depth > 8:
        return None
    base = "" if path in ("", ".") else path.strip("/")
    resolved = os.path.normpath(os.path.join(base, name, "..", target.decode(errors="replace")))
    if resolved.startswith("..") or os.path.isabs(resolved):
        return None                     # points outside the repository
    r = subprocess.run(["git", "-C", str(repo), "ls-tree", commit, "--", resolved],
                       capture_output=True, env=GIT_ENV)
    line = r.stdout.decode(errors="replace").strip()
    if r.returncode != 0 or not line:
        return None
    mode, typ, sha = line.split("\t", 1)[0].split()
    if typ != "blob":
        return None
    if mode == "120000":
        d, n = os.path.split(resolved)
        return resolve_symlink(repo, commit, d, n, sha, blob_cache, depth + 1)
    return sha


def compare(repo: Path, commit: str, path: str, local: dict[str, bytes],
            remote: dict[str, tuple[str, str]], blob_cache: dict):
    """Return (exact, byte_identical, names_overlap, identical_files, symlinks_followed).

    byte_identical: every file matched its git blob byte-for-byte with no
    symlink following and no line-ending normalization."""
    lnames, rnames = set(local), set(remote)
    same = 0
    symlinks = 0
    byte_identical = True
    for name in lnames & rnames:
        mode, sha = remote[name]
        if mode == "120000":
            # Symlink in the repo. The sampler checked the repo out and read the
            # file through the link, so the local copy holds the TARGET's
            # content. Resolve the link inside the same commit's tree.
            sha = resolve_symlink(repo, commit, path, name, sha, blob_cache)
            byte_identical = False
            if sha is None:
                continue
            symlinks += 1
        if blob_sha(local[name]) == sha:
            same += 1
            continue
        data = _fetch(repo, sha, blob_cache)
        byte_identical = False
        if data is not None and norm(data) == norm(local[name]):
            same += 1
    exact = lnames == rnames and same == len(lnames) and len(lnames) > 0
    return exact, exact and byte_identical, len(lnames & rnames), same, symlinks


def verify_repo(clone_url: str, cand_by_module: dict[str, dict], clones: Path) -> list[dict]:
    d = clones / (clone_url.rstrip("/").removesuffix(".git").split("github.com/")[-1].replace("/", "__"))
    results = []
    try:
        if not d.exists():
            r = subprocess.run(["git", "clone", "--bare", "--filter=blob:none", "--quiet", clone_url, str(d)],
                               capture_output=True, env=GIT_ENV, timeout=1800)
            if r.returncode != 0:
                raise RuntimeError(r.stderr.decode(errors="replace").strip()[-300:])
        head = git(d, "rev-parse", "HEAD").strip()
    except Exception as e:  # noqa: BLE001
        for mod, c in cand_by_module.items():
            results.append({"module_id": mod, "outcome": "no_match", "reason": f"clone failed: {e}", **_cand(c)})
        return results

    blob_cache: dict = {}
    for mod, c in sorted(cand_by_module.items()):
        try:
            results.append(_verify_module(d, head, mod, c, blob_cache))
        except Exception as e:  # noqa: BLE001 - record, never silently resolve
            results.append({"module_id": mod, **_cand(c), "outcome": "error",
                            "reason": f"{type(e).__name__}: {e}"})
    return results


def _verify_module(d: Path, head: str, mod: str, c: dict, blob_cache: dict) -> dict:
    local = local_files(ROOT / "data" / "terrads_sample" / mod)
    path = c["relative_path"]
    tds = c["latest_commit_sha"]
    tds_present = subprocess.run(["git", "-C", str(d), "cat-file", "-e", f"{tds}^{{commit}}"],
                                 capture_output=True, env=GIT_ENV).returncode == 0 if tds else False
    pathspec = "." if path in ("", ".") else path.strip("/")
    order = []
    if tds_present:
        order.append(("terrads_commit", tds))
    order.append(("current_head", head))
    hist = git(d, "log", "--format=%H", "HEAD", "--", pathspec, check=False).split()
    allh = git(d, "log", "--format=%H", "--all", "--", pathspec, check=False).split()
    seen = {x[1] for x in order}
    for kind, lst in (("head_history", hist), ("other_refs_history", allh)):
        for h in lst:
            if h not in seen:
                order.append((kind, h)); seen.add(h)

    best = None  # (overlap+same, overlap, same, commit, kind)
    found = None
    path_ever = False
    for kind, commit in order:
        remote = tree_tf(d, commit, path)
        if remote is None:
            continue
        path_ever = True
        exact, byte_ident, overlap, same, symlinks = compare(d, commit, path, local, remote, blob_cache)
        if exact:
            found = (kind, commit, byte_ident, symlinks)
            break
        score = (same, overlap)
        if best is None or score > best[0]:
            best = (score, commit, kind, sorted(set(local) - set(remote)), sorted(set(remote) - set(local)))
    rec = {"module_id": mod, **_cand(c), "terrads_commit_in_clone": tds_present,
           "current_head": head, "commits_checked": len(order), "local_tf_files": len(local)}
    if found:
        kind, commit, byte_ident, symlinks = found
        commit_date = git(d, "show", "-s", "--format=%cI", commit).strip()
        rec.update(outcome="exact", match_basis=kind, verified_commit=commit, verified_commit_date=commit_date,
                   byte_identical=byte_ident, symlinks_followed=symlinks)
    elif best and (best[0][0] > 0 or best[0][1] > 0):
        (same, overlap), commit, kind, only_local, only_remote = best
        rec.update(outcome="partial", reason=f"best at {kind} {commit[:12]}: {same}/{len(local)} files identical, "
                   f"{overlap} names shared", best_commit=commit, only_local=only_local, only_remote=only_remote)
    else:
        rec.update(outcome="no_match",
                   reason="path never contains *.tf in checked history" if not path_ever else "no shared file names or contents at any commit")
    return rec


def _cand(c):
    return {k: c[k] for k in ("candidate_index", "repository_id", "full_name", "clone_url", "relative_path",
                              "license", "latest_commit_sha", "latest_commit_at", "stars")}


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--sqlite", required=True)
    ap.add_argument("--manifest", default=str(ROOT / "experiments/results/release_slice_2026-10/corpus_manifest.jsonl"))
    ap.add_argument("--limit", type=int, default=1000)
    ap.add_argument("--clones", default="/tmp/terrads_clones")
    ap.add_argument("--out", required=True)
    ap.add_argument("--workers", type=int, default=6)
    args = ap.parse_args(argv)

    import sqlite3
    rows = query_candidate_modules(args.sqlite, min_resource_types=4, min_stars=5, provider="aws", limit=args.limit)
    con = sqlite3.connect(args.sqlite)
    meta = {r[0]: r[1:] for r in con.execute(
        "SELECT Id, FullName, License, LatestCommitSha, LatestCommitAt FROM Repositories")}
    modules = [json.loads(l)["module_id"] for l in open(args.manifest) if l.strip()]

    by_repo: dict[str, dict[str, dict]] = {}
    for mod in modules:
        i = int(mod.split("_")[1])
        c = dict(rows[i])
        full_name, lic, sha, at = meta[c["repository_id"]]
        c.update(candidate_index=i, full_name=full_name, license=lic, latest_commit_sha=sha, latest_commit_at=at)
        by_repo.setdefault(c["clone_url"], {})[mod] = c

    clones = Path(args.clones); clones.mkdir(parents=True, exist_ok=True)
    results = []
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        for res in ex.map(lambda kv: verify_repo(kv[0], kv[1], clones), by_repo.items()):
            results.extend(res)
            for r in res:
                print(f"{r['module_id']} {r['outcome']:8s} {r['full_name']}/{r['relative_path']}", flush=True)
    results.sort(key=lambda r: r["module_id"])

    from collections import Counter
    report = {
        "generated": datetime.now(timezone.utc).isoformat(),
        "terrads_sqlite": args.sqlite,
        "query": {"min_resource_types": 4, "min_stars": 5, "provider": "aws", "limit": args.limit},
        "n_modules": len(results),
        "n_repositories": len(by_repo),
        "outcomes": dict(Counter(r["outcome"] for r in results)),
        "exact_by_basis": dict(Counter(r["match_basis"] for r in results if r["outcome"] == "exact")),
        "modules": results,
    }
    Path(args.out).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: report[k] for k in ("n_modules", "n_repositories", "outcomes", "exact_by_basis")}, indent=2))


if __name__ == "__main__":
    main()
