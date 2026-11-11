"""
Offline wiring tests for the 2026 model refresh.

Prove — WITHOUT a live Bedrock endpoint — that the four new models are wired
correctly: friendly-id -> Bedrock-id mapping (+ CRIS prefix), API routing
(Converse vs OpenAI-shaped raw), per-model token clamp present, real
MODEL_COSTS entry (non-default), and reasoning thinking-delimiter stripping.

These cover the offline-checkable columns of the Phase-1 smoke PASS/FAIL table.
The live columns (endpoint resolves, scanner runs) require Bedrock + Checkov and
are exercised by scripts/smoke_test.py on the remote instance.

Stdlib + pytest only. Delta-scorer math untouched.
"""
from __future__ import annotations

import pytest

from src.repair.repair_agent import MODEL_COSTS
from src.utils import bedrock_client as bc
from src.utils.response_sanitizer import sanitize_repair_response

NEW_MODELS = ["claude-sonnet-5", "deepseek-v3-2", "kimi-k2-5", "grok-4-6"]
ALL_MODELS = [
    "claude-sonnet-4", "claude-sonnet-4-5", "nova-pro", "nova-lite",
    "llama-3-3-70b", "deepseek-r1", "qwen3-32b",
] + NEW_MODELS

# Per-model output-token ceilings CONFIRMED live via Converse maxTokens probes
# (2026-09-30). A re-run at a large --max-tokens must clamp each model to its
# real ceiling; these pin the ones that changed or that matter for the recovery.
CONFIRMED_CEILINGS = {
    "grok-4-6": 40000,
    "deepseek-r1": 32768,
    "nova-pro": 10000,
    "nova-lite": 10000,
    "llama-3-3-70b": 8192,
    "claude-sonnet-4-5": 64000,
}


# ---------------------------------------------------------------------------
# Mapping / prefix / clamp / cost
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("model_id", ALL_MODELS)
def test_every_model_is_fully_wired(model_id):
    assert model_id in bc.SUPPORTED_MODELS, "missing SUPPORTED_MODELS entry"
    assert model_id in bc._MODEL_MAX_TOKENS, "missing token clamp"
    assert model_id in MODEL_COSTS, "missing MODEL_COSTS entry"


@pytest.mark.parametrize("model_id", ALL_MODELS)
def test_cost_is_non_default(model_id):
    """A real cost tuple, not the (0.001, 0.001) silent fallback used when a
    model is unknown to MODEL_COSTS."""
    cost = MODEL_COSTS[model_id]
    assert isinstance(cost, tuple) and len(cost) == 2
    assert cost != (0.001, 0.001) or model_id in {"nova-pro"}  # nova-pro really is 0.001/0.001


@pytest.mark.parametrize("model_id,expected_prefix", [
    ("claude-sonnet-5", "global."),
    ("grok-4-6", "us."),
    ("deepseek-v3-2", "deepseek."),
    ("kimi-k2-5", "moonshotai."),
])
def test_new_model_bedrock_ids(model_id, expected_prefix):
    bid = bc.SUPPORTED_MODELS[model_id]
    assert bid.startswith(expected_prefix), f"{model_id} -> {bid}"


def test_grok_uses_xai_namespace():
    assert "xai" in bc.SUPPORTED_MODELS["grok-4-6"]


@pytest.mark.parametrize("model_id,ceiling", sorted(CONFIRMED_CEILINGS.items()))
def test_confirmed_token_ceilings(model_id, ceiling):
    """Pin the probe-confirmed per-model output ceilings so a future edit can't
    silently reintroduce the 16384 truncation that broke the reasoning models,
    or set a value above a model's hard limit (which would fail every call)."""
    assert bc._MODEL_MAX_TOKENS[model_id] == ceiling


def test_grok_ceiling_above_observed_max():
    """grok's valid outputs reached ~34850 tokens in the 2026-09 run; its clamp
    must sit above that so the recovery run is not truncated again."""
    assert bc._MODEL_MAX_TOKENS["grok-4-6"] >= 35000


def test_sonnet45_replacement_wired():
    """The Legacy claude-sonnet-4 replacement must be fully wired and use the
    cross-region (us.) Anthropic profile."""
    bid = bc.SUPPORTED_MODELS["claude-sonnet-4-5"]
    assert bid == "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
    assert "anthropic" in bid  # routes via the claude messages path


# ---------------------------------------------------------------------------
# Routing — assert WHICH API path each model takes, without a live call.
# We stub the three _invoke_* methods to record which one fires.
# ---------------------------------------------------------------------------

