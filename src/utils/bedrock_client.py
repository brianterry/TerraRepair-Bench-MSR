"""
AWS Bedrock wrapper supporting all six target models.

Handles cross-region inference profiles (us.anthropic, us.amazon, etc.).
"""
from __future__ import annotations

import json
import logging
import os
import random
import time

import boto3
from botocore.config import Config as BotoConfig
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)

# Bedrock error codes that indicate transient throttling / capacity pressure.
# Over a multi-day, multi-model run these are expected; we back off and retry,
# and log loudly so throttle-driven delays/skips are never invisible.
_THROTTLE_ERROR_CODES = {
    "ThrottlingException",
    "TooManyRequestsException",
    "ServiceUnavailableException",
    "ModelTimeoutException",
    "ModelNotReadyException",
}


class ThrottlingError(Exception):
    """Raised after retries are exhausted on a throttling error, so the caller
    can log a loud, scored-as-skip (never scored-as-clean) outcome."""


class InvokeTimeout(Exception):
    """Raised when a single invocation exceeds the hard wall-clock cap. A slow
    or streaming model (observed: Claude at a large max_tokens can run for many
    minutes and a read timeout never fires because chunks keep arriving) must
    not wedge a multi-day run; the runner logs this as a skip, never scored as
    a clean/empty repair."""


# Models that reject an explicit `temperature` field (newer models use adaptive
# / effort-based control instead). Confirmed via smoke test 2026-09:
#   Claude Sonnet 5:  "`temperature` is deprecated for this model"
#   Grok 4.6:         "This model doesn't support the temperature field"
# The dispatch path ALSO auto-detects this at runtime (see _temperature_rejected)
# and adds the model here, so a future new model is handled without a code change.
NO_TEMPERATURE_MODELS = {"claude-sonnet-5", "grok-4-6"}


def _is_temperature_validation_error(e: "ClientError") -> bool:
    code = e.response.get("Error", {}).get("Code", "")
    msg = e.response.get("Error", {}).get("Message", "") or ""
    return code == "ValidationException" and "temperature" in msg.lower()

SUPPORTED_MODELS = {
    # Non-reasoning (us. prefix = cross-region inference profile)
    # claude-sonnet-4 is LEGACY on account <ACCOUNT_ID> (invoke ->
    # ResourceNotFoundException); kept only so historical game ids still resolve.
    # It is REPLACED in the active cohort by claude-sonnet-4-5 below.
    "claude-sonnet-4": "us.anthropic.claude-sonnet-4-20250514-v1:0",
    # Replacement anchor for the Legacy claude-sonnet-4. Same Sonnet tier, one
    # minor gen up. Needs the CRIS us. prefix (plain slug rejects on-demand);
    # CONFIRMED live via Converse 2026-09-30. Routed through the Anthropic
    # Messages path by _dispatch (bedrock_id contains "anthropic").
    "claude-sonnet-4-5": "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
    "nova-pro": "us.amazon.nova-pro-v1:0",
    "nova-lite": "us.amazon.nova-lite-v1:0",
    "llama-3-3-70b": "us.meta.llama3-3-70b-instruct-v1:0",
    # Reasoning
    "deepseek-r1": "us.deepseek.r1-v1:0",
    "qwen3-32b": "qwen.qwen3-32b-v1:0",
    # --- 2026 refresh (see MODEL_COHORT_2026.md) ---
    # CONFIRM every slug + CRIS prefix in the Bedrock console before firing;
    # this is the us.qwen vs qwen. mismatch the audit flagged.
    # Converse-native (Anthropic + xAI):
    "claude-sonnet-5": "global.anthropic.claude-sonnet-5",
    "grok-4-6": "us.xai.grok-4.6",
    # OpenAI-compatible via Project Mantle (route through _invoke_raw).
    # Slugs CONFIRMED against Bedrock us-east-1 list_foundation_models (2026-09):
    "deepseek-v3-2": "deepseek.v3.2",
    "kimi-k2-5": "moonshotai.kimi-k2.5",
}

# Models that need the OpenAI-shaped invoke_model path instead of Converse.
# Matched against the FRIENDLY model_id (not the Bedrock id), because the new
# OpenAI-compatible DeepSeek V3.2 must NOT be confused with the Converse-based
# DeepSeek-R1 (both contain "deepseek" in their Bedrock id).
_OPENAI_COMPATIBLE_MODELS = {"qwen3-32b", "deepseek-v3-2", "kimi-k2-5"}

# Legacy substring set kept for the Qwen Bedrock-id path (back-compat).
_INVOKE_MODEL_IDS = {"qwen"}

