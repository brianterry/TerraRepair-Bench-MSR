"""
Resource-completeness checker for Terraform HCL output.

Validates that LLM-repaired Terraform satisfies structural completeness
rules — e.g. every aws_s3_bucket has a companion
aws_s3_bucket_public_access_block. Operates on parsed resource blocks
extracted from HCL text (regex-based, no external HCL parser required).

The checker targets the top regression patterns observed in
TerraRepair-Bench experiments, covering ~58% of all introduced regressions
with deterministic, sub-millisecond checks.

Usage as library:
    checker = CompletenessChecker()
    violations = checker.check(hcl_text)

Usage on game JSONs (analytical mode):
    results = evaluate_games(games_dir)
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    pass


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass
class Violation:
    rule_id: str
    resource_type: str
    resource_name: str
    description: str
    severity: str  # CRITICAL, HIGH, MEDIUM


@dataclass
class CheckResult:
    violations: list[Violation] = field(default_factory=list)
    resources_checked: int = 0
    rules_applied: int = 0

    @property
    def passed(self) -> bool:
        return len(self.violations) == 0


# ---------------------------------------------------------------------------
# HCL resource extractor (regex-based, covers ~95% of real-world patterns)
# ---------------------------------------------------------------------------

_RESOURCE_RE = re.compile(
    r'resource\s+"([^"]+)"\s+"([^"]+)"\s*\{',
    re.MULTILINE,
)

_BLOCK_ATTR_RE = re.compile(
    r'^\s*(\w+)\s*[={]',
    re.MULTILINE,
)


def _extract_resources(hcl: str) -> dict[str, list[dict]]:
    """Return {resource_type: [{name, body, attrs}]}."""
    resources: dict[str, list[dict]] = {}
    matches = list(_RESOURCE_RE.finditer(hcl))
    for i, m in enumerate(matches):
        rtype = m.group(1)
        rname = m.group(2)
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(hcl)
        body = hcl[start:end]
        attrs = set(_BLOCK_ATTR_RE.findall(body))
        resources.setdefault(rtype, []).append({
            "name": rname,
            "body": body,
            "attrs": attrs,
        })
    return resources


# ---------------------------------------------------------------------------
# Completeness rules
# ---------------------------------------------------------------------------

class CompletenessChecker:
    """Rule-based checker targeting the top 10 regression patterns."""

    def check(self, hcl: str) -> CheckResult:
        resources = _extract_resources(hcl)
        result = CheckResult()
        result.resources_checked = sum(len(v) for v in resources.values())
        result.rules_applied = 10

        self._check_s3_public_access_block(resources, result)
        self._check_sg_egress(resources, result)
        self._check_sg_description(resources, result)
        self._check_kms_rotation(resources, result)
        self._check_cloudwatch_encryption(resources, result)
        self._check_cloudwatch_retention(resources, result)
        self._check_s3_encryption(resources, result)
        self._check_s3_logging(resources, result)
        self._check_vpc_flow_logs(resources, result)
        self._check_kms_policy(resources, result)

        return result

    def _check_s3_public_access_block(
        self, resources: dict, result: CheckResult
    ) -> None:
        buckets = resources.get("aws_s3_bucket", [])
        pab_blocks = resources.get("aws_s3_bucket_public_access_block", [])
        pab_bodies = " ".join(b["body"] for b in pab_blocks)

        for bucket in buckets:
            name = bucket["name"]
            ref_pattern = f"aws_s3_bucket.{name}"
            if ref_pattern not in pab_bodies:
                result.violations.append(Violation(
                    rule_id="RC-001",
                    resource_type="aws_s3_bucket",
                    resource_name=name,
                    description=(
                        f"S3 bucket '{name}' has no companion "
                        f"aws_s3_bucket_public_access_block"
                    ),
                    severity="HIGH",
                ))

    def _check_sg_egress(
        self, resources: dict, result: CheckResult
    ) -> None:
        for sg in resources.get("aws_security_group", []):
            if re.search(r'egress\s*\{', sg["body"]):
                if re.search(r'cidr_blocks\s*=\s*\[\s*"0\.0\.0\.0/0"\s*\]', sg["body"]):
                    if re.search(r'protocol\s*=\s*"-1"', sg["body"]):
                        result.violations.append(Violation(
                            rule_id="RC-002",
                            resource_type="aws_security_group",
                            resource_name=sg["name"],
                            description=(
                                f"Security group '{sg['name']}' allows "
                                f"unrestricted egress (0.0.0.0/0, all protocols)"
                            ),
                            severity="HIGH",
                        ))

    def _check_sg_description(
        self, resources: dict, result: CheckResult
    ) -> None:
        for sg in resources.get("aws_security_group", []):
            if "description" not in sg["attrs"]:
                result.violations.append(Violation(
                    rule_id="RC-003",
                    resource_type="aws_security_group",
                    resource_name=sg["name"],
                    description=(
                        f"Security group '{sg['name']}' missing description"
                    ),
                    severity="MEDIUM",
                ))

    def _check_kms_rotation(
        self, resources: dict, result: CheckResult
    ) -> None:
        for key in resources.get("aws_kms_key", []):
            if not re.search(
                r'enable_key_rotation\s*=\s*true', key["body"], re.IGNORECASE
            ):
                result.violations.append(Violation(
                    rule_id="RC-004",
                    resource_type="aws_kms_key",
                    resource_name=key["name"],
                    description=(
                        f"KMS key '{key['name']}' missing "
                        f"enable_key_rotation = true"
                    ),
                    severity="HIGH",
                ))

    def _check_cloudwatch_encryption(
        self, resources: dict, result: CheckResult
    ) -> None:
        for lg in resources.get("aws_cloudwatch_log_group", []):
            if "kms_key_id" not in lg["attrs"]:
                result.violations.append(Violation(
                    rule_id="RC-005",
                    resource_type="aws_cloudwatch_log_group",
                    resource_name=lg["name"],
                    description=(
                        f"CloudWatch log group '{lg['name']}' missing "
                        f"kms_key_id (encryption at rest)"
                    ),
                    severity="HIGH",
                ))

    def _check_cloudwatch_retention(
        self, resources: dict, result: CheckResult
    ) -> None:
        for lg in resources.get("aws_cloudwatch_log_group", []):
            if "retention_in_days" not in lg["attrs"]:
                result.violations.append(Violation(
                    rule_id="RC-006",
                    resource_type="aws_cloudwatch_log_group",
                    resource_name=lg["name"],
                    description=(
                        f"CloudWatch log group '{lg['name']}' missing "
                        f"retention_in_days"
                    ),
                    severity="MEDIUM",
                ))

    def _check_s3_encryption(
        self, resources: dict, result: CheckResult
    ) -> None:
        buckets = resources.get("aws_s3_bucket", [])
        sse_blocks = resources.get(
            "aws_s3_bucket_server_side_encryption_configuration", []
        )
        sse_bodies = " ".join(b["body"] for b in sse_blocks)

        for bucket in buckets:
            name = bucket["name"]
            ref = f"aws_s3_bucket.{name}"
            has_inline = re.search(
                r'server_side_encryption_configuration\s*\{', bucket["body"]
            )
            if ref not in sse_bodies and not has_inline:
                result.violations.append(Violation(
                    rule_id="RC-007",
                    resource_type="aws_s3_bucket",
                    resource_name=name,
                    description=(
                        f"S3 bucket '{name}' missing KMS encryption "
                        f"configuration"
                    ),
                    severity="HIGH",
                ))

    def _check_s3_logging(
        self, resources: dict, result: CheckResult
    ) -> None:
        buckets = resources.get("aws_s3_bucket", [])
        log_blocks = resources.get("aws_s3_bucket_logging", [])
        log_bodies = " ".join(b["body"] for b in log_blocks)

        for bucket in buckets:
            name = bucket["name"]
            ref = f"aws_s3_bucket.{name}"
            has_inline = re.search(r'logging\s*\{', bucket["body"])
            if ref not in log_bodies and not has_inline:
                result.violations.append(Violation(
                    rule_id="RC-008",
                    resource_type="aws_s3_bucket",
                    resource_name=name,
                    description=(
                        f"S3 bucket '{name}' missing access logging"
                    ),
                    severity="MEDIUM",
                ))

    def _check_vpc_flow_logs(
        self, resources: dict, result: CheckResult
    ) -> None:
        vpcs = resources.get("aws_vpc", [])
        flow_logs = resources.get("aws_flow_log", [])
        flow_bodies = " ".join(fl["body"] for fl in flow_logs)

        for vpc in vpcs:
            name = vpc["name"]
            ref = f"aws_vpc.{name}"
            if ref not in flow_bodies:
                result.violations.append(Violation(
                    rule_id="RC-009",
                    resource_type="aws_vpc",
                    resource_name=name,
                    description=(
                        f"VPC '{name}' has no companion aws_flow_log"
                    ),
                    severity="MEDIUM",
                ))

    def _check_kms_policy(
        self, resources: dict, result: CheckResult
    ) -> None:
        for key in resources.get("aws_kms_key", []):
            if "policy" not in key["attrs"]:
                result.violations.append(Violation(
                    rule_id="RC-010",
                    resource_type="aws_kms_key",
                    resource_name=key["name"],
                    description=(
                        f"KMS key '{key['name']}' missing explicit "
                        f"key policy"
                    ),
                    severity="MEDIUM",
                ))


# ---------------------------------------------------------------------------
# Analytical evaluation against game JSON data
# ---------------------------------------------------------------------------

RULE_MAPPING: dict[str, set[str]] = {
    "RC-001": {"AWS-0094", "AWS-0093", "AWS-0091", "AWS-0087", "AWS-0086", "CKV2_AWS_6"},
    "RC-002": {"AWS-0104", "CKV_AWS_382"},
    "RC-003": {"AWS-0099", "AWS-0124", "CKV_AWS_23"},
    "RC-004": {"AWS-0065", "CKV_AWS_7"},
    "RC-005": {"AWS-0017", "CKV_AWS_158"},
    "RC-006": {"CKV_AWS_338", "CKV_AWS_66"},
    "RC-007": {"AWS-0132", "CKV_AWS_145"},
    "RC-008": {"AWS-0089"},
    "RC-009": {"AWS-0178"},
    "RC-010": {"CKV2_AWS_64"},
}

ALL_COVERED_SCANNER_RULES: set[str] = set()
for rules in RULE_MAPPING.values():
    ALL_COVERED_SCANNER_RULES |= rules


def evaluate_coverage_on_games(games_dir: str | Path) -> dict:
    """
    Evaluate what fraction of observed regressions match completeness
    checker patterns, using only game JSON data (no HCL needed).

    Returns aggregate statistics and per-model breakdowns.
    """
    import json
    from collections import Counter, defaultdict

    from src.scanning.scanner_normalizer import canonicalize_rule_id

    games_dir = Path(games_dir)
    model_stats: dict[str, dict] = defaultdict(lambda: {
        "total_regressions": 0,
        "covered_regressions": 0,
        "by_rule": Counter(),
        "games": 0,
        "games_with_covered": 0,
    })

    total_regressions = 0
    total_covered = 0

    for f in sorted(games_dir.glob("*.json")):
        g = json.loads(f.read_text())
        model = g["model_id"]
        stats = model_stats[model]
        stats["games"] += 1

        before_keys = {(ff["rule_id"], ff["resource_name"]) for ff in g["findings_before"]}
        after_map = {(ff["rule_id"], ff["resource_name"]): ff for ff in g["findings_after"]}
        introduced = {k: after_map[k] for k in set(after_map) - before_keys}

        game_covered = 0
        for (rule_id, _rname), finding in introduced.items():
            total_regressions += 1
            stats["total_regressions"] += 1

            # Canonicalize so this reproduces regardless of whether the game
            # JSON stored bare Trivy ids ("AWS-0094") or modern "AVD-"-prefixed
            # ids. RULE_MAPPING is keyed on the bare form (audit Claim 2/4).
            rule_id = canonicalize_rule_id(rule_id)
            if rule_id in ALL_COVERED_SCANNER_RULES:
                total_covered += 1
                game_covered += 1
                stats["covered_regressions"] += 1
                for rc_rule, scanner_rules in RULE_MAPPING.items():
                    if rule_id in scanner_rules:
                        stats["by_rule"][rc_rule] += 1
                        break

        if game_covered > 0:
            stats["games_with_covered"] += 1

    results = {
        "total_regressions": total_regressions,
        "covered_by_checker": total_covered,
        "coverage_pct": total_covered / total_regressions * 100 if total_regressions else 0,
        "per_model": {},
    }

    for model, stats in sorted(model_stats.items()):
        pct = stats["covered_regressions"] / stats["total_regressions"] * 100 if stats["total_regressions"] else 0
        results["per_model"][model] = {
            "total_regressions": stats["total_regressions"],
            "covered_regressions": stats["covered_regressions"],
            "coverage_pct": round(pct, 1),
            "by_rule": dict(stats["by_rule"].most_common()),
            "games": stats["games"],
            "games_with_covered": stats["games_with_covered"],
        }

    return results
