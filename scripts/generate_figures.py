"""
Generate all paper figures and LaTeX table fragments from experiment data.

Usage:
  python scripts/generate_figures.py \
      --games experiments/results/full_180_game/games/ \
      --outdir paper/figures/

Produces:
  Figures (PDF):
    corpus_distribution.pdf        Histogram of pre-repair findings per module
    net_delta_boxplot.pdf          Per-model box plot of net delta
    severity_stacked_bar.pdf       Stacked bar of regression severity by model
    rsr_rr_scatter.pdf             RSR vs RR scatter with CI error bars
    cost_effectiveness.pdf         Cost per net-positive finding by model
    reasoning_complexity.pdf       Reasoning x complexity interaction heatmap

  Tables (LaTeX fragments):
    table_main.tex                 Main results (RSR, RR, ND, cost)
    table_ci.tex                   Bootstrap 95% confidence intervals
    table_severity.tex             Severity breakdown of introduced regressions
    table_gating.tex               Gating policy acceptance rates
    table_swnd.tex                 Severity-weighted ND + regression ratio
    table_reasoning_complexity.tex Reasoning x module complexity interaction
    table_completeness.tex         Completeness checker coverage + composed defense
    table_unmapped.tex             Characterization of unmapped Checkov regressions

  Data:
    results_summary.json           Full aggregate statistics
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

# ---------------------------------------------------------------------------
# Style
# ---------------------------------------------------------------------------
plt.rcParams.update({
    "font.family": "serif",
    "font.size": 9,
    "axes.titlesize": 10,
    "axes.labelsize": 9,
    "xtick.labelsize": 8,
    "ytick.labelsize": 8,
    "legend.fontsize": 7,
    "figure.dpi": 300,
    "savefig.bbox": "tight",
    "savefig.pad_inches": 0.05,
})

COLUMN_WIDTH = 3.35  # inches, typical acmart single-column
MODEL_ORDER = [
    "deepseek-r1",
    "nova-pro",
    "qwen3-32b",
    "claude-sonnet-4",
    "nova-lite",
    "llama-3-3-70b",
]
MODEL_LABELS = {
    "deepseek-r1": "DeepSeek-R1",
    "nova-pro": "Nova Pro",
    "qwen3-32b": "Qwen3-32B",
    "claude-sonnet-4": "Claude Son. 4",
    "nova-lite": "Nova Lite",
    "llama-3-3-70b": "Llama 70B",
}
MODEL_COLORS = {
    "deepseek-r1": "#2ca02c",
    "nova-pro": "#1f77b4",
    "qwen3-32b": "#9467bd",
    "claude-sonnet-4": "#ff7f0e",
    "nova-lite": "#d62728",
    "llama-3-3-70b": "#8c564b",
}

SEVERITY_ORDER = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"]
SEVERITY_COLORS = {
    "CRITICAL": "#c0392b",
    "HIGH": "#e67e22",
    "MEDIUM": "#f1c40f",
    "LOW": "#5dade2",
    "UNKNOWN": "#bdc3c7",
}
SEVERITY_WEIGHTS = {"CRITICAL": 4, "HIGH": 3, "MEDIUM": 2, "LOW": 1, "UNKNOWN": 1}

REASONING_MODELS = {"deepseek-r1", "qwen3-32b"}
COMPLEXITY_BINS = ["<6", "6--15", "16--30", "31+"]

ALL_COMPLETENESS_RULES = {
    "AWS-0094", "AWS-0093", "AWS-0091", "AWS-0087", "AWS-0086", "CKV2_AWS_6",
    "AWS-0104", "CKV_AWS_382", "AWS-0099", "AWS-0124", "CKV_AWS_23",
    "AWS-0065", "CKV_AWS_7", "AWS-0017", "CKV_AWS_158",
    "CKV_AWS_338", "CKV_AWS_66", "AWS-0132", "CKV_AWS_145",
    "AWS-0089", "AWS-0178", "CKV2_AWS_64",
}

# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

def load_games(games_dir: Path) -> list[dict]:
    games = []
    for f in sorted(games_dir.glob("*.json")):
        games.append(json.loads(f.read_text()))
    return games


def group_by_model(games: list[dict]) -> dict[str, list[dict]]:
    by_model: dict[str, list[dict]] = defaultdict(list)
    for g in games:
        by_model[g["model_id"]].append(g)
    return dict(by_model)


def bootstrap_ci(data: list[float], n_boot: int = 2000, ci: float = 0.95):
    arr = np.array(data)
    n = len(arr)
    if n == 0:
        return 0.0, 0.0
    rng = np.random.default_rng(42)
    boot = [np.mean(rng.choice(arr, size=n, replace=True)) for _ in range(n_boot)]
    lo = np.percentile(boot, (1 - ci) / 2 * 100)
    hi = np.percentile(boot, (1 + ci) / 2 * 100)
    return float(lo), float(hi)


# ---------------------------------------------------------------------------
# Figure 1: Corpus distribution histogram
# ---------------------------------------------------------------------------

def fig_corpus_distribution(games: list[dict], outdir: Path):
    module_findings: dict[str, int] = {}
    for g in games:
        mid = g["module_id"]
        if mid not in module_findings:
            module_findings[mid] = g["target_count"]

    counts = list(module_findings.values())
    bins = [0, 1, 6, 11, 16, 21, 31, 51, max(counts) + 1]
    bin_labels = ["0", "1-5", "6-10", "11-15", "16-20", "21-30", "31-50", "51+"]
    hist, _ = np.histogram(counts, bins=bins)

    fig, ax = plt.subplots(figsize=(COLUMN_WIDTH, 2.2))
    x = np.arange(len(bin_labels))
    bars = ax.bar(x, hist, color="#5b9bd5", edgecolor="white", width=0.75)
    for bar, h in zip(bars, hist):
        ax.text(bar.get_x() + bar.get_width() / 2, h + 0.8,
                str(int(h)), ha="center", va="bottom", fontsize=7)
    ax.set_xticks(x)
    ax.set_xticklabels(bin_labels, rotation=30, ha="right")
    ax.set_xlabel("Pre-repair findings per module")
    ax.set_ylabel("Number of modules")
    ax.set_ylim(0, max(hist) + 8)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    fig.savefig(outdir / "corpus_distribution.pdf")
    plt.close(fig)
    print(f"  corpus_distribution.pdf  ({len(module_findings)} modules)")


# ---------------------------------------------------------------------------
# Figure 2: Net-delta box plot
# ---------------------------------------------------------------------------

def fig_net_delta_boxplot(by_model: dict[str, list[dict]], outdir: Path):
    data = []
    labels = []
    colors = []
    for mid in MODEL_ORDER:
        if mid not in by_model:
            continue
        nd = [g["net_delta"] for g in by_model[mid]]
        data.append(nd)
        labels.append(MODEL_LABELS.get(mid, mid))
        colors.append(MODEL_COLORS.get(mid, "#999"))

    fig, ax = plt.subplots(figsize=(COLUMN_WIDTH, 2.8))
    bp = ax.boxplot(
        data,
        patch_artist=True,
        widths=0.5,
        showfliers=True,
        flierprops=dict(marker=".", markersize=2, alpha=0.4),
        medianprops=dict(color="black", linewidth=1.2),
    )
    for patch, c in zip(bp["boxes"], colors):
        patch.set_facecolor(c)
        patch.set_alpha(0.45)

    ax.axhline(y=0, color="gray", linestyle="--", linewidth=0.8, alpha=0.7)
    ax.set_xticklabels(labels, rotation=30, ha="right")
    ax.set_ylabel("Net delta per module")
    ax.yaxis.set_major_locator(ticker.MaxNLocator(integer=True, nbins=8))
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    fig.savefig(outdir / "net_delta_boxplot.pdf")
    plt.close(fig)
    print(f"  net_delta_boxplot.pdf    ({len(data)} models)")


# ---------------------------------------------------------------------------
# Figure 3: Severity stacked bar
# ---------------------------------------------------------------------------

def fig_severity_stacked_bar(by_model: dict[str, list[dict]], outdir: Path):
    sev_counts: dict[str, dict[str, int]] = {}
    for mid in MODEL_ORDER:
        if mid not in by_model:
            continue
        sev_counts[mid] = Counter()
        for g in by_model[mid]:
            before_keys = {(f["rule_id"], f["resource_name"]) for f in g["findings_before"]}
            after_map = {(f["rule_id"], f["resource_name"]): f for f in g["findings_after"]}
            for k in set(after_map) - before_keys:
                sev = after_map[k].get("severity", "UNKNOWN")
                sev_counts[mid][sev] += 1

    models = [m for m in MODEL_ORDER if m in sev_counts]
    x = np.arange(len(models))
    fig, ax = plt.subplots(figsize=(COLUMN_WIDTH, 2.5))

    bottom = np.zeros(len(models))
    for sev in SEVERITY_ORDER:
        vals = [sev_counts[m].get(sev, 0) for m in models]
        ax.bar(x, vals, bottom=bottom, width=0.6,
               color=SEVERITY_COLORS[sev], edgecolor="white", linewidth=0.3,
               label=sev[:4])
        bottom += vals

    ax.set_xticks(x)
    ax.set_xticklabels([MODEL_LABELS.get(m, m) for m in models], rotation=30, ha="right")
    ax.set_ylabel("Introduced regressions")
    ax.legend(ncol=5, loc="upper center", bbox_to_anchor=(0.5, 1.18),
              frameon=False, handlelength=1.0, handletextpad=0.3, columnspacing=0.8)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    fig.savefig(outdir / "severity_stacked_bar.pdf")
    plt.close(fig)
    print(f"  severity_stacked_bar.pdf ({len(models)} models)")


# ---------------------------------------------------------------------------
# Figure 4: RSR vs RR scatter
# ---------------------------------------------------------------------------

def fig_rsr_rr_scatter(by_model: dict[str, list[dict]], outdir: Path):
    fig, ax = plt.subplots(figsize=(COLUMN_WIDTH, 2.8))
    for mid in MODEL_ORDER:
        if mid not in by_model:
            continue
        rsr_vals = [g["repair_success_rate"] for g in by_model[mid]]
        rr_vals = [g["regression_rate"] for g in by_model[mid]]
        rsr_mean, rr_mean = np.mean(rsr_vals), np.mean(rr_vals)
        rsr_lo, rsr_hi = bootstrap_ci(rsr_vals)
        rr_lo, rr_hi = bootstrap_ci(rr_vals)
        ax.errorbar(
            rsr_mean, rr_mean,
            xerr=[[rsr_mean - rsr_lo], [rsr_hi - rsr_mean]],
            yerr=[[rr_mean - rr_lo], [rr_hi - rr_mean]],
            fmt="o", markersize=6, capsize=3,
            color=MODEL_COLORS.get(mid, "#999"),
            label=MODEL_LABELS.get(mid, mid),
        )
    ax.set_xlabel("Repair Success Rate (RSR)")
    ax.set_ylabel("Regression Rate (RR)")
    ax.legend(loc="upper left", frameon=True, fancybox=False, edgecolor="gray",
              fontsize=6.5)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.set_xlim(0.2, 0.95)
    ax.set_ylim(0, 1.15)
    fig.savefig(outdir / "rsr_rr_scatter.pdf")
    plt.close(fig)
    print(f"  rsr_rr_scatter.pdf")


# ---------------------------------------------------------------------------
# Figure 5: Cost effectiveness
# ---------------------------------------------------------------------------

def fig_cost_effectiveness(by_model: dict[str, list[dict]], outdir: Path):
    models = []
    cost_per_pos = []
    colors = []
    for mid in MODEL_ORDER:
        if mid not in by_model:
            continue
        total_cost = sum(g["repair_cost_usd"] for g in by_model[mid])
        total_nd = sum(g["net_delta"] for g in by_model[mid])
        if total_nd > 0:
            cpp = total_cost / total_nd
        else:
            cpp = float("inf")
        models.append(MODEL_LABELS.get(mid, mid))
        cost_per_pos.append(cpp if cpp != float("inf") else 0)
        colors.append(MODEL_COLORS.get(mid, "#999"))

    fig, ax = plt.subplots(figsize=(COLUMN_WIDTH, 2.2))
    x = np.arange(len(models))
    bars = ax.bar(x, cost_per_pos, color=colors, edgecolor="white", width=0.6, alpha=0.8)
    for bar, v in zip(bars, cost_per_pos):
        if v > 0:
            ax.text(bar.get_x() + bar.get_width() / 2, v + 0.002,
                    f"${v:.3f}", ha="center", va="bottom", fontsize=6.5)
        else:
            ax.text(bar.get_x() + bar.get_width() / 2, 0.005,
                    "ND\u22640", ha="center", va="bottom", fontsize=6, color="red")
    ax.set_xticks(x)
    ax.set_xticklabels(models, rotation=30, ha="right")
    ax.set_ylabel("Cost per net-positive finding (USD)")
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    fig.savefig(outdir / "cost_effectiveness.pdf")
    plt.close(fig)
    print(f"  cost_effectiveness.pdf")


# ---------------------------------------------------------------------------
# LaTeX table: Main results
# ---------------------------------------------------------------------------

def tex_table_main(by_model: dict[str, list[dict]], summary: dict, outdir: Path):
    lines = [
        r"\begin{tabular}{@{}lrrrr@{}}",
        r"\toprule",
        r"\textbf{Model} & \textbf{RSR} & \textbf{RR} & \textbf{Mean ND} & \textbf{Cost (\$)} \\",
        r"\midrule",
    ]
    for mid in MODEL_ORDER:
        if mid not in summary:
            continue
        s = summary[mid]
        label = MODEL_LABELS.get(mid, mid)
        lines.append(
            f"{label} & "
            f"{s['rsr_mean']:.2f} $\\pm$ {s['rsr_std']:.2f} & "
            f"{s['rr_mean']:.2f} $\\pm$ {s['rr_std']:.2f} & "
            f"{s['nd_mean']:+.1f} & "
            f"{s['total_cost']:.2f} \\\\"
        )
    lines.extend([r"\bottomrule", r"\end{tabular}"])
    (outdir / "table_main.tex").write_text("\n".join(lines))
    print("  table_main.tex")


# ---------------------------------------------------------------------------
# LaTeX table: Confidence intervals
# ---------------------------------------------------------------------------

def tex_table_ci(summary: dict, outdir: Path):
    lines = [
        r"\begin{tabular}{@{}lcccc@{}}",
        r"\toprule",
        r"\textbf{Model} & \textbf{RSR 95\% CI} & \textbf{RR 95\% CI} & \textbf{ND 95\% CI} \\",
        r"\midrule",
    ]
    for mid in MODEL_ORDER:
        if mid not in summary:
            continue
        s = summary[mid]
        label = MODEL_LABELS.get(mid, mid)
        lines.append(
            f"{label} & "
            f"[{s['rsr_ci'][0]:.2f}, {s['rsr_ci'][1]:.2f}] & "
            f"[{s['rr_ci'][0]:.2f}, {s['rr_ci'][1]:.2f}] & "
            f"[{s['nd_ci'][0]:+.1f}, {s['nd_ci'][1]:+.1f}] \\\\"
        )
    lines.extend([r"\bottomrule", r"\end{tabular}"])
    (outdir / "table_ci.tex").write_text("\n".join(lines))
    print("  table_ci.tex")


# ---------------------------------------------------------------------------
# LaTeX table: Severity breakdown
# ---------------------------------------------------------------------------

def tex_table_severity(by_model: dict[str, list[dict]], outdir: Path):
    sev_counts: dict[str, dict[str, int]] = {}
    for mid in MODEL_ORDER:
        if mid not in by_model:
            continue
        sev_counts[mid] = Counter()
        for g in by_model[mid]:
            before_keys = {(f["rule_id"], f["resource_name"]) for f in g["findings_before"]}
            after_map = {(f["rule_id"], f["resource_name"]): f for f in g["findings_after"]}
            for k in set(after_map) - before_keys:
                sev = after_map[k].get("severity", "UNKNOWN")
                sev_counts[mid][sev] += 1

    lines = [
        r"\begin{tabular}{@{}lrrrrr@{}}",
        r"\toprule",
        r"\textbf{Model} & \textbf{CRIT} & \textbf{HIGH} & \textbf{MED} & \textbf{LOW} & \textbf{UNK} \\",
        r"\midrule",
    ]
    for mid in MODEL_ORDER:
        if mid not in sev_counts:
            continue
        c = sev_counts[mid]
        label = MODEL_LABELS.get(mid, mid)
        lines.append(
            f"{label} & {c.get('CRITICAL',0)} & {c.get('HIGH',0)} & "
            f"{c.get('MEDIUM',0)} & {c.get('LOW',0)} & {c.get('UNKNOWN',0)} \\\\"
        )
    total = Counter()
    for c in sev_counts.values():
        total.update(c)
    lines.append(r"\midrule")
    lines.append(
        f"\\textbf{{Total}} & {total.get('CRITICAL',0)} & {total.get('HIGH',0)} & "
        f"{total.get('MEDIUM',0)} & {total.get('LOW',0)} & {total.get('UNKNOWN',0)} \\\\"
    )
    lines.extend([r"\bottomrule", r"\end{tabular}"])
    (outdir / "table_severity.tex").write_text("\n".join(lines))
    print("  table_severity.tex")


# ---------------------------------------------------------------------------
# LaTeX table: Gating analysis
# ---------------------------------------------------------------------------

def tex_table_gating(by_model: dict[str, list[dict]], outdir: Path):
    def apply_gate(g, level):
        before_keys = {(f["rule_id"], f["resource_name"]) for f in g["findings_before"]}
        after_map = {(f["rule_id"], f["resource_name"]): f for f in g["findings_after"]}
        introduced_keys = set(after_map) - before_keys
        resolved = len(before_keys - set(after_map))
        nd = resolved - len(introduced_keys)

        if nd < 0:
            return False
        if level in ("G2", "G3"):
            crit = sum(1 for k in introduced_keys if after_map[k].get("severity") == "CRITICAL")
            if crit > 0:
                return False
        if level == "G3":
            high = sum(1 for k in introduced_keys if after_map[k].get("severity") == "HIGH")
            if high > 0:
                return False
        return True

    lines = [
        r"\begin{tabular}{@{}lccc@{}}",
        r"\toprule",
        r"\textbf{Model} & \textbf{G1 Accept\%} & \textbf{G2 Accept\%} & \textbf{G3 Accept\%} \\",
        r"\midrule",
    ]
    for mid in MODEL_ORDER:
        if mid not in by_model:
            continue
        games = by_model[mid]
        n = len(games)
        g1 = sum(1 for g in games if apply_gate(g, "G1")) / n * 100
        g2 = sum(1 for g in games if apply_gate(g, "G2")) / n * 100
        g3 = sum(1 for g in games if apply_gate(g, "G3")) / n * 100
        label = MODEL_LABELS.get(mid, mid)
        lines.append(f"{label} & {g1:.1f}\\% & {g2:.1f}\\% & {g3:.1f}\\% \\\\")
    lines.extend([r"\bottomrule", r"\end{tabular}"])
    (outdir / "table_gating.tex").write_text("\n".join(lines))
    print("  table_gating.tex")


# ---------------------------------------------------------------------------
# Figure 6: Reasoning x complexity interaction
# ---------------------------------------------------------------------------

def _complexity_bin(target_count: int) -> str:
    if target_count < 6:
        return "<6"
    if target_count <= 15:
        return "6--15"
    if target_count <= 30:
        return "16--30"
    return "31+"


def fig_reasoning_complexity(games: list[dict], outdir: Path):
    from collections import defaultdict

    data: dict[str, dict[str, list]] = {
        b: {"reasoning": [], "non_reasoning": []} for b in COMPLEXITY_BINS
    }
    for g in games:
        b = _complexity_bin(g["target_count"])
        bucket = "reasoning" if g["model_id"] in REASONING_MODELS else "non_reasoning"
        data[b][bucket].append(g["regression_rate"])

    r_means = [np.mean(data[b]["reasoning"]) if data[b]["reasoning"] else 0 for b in COMPLEXITY_BINS]
    nr_means = [np.mean(data[b]["non_reasoning"]) if data[b]["non_reasoning"] else 0 for b in COMPLEXITY_BINS]

    x = np.arange(len(COMPLEXITY_BINS))
    w = 0.35
    fig, ax = plt.subplots(figsize=(COLUMN_WIDTH, 2.4))
    ax.bar(x - w / 2, r_means, w, label="Reasoning", color="#2ca02c", alpha=0.8, edgecolor="white")
    ax.bar(x + w / 2, nr_means, w, label="Non-reasoning", color="#d62728", alpha=0.8, edgecolor="white")
    ax.set_xticks(x)
    ax.set_xticklabels([f"{b} findings" for b in COMPLEXITY_BINS])
    ax.set_ylabel("Mean Regression Rate")
    ax.set_ylim(0, 1.0)
    ax.legend(frameon=True, fancybox=False, edgecolor="gray", fontsize=7)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    fig.savefig(outdir / "reasoning_complexity.pdf")
    plt.close(fig)
    print("  reasoning_complexity.pdf")


# ---------------------------------------------------------------------------
# LaTeX table: Severity-weighted ND + regression ratio
# ---------------------------------------------------------------------------

def tex_table_swnd(by_model: dict[str, list[dict]], outdir: Path):
    lines = [
        r"\begin{tabular}{@{}lrrrrc@{}}",
        r"\toprule",
        r"\textbf{Model} & \textbf{ND} & \textbf{SW-ND} & "
        r"\textbf{Resolved} & \textbf{Introduced} & \textbf{Ratio} \\",
        r"\midrule",
    ]
    for mid in MODEL_ORDER:
        if mid not in by_model:
            continue
        games = by_model[mid]
        nd_vals = [g["net_delta"] for g in games]
        swnd_vals = []
        tot_res, tot_intro = 0, 0

        for g in games:
            before_keys = {(f["rule_id"], f["resource_name"]) for f in g["findings_before"]}
            after_map = {(f["rule_id"], f["resource_name"]): f for f in g["findings_after"]}
            before_map = {(f["rule_id"], f["resource_name"]): f for f in g["findings_before"]}
            resolved_keys = before_keys - set(after_map)
            introduced_keys = set(after_map) - before_keys
            sw_res = sum(SEVERITY_WEIGHTS.get(before_map[k]["severity"], 1) for k in resolved_keys)
            sw_intro = sum(SEVERITY_WEIGHTS.get(after_map[k]["severity"], 1) for k in introduced_keys)
            swnd_vals.append(sw_res - sw_intro)
            tot_res += g["resolved_count"]
            tot_intro += g["introduced_count"]

        ratio = tot_intro / tot_res if tot_res > 0 else float("inf")
        label = MODEL_LABELS.get(mid, mid)
        lines.append(
            f"{label} & {np.mean(nd_vals):+.1f} & "
            f"{np.mean(swnd_vals):+.1f} & "
            f"{tot_res} & {tot_intro} & {ratio:.2f} \\\\"
        )
    lines.extend([r"\bottomrule", r"\end{tabular}"])
    (outdir / "table_swnd.tex").write_text("\n".join(lines))
    print("  table_swnd.tex")


# ---------------------------------------------------------------------------
# LaTeX table: Reasoning x complexity interaction
# ---------------------------------------------------------------------------

def tex_table_reasoning_complexity(games: list[dict], outdir: Path):
    from collections import defaultdict

    data: dict[str, dict[str, list]] = {
        b: {"r_rr": [], "nr_rr": [], "r_nd": [], "nr_nd": []} for b in COMPLEXITY_BINS
    }
    for g in games:
        b = _complexity_bin(g["target_count"])
        if g["model_id"] in REASONING_MODELS:
            data[b]["r_rr"].append(g["regression_rate"])
            data[b]["r_nd"].append(g["net_delta"])
        else:
            data[b]["nr_rr"].append(g["regression_rate"])
            data[b]["nr_nd"].append(g["net_delta"])

    lines = [
        r"\begin{tabular}{@{}lcccccc@{}}",
        r"\toprule",
        r"& \multicolumn{2}{c}{\textbf{Regression Rate}} & "
        r"\multicolumn{2}{c}{\textbf{Mean ND}} & \\",
        r"\cmidrule(lr){2-3} \cmidrule(lr){4-5}",
        r"\textbf{Findings} & \textbf{Reasoning} & \textbf{Non-R.} & "
        r"\textbf{Reasoning} & \textbf{Non-R.} & \textbf{$N$} \\",
        r"\midrule",
    ]
    for b in COMPLEXITY_BINS:
        d = data[b]
        r_rr = np.mean(d["r_rr"]) if d["r_rr"] else 0
        nr_rr = np.mean(d["nr_rr"]) if d["nr_rr"] else 0
        r_nd = np.mean(d["r_nd"]) if d["r_nd"] else 0
        nr_nd = np.mean(d["nr_nd"]) if d["nr_nd"] else 0
        n = len(d["r_rr"]) + len(d["nr_rr"])
        lines.append(
            f"{b} & {r_rr:.2f} & {nr_rr:.2f} & "
            f"{r_nd:+.1f} & {nr_nd:+.1f} & {n} \\\\"
        )
    lines.extend([r"\bottomrule", r"\end{tabular}"])
    (outdir / "table_reasoning_complexity.tex").write_text("\n".join(lines))
    print("  table_reasoning_complexity.tex")


# ---------------------------------------------------------------------------
# LaTeX table: Completeness checker coverage + composed defense
# ---------------------------------------------------------------------------

def tex_table_completeness(by_model: dict[str, list[dict]], outdir: Path):
    lines = [
        r"\begin{tabular}{@{}lrrrrrr@{}}",
        r"\toprule",
        r"& \multicolumn{2}{c}{\textbf{G2 Gate}} & "
        r"\multicolumn{2}{c}{\textbf{CC Only}} & "
        r"\multicolumn{2}{c}{\textbf{G2 + CC}} \\",
        r"\cmidrule(lr){2-3} \cmidrule(lr){4-5} \cmidrule(lr){6-7}",
        r"\textbf{Model} & \textbf{Acc.\%} & \textbf{ND} & "
        r"\textbf{Acc.\%} & \textbf{ND} & "
        r"\textbf{Acc.\%} & \textbf{ND} \\",
        r"\midrule",
    ]
    for mid in MODEL_ORDER:
        if mid not in by_model:
            continue
        games = by_model[mid]
        n = len(games)
        g2_acc, cc_acc, comb_acc = 0, 0, 0
        g2_nd, cc_nd, comb_nd = [], [], []

        for g in games:
            before_keys = {(f["rule_id"], f["resource_name"]) for f in g["findings_before"]}
            after_map = {(f["rule_id"], f["resource_name"]): f for f in g["findings_after"]}
            introduced_keys = set(after_map) - before_keys
            resolved = len(before_keys - set(after_map))
            nd = resolved - len(introduced_keys)

            crit = sum(1 for k in introduced_keys if after_map[k].get("severity") == "CRITICAL")
            g2_pass = nd >= 0 and crit == 0
            cc_pass = not any(after_map[k]["rule_id"] in ALL_COMPLETENESS_RULES for k in introduced_keys)
            combined = g2_pass and cc_pass

            g2_acc += int(g2_pass)
            cc_acc += int(cc_pass)
            comb_acc += int(combined)
            g2_nd.append(nd if g2_pass else 0)
            cc_nd.append(nd if cc_pass else 0)
            comb_nd.append(nd if combined else 0)

        label = MODEL_LABELS.get(mid, mid)
        lines.append(
            f"{label} & {g2_acc / n * 100:.1f}\\% & {np.mean(g2_nd):+.1f} & "
            f"{cc_acc / n * 100:.1f}\\% & {np.mean(cc_nd):+.1f} & "
            f"{comb_acc / n * 100:.1f}\\% & {np.mean(comb_nd):+.1f} \\\\"
        )
    lines.extend([r"\bottomrule", r"\end{tabular}"])
    (outdir / "table_completeness.tex").write_text("\n".join(lines))
    print("  table_completeness.tex")


# ---------------------------------------------------------------------------
# LaTeX table: Unmapped Checkov regressions characterization
# ---------------------------------------------------------------------------

def tex_table_unmapped(games: list[dict], outdir: Path):
    trivy_mapped = 0
    checkov_total = 0
    trivy_unmapped = 0
    unmapped_sev = Counter()
    unmapped_top_rules: Counter = Counter()
    total = 0

    TRIVY_CWE = {
        "AWS-0086", "AWS-0087", "AWS-0091", "AWS-0093", "AWS-0094", "AWS-0104",
        "AWS-0065", "AWS-0017", "AWS-0132", "AWS-0089", "AWS-0099", "AWS-0124",
        "AWS-0178",
    }

    for g in games:
        before_keys = {(f["rule_id"], f["resource_name"]) for f in g["findings_before"]}
        after_map = {(f["rule_id"], f["resource_name"]): f for f in g["findings_after"]}
        for k in set(after_map) - before_keys:
            f = after_map[k]
            total += 1
            rule = f["rule_id"]
            if rule.startswith("AWS-") and rule in TRIVY_CWE:
                trivy_mapped += 1
            elif rule.startswith("AWS-"):
                trivy_unmapped += 1
                unmapped_sev[f["severity"]] += 1
                unmapped_top_rules[rule] += 1
            else:
                checkov_total += 1
                unmapped_sev[f["severity"]] += 1
                unmapped_top_rules[rule] += 1

    unmapped_total = checkov_total + trivy_unmapped
    lines = [
        r"\begin{tabular}{@{}lr@{}}",
        r"\toprule",
        r"\textbf{Category} & \textbf{Count (\%)} \\",
        r"\midrule",
        f"Total regressions & {total} \\\\",
        f"CWE-mapped (Trivy) & {trivy_mapped} ({trivy_mapped / total * 100:.0f}\\%) \\\\",
        f"Unmapped total & {unmapped_total} ({unmapped_total / total * 100:.0f}\\%) \\\\",
        r"\midrule",
        r"\multicolumn{2}{@{}l}{\textit{Unmapped by severity:}} \\",
    ]
    for sev in SEVERITY_ORDER:
        c = unmapped_sev.get(sev, 0)
        if c > 0:
            lines.append(f"\\quad {sev} & {c} ({c / unmapped_total * 100:.0f}\\%) \\\\")
    lines.extend([r"\bottomrule", r"\end{tabular}"])
    (outdir / "table_unmapped.tex").write_text("\n".join(lines))
    print("  table_unmapped.tex")


# ---------------------------------------------------------------------------
# Aggregate summary
# ---------------------------------------------------------------------------

def compute_summary(by_model: dict[str, list[dict]]) -> dict:
    summary = {}
    for mid in MODEL_ORDER:
        if mid not in by_model:
            continue
        games = by_model[mid]
        rsr = [g["repair_success_rate"] for g in games]
        rr = [g["regression_rate"] for g in games]
        nd = [g["net_delta"] for g in games]
        hcl_fail = sum(1 for g in games if not g.get("hcl_valid", True))
        summary[mid] = {
            "n": len(games),
            "rsr_mean": float(np.mean(rsr)),
            "rsr_std": float(np.std(rsr)),
            "rsr_ci": list(bootstrap_ci(rsr)),
            "rr_mean": float(np.mean(rr)),
            "rr_std": float(np.std(rr)),
            "rr_ci": list(bootstrap_ci(rr)),
            "nd_mean": float(np.mean(nd)),
            "nd_std": float(np.std(nd)),
            "nd_ci": list(bootstrap_ci(nd)),
            "total_cost": float(sum(g["repair_cost_usd"] for g in games)),
            "hcl_failures": hcl_fail,
            "total_resolved": sum(g["resolved_count"] for g in games),
            "total_introduced": sum(g["introduced_count"] for g in games),
        }
    return summary


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Generate paper figures and tables")
    parser.add_argument("--games", required=True, help="Path to games/ directory with JSON files")
    parser.add_argument("--outdir", default="paper/figures", help="Output directory for PDFs and .tex")
    args = parser.parse_args()

    games_dir = Path(args.games)
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    print(f"Loading games from {games_dir} ...")
    games = load_games(games_dir)
    print(f"  Loaded {len(games)} game files")

    by_model = group_by_model(games)
    for mid, g in by_model.items():
        print(f"  {mid}: {len(g)} games")

    summary = compute_summary(by_model)

    print("\nGenerating figures ...")
    fig_corpus_distribution(games, outdir)
    fig_net_delta_boxplot(by_model, outdir)
    fig_severity_stacked_bar(by_model, outdir)
    fig_rsr_rr_scatter(by_model, outdir)
    fig_cost_effectiveness(by_model, outdir)
    fig_reasoning_complexity(games, outdir)

    print("\nGenerating LaTeX tables ...")
    tex_table_main(by_model, summary, outdir)
    tex_table_ci(summary, outdir)
    tex_table_severity(by_model, outdir)
    tex_table_gating(by_model, outdir)
    tex_table_swnd(by_model, outdir)
    tex_table_reasoning_complexity(games, outdir)
    tex_table_completeness(by_model, outdir)
    tex_table_unmapped(games, outdir)

    print("\nWriting results_summary.json ...")
    (outdir / "results_summary.json").write_text(json.dumps(summary, indent=2))

    print(f"\nDone. All outputs in {outdir}/")


if __name__ == "__main__":
    main()