# Per-model max output token limits (from Bedrock validation errors).
# CONFIRM the new models' ceilings in-console; do not let them silently fall
# back to the caller's max_tokens.
# Ceilings CONFIRMED 2026-09-30 via live Converse maxTokens probes (a request
# above a model's ceiling fails with ValidationException "exceeds the model
# limit of N"). The 2026-09 run capped output at 16384, which truncated the
# verbose reasoning models mid-answer; grok/sonnet-5/deepseek-r1 have ample
# ceilings and were re-run at a larger budget. nova/llama ceilings (8-10K) are
# HARD model limits — their >16K-token failures are structural, not budget.
_MODEL_MAX_TOKENS = {
    "claude-sonnet-4": 64000,
    "claude-sonnet-4-5": 64000,  # Sonnet tier; ample for repair (replacement anchor)
    "nova-pro": 10000,          # CONFIRMED hard limit 10000
    "nova-lite": 10000,         # CONFIRMED hard limit 10000
    "llama-3-3-70b": 8192,      # CONFIRMED hard limit 8192
    "deepseek-r1": 32768,       # CONFIRMED hard limit 32768 (was 16384)
    "qwen3-32b": 16384,
    # 2026 refresh
    "claude-sonnet-5": 64000,   # CONFIRMED >=100000 accepted; 64000 ample for repair
    "grok-4-6": 40000,          # CONFIRMED >=100000 accepted; 40000 fits observed 35K max
    "deepseek-v3-2": 16384,
    "kimi-k2-5": 16384,
}


def _int_env(name: str, default: int) -> int:
    """Read a positive int from env; fall back to default on missing/invalid so
    a bad value can never silently disable a timeout."""
    raw = os.environ.get(name)
    if raw is None or not raw.strip():
        return default
    try:
        v = int(raw)
    except ValueError:
        return default
    return v if v > 0 else default


def _float_env(name: str, default: float) -> float:
    """Read a positive float from env; fall back to default on missing/invalid."""
    raw = os.environ.get(name)
    if raw is None or not raw.strip():
        return default
    try:
        v = float(raw)
    except ValueError:
        return default
    return v if v > 0 else default


