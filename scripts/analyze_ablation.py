"""
Analyze prompt ablation results and generate LaTeX table for the paper.

Usage:
  python scripts/analyze_ablation.py \
      --results experiments/results/prompt_ablation/games/ \
      --outdir paper/figures/
"""
from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np


ALL_COMPLETENESS_RULES = {
    "AWS-0094", "AWS-0093", "AWS-0091", "AWS-0087", "AWS-0086", "CKV2_AWS_6",
    "AWS-0104", "CKV_AWS_382", "AWS-0099", "AWS-0124", "CKV_AWS_23",
    "AWS-0065", "CKV_AWS_7", "AWS-0017", "CKV_AWS_158",
    "CKV_AWS_338", "CKV_AWS_66", "AWS-0132", "CKV_AWS_145",
    "AWS-0089", "AWS-0178", "CKV2_AWS_64",
}

MODEL_LABELS = {
    "deepseek-r1": "DeepSeek-R1",
    "claude-sonnet-4": "Claude Son. 4",
    "nova-pro": "Nova Pro",
    "llama-3-3-70b": "Llama 70B",
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", required=True)
    parser.add_argument("--outdir", default="paper/figures")
    args = parser.parse_args()

    results_dir = Path(args.results)
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    # group: (model, variant) -> list of games
    groups: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for f in sorted(results_dir.glob("*.json")):
        g = json.loads(f.read_text())
        key = (g["model_id"], g["prompt_variant"])
        groups[key].append(g)

    models = sorted({k[0] for k in groups})
    variants = ["P0", "P1", "P2"]

    # Print summary
    print(f"{'Model':22s} {'Variant':8s} {'N':>4} {'RSR':>6} {'RR':>6} {'ND':>7} {'HCL%':>6} {'NR%':>6}")
    print("-" * 70)
    for model in models:
        for v in variants:
            games = groups.get((model, v), [])
            if not games:
                continue
            n = len(games)
            rsr_vals = []
            rr_vals = []
            nd_vals = []
            hcl_ok = 0
            nr_count = 0
            total_intro = 0

            for g in games:
                tc = g["target_count"]
                if tc > 0:
                    rsr_vals.append(g["resolved_count"] / tc)
                    rr_vals.append(g["introduced_count"] / tc)
                nd_vals.append(g["net_delta"])
                if g["hcl_valid"]:
                    hcl_ok += 1

                before_keys = {(f["rule_id"], f["resource_name"]) for f in g["findings_before"]}
                after_map = {(f["rule_id"], f["resource_name"]): f for f in g["findings_after"]}
                for k in set(after_map) - before_keys:
                    total_intro += 1
                    if after_map[k]["rule_id"] in ALL_COMPLETENESS_RULES:
                        nr_count += 1

            nr_pct = nr_count / total_intro * 100 if total_intro > 0 else 0
            label = MODEL_LABELS.get(model, model)
            print(
                f"{label:22s} {v:8s} {n:4d} "
                f"{np.mean(rsr_vals):5.2f} {np.mean(rr_vals):5.2f} "
                f"{np.mean(nd_vals):+6.1f} "
                f"{hcl_ok / n * 100:5.1f} "
                f"{nr_pct:5.1f}"
            )
        print()

    # Generate LaTeX table
    lines = [
        r"\begin{tabular}{@{}llrrrr@{}}",
        r"\toprule",
        r"\textbf{Model} & \textbf{Prompt} & \textbf{RSR} & \textbf{RR} & "
        r"\textbf{Mean ND} & \textbf{CC Cov.\%} \\",
        r"\midrule",
    ]

    for model in models:
        first = True
        for v in variants:
            games = groups.get((model, v), [])
            if not games:
                continue
            rsr_vals = [g["resolved_count"] / g["target_count"] for g in games if g["target_count"] > 0]
            rr_vals = [g["introduced_count"] / g["target_count"] for g in games if g["target_count"] > 0]
            nd_vals = [g["net_delta"] for g in games]

            total_intro = 0
            nr_count = 0
            for g in games:
                before_keys = {(f["rule_id"], f["resource_name"]) for f in g["findings_before"]}
                after_map = {(f["rule_id"], f["resource_name"]): f for f in g["findings_after"]}
                for k in set(after_map) - before_keys:
                    total_intro += 1
                    if after_map[k]["rule_id"] in ALL_COMPLETENESS_RULES:
                        nr_count += 1
            cc_pct = nr_count / total_intro * 100 if total_intro > 0 else 0

            label = MODEL_LABELS.get(model, model) if first else ""
            first = False
            vlabel = {"P0": "Baseline", "P1": "Hardening", "P2": "Checklist"}[v]
            lines.append(
                f"{label} & {vlabel} & "
                f"{np.mean(rsr_vals):.2f} & {np.mean(rr_vals):.2f} & "
                f"{np.mean(nd_vals):+.1f} & {cc_pct:.0f}\\% \\\\"
            )
        lines.append(r"\midrule")

    lines[-1] = r"\bottomrule"
    lines.append(r"\end{tabular}")
    (outdir / "table_ablation.tex").write_text("\n".join(lines))
    print(f"\nSaved table_ablation.tex to {outdir}")


if __name__ == "__main__":
    main()
