"""
Apply severity-aware gating to existing experiment results.

Reads game JSON files from a completed experiment, applies a gating policy,
and reports effective metrics (accepted repairs count as-is, rejected repairs
count as ND=0).

Usage:
  python scripts/gated_repair.py --results experiments/results/full_180_game/games/ --gate G2
  python scripts/gated_repair.py --results experiments/results/full_180_game/games/ --gate G3
"""
from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.scanning.scanner_normalizer import Finding
from src.scoring.gating import GateLevel, GatingPolicy


def _dicts_to_findings(dicts: list[dict]) -> list[Finding]:
    return [
        Finding(
            tool=d["tool"],
            rule_id=d["rule_id"],
            title=d["title"],
            severity=d["severity"],
            resource_name=d["resource_name"],
            resource_type=d.get("resource_type", ""),
            file_path=d.get("file_path", ""),
            start_line=d.get("start_line", 0),
            end_line=d.get("end_line", 0),
        )
        for d in dicts
    ]


def main():
    parser = argparse.ArgumentParser(description="Apply gating to experiment results")
    parser.add_argument("--results", required=True, help="Path to games/ directory")
    parser.add_argument(
        "--gate",
        choices=["G1", "G2", "G3"],
        default="G2",
        help="Gating level (default: G2)",
    )
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    args = parser.parse_args()

    results_dir = Path(args.results)
    gate = GateLevel(args.gate)
    policy = GatingPolicy(gate)

    model_stats: dict[str, dict] = {}

    for game_file in sorted(results_dir.glob("*.json")):
        data = json.loads(game_file.read_text())
        model_id = data["model_id"]
        if model_id not in model_stats:
            model_stats[model_id] = {
                "total": 0,
                "accepted": 0,
                "eff_resolved": [],
                "eff_introduced": [],
                "eff_nd": [],
            }

        findings_before = _dicts_to_findings(data["findings_before"])
        findings_after = _dicts_to_findings(data["findings_after"])
        target_count = data["target_count"]

        decision = policy.evaluate(findings_before, findings_after)
        stats = model_stats[model_id]
        stats["total"] += 1

        if decision.accepted:
            stats["accepted"] += 1
            stats["eff_resolved"].append(data["resolved_count"])
            stats["eff_introduced"].append(data["introduced_count"])
            stats["eff_nd"].append(data["net_delta"])
        else:
            stats["eff_resolved"].append(0)
            stats["eff_introduced"].append(0)
            stats["eff_nd"].append(0)

    results = {}
    for model_id, stats in sorted(model_stats.items()):
        n = stats["total"]
        acc_pct = stats["accepted"] / n * 100 if n else 0
        mean_rsr = (
            sum(stats["eff_resolved"]) / sum(1 for _ in stats["eff_resolved"])
            if stats["eff_resolved"]
            else 0
        )
        eff_nd = statistics.mean(stats["eff_nd"]) if stats["eff_nd"] else 0
        results[model_id] = {
            "gate": gate.value,
            "total": n,
            "accepted": stats["accepted"],
            "accept_pct": round(acc_pct, 1),
            "eff_mean_nd": round(eff_nd, 2),
        }

    if args.json:
        print(json.dumps(results, indent=2))
    else:
        print(f"\nGating Policy: {gate.value}")
        print(f"{'Model':<22} {'Accept%':>8} {'Eff. ND':>8} {'Accepted':>9}/{' Total'}")
        print("-" * 60)
        for model_id, r in results.items():
            print(
                f"{model_id:<22} {r['accept_pct']:>7.1f}% "
                f"{r['eff_mean_nd']:>+8.2f} "
                f"{r['accepted']:>8}/{r['total']:>5}"
            )


if __name__ == "__main__":
    main()