class _RouteRecorder(bc.BedrockClient):
    def __init__(self):
        # Bypass boto client construction entirely.
        self.route = None
        self.invoke_timeout = None  # disable the wall-clock cap in routing tests

    def _invoke_claude(self, *a, **k):
        self.route = "claude"; return ("x" * 60, {"input_tokens": 1, "output_tokens": 1})

    def _invoke_converse(self, *a, **k):
        self.route = "converse"; return ("x" * 60, {"input_tokens": 1, "output_tokens": 1})

    def _invoke_raw(self, *a, **k):
        self.route = "raw"; return ("x" * 60, {"input_tokens": 1, "output_tokens": 1})


@pytest.mark.parametrize("model_id,expected_route", [
    # Anthropic -> claude messages body
    ("claude-sonnet-4", "claude"),
    ("claude-sonnet-4-5", "claude"),
    ("claude-sonnet-5", "claude"),
    # OpenAI-shaped raw invoke (Project Mantle + Qwen)
    ("qwen3-32b", "raw"),
    ("deepseek-v3-2", "raw"),
    ("kimi-k2-5", "raw"),
    # Converse for everyone else — including DeepSeek-R1 (must NOT be confused
    # with DeepSeek V3.2) and xAI Grok.
    ("deepseek-r1", "converse"),
    ("grok-4-6", "converse"),
    ("nova-pro", "converse"),
    ("llama-3-3-70b", "converse"),
])
def test_invoke_routes_to_expected_api(model_id, expected_route):
    client = _RouteRecorder()
    client.invoke(model_id=model_id, prompt="fix this", max_tokens=1024, temperature=0.0)
    assert client.route == expected_route, (
        f"{model_id} routed to {client.route}, expected {expected_route}"
    )


def test_deepseek_v32_and_r1_route_differently():
    """The critical disambiguation: both share 'deepseek' but must split."""
    c1, c2 = _RouteRecorder(), _RouteRecorder()
    c1.invoke("deepseek-v3-2", "p", 1024, 0.0)
    c2.invoke("deepseek-r1", "p", 1024, 0.0)
    assert c1.route == "raw"
    assert c2.route == "converse"


# ---------------------------------------------------------------------------
# Thinking-delimiter stripping for the new reasoning models
# ---------------------------------------------------------------------------

_VALID_TAIL = (
    '\nresource "aws_s3_bucket" "b" {\n'
    '  bucket = "my-example-bucket-name"\n'
    '  acl    = "private"\n'
    '  versioning { enabled = true }\n'
    '}\n'
)


def test_strip_think_block_deepseek_v32():
    raw = "<think>I should enable encryption and versioning.</think>" + _VALID_TAIL
    out = sanitize_repair_response(raw, "deepseek-v3-2")
    assert "<think>" not in out and "should enable" not in out
    assert 'resource "aws_s3_bucket"' in out


def test_strip_thinking_block_kimi():
    """Kimi may use <thinking> rather than <think>; generalized stripping must
    catch it or the HCL fails validation."""
    raw = "<thinking>plan: add public access block</thinking>" + _VALID_TAIL
    out = sanitize_repair_response(raw, "kimi-k2-5")
    assert "<thinking>" not in out and "plan:" not in out
    assert 'resource "aws_s3_bucket"' in out


def test_strip_reasoning_block_generic():
    raw = "<reasoning>chain of thought</reasoning>" + _VALID_TAIL
    out = sanitize_repair_response(raw, "grok-4-6")
    assert "<reasoning>" not in out


# ---------------------------------------------------------------------------
# Throttle retry behavior (no sleep, no live call)
# ---------------------------------------------------------------------------

def test_throttle_retries_then_raises(monkeypatch):
    from botocore.exceptions import ClientError
    monkeypatch.setattr(bc.time, "sleep", lambda s: None)  # no real backoff
    client = _RouteRecorder()
    calls = {"n": 0}

    def always_throttle():
        calls["n"] += 1
        raise ClientError({"Error": {"Code": "ThrottlingException"}}, "Converse")

    with pytest.raises(bc.ThrottlingError):
        client._with_retry("grok-4-6", always_throttle, max_attempts=4, base_delay=0.0)
    assert calls["n"] == 4  # tried the full budget


def test_non_throttle_error_propagates_immediately(monkeypatch):
    from botocore.exceptions import ClientError
    monkeypatch.setattr(bc.time, "sleep", lambda s: None)
    client = _RouteRecorder()

    def access_denied():
        raise ClientError({"Error": {"Code": "AccessDeniedException"}}, "Converse")

    with pytest.raises(ClientError):
        client._with_retry("grok-4-6", access_denied, max_attempts=4)
