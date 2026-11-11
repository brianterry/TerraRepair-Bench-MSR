"""
Severity-aware gating policies for LLM-based IaC repair.

Given pre-repair and post-repair scanner findings, a gating policy decides
whether the repair should be accepted (deployed) or rejected (original
module preserved).  Three policies with increasing strictness:

  G1 (net-positive):   accept iff net_delta >= 0
  G2 (no-CRITICAL):    G1 AND zero CRITICAL-severity regressions
  G3 (no-HIGH):        G2 AND zero HIGH-severity regressions
"""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from src.scanning.scanner_normalizer import Finding


class GateLevel(str, Enum):
    G1 = "G1"
    G2 = "G2"
    G3 = "G3"


@dataclass
class GateDecision:
    accepted: bool
    gate: GateLevel
    net_delta: int
    critical_introduced: int
    high_introduced: int
    reason: str


class GatingPolicy:
    """Evaluate whether a repair passes a severity-aware gate."""

    def __init__(self, gate: GateLevel = GateLevel.G2):
        self.gate = gate

    def evaluate(
        self,
        findings_before: list[Finding],
        findings_after: list[Finding],
    ) -> GateDecision:
        before_keys = {(f.rule_id, f.resource_name) for f in findings_before}
        after_keys = {(f.rule_id, f.resource_name) for f in findings_after}

        resolved = len(before_keys - after_keys)
        introduced_keys = after_keys - before_keys
        net_delta = resolved - len(introduced_keys)

        after_map = {(f.rule_id, f.resource_name): f for f in findings_after}
        critical_count = sum(
            1 for k in introduced_keys
            if after_map[k].severity == "CRITICAL"
        )
        high_count = sum(
            1 for k in introduced_keys
            if after_map[k].severity == "HIGH"
        )

        accepted = True
        reason = "accepted"

        if net_delta < 0:
            accepted = False
            reason = f"net_delta={net_delta} < 0"

        if accepted and self.gate in (GateLevel.G2, GateLevel.G3):
            if critical_count > 0:
                accepted = False
                reason = f"{critical_count} CRITICAL regressions introduced"

        if accepted and self.gate == GateLevel.G3:
            if high_count > 0:
                accepted = False
                reason = f"{high_count} HIGH regressions introduced"

        return GateDecision(
            accepted=accepted,
            gate=self.gate,
            net_delta=net_delta,
            critical_introduced=critical_count,
            high_introduced=high_count,
            reason=reason,
        )