class BedrockClient:
    def __init__(
        self,
        region: str = "us-east-1",
        read_timeout: int | None = None,
        invoke_timeout: float | None = None,
    ):
        """
        Args:
            read_timeout: botocore socket read timeout. Note this does NOT bound
                a streaming response that keeps sending chunks. Defaults to the
                BEDROCK_READ_TIMEOUT env var, else 300s.
            invoke_timeout: HARD wall-clock cap (seconds) on a single
                invocation, enforced independently of the socket timeout so a
                slow/streaming model cannot wedge a multi-day run. None disables
                it. Should be >= read_timeout. Defaults to the
                BEDROCK_INVOKE_TIMEOUT env var, else 420s.

        Env overrides let a slow-model backfill (e.g. grok at 40K tokens hitting
        the 420s cap under concurrency) raise the ceiling without a code change;
        unset, behavior is byte-identical to the historical 300/420 defaults.
        """
        if read_timeout is None:
            read_timeout = _int_env("BEDROCK_READ_TIMEOUT", 300)
        if invoke_timeout is None:
            invoke_timeout = _float_env("BEDROCK_INVOKE_TIMEOUT", 420.0)
        config = BotoConfig(
            read_timeout=read_timeout,
            retries={"max_attempts": 2, "mode": "adaptive"},
        )
        self.client = boto3.client(
            "bedrock-runtime", region_name=region, config=config
        )
        self.invoke_timeout = invoke_timeout
        # Kept for provenance (run_manifest records the effective timeouts).
        self.read_timeout = read_timeout

    def _call_with_wall_clock_cap(self, fn):
        """Run ``fn`` in a worker thread and enforce self.invoke_timeout.

        boto's read_timeout does not fire while a response is still streaming
        chunks, so a verbose model can run effectively unbounded. A thread +
        join(timeout) gives a hard ceiling. On timeout we raise InvokeTimeout;
        the orphaned worker thread is daemonized so it cannot block process
        exit (the underlying HTTP call will be abandoned)."""
        if not self.invoke_timeout:
            return fn()

        import threading

        box: dict = {}

        def worker():
            try:
                box["result"] = fn()
            except BaseException as e:  # noqa: BLE001 - propagate to caller
                box["error"] = e

        t = threading.Thread(target=worker, daemon=True)
        t.start()
        t.join(self.invoke_timeout)
        if t.is_alive():
            raise InvokeTimeout(
                f"invocation exceeded {self.invoke_timeout:.0f}s wall-clock cap"
            )
        if "error" in box:
            raise box["error"]
        return box["result"]

    @staticmethod
    def _extract_converse_text(content_blocks: list[dict]) -> str:
        """Extract the ANSWER text from Converse API content blocks.

        Reasoning models (grok-4-6, DeepSeek-R1, claude-sonnet-5) return their
        chain-of-thought in a SEPARATE block from the answer. On the Converse
        API that block is ``reasoningContent``; depending on the botocore
        version it may instead surface as the opaque ``SDK_UNKNOWN_MEMBER``
        placeholder (an unmapped newer response member). Either way it is NOT
        the answer and must never be treated as HCL.

        We therefore return ONLY the concatenation of ``text`` blocks — the
        model's actual answer. Reasoning blocks (recognized ``reasoningContent``
        or opaque ``SDK_UNKNOWN_MEMBER``) are skipped.

        This deliberately does NOT fall back to reasoning text when there are no
        text blocks. The previous fallback fed chain-of-thought prose into the
        HCL sanitizer/validator, which let reasoning masquerade as a repair. An
        empty text set now means a genuinely empty answer, reported honestly by
        the caller rather than papered over.

        NOTE on grok-4-6's high failure rate in the 2026-09 run: the dominant
        cause was NOT this extractor but an OUTPUT TOKEN BUDGET one — the run
        used max_tokens=16384, and grok's reasoning+answer routinely needs
        ~18-35K tokens, so responses were truncated before/within the answer
        block (empty or half-written HCL). See _MODEL_MAX_TOKENS and the run's
        --max-tokens. This extractor hardening is a correctness fix that stands
        on its own, but the grok recovery also required a larger token budget.
        """
        text_parts: list[str] = []
        for block in content_blocks:
            # Only real answer text counts. reasoningContent and the opaque
            # SDK_UNKNOWN_MEMBER (unmapped reasoning member) are intentionally
            # ignored so chain-of-thought never leaks into the repaired HCL.
            if "text" in block:
                text_parts.append(block["text"])
        return "".join(text_parts)

    def invoke(
        self,
        model_id: str,
        prompt: str,
        max_tokens: int = 8192,
        temperature: float = 0.0,
    ) -> tuple[str, dict]:
        """
        Invoke Bedrock model. Returns (response_text, usage_dict).
        usage_dict contains input_tokens, output_tokens for cost tracking.
        Temperature 0.0 for deterministic repair.
        """
        bedrock_id = SUPPORTED_MODELS.get(model_id, model_id)
        model_limit = _MODEL_MAX_TOKENS.get(model_id, max_tokens)
        max_tokens = min(max_tokens, model_limit)

        def call():
            # Resolve temperature per model: None => omit the field entirely.
            temp = None if model_id in NO_TEMPERATURE_MODELS else temperature
            try:
                return self._call_with_wall_clock_cap(
                    lambda: self._dispatch(bedrock_id, prompt, max_tokens, temp)
                )
            except ClientError as e:
                # Auto-recover from a temperature-unsupported ValidationException:
                # remember the model and retry once WITHOUT temperature. Makes
                # the harness robust to future models that drop the field.
                if temp is not None and _is_temperature_validation_error(e):
                    logger.warning(
                        "%s rejects temperature; retrying without it and "
                        "marking model temperature-free", model_id,
                    )
                    NO_TEMPERATURE_MODELS.add(model_id)
                    return self._call_with_wall_clock_cap(
                        lambda: self._dispatch(bedrock_id, prompt, max_tokens, None)
                    )
                raise

        return self._with_retry(model_id, call)

    def _dispatch(
        self, bedrock_id: str, prompt: str, max_tokens: int, temperature: float | None
    ) -> tuple[str, dict]:
        """Route to the right API shape for the model. No retry here.

        ``temperature=None`` means omit the temperature field from the request
        (required by models that reject it, e.g. Claude Sonnet 5, Grok 4.6).
        """
        # Anthropic (Claude Sonnet 4/5, Opus, etc.) use the Messages API body.
        if "claude" in bedrock_id or "anthropic" in bedrock_id:
            return self._invoke_claude(bedrock_id, prompt, max_tokens, temperature)

        # OpenAI-compatible models (Qwen3-32B, and the Project Mantle models
        # DeepSeek V3.2 / Kimi K2.5) use the raw invoke_model path. The caller
        # (invoke) has already resolved routing by friendly id; here we detect
        # the OpenAI-shaped Bedrock ids by their provider prefixes.
        if any(bedrock_id.startswith(p) for p in ("qwen", "deepseek.v3", "moonshotai")):
            return self._invoke_raw(bedrock_id, prompt, max_tokens, temperature)

        # Everything else (Nova, Llama, DeepSeek-R1, xAI Grok) via Converse.
        return self._invoke_converse(bedrock_id, prompt, max_tokens, temperature)

    def _with_retry(
        self, model_id: str, fn, max_attempts: int = 6, base_delay: float = 2.0
    ) -> tuple[str, dict]:
        """
        Call ``fn`` with exponential backoff + jitter on Bedrock throttling.

        Botocore's adaptive retries handle some of this, but a long multi-model
        run needs an explicit, LOUD outer loop: each throttle is logged with the
        attempt number and the model, and if retries are exhausted we raise
        ThrottlingError so the runner records a logged skip (never a clean/empty
        scored result). Non-throttle ClientErrors propagate immediately.
        """
        attempt = 0
        while True:
            try:
                return fn()
            except ClientError as e:
                code = e.response.get("Error", {}).get("Code", "")
                if code not in _THROTTLE_ERROR_CODES:
                    raise
                attempt += 1
                if attempt >= max_attempts:
                    logger.error(
                        "throttled on %s: giving up after %d attempts (%s)",
                        model_id, attempt, code,
                    )
                    raise ThrottlingError(
                        f"{model_id}: throttled after {attempt} attempts ({code})"
                    ) from e
                delay = base_delay * (2 ** (attempt - 1)) + random.uniform(0, 1)
                logger.warning(
                    "throttled on %s (%s); backoff %.1fs then retry %d/%d",
                    model_id, code, delay, attempt, max_attempts,
                )
                time.sleep(delay)

    def _invoke_claude(
        self, bedrock_id: str, prompt: str, max_tokens: int, temperature: float | None
    ) -> tuple[str, dict]:
        body = {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": max_tokens,
            "messages": [{"role": "user", "content": prompt}],
        }
        if temperature is not None:
            body["temperature"] = temperature
        response = self.client.invoke_model(
            modelId=bedrock_id,
            body=json.dumps(body),
            contentType="application/json",
            accept="application/json",
        )
        resp_body = json.loads(response["body"].read())
        text = ""
        for block in resp_body.get("content", []):
            if block.get("type") == "text":
                text += block.get("text", "")
        usage = {
            "input_tokens": resp_body.get("usage", {}).get("input_tokens", 0),
            "output_tokens": resp_body.get("usage", {}).get("output_tokens", 0),
        }
        return text, usage

    def _invoke_converse(
        self, bedrock_id: str, prompt: str, max_tokens: int, temperature: float | None
    ) -> tuple[str, dict]:
        """Nova, Llama, DeepSeek, xAI Grok via the Converse API."""
        inference_config: dict = {"maxTokens": max_tokens}
        if temperature is not None:
            inference_config["temperature"] = temperature
        response = self.client.converse(
            modelId=bedrock_id,
            messages=[{"role": "user", "content": [{"text": prompt}]}],
            inferenceConfig=inference_config,
        )
        content_blocks = response["output"]["message"]["content"]
        text = self._extract_converse_text(content_blocks)
        usage = {
            "input_tokens": response.get("usage", {}).get("inputTokens", 0),
            "output_tokens": response.get("usage", {}).get("outputTokens", 0),
        }
        return text, usage

    def _invoke_raw(
        self, bedrock_id: str, prompt: str, max_tokens: int, temperature: float | None
    ) -> tuple[str, dict]:
        """OpenAI-shaped invoke_model path (Qwen3, DeepSeek V3.2, Kimi K2.5)."""
        body = {
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens,
        }
        if temperature is not None:
            body["temperature"] = temperature
        response = self.client.invoke_model(
            modelId=bedrock_id,
            body=json.dumps(body),
            contentType="application/json",
            accept="application/json",
        )
        resp_body = json.loads(response["body"].read())
        # Qwen3 returns {"choices": [{"message": {"content": "..."}}]}
        choices = resp_body.get("choices", [])
        if choices:
            text = choices[0].get("message", {}).get("content", "")
        else:
            text = resp_body.get("output", {}).get("text", "")
        usage_block = resp_body.get("usage", {})
        usage = {
            "input_tokens": usage_block.get("prompt_tokens", usage_block.get("input_tokens", 0)),
            "output_tokens": usage_block.get("completion_tokens", usage_block.get("output_tokens", 0)),
        }
        return text, usage
