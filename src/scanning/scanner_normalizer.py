"""
Unified finding format across Trivy and Checkov.

Normalizes raw scanner output into Finding dataclass.
Deduplicates by (rule_id, resource_name).
"""
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    pass

logger = logging.getLogger(__name__)


@dataclass
class Finding:
    tool: str  # "trivy" or "checkov"
    rule_id: str  # canonical: "AWS-0086" (Trivy) or "CKV_AWS_19" (Checkov)
    title: str
    severity: str  # CRITICAL, HIGH, MEDIUM, LOW
    resource_name: str  # "aws_s3_bucket.example"
    resource_type: str  # "aws_s3_bucket"
    file_path: str
    start_line: int
    end_line: int


def canonicalize_rule_id(rule_id: str) -> str:
    """
    Canonicalize a scanner rule id so the (rule_id, resource_name) key is
    STABLE across scanner versions (audit Claim 2 / re-run hazard).

    Trivy's ``config`` scanner emits misconfiguration ids as ``AVD-AWS-0086``
    in current releases, but the recorded TerraRepair-Bench corpus stored them
    bare as ``AWS-0086`` (and completeness_checker.RULE_MAPPING is keyed on the
    bare form). Stripping the leading ``AVD-`` prefix collapses both spellings
    to one canonical id, so:
      * delta keys match across a corpus scanned with different Trivy versions;
      * RULE_MAPPING keeps matching after a Trivy upgrade.

    Checkov ids (``CKV_AWS_19``, ``CKV2_AWS_6``) are left untouched.
    """
    if rule_id.startswith("AVD-"):
        return rule_id[len("AVD-"):]
    return rule_id


def normalize_trivy_findings(raw: list[dict]) -> list[Finding]:
    """Convert raw Trivy Misconfigurations to Finding objects.

    Rule ids are canonicalized (AVD- prefix stripped) for cross-version key
    stability; see ``canonicalize_rule_id``.
    """
    findings = []
    for item in raw:
        meta = item.get("CauseMetadata", {})
        resource = meta.get("Resource", "unknown")
        # Extract resource type (e.g., aws_s3_bucket from aws_s3_bucket.example)
        resource_type = resource.split(".")[0] if "." in resource else resource
        findings.append(
            Finding(
                tool="trivy",
                rule_id=canonicalize_rule_id(item.get("ID", "")),
                title=item.get("Title", ""),
                severity=item.get("Severity", "UNKNOWN").upper(),
                resource_name=resource,
                resource_type=resource_type,
                file_path=item.get("Target", ""),
                start_line=meta.get("StartLine", 0),
                end_line=meta.get("EndLine", 0),
            )
        )
    return findings


def normalize_checkov_findings(raw: list[dict]) -> list[Finding]:
    """Convert raw Checkov failed_checks to Finding objects."""
    findings = []
    for item in raw:
        line_range = item.get("file_line_range", [0, 0])
        resource = item.get("resource", "unknown")
        resource_type = resource.split(".")[0] if "." in resource else resource
        severity = item.get("severity", item.get("check", {}).get("severity", "UNKNOWN"))
        findings.append(
            Finding(
                tool="checkov",
                rule_id=item.get("check_id", ""),
                title=item.get("check_name", ""),
                severity=(severity or "UNKNOWN").upper(),
                resource_name=resource,
                resource_type=resource_type,
                file_path=item.get("file_path", ""),
                start_line=line_range[0] if line_range else 0,
                end_line=line_range[1] if len(line_range) > 1 else line_range[0],
            )
        )
    return findings


def deduplicate_findings(findings: list[Finding]) -> list[Finding]:
    """
    Remove findings that describe the same issue on the same resource.

    A finding is a duplicate if: same resource_name AND same rule_id.
    Keeps first occurrence.
    """
    seen: set[tuple[str, str]] = set()
    result = []
    for f in findings:
        key = (f.resource_name, f.rule_id)
        if key not in seen:
            seen.add(key)
            result.append(f)
    return result


@dataclass
class ScanResult:
    """
    Outcome of running the scanner stack on one directory.

    Distinguishes a genuinely CLEAN scan (``ok`` with no findings) from a
    FAILED scan (a scanner crashed / timed out / was not installed). Before
    this, ``ScannerStack.run`` swallowed scanner exceptions and returned an
    empty list, so a crashed post-repair scan was indistinguishable from a
    perfect repair (audit Claim 2). ``ok`` is True only if EVERY invoked
    scanner completed; ``failures`` lists the scanners that errored and why.
    """
    findings: list[Finding] = field(default_factory=list)
    failures: dict[str, str] = field(default_factory=dict)  # scanner -> error text

    @property
    def ok(self) -> bool:
        return not self.failures


class ScannerFailure(Exception):
    """Raised by run(strict=True) when any scanner fails, so a failed scan can
    never be silently mistaken for a clean (all-resolved) repair."""


class ScannerStack:
    """
    Runs Trivy and Checkov, normalizes and deduplicates findings.
    """

    def __init__(self, trivy_runner=None, checkov_runner=None):
        if trivy_runner is None:
            from src.scanning.trivy_runner import run_trivy
            trivy_runner = run_trivy
        if checkov_runner is None:
            from src.scanning.checkov_runner import run_checkov
            checkov_runner = run_checkov
        self._run_trivy = trivy_runner
        self._run_checkov = checkov_runner

    def run_checked(self, target_dir: str) -> ScanResult:
        """
        Run both scanners and return a ScanResult that separates a clean scan
        from a failed one. Scanner errors are LOGGED (never silently dropped)
        and recorded in ``result.failures``.
        """
        result = ScanResult()
        for name, runner, normalizer in (
            ("trivy", self._run_trivy, normalize_trivy_findings),
            ("checkov", self._run_checkov, normalize_checkov_findings),
        ):
            try:
                raw = runner(target_dir)
                result.findings.extend(normalizer(raw))
            except Exception as e:  # noqa: BLE001 - record and surface, don't swallow
                msg = f"{type(e).__name__}: {e}"
                result.failures[name] = msg
                logger.error("scanner %r failed on %s: %s", name, target_dir, msg)
        result.findings = deduplicate_findings(result.findings)
        return result

    def run(self, target_dir: str, strict: bool = False) -> list[Finding]:
        """Run both scanners, normalize, deduplicate. Returns combined findings.

        Scanner failures are now LOGGED loudly (never silently ``pass``ed).
        Default behavior remains best-effort so a single missing scanner does
        not abort a long run, but the failure is visible in the logs and via
        ``run_checked``. Pass ``strict=True`` to raise ``ScannerFailure``
        instead — recommended for the POST-repair scan, where an empty result
        from a crashed scanner would otherwise be scored as a perfect repair.
        """
        result = self.run_checked(target_dir)
        if result.failures and strict:
            raise ScannerFailure(
                f"scanner(s) failed on {target_dir}: {result.failures}"
            )
        return result.findings
