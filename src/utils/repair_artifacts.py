"""
Persist each game's model output as sidecar files next to the game JSON.

For a game JSON ``<stem>.json`` this writes:

  <stem>.repaired.tf  -- the sanitized repaired code (``RepairResult.repaired_code``),
                         i.e. the exact text written to main.tf and scanned when
                         the game is hcl_valid. For hcl_invalid games it is the
                         sanitized text that FAILED validation and was NOT
                         scanned (findings_after == findings_before by the
                         scoring rule). Empty when the model refused / returned
                         nothing / the call errored.
  <stem>.raw.txt      -- the raw model response text BEFORE sanitization.
                         Empty if the invocation itself failed.

and returns the fields to merge into the game JSON. Paths are relative to the
directory containing the game JSON (i.e. bare filenames), so a results tree can
be moved or archived without breaking references. Code is never inlined in the
JSON.

Both files are written as UTF-8 bytes; ``repaired_code_sha256`` is computed over
exactly those bytes, so ``sha256(<stem>.repaired.tf) == repaired_code_sha256``.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from src.repair.repair_agent import RepairResult

REPAIRED_SUFFIX = ".repaired.tf"
RAW_SUFFIX = ".raw.txt"


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_repair_sidecars(game_file: Path, result: "RepairResult") -> dict:
    """Write the sidecars for ``game_file`` and return the JSON fields.

    Call this BEFORE writing the game JSON: the game JSON's existence is the
    runners' resume marker, so if the process dies between the two writes the
    game is simply re-run and its sidecars overwritten.
    """
    game_file = Path(game_file)
    stem = game_file.stem  # "<module>_<model>[_<arm>_d<N>]"
    repaired_path = game_file.with_name(stem + REPAIRED_SUFFIX)
    raw_path = game_file.with_name(stem + RAW_SUFFIX)

    repaired_bytes = (result.repaired_code or "").encode("utf-8")
    raw_bytes = (result.raw_response or "").encode("utf-8")
    repaired_path.write_bytes(repaired_bytes)
    raw_path.write_bytes(raw_bytes)

    return {
        "repaired_code_path": repaired_path.name,
        "raw_response_path": raw_path.name,
        "repaired_code_sha256": sha256_hex(repaired_bytes),
    }
