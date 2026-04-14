"""Contract test for the summariser — it must use the SYSTEM_PROMPT unchanged
and call LiteLLM with deterministic parameters. We stub the LiteLLM client so
no network is touched; the eval suite covers real-LLM behaviour."""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from src import summariser
from src.langfuse_client import Activity, Stats


@pytest.fixture
def stub_llm(monkeypatch: pytest.MonkeyPatch) -> MagicMock:
    mock = MagicMock()
    mock.chat.completions.create.return_value = SimpleNamespace(
        choices=[SimpleNamespace(message=SimpleNamespace(content="- bullet one\n- bullet two"))]
    )
    monkeypatch.setattr(summariser, "_client", lambda: mock)
    return mock


def test_summariser_uses_system_prompt(stub_llm: MagicMock) -> None:
    activity = Activity(
        traces=[{"name": "draft email", "tags": []}],
        stats=Stats(trace_count=1),
    )
    out = summariser.summarise(activity)
    assert out == "- bullet one\n- bullet two"

    call = stub_llm.chat.completions.create.call_args
    messages = call.kwargs["messages"]
    assert messages[0]["role"] == "system"
    assert messages[0]["content"] == summariser.SYSTEM_PROMPT
    assert call.kwargs["temperature"] == 0
    assert call.kwargs["model"] == "claude-haiku-4-5"


def test_summariser_handles_empty(stub_llm: MagicMock) -> None:
    activity = Activity(traces=[], stats=Stats())
    summariser.summarise(activity)
    user_msg = stub_llm.chat.completions.create.call_args.kwargs["messages"][1]["content"]
    assert "(none)" in user_msg
