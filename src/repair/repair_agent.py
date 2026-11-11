"""
Single LLM call to repair Terraform code given scanner findings.
"""
from __future__ import annotations

import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from src.scanning.scanner_normalizer import Finding
    from src.utils.bedrock_client import BedrockClient

REPAIR_PROMPT = """You are a cloud security engineer. You have been given
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


@dataclass
class RepairResult:
    model_id: str
    module_id: str
    original_code: str
    repaired_code: str
    repaired_dir: str | None  # Temp dir with repaired .tf files; caller must clean up
    repair_prompt_tokens: int
    repair_completion_tokens: int
    repair_cost_usd: float
    success: bool  # False if LLM refused or returned invalid HCL
    hcl_valid: bool  # True if repaired code passes basic HCL structural validation
    error: str | None
    # Raw model response text BEFORE sanitize_repair_response. Persisted as the
    # <game>.raw.txt sidecar. "" if the invocation itself failed.
    raw_response: str = ""


# Approximate cost per 1K tokens (USD) as (input, output) - update as needed.
# 2026 refresh prices from MODEL_COHORT_2026.md; CONFIRM Bedrock on-demand rates
# in-console at wiring time (esp. kimi-k2-5, whose price was unconfirmed).
MODEL_COSTS = {
    "claude-sonnet-4": (0.003, 0.015),
    # Sonnet 4.5 (replacement anchor): Bedrock on-demand $3/1M in, $15/1M out
    # (same Sonnet-tier rate as 4), confirmed 2026-09-30.
    "claude-sonnet-4-5": (0.003, 0.015),
    "nova-pro": (0.001, 0.001),
    "nova-lite": (0.0001, 0.0002),
    "llama-3-3-70b": (0.0008, 0.0008),
    "deepseek-r1": (0.0014, 0.0028),
    "qwen3-32b": (0.0004, 0.0004),
    # --- 2026 refresh ---
    "claude-sonnet-5": (0.002, 0.010),
    "grok-4-6": (0.002, 0.006),
    "deepseek-v3-2": (0.00074, 0.00222),
    "kimi-k2-5": (0.00060, 0.00250),  # CONFIRM in-console; unconfirmed in report
}


def _format_findings(findings: list["Finding"]) -> str:
    lines = []
    for f in findings:
        lines.append(
            f"- [{f.rule_id}] {f.title} (severity: {f.severity})\n"
            f"  Resource: {f.resource_name} in {f.file_path}:{f.start_line}-{f.end_line}"
        )
    return "\n".join(lines)


def _read_module_code(module_dir: str) -> str:
    """Concatenate all .tf files in module_dir into a single string."""
    path = Path(module_dir)
    parts = []
    for tf_file in sorted(path.glob("*.tf")):
        parts.append(tf_file.read_text())
    return "\n\n".join(parts)


# Optional few-shot retrieval block, prepended to REPAIR_PROMPT only when
# exemplars are supplied. Kept OUT of REPAIR_PROMPT itself so the no-retrieval
# ("none") arm renders the exact original prompt byte-for-byte and reproduces
# the baseline numbers. The ablation varies ONLY this block's content/presence.
RETRIEVAL_PREFIX = """EXAMPLES OF SECURELY-CONFIGURED SIMILAR MODULES:
The following Terraform modules are already securely configured. Use them as
reference for how similar resources should be configured, but repair ONLY the
module given below.

{retrieved_exemplars}

"""


def repair_module(
    module_dir: str,
    findings: list["Finding"],
    model_id: str,
    bedrock_client: "BedrockClient",
    max_tokens: int = 16384,
    exemplar_block: str = "",
) -> RepairResult:
    """
    Concatenate all .tf files in module_dir into a single string.
    Format findings into the prompt.
    Call the LLM via Bedrock.
    Parse and sanitize the response.
    Write repaired code to a temp directory.
    Return RepairResult with original code, repaired code, and metadata.

    ``exemplar_block`` (retrieval ablation): rendered few-shot exemplar text. When
    empty (default / "none" arm) the prompt is identical to the baseline. When
    non-empty it is prepended via RETRIEVAL_PREFIX. This is strictly additive —
    REQUIREMENTS 1-5 and the repair instruction are unchanged.
    """
    from src.utils.response_sanitizer import is_valid_hcl, sanitize_repair_response
    from src.utils.bedrock_client import InvokeTimeout, ThrottlingError

    module_id = Path(module_dir).name
    original_code = _read_module_code(module_dir)
    findings_formatted = _format_findings(findings)

    prompt = REPAIR_PROMPT.format(
        findings_formatted=findings_formatted,
        terraform_code=original_code,
    )
    if exemplar_block:
        prompt = RETRIEVAL_PREFIX.format(retrieved_exemplars=exemplar_block) + prompt

    success = False
    repaired_code = ""
    repaired_dir = None
    hcl_valid = False
    error_msg = None
    prompt_tokens = 0
    completion_tokens = 0
    raw_response = ""

    try:
        response_text, usage = bedrock_client.invoke(
            model_id=model_id,
            prompt=prompt,
            max_tokens=max_tokens,
            temperature=0.0,
        )
        # Capture BEFORE sanitizing: sanitize_repair_response raises on
        # refusals/short output, and the raw text must survive that.
        raw_response = response_text or ""
        prompt_tokens = usage.get("input_tokens", 0)
        completion_tokens = usage.get("output_tokens", 0)

        repaired_code = sanitize_repair_response(response_text, model_id)
        success = bool(repaired_code)  # True if LLM returned non-empty response
        hcl_valid = is_valid_hcl(repaired_code) if success else False

        if success and hcl_valid:
            # Write repaired code to temp dir for scanning
            tmp = tempfile.mkdtemp()
            (Path(tmp) / "main.tf").write_text(repaired_code)
            repaired_dir = tmp
        elif success and not hcl_valid:
            error_msg = "Repaired code failed HCL validation"
    except (ThrottlingError, InvokeTimeout):
        # Control-flow signals: the caller (runner) must record these as loud
        # SKIPS, not as a scored (empty) repair that would look like a clean
        # result. Re-raise rather than swallowing into success=False.
        raise
    except Exception as e:
        error_msg = f"{type(e).__name__}: {str(e)}"

    # Cost estimation
    costs = MODEL_COSTS.get(model_id, (0.001, 0.001))
    cost_usd = (prompt_tokens / 1000 * costs[0]) + (completion_tokens / 1000 * costs[1])

    return RepairResult(
        model_id=model_id,
        module_id=module_id,
        original_code=original_code,
        repaired_code=repaired_code,
        repaired_dir=repaired_dir,
        repair_prompt_tokens=prompt_tokens,
        repair_completion_tokens=completion_tokens,
        repair_cost_usd=cost_usd,
        success=success,
        hcl_valid=hcl_valid,
        error=error_msg,
        raw_response=raw_response,
    )
