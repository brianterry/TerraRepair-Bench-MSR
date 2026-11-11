"""
Retriever for the relevance-vs-utility ablation.

Three retrieval arms over the hardened-exemplar pool (86 clean modules), plus a
no-retrieval baseline handled by the caller:

  random      - K exemplars drawn at random from the pool (relevance floor),
                seeded per-target for reproducibility.
  similarity  - top-K by cosine similarity of Bedrock Titan embeddings over the
                module's concatenated .tf source (realistic retrieval).
  oracle      - top-K by an OVERLAP heuristic that scores how useful an exemplar
                is for THIS target's repair: it rewards exemplars that (a) share
                resource TYPES with the target, and (b) among those, cover the
                resource types implicated in the target's pre-repair FINDINGS
                (the resources that actually need fixing). Hardened exemplars have
                zero findings themselves, so the heuristic uses the exemplar's
                resource types against the TARGET's finding-bearing resources —
                i.e. "does this clean example show how to configure the kind of
                resource the target got wrong." Empirical upper bound (per CRUX).

Embeddings use amazon.titan-embed-text-v2:0 via Bedrock (same infra as repair;
no new dependency, no model download). Vectors are cached to disk so the arms
are reproducible and cheap. Pure-stdlib + numpy; no sklearn/sentence-transformers.
"""
from __future__ import annotations

import glob
import json
import math
import random as _random
import re
from pathlib import Path

import numpy as np

_RES = re.compile(r'resource\s+"([a-z0-9_]+)"\s+"([a-z0-9_\-]+)"')
_EMBED_MODEL = "amazon.titan-embed-text-v2:0"


def module_source(sample_dir: Path, module_id: str) -> str:
    parts = []
    for f in sorted(glob.glob(str(sample_dir / module_id / "*.tf"))):
        parts.append(Path(f).read_text(errors="ignore"))
    return "\n\n".join(parts)


def resource_pairs(src: str) -> list[tuple[str, str]]:
    """(resource_type, resource_name) declared in the source."""
    return _RES.findall(src)


def resource_types(src: str) -> set[str]:
    return {t for t, _ in resource_pairs(src)}


# ---------------------------------------------------------------------------
# Embeddings (Bedrock Titan), cached to disk
# ---------------------------------------------------------------------------

def _titan_embed(bedrock, text: str) -> list[float]:
    import json as _json
    from botocore.exceptions import ClientError
    # Titan v2 hard input cap is 8192 tokens. HCL is token-dense, so start at a
    # conservative char cap and shrink on a token-overflow ValidationException,
    # so no module silently fails. The module-level embedding is for coarse
    # similarity; the leading section is representative enough.
    for cap in (24000, 16000, 10000, 6000):
        try:
            resp = bedrock.invoke_model(
                modelId=_EMBED_MODEL, body=_json.dumps({"inputText": text[:cap]}),
                contentType="application/json", accept="application/json",
            )
            return _json.loads(resp["body"].read())["embedding"]
        except ClientError as e:
            msg = e.response.get("Error", {}).get("Message", "")
            if "input tokens" in msg.lower() and cap != 6000:
                continue  # shrink and retry
            raise
    raise RuntimeError("titan embed failed after truncation retries")


def build_embedding_cache(bedrock, sample_dir: Path, module_ids: list[str],
                          cache_path: Path) -> dict[str, list[float]]:
    """Embed each module's source once; persist to cache_path. Reuses existing."""
    cache: dict[str, list[float]] = {}
    if cache_path.exists():
        cache = json.loads(cache_path.read_text())
    changed = False
    for mid in module_ids:
        if mid in cache:
            continue
        src = module_source(sample_dir, mid)
        if not src.strip():
            continue
        cache[mid] = _titan_embed(bedrock, src)
        changed = True
    if changed:
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        cache_path.write_text(json.dumps(cache))
    return cache


def _cos(a: np.ndarray, b: np.ndarray) -> float:
    # Use float64 dot + explicit norms. np.dot avoids a spurious matmul
    # RuntimeWarning seen with numpy 2.0 on macOS Accelerate BLAS (the warning
    # is a false alarm from the BLAS backend; the value is correct). Titan
    # embeddings are already unit-normalized, but we normalize defensively.
    na = float(np.linalg.norm(a))
    nb = float(np.linalg.norm(b))
    if na == 0.0 or nb == 0.0:
        return 0.0
    return float(np.dot(a, b)) / (na * nb)


# ---------------------------------------------------------------------------
# Arm selectors
# ---------------------------------------------------------------------------

class Retriever:
    def __init__(self, sample_dir: Path, pool_ids: list[str],
                 embeddings: dict[str, list[float]], seed: int = 42):
        self.sample_dir = sample_dir
        self.pool_ids = [m for m in pool_ids if m in embeddings]
        self.emb = {m: np.array(v, dtype=float) for m, v in embeddings.items()}
        self.seed = seed
        # precompute pool resource types
        self.pool_types = {m: resource_types(module_source(sample_dir, m))
                           for m in self.pool_ids}

    def random_arm(self, target_id: str, k: int) -> list[str]:
        rng = _random.Random(f"{self.seed}:{target_id}")
        return rng.sample(self.pool_ids, min(k, len(self.pool_ids)))

    def similarity_arm(self, target_id: str, k: int) -> list[str]:
        tv = self.emb.get(target_id)
        if tv is None:
            return self.random_arm(target_id, k)
        scored = sorted(self.pool_ids, key=lambda m: -_cos(tv, self.emb[m]))
        return scored[:k]

    def oracle_arm(self, target_id: str, target_finding_resources: set[str],
                   k: int) -> list[str]:
        """Rank exemplars by usefulness for THIS repair:
        score = |exemplar_types ∩ target_finding_bearing_types| * 2
              + |exemplar_types ∩ target_all_types|
        Rewards covering the resource types that actually have findings, then
        general type overlap. Ties broken by embedding similarity."""
        tgt_src = module_source(self.sample_dir, target_id)
        tgt_all = resource_types(tgt_src)
        tv = self.emb.get(target_id)

        def score(m: str) -> tuple[int, float]:
            et = self.pool_types[m]
            fix_overlap = len(et & target_finding_resources)
            type_overlap = len(et & tgt_all)
            sim = _cos(tv, self.emb[m]) if tv is not None else 0.0
            return (fix_overlap * 2 + type_overlap, sim)

        return sorted(self.pool_ids, key=lambda m: score(m), reverse=True)[:k]

    def select(self, arm: str, target_id: str,
               target_finding_resources: set[str], k: int) -> list[str]:
        if arm == "random":
            return self.random_arm(target_id, k)
        if arm == "similarity":
            return self.similarity_arm(target_id, k)
        if arm == "oracle":
            return self.oracle_arm(target_id, target_finding_resources, k)
        raise ValueError(f"unknown arm: {arm!r}")


def format_exemplars(sample_dir: Path, exemplar_ids: list[str],
                     max_chars_each: int = 4000) -> str:
    """Render retrieved exemplars as a prompt block. Truncate each to bound budget."""
    if not exemplar_ids:
        return ""
    blocks = []
    for i, mid in enumerate(exemplar_ids, 1):
        src = module_source(sample_dir, mid)[:max_chars_each]
        blocks.append(f"# Secure example {i}\n```hcl\n{src}\n```")
    return "\n\n".join(blocks)
