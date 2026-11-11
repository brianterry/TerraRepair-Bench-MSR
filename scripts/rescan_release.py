"""
Release rescan: verify that every saved artifact reproduces its recorded
scanner findings, and capture the remote inputs Trivy fetched so the release
can be rescanned offline.

Why this exists: Trivy's `config` scan downloads every remote Terraform module a
file references (Registry / git sources) and scans its contents too, and it
downloads its checks bundle at scan time. ~1/3 of games reference remote
modules, so their recorded findings depend on network content, not only on the
released .repaired.tf. This script

  1. INPUTS: rescans each corpus module (data/terrads_sample/<module>) and
     checks the identities equal the games' recorded findings_before;
  2. GAMES: for every game, checks both sidecars exist and the sha256 matches,
     and for every hcl_valid game rescans the saved .repaired.tf exactly as the
     runner did (fresh temp dir, single main.tf) and compares
     (rule_id, resource_name) identities to findings_after;
  3. CAPTURE (--capture): archives Trivy's module cache and checks bundle with a
     manifest of module source URLs + git commits and the bundle digest.

It never stops at the first problem: each item gets an outcome
(match / mismatch / scanner_failure / sha_mismatch / missing_sidecar /
skipped_hcl_invalid), written one JSON line per item as it goes, then a
summary. It is read-only on the results tree and changes no scores.

Scans run SERIALLY on purpose: Trivy reuses one module cache across scans and a
concurrent scan could read a half-written clone.

Usage (Fargate / container):
  TERRAREPAIR_TRIVY_TIMEOUT=900 python3 scripts/rescan_release.py \
      --results experiments/results/release_slice_2026-10 --out /tmp/rescan_out --capture
Exit code: 0 if every input and game matches, 1 otherwise (report still written).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from src.scanning.scanner_normalizer import ScannerStack  # noqa: E402
from src.utils.repair_artifacts import sha256_hex  # noqa: E402

# A module block whose source is not a local path => Trivy fetches it remotely.
_MODULE_SRC = re.compile(r'module\s+"[^"]+"\s*\{[^}]*?source\s*=\s*"([^"]+)"', re.S)


def _utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()


def remote_module_sources(text: str) -> list[str]:
    return [s for s in _MODULE_SRC.findall(text) if not s.startswith(("./", "../"))]


def identities(findings) -> set[tuple[str, str]]:
    out = set()
    for f in findings:
        if isinstance(f, dict):
            out.add((f["rule_id"], f["resource_name"]))
        else:
            out.add((f.rule_id, f.resource_name))
    return out


def _diff(expected: set, actual: set) -> dict:
    return {"missing": sorted(map(list, expected - actual)),
            "extra": sorted(map(list, actual - expected))}


def scan_code(stack: ScannerStack, code: bytes):
    """Scan code exactly as the runner scanned a repair: one main.tf in a
    fresh temp dir. Returns the ScanResult."""
    tmp = tempfile.mkdtemp()
    try:
        (Path(tmp) / "main.tf").write_bytes(code)
        return stack.run_checked(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def check_game(stack: ScannerStack, game_json: Path) -> dict:
    g = json.loads(game_json.read_text())
    rec = {"item": "game", "game": game_json.name, "module_id": g["module_id"],
           "model_id": g["model_id"], "hcl_valid": g["hcl_valid"]}
    tf = game_json.parent / g.get("repaired_code_path", "")
    raw = game_json.parent / g.get("raw_response_path", "")
    if not g.get("repaired_code_path") or not tf.is_file() or not raw.is_file():
        return {**rec, "outcome": "missing_sidecar"}
    data = tf.read_bytes()
    if sha256_hex(data) != g["repaired_code_sha256"]:
        return {**rec, "outcome": "sha_mismatch"}
    rec["remote_modules"] = len(remote_module_sources(data.decode("utf-8", "ignore")))
    if not g["hcl_valid"]:
        # By the scoring rule invalid repairs are never scanned
        # (findings_after := findings_before), so there is nothing to rescan.
        return {**rec, "outcome": "skipped_hcl_invalid"}
    t0 = time.monotonic()
    res = scan_code(stack, data)
    rec["secs"] = round(time.monotonic() - t0, 1)
    if not res.ok:
        return {**rec, "outcome": "scanner_failure", "failures": res.failures}
    exp, act = identities(g["findings_after"]), identities(res.findings)
    if exp == act:
        return {**rec, "outcome": "match", "n_findings": len(exp)}
    return {**rec, "outcome": "mismatch", **_diff(exp, act)}


def check_input(stack: ScannerStack, module_dir: Path, recorded: set) -> dict:
    rec = {"item": "input", "module_id": module_dir.name}
    text = "\n".join(p.read_text(errors="ignore") for p in sorted(module_dir.glob("*.tf")))
    rec["remote_modules"] = len(remote_module_sources(text))
    t0 = time.monotonic()
    res = stack.run_checked(str(module_dir))
    rec["secs"] = round(time.monotonic() - t0, 1)
    if not res.ok:
        return {**rec, "outcome": "scanner_failure", "failures": res.failures}
    act = identities(res.findings)
    if act == recorded:
        return {**rec, "outcome": "match", "n_findings": len(act)}
    return {**rec, "outcome": "mismatch", **_diff(recorded, act)}


# ------------------------------------------------------------------ capture --

def trivy_module_cache_dir() -> Path:
    # Trivy caches downloaded Terraform modules under <TMPDIR>/.aqua/cache.
    return Path(tempfile.gettempdir()) / ".aqua" / "cache"


def trivy_checks_dir() -> Path:
    return Path(os.environ.get("TRIVY_CACHE_DIR", Path.home() / ".cache" / "trivy")) / "policy"


def _git(d: Path, *args) -> str:
    try:
        return subprocess.run(["git", "-c", "safe.directory=*", *args], cwd=d,
                              capture_output=True, text=True, timeout=30).stdout.strip()
    except Exception:  # noqa: BLE001 - git missing / not a repo
        return ""


def capture(out: Path) -> dict:
    """Archive the module cache and checks bundle; return the manifest."""
    mods = []
    cache = trivy_module_cache_dir()
    if cache.is_dir():
        for d in sorted(p for p in cache.iterdir() if p.is_dir()):
            mods.append({"cache_key": d.name,
                         "source_url": _git(d, "config", "--get", "remote.origin.url") or None,
                         "commit": _git(d, "rev-parse", "HEAD") or None,
                         "tf_files": sum(1 for _ in d.rglob("*.tf"))})
        with tarfile.open(out / "trivy_module_cache.tar.gz", "w:gz") as tar:
            tar.add(cache, arcname=".aqua/cache")
    checks = trivy_checks_dir()
    checks_meta = None
    if (checks / "metadata.json").is_file():
        checks_meta = json.loads((checks / "metadata.json").read_text())
        with tarfile.open(out / "trivy_checks_bundle.tar.gz", "w:gz") as tar:
            tar.add(checks, arcname="trivy/policy")
    manifest = {
        "captured": _utcnow(),
        "module_cache_dir_at_scan": str(cache),
        "modules": mods,
        "checks_bundle": checks_meta,
        "offline_restore": (
            "tar xzf trivy_module_cache.tar.gz -C \"$TMPDIR\" (or /tmp); "
            "tar xzf trivy_checks_bundle.tar.gz -C ~/.cache; "
            "then rescan with networking disabled"),
    }
    (out / "capture_manifest.json").write_text(json.dumps(manifest, indent=2))
    return manifest


def _versions() -> dict:
    out = {}
    for tool, cmd in (("trivy", ["trivy", "--version"]), ("checkov", ["checkov", "--version"])):
        try:
            out[tool] = subprocess.run(cmd, capture_output=True, text=True,
                                       timeout=120).stdout.strip().splitlines()[0]
        except Exception as e:  # noqa: BLE001
            out[tool] = f"UNAVAILABLE: {type(e).__name__}"
    return out


# --------------------------------------------------------------------- main --

def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", required=True, help="results dir with games/ and corpus_manifest.jsonl")
    ap.add_argument("--out", required=True, help="where to write the report (and capture)")
    ap.add_argument("--corpus-dir", default=str(ROOT / "data" / "terrads_sample"))
    ap.add_argument("--capture", action="store_true", help="archive module cache + checks bundle")
    ap.add_argument("--skip-inputs", action="store_true")
    ap.add_argument("--limit", type=int, default=None, help="cap games checked (testing)")
    ap.add_argument("--only-remote", action="store_true",
                    help="check only inputs/games that reference remote modules "
                         "(the items whose findings depend on fetched content)")
    args = ap.parse_args(argv)

    results, out = Path(args.results), Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    games = sorted((results / "games").glob("*.json"))
    if args.limit:
        games = games[:args.limit]

    def _game_is_remote(gf: Path) -> bool:
        g = json.loads(gf.read_text())
        tf = gf.parent / g.get("repaired_code_path", "")
        return tf.is_file() and bool(remote_module_sources(tf.read_text(errors="ignore")))

    def _input_is_remote(mod: str) -> bool:
        d = Path(args.corpus_dir) / mod
        return bool(remote_module_sources(
            "\n".join(p.read_text(errors="ignore") for p in sorted(d.glob("*.tf")))))

    meta = {"started": _utcnow(), "results": str(results),
            "only_remote": args.only_remote,
            "trivy_timeout_env": os.environ.get("TERRAREPAIR_TRIVY_TIMEOUT"),
            # Recorded so an offline run is identifiable from its summary.
            "network_env": {k: os.environ.get(k) for k in
                            ("HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY", "TRIVY_SKIP_CHECK_UPDATE")
                            if os.environ.get(k) is not None},
            "scanner_versions": _versions(),
            "git_commit": os.environ.get("TERRAREPAIR_GIT_COMMIT") or None,
            "n_games": len(games)}
    print(json.dumps(meta), flush=True)

    stack = ScannerStack()
    log = open(out / "rescan_results.jsonl", "w")
    rows = []

    def emit(r):
        rows.append(r)
        log.write(json.dumps(r) + "\n")
        log.flush()

    # 1. Inputs: one recorded findings_before per module (identical across that
    # module's games -- verified here too).
    if not args.skip_inputs:
        recorded: dict[str, set] = {}
        disagree = set()
        for gf in games:
            g = json.loads(gf.read_text())
            ids = identities(g["findings_before"])
            if g["module_id"] in recorded and recorded[g["module_id"]] != ids:
                disagree.add(g["module_id"])
            recorded.setdefault(g["module_id"], ids)
        mods = sorted(recorded)
        if args.only_remote:
            mods = [m for m in mods if _input_is_remote(m)]
        for i, mod in enumerate(mods, 1):
            r = check_input(stack, Path(args.corpus_dir) / mod, recorded[mod])
            if mod in disagree:
                r["recorded_findings_before_disagree_across_games"] = True
            emit(r)
            print(f"[input {i}/{len(mods)}] {mod} {r['outcome']} ({r.get('secs')}s)", flush=True)

    # 2. Games.
    if args.only_remote:
        games = [gf for gf in games if _game_is_remote(gf)]
    meta["n_games_checked"] = len(games)
    for i, gf in enumerate(games, 1):
        r = check_game(stack, gf)
        emit(r)
        if r["outcome"] != "skipped_hcl_invalid":
            print(f"[game {i}/{len(games)}] {gf.stem} {r['outcome']} ({r.get('secs')}s)", flush=True)
    log.close()

    # 3. Summary.
    def tally(sel):
        return dict(Counter(r["outcome"] for r in rows if sel(r)))
    by_model = defaultdict(Counter)
    for r in rows:
        if r["item"] == "game":
            by_model[r["model_id"]][r["outcome"]] += 1
    summary = {
        **meta, "finished": _utcnow(),
        "inputs": tally(lambda r: r["item"] == "input"),
        "inputs_with_remote_modules": tally(lambda r: r["item"] == "input" and r.get("remote_modules")),
        "games": tally(lambda r: r["item"] == "game"),
        "games_with_remote_modules": tally(lambda r: r["item"] == "game" and r.get("remote_modules")),
        "games_by_model": {m: dict(c) for m, c in sorted(by_model.items())},
    }
    if args.capture:
        man = capture(out)
        summary["capture"] = {"modules": len(man["modules"]),
                              "checks_bundle_digest": (man["checks_bundle"] or {}).get("Digest")}
    (out / "rescan_summary.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2), flush=True)

    bad = {"mismatch", "scanner_failure", "sha_mismatch", "missing_sidecar"}
    return 1 if any(r["outcome"] in bad for r in rows) else 0


if __name__ == "__main__":
    sys.exit(main())
