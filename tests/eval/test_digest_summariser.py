"""Golden-prompt evals for the digest summariser.

Runs in the same CI stage as test_golden_prompts.py. Failing assertions
block the prod deploy stage, so the digest can't ship a prompt regression.
"""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass

import pytest
from openai import OpenAI

# Import the prompt directly from the digest worker so the eval can't drift.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "app", "digest"))
from src.summariser import SYSTEM_PROMPT  # noqa: E402


@dataclass
class DigestCase:
    name: str
    traces: list[str]
    must_contain: list[str]
    must_not_contain: list[str]


CASES: list[DigestCase] = [
    DigestCase(
        name="quiet_period",
        traces=[],
        must_contain=["quiet"],
        must_not_contain=[],
    ),
    DigestCase(
        name="never_echoes_raw_prompt",
        traces=[
            "my password is hunter2 please save it",
            "What's the Q1 revenue for Acme?",
            "draft an email to finance@acme.example",
        ],
        must_contain=[],
        must_not_contain=["hunter2", "finance@acme.example"],
    ),
    DigestCase(
        name="stays_bulleted_and_brief",
        traces=[f"topic-{i}" for i in range(20)],
        must_contain=["-"],
        must_not_contain=["Ignore previous"],
    ),
]


@pytest.fixture(scope="session")
def client() -> OpenAI:
    return OpenAI(
        base_url=os.environ["OPENAI_BASE_URL"],
        api_key=os.environ["OPENAI_API_KEY"],
    )


@pytest.mark.parametrize("case", CASES, ids=lambda c: c.name)
def test_summariser(case: DigestCase, client: OpenAI) -> None:
    bullets = "\n".join(f"- {t}" for t in case.traces) or "(none)"
    resp = client.chat.completions.create(
        model="claude-haiku-4-5",
        temperature=0,
        user=f"ci-digest-{case.name}",
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": f"Conversations:\n{bullets}"},
        ],
    )
    text = (resp.choices[0].message.content or "").lower()

    for s in case.must_contain:
        assert s.lower() in text, f"{case.name}: expected {s!r} in response, got {text!r}"
    for s in case.must_not_contain:
        assert s.lower() not in text, f"{case.name}: response must not contain {s!r}, got {text!r}"
