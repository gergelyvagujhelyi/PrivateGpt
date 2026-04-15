"""Contract tests for the tool dispatcher."""

from __future__ import annotations

import json

import pytest

from src import tools


def test_unknown_tool_returns_structured_error():
    out = json.loads(tools.call_tool("nonsense", "{}"))
    assert out == {"error_code": "unknown_tool", "name": "nonsense"}


def test_bad_json_returns_correlated_error():
    out = json.loads(tools.call_tool("get_chat_titles", "not-json"))
    assert out["error_code"] == "tool_failed"
    assert "correlation_id" in out


def test_tool_exception_does_not_leak_message(monkeypatch: pytest.MonkeyPatch):
    def boom(**_kwargs):
        raise RuntimeError("postgres password auth failed for user admin")
    monkeypatch.setattr(tools, "_get_chat_titles", boom)

    out = json.loads(tools.call_tool(
        "get_chat_titles",
        json.dumps({"user_id": "u", "since_iso": "2026-04-14T00:00:00+00:00"}),
    ))

    assert out["error_code"] == "tool_failed"
    assert "postgres" not in json.dumps(out)
    assert "password" not in json.dumps(out)


def test_monkeypatch_flows_through_without_registry_rebuild(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(
        tools, "_get_chat_titles",
        lambda user_id, since_iso, limit=30: {"count": 0, "items": []},
    )
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
