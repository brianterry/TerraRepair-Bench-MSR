"""
Offline tests for the two smoke-surfaced fixes in bedrock_client:

  Fix 1 — temperature is optional. Models in NO_TEMPERATURE_MODELS omit the
          field; a ValidationException mentioning temperature triggers a
          one-shot retry WITHOUT temperature and marks the model.
  Fix 2 — a hard wall-clock cap (InvokeTimeout) so a slow/streaming model can't
          wedge the run.

No live endpoint, no delta-scorer changes. We drive the body-builders and the
cap directly with stubs.
"""
from __future__ import annotations

import time

import pytest
from botocore.exceptions import ClientError

from src.utils import bedrock_client as bc
from src.utils.bedrock_client import (
    NO_TEMPERATURE_MODELS,
    BedrockClient,
    InvokeTimeout,
    _is_temperature_validation_error,
)


class _Client(BedrockClient):
    """BedrockClient with boto construction bypassed; captures request bodies."""
    def __init__(self, invoke_timeout=None):
        self.invoke_timeout = invoke_timeout
        self.captured = {}

    # capture what each body-builder would send, without calling AWS
    def _invoke_claude(self, bedrock_id, prompt, max_tokens, temperature):
        self.captured = {"path": "claude", "temperature": temperature}
        return ("x" * 60, {"input_tokens": 1, "output_tokens": 1})

    def _invoke_converse(self, bedrock_id, prompt, max_tokens, temperature):
        self.captured = {"path": "converse", "temperature": temperature}
        return ("x" * 60, {"input_tokens": 1, "output_tokens": 1})

    def _invoke_raw(self, bedrock_id, prompt, max_tokens, temperature):
        self.captured = {"path": "raw", "temperature": temperature}
        return ("x" * 60, {"input_tokens": 1, "output_tokens": 1})


# ---------------------------------------------------------------------------
# Fix 1: temperature optional
# ---------------------------------------------------------------------------

def test_temperature_omitted_for_no_temperature_models():
    c = _Client()
    c.invoke("claude-sonnet-5", "p", 1024, 0.0)   # in NO_TEMPERATURE_MODELS
    assert c.captured["path"] == "claude"
    assert c.captured["temperature"] is None       # omitted


def test_temperature_omitted_for_grok():
    c = _Client()
    c.invoke("grok-4-6", "p", 1024, 0.0)           # converse + no temperature
    assert c.captured["path"] == "converse"
    assert c.captured["temperature"] is None


def test_temperature_passed_for_normal_models():
    c = _Client()
    c.invoke("claude-sonnet-4", "p", 1024, 0.0)
    assert c.captured["temperature"] == 0.0
    c.invoke("nova-pro", "p", 1024, 0.0)
    assert c.captured["temperature"] == 0.0


def test_body_builders_drop_temperature_field_when_none():
    """The actual request dicts must not carry a temperature key when None."""
    captured = {}

    class Rec(BedrockClient):
        def __init__(self):
            self.invoke_timeout = None
            class _C:
                def invoke_model(self, **kw):
                    import json as _j
                    captured.update(_j.loads(kw["body"]))
                    return {"body": _Body('{"content":[{"type":"text","text":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}],"usage":{}}')}
                def converse(self, **kw):
                    captured.update(kw["inferenceConfig"])
                    return {"output": {"message": {"content": [{"text": "x" * 60}]}}, "usage": {}}
            self.client = _C()

    class _Body:
        def __init__(self, s): self._s = s.encode()
        def read(self): return self._s

    # Claude with temperature None -> no 'temperature' key
    r = Rec()
    r._invoke_claude("global.anthropic.claude-sonnet-5", "p", 100, None)
    assert "temperature" not in captured
    captured.clear()
    # Converse with temperature None -> no 'temperature' key
    r._invoke_converse("us.xai.grok-4.6", "p", 100, None)
    assert "temperature" not in captured


def test_validation_error_detector():
    err = ClientError(
        {"Error": {"Code": "ValidationException",
                   "Message": "`temperature` is deprecated for this model."}},
        "InvokeModel",
    )
    assert _is_temperature_validation_error(err) is True
    other = ClientError(
        {"Error": {"Code": "ValidationException", "Message": "bad max_tokens"}},
        "InvokeModel",
    )
    assert _is_temperature_validation_error(other) is False


def test_temperature_validation_triggers_retry_without_temperature(monkeypatch):
    """A model NOT pre-listed that rejects temperature: first call raises the
    ValidationException, the client retries without temperature and adds the
    model to NO_TEMPERATURE_MODELS."""
    monkeypatch.setattr(bc.time, "sleep", lambda s: None)
    NO_TEMPERATURE_MODELS.discard("some-new-model")

    class Flaky(BedrockClient):
        def __init__(self):
            self.invoke_timeout = None
            self.calls = []

        def _invoke_converse(self, bedrock_id, prompt, max_tokens, temperature):
            self.calls.append(temperature)
            if temperature is not None:
                raise ClientError(
                    {"Error": {"Code": "ValidationException",
                               "Message": "This model doesn't support the temperature field."}},
                    "Converse",
                )
            return ("x" * 60, {"input_tokens": 1, "output_tokens": 1})

    c = Flaky()
    # route an unknown id through converse
    bc.SUPPORTED_MODELS["some-new-model"] = "someprovider.new-model"
    try:
        text, _ = c.invoke("some-new-model", "p", 1024, 0.0)
        assert text
        assert c.calls == [0.0, None]                  # retried without temp
        assert "some-new-model" in NO_TEMPERATURE_MODELS
    finally:
        bc.SUPPORTED_MODELS.pop("some-new-model", None)
        NO_TEMPERATURE_MODELS.discard("some-new-model")


# ---------------------------------------------------------------------------
# Fix 2: hard wall-clock cap
# ---------------------------------------------------------------------------

def test_wall_clock_cap_raises_on_slow_call():
    c = _Client(invoke_timeout=0.5)

    def slow():
        time.sleep(5)
        return ("x", {})

    t0 = time.monotonic()
    with pytest.raises(InvokeTimeout):
        c._call_with_wall_clock_cap(slow)
    assert time.monotonic() - t0 < 3     # returned promptly at the cap, not 5s


def test_wall_clock_cap_passes_fast_call():
    c = _Client(invoke_timeout=5)
    out = c._call_with_wall_clock_cap(lambda: ("ok", {"input_tokens": 1}))
    assert out[0] == "ok"


def test_wall_clock_cap_propagates_inner_error():
    c = _Client(invoke_timeout=5)

    def boom():
        raise ValueError("inner")

    with pytest.raises(ValueError):
        c._call_with_wall_clock_cap(boom)


def test_cap_disabled_when_none():
    c = _Client(invoke_timeout=None)
    out = c._call_with_wall_clock_cap(lambda: ("ok", {}))
    assert out[0] == "ok"
