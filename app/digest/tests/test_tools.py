"""Contract tests for the tool dispatcher."""

from __future__ import annotations

import json

import pytest

from src import tools


def test_unknown_tool_returns_error():
    out = tools.call_tool("nonsense", "{}")
    assert json.loads(out) == {"error": "unknown tool: nonsense"}


def test_bad_json_returns_error():
    out = tools.call_tool("get_chat_titles", "not-json")
    assert "error" in json.loads(out)


def test_dispatches_to_registered(monkeypatch):
    monkeypatch.setattr(tools, "_get_chat_titles",
                        lambda user_id, since_iso, limit=30: {"count": 0, "items": []})
    monkeypatch.setattr(tools, "_REGISTRY",
                        {"get_chat_titles": tools._get_chat_titles})

    out = json.loads(tools.call_tool(
        "get_chat_titles",
        json.dumps({"user_id": "u", "since_iso": "2026-04-14T00:00:00+00:00"}),
    ))
    assert out == {"count": 0, "items": []}


def test_tool_schemas_are_valid_json_schema():
    for tool in tools.TOOLS:
        assert tool["type"] == "function"
        fn = tool["function"]
        assert "name" in fn and "description" in fn and "parameters" in fn
        assert fn["parameters"]["type"] == "object"
