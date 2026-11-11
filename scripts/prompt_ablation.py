"""
Prompt ablation study for root cause analysis of new-resource regressions.

Tests three prompt variants on a subset of modules to determine whether the
73% new-resource regression rate is an inherent model limitation or a prompt
engineering problem.

Variants:
  P0 (baseline): Original prompt with "do not add resources" instruction
  P1 (hardening): Removes "do not add resources", adds explicit hardening
                   requirements for any newly created resources
  P2 (checklist): Adds a structured checklist of required companion resources
                   (e.g., S3 → public_access_block, SG → description + egress)

Usage:
  python scripts/prompt_ablation.py \
      --corpus data/terrads_corpus/ \
      --models deepseek-r1 claude-sonnet-4 \
      --n-modules 50 \
      --region us-east-1 \
      --outdir experiments/results/prompt_ablation/
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.scanning.checkov_runner import run_checkov
from src.scanning.scanner_normalizer import (
    normalize_checkov_findings,
    normalize_trivy_findings,
)
from src.scanning.trivy_runner import run_trivy
from src.utils.bedrock_client import BedrockClient
from src.utils.response_sanitizer import is_valid_hcl, sanitize_repair_response

# ---------------------------------------------------------------------------
# Prompt variants
# ---------------------------------------------------------------------------

PROMPT_P0 = """You are a cloud security engineer. You have been given
Terraform code with confirmed security misconfigurations identified by
static analysis tools.

Your task: repair the Terraform code to fix the identified misconfigurations.

REQUIREMENTS:
1. Fix ALL identified misconfigurations
2. Preserve the original infrastructure intent and resource names exactly
3. Do not add resources, modules, or variables that weren't in the original
4. Generate valid, deployable Terraform (HCL) syntax
5. Do not add comments explaining your changes

MISCONFIGURATIONS TO FIX:
{findings_formatted}

TERRAFORM CODE:
```hcl
{terraform_code}
```

Return ONLY the complete repaired Terraform code. No explanations, no
markdown fences, no preamble. Start directly with the HCL content."""

PROMPT_P1 = """You are a cloud security engineer. You have been given
Terraform code with confirmed security misconfigurations identified by
static analysis tools.

Your task: repair the Terraform code to fix the identified misconfigurations.

REQUIREMENTS:
1. Fix ALL identified misconfigurations
2. Preserve the original infrastructure intent and resource names exactly
3. If fixing a misconfiguration requires creating a new companion resource
   (e.g., aws_s3_bucket_public_access_block for an S3 bucket), you MUST
   include ALL required security hardening for that new resource
4. Every new aws_s3_bucket MUST have a corresponding
   aws_s3_bucket_public_access_block with all four flags set to true
5. Every new aws_security_group MUST have a description and constrained
   egress rules (no 0.0.0.0/0 on all protocols)
6. Every new aws_kms_key MUST have enable_key_rotation = true and an
   explicit key policy
7. Every new aws_cloudwatch_log_group MUST have kms_key_id and
   retention_in_days set
8. Generate valid, deployable Terraform (HCL) syntax
9. Do not add comments explaining your changes

MISCONFIGURATIONS TO FIX:
{findings_formatted}

TERRAFORM CODE:
```hcl
{terraform_code}
```

Return ONLY the complete repaired Terraform code. No explanations, no
markdown fences, no preamble. Start directly with the HCL content."""

PROMPT_P2 = """You are a cloud security engineer. You have been given
Terraform code with confirmed security misconfigurations identified by
static analysis tools.

Your task: repair the Terraform code to fix the identified misconfigurations.

REQUIREMENTS:
1. Fix ALL identified misconfigurations
2. Preserve the original infrastructure intent and resource names exactly
3. Do not add resources unless absolutely required to fix a misconfiguration
4. Generate valid, deployable Terraform (HCL) syntax
5. Do not add comments explaining your changes

