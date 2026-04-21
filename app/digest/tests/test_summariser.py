"""Shim contract: `summariser.summarise(user_id, since)` delegates to the agent
so legacy call sites keep working. Agent internals are tested in test_agent.py."""

from __future__ import annotations

from datetime import UTC, datetime
from unittest.mock import MagicMock

import pytest

from src import summariser


def test_shim_delegates_to_agent(monkeypatch: pytest.MonkeyPatch):
    called = MagicMock(return_value="- recap bullet")
    monkeypatch.setattr(summariser, "_agent_summarise", called)

    out = summariser.summarise("u1", datetime(2026, 4, 14, tzinfo=UTC))

    assert out == "- recap bullet"
    called.assert_called_once()
    args = called.call_args.args
    assert args[0] == "u1"
    assert args[1].year == 2026


def test_exposes_system_prompt():
    assert "Never echo raw prompts" in summariser.SYSTEM_PROMPT
