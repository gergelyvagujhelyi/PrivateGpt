"""Unit tests for the tool-calling agent loop.

The Claude-facing client is fully stubbed; we assert that the loop drives
tools, feeds results back, and terminates with the model's final text.
"""

from __future__ import annotations

import json
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from src import agent, tools


def _msg(content=None, tool_calls=None):
    return SimpleNamespace(
        content=content,
        tool_calls=[
            SimpleNamespace(
                id=tc["id"],
                function=SimpleNamespace(name=tc["name"], arguments=json.dumps(tc["args"])),
            )
            for tc in (tool_calls or [])
        ] or None,
    )


def _resp(msg):
    return SimpleNamespace(choices=[SimpleNamespace(message=msg)])


@pytest.fixture
def stub_llm(monkeypatch: pytest.MonkeyPatch) -> MagicMock:
    mock = MagicMock()
    monkeypatch.setattr(agent, "_client", lambda: mock)
    return mock


@pytest.fixture(autouse=True)
def stub_tools(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(
        tools, "_get_chat_titles",
        lambda user_id, since_iso, limit=30: {
            "count": 2,
            "items": [{"title": "draft email", "tags": []}, {"title": "debug script", "tags": []}],
        },
    )
    monkeypatch.setattr(
        tools, "_get_usage_stats",
        lambda user_id, since_iso: {
            "trace_count": 2, "total_tokens": 412, "cost_usd": 0.01,
            "top_models": [{"name": "claude-haiku-4-5", "count": 2}],
        },
    )


def test_agent_calls_tools_then_composes_summary(stub_llm: MagicMock):
    stub_llm.chat.completions.create.side_effect = [
        _resp(_msg(tool_calls=[
            {"id": "c1", "name": "get_chat_titles", "args": {"user_id": "u1", "since_iso": "2026-04-14T00:00:00+00:00"}},
            {"id": "c2", "name": "get_usage_stats", "args": {"user_id": "u1", "since_iso": "2026-04-14T00:00:00+00:00"}},
        ])),
        _resp(_msg(content="- drafted an email\n- debugged a script\n- 2 conversations, 412 tokens")),
    ]

    from datetime import datetime, timezone
    out = agent.summarise("u1", datetime(2026, 4, 14, tzinfo=timezone.utc))

    assert "drafted" in out
    assert stub_llm.chat.completions.create.call_count == 2

    # Second call must include the tool results so the model can compose.
    second = stub_llm.chat.completions.create.call_args_list[1].kwargs["messages"]
    roles = [m["role"] for m in second]
    assert roles.count("tool") == 2
    assert "412" in json.dumps(second)


def test_agent_bails_after_max_steps(stub_llm: MagicMock, monkeypatch):
    monkeypatch.setattr(agent, "MAX_STEPS", 2)
    # Model forever asks for more tool calls.
    stub_llm.chat.completions.create.return_value = _resp(_msg(tool_calls=[
        {"id": "c", "name": "get_chat_titles", "args": {"user_id": "u", "since_iso": "2026-04-14T00:00:00+00:00"}},
    ]))
    from datetime import datetime, timezone
    with pytest.raises(RuntimeError, match="exceeded"):
        agent.summarise("u", datetime(2026, 4, 14, tzinfo=timezone.utc))


def test_agent_returns_empty_when_model_returns_no_tools_no_content(stub_llm: MagicMock):
    stub_llm.chat.completions.create.return_value = _resp(_msg(content=""))
    from datetime import datetime, timezone
    out = agent.summarise("u", datetime(2026, 4, 14, tzinfo=timezone.utc))
    assert out == ""