SECURITY COMPLETENESS CHECKLIST — if any of these resources exist in your
output (whether original or newly created), verify each has the required
companion resources and attributes:

  aws_s3_bucket:
    [ ] aws_s3_bucket_public_access_block (block_public_acls = true,
        block_public_policy = true, ignore_public_acls = true,
        restrict_public_buckets = true)
    [ ] aws_s3_bucket_server_side_encryption_configuration (KMS)
    [ ] aws_s3_bucket_logging

  aws_security_group:
    [ ] description attribute set
    [ ] egress rules constrained (no 0.0.0.0/0 with protocol = "-1")

  aws_kms_key:
    [ ] enable_key_rotation = true
    [ ] explicit key policy

  aws_cloudwatch_log_group:
    [ ] kms_key_id set
    [ ] retention_in_days set

  aws_vpc:
    [ ] companion aws_flow_log resource

MISCONFIGURATIONS TO FIX:
{findings_formatted}

TERRAFORM CODE:
```hcl
{terraform_code}
```

Return ONLY the complete repaired Terraform code. No explanations, no
markdown fences, no preamble. Start directly with the HCL content."""

PROMPTS = {"P0": PROMPT_P0, "P1": PROMPT_P1, "P2": PROMPT_P2}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

MODEL_COSTS = {
    "claude-sonnet-4": (0.003, 0.015),
    "nova-pro": (0.001, 0.001),
    "nova-lite": (0.0001, 0.0002),
    "llama-3-3-70b": (0.0008, 0.0008),
    "deepseek-r1": (0.0014, 0.0028),
    "qwen3-32b": (0.0004, 0.0004),
}


def _format_findings(findings):
    lines = []
    for f in findings:
        lines.append(
            f"- [{f.rule_id}] {f.title} (severity: {f.severity})\n"
            f"  Resource: {f.resource_name} in {f.file_path}:{f.start_line}-{f.end_line}"
        )
    return "\n".join(lines)


def scan_module(module_dir: str):
    trivy_raw = run_trivy(module_dir)
    checkov_raw = run_checkov(module_dir)
    findings = normalize_trivy_findings(trivy_raw) + normalize_checkov_findings(checkov_raw)
    seen = set()
    deduped = []
    for f in findings:
        key = (f.rule_id, f.resource_name)
        if key not in seen:
            seen.add(key)
            deduped.append(f)
    return deduped


def finding_to_dict(f):
    return {
        "tool": f.tool,
        "rule_id": f.rule_id,
        "title": f.title,
        "severity": f.severity,
        "resource_name": f.resource_name,
        "resource_type": f.resource_type,
        "file_path": f.file_path,
        "start_line": f.start_line,
        "end_line": f.end_line,
    }


def run_one_trial(
    module_dir: str,
    module_id: str,
    model_id: str,
    prompt_variant: str,
    findings_before,
    bedrock_client,
    max_tokens: int = 16384,
):
    module_code = ""
    for tf_file in sorted(Path(module_dir).glob("*.tf")):
        module_code += tf_file.read_text() + "\n\n"

    findings_formatted = _format_findings(findings_before)
    prompt_template = PROMPTS[prompt_variant]
    prompt = prompt_template.format(
        findings_formatted=findings_formatted,
        terraform_code=module_code,
    )

    try:
        response_text, usage = bedrock_client.invoke(
            model_id=model_id,
            prompt=prompt,
            max_tokens=max_tokens,
            temperature=0.0,
        )
    except Exception as e:
        return {
            "module_id": module_id,
            "model_id": model_id,
            "prompt_variant": prompt_variant,
            "error": f"{type(e).__name__}: {e}",
            "hcl_valid": False,
            "findings_before": [finding_to_dict(f) for f in findings_before],
            "findings_after": [finding_to_dict(f) for f in findings_before],
            "target_count": len(findings_before),
            "resolved_count": 0,
            "introduced_count": 0,
            "net_delta": 0,
            "repair_cost_usd": 0,
            "input_tokens": 0,
            "output_tokens": 0,
        }

    repaired_code = sanitize_repair_response(response_text, model_id)
    hcl_valid = is_valid_hcl(repaired_code) if repaired_code else False

    findings_after = list(findings_before)
    if hcl_valid:
        tmp = tempfile.mkdtemp()
        (Path(tmp) / "main.tf").write_text(repaired_code)
        try:
            findings_after = scan_module(tmp)
        except Exception:
            findings_after = list(findings_before)

    before_keys = {(f.rule_id, f.resource_name) for f in findings_before}
    after_keys = {(f.rule_id, f.resource_name) for f in findings_after}
    resolved = len(before_keys - after_keys)
    introduced = len(after_keys - before_keys)

    costs = MODEL_COSTS.get(model_id, (0.001, 0.001))
    input_tokens = usage.get("input_tokens", 0)
    output_tokens = usage.get("output_tokens", 0)
    cost_usd = (input_tokens / 1000 * costs[0]) + (output_tokens / 1000 * costs[1])

    return {
        "module_id": module_id,
        "model_id": model_id,
        "prompt_variant": prompt_variant,
        "error": None,
        "hcl_valid": hcl_valid,
        "findings_before": [finding_to_dict(f) for f in findings_before],
        "findings_after": [finding_to_dict(f) for f in findings_after],
        "target_count": len(before_keys),
        "resolved_count": resolved,
        "introduced_count": introduced,
        "net_delta": resolved - introduced,
        "repair_cost_usd": cost_usd,
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Prompt ablation study")
    parser.add_argument("--corpus", required=True, help="Corpus directory")
    parser.add_argument(
        "--models",
        nargs="+",
        default=["deepseek-r1", "claude-sonnet-4"],
        help="Models to test",
    )
    parser.add_argument("--n-modules", type=int, default=50, help="Number of modules")
    parser.add_argument("--region", default="us-east-1")
    parser.add_argument("--outdir", default="experiments/results/prompt_ablation/")
    parser.add_argument("--resume", action="store_true", help="Skip completed trials")
    args = parser.parse_args()

    corpus_dir = Path(args.corpus)
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    (outdir / "games").mkdir(exist_ok=True)

    module_dirs = sorted([
        d for d in corpus_dir.iterdir()
        if d.is_dir() and any(d.glob("*.tf"))
    ])[:args.n_modules]

    print(f"Prompt ablation: {len(module_dirs)} modules x {len(args.models)} models x 3 variants")
    total = len(module_dirs) * len(args.models) * 3

    client = BedrockClient(region=args.region)

    done = 0
    errors = 0
    for i, mod_dir in enumerate(module_dirs):
        module_id = mod_dir.name
        print(f"\n[{i + 1}/{len(module_dirs)}] Scanning {module_id} ...")
        try:
            findings_before = scan_module(str(mod_dir))
        except Exception as e:
            print(f"  SCAN ERROR: {e}")
            errors += 1
            continue

        for model_id in args.models:
            for variant in ["P0", "P1", "P2"]:
                out_file = outdir / "games" / f"{module_id}_{model_id}_{variant}.json"
                if args.resume and out_file.exists():
                    done += 1
                    continue

                print(f"  {model_id} / {variant} ...", end=" ", flush=True)
                t0 = time.time()
                result = run_one_trial(
                    str(mod_dir), module_id, model_id, variant,
                    findings_before, client,
                )
                elapsed = time.time() - t0

                out_file.write_text(json.dumps(result, indent=2))
                done += 1

                status = "OK" if result["hcl_valid"] else "FAIL"
                if result.get("error"):
                    status = "ERR"
                    errors += 1

                print(
                    f"{status} ND={result['net_delta']:+d} "
                    f"({elapsed:.1f}s) [{done}/{total}]"
                )

    print(f"\nDone. {done} trials, {errors} errors.")
    print(f"Results in {outdir}/games/")


if __name__ == "__main__":
    main()
