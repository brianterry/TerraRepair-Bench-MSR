"""
Tests for BedrockClient._extract_converse_text across the Converse content-block
shapes that reasoning models (grok-4-6, deepseek-r1, claude-sonnet-5) produce.

Background: reasoning models return chain-of-thought in a SEPARATE block from
the answer. On Converse that is a ``reasoningContent`` block; depending on the
botocore version it may instead surface as the opaque ``SDK_UNKNOWN_MEMBER``
placeholder. An unpinned SDK let the container build with a version that routed
grok's answer/reasoning differently than the tested SDK, and the old extractor's
"fall back to reasoning text when no text block" behavior turned that into HCL —
inflating grok-4-6's failure rate (92 "empty after sanitization" + 34 "failed
HCL validation").

The hardened extractor returns ONLY concatenated ``text`` blocks and never falls
back to reasoning. These tests pin that contract for every shape we have observed
live:
  - text-only (non-reasoning models)
  - text + SDK_UNKNOWN_MEMBER (grok-4-6 / deepseek-r1 on the tested SDK)
  - text + reasoningContent (newer SDK that maps the reasoning member)
  - reasoning-only (no answer) -> returns "" so the caller reports an honest
    empty answer instead of scoring reasoning prose as a repair
"""
from __future__ import annotations

from src.utils.bedrock_client import BedrockClient

_extract = BedrockClient._extract_converse_text

_HCL = 'resource "aws_s3_bucket" "b" {\n  bucket = "x"\n}\n'


def test_text_only():
    blocks = [{"text": _HCL}]
    assert _extract(blocks) == _HCL


def test_text_plus_sdk_unknown_member():
    # Observed live on botocore 1.35.x: reasoning arrives as SDK_UNKNOWN_MEMBER.
    blocks = [{"text": _HCL}, {"SDK_UNKNOWN_MEMBER": {"name": "reasoningContent"}}]
    assert _extract(blocks) == _HCL


def test_sdk_unknown_member_before_text():
    # Order must not matter: reasoning block first, answer second.
    blocks = [{"SDK_UNKNOWN_MEMBER": {"name": "reasoningContent"}}, {"text": _HCL}]
    assert _extract(blocks) == _HCL


def test_text_plus_reasoning_content():
    # Newer SDK that maps the reasoning member explicitly.
    blocks = [
        {"reasoningContent": {"reasoningText": {"text": "Let me think... the bucket needs..."}}},
        {"text": _HCL},
    ]
    got = _extract(blocks)
    assert got == _HCL
    assert "think" not in got, "reasoning must never leak into the answer"


def test_reasoning_only_returns_empty():
    # Model spent its budget reasoning and never emitted an answer. The old code
    # returned the reasoning prose (which then tripped the sanitizer in an
    # SDK-dependent way). Now it must return "" so the caller reports a genuine
    # empty answer.
    blocks = [{"reasoningContent": {"reasoningText": {"text": "long chain of thought with no code"}}}]
    assert _extract(blocks) == ""


def test_sdk_unknown_member_only_returns_empty():
    blocks = [{"SDK_UNKNOWN_MEMBER": {"name": "reasoningContent"}}]
    assert _extract(blocks) == ""


def test_multiple_text_blocks_concatenated():
    blocks = [{"text": "resource \"a\" \"b\" {\n"}, {"text": "}\n"}]
    assert _extract(blocks) == "resource \"a\" \"b\" {\n}\n"


def test_empty_blocks_returns_empty():
    assert _extract([]) == ""
