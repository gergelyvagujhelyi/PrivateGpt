"""Tool implementations exposed to the digest agent.

Each tool is pure data retrieval — no summarisation. The agent (Claude) decides
what to fetch and in what order, then composes the final summary from the
results. Keeping tools narrow makes the agent's behaviour easy to audit in
Langfuse traces.
"""

from __future__ import annotations

import json
from datetime import datetime
from typing import Any, Callable

from .langfuse_client import _client as _lf_client

# JSON Schemas registered with the LLM (OpenAI tool-calling format — LiteLLM
# translates to Anthropic tool_use for the azure_ai/claude-* route).
TOOLS: list[dict[str, Any]] = [
    {
        "type": "function",
        "function": {
            "name": "get_chat_titles",
            "description": (
                "Return the titles and tags of the user's conversations in a "
                "time window. Titles are short, user-facing; never return raw "
                "prompt bodies."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "user_id":   {"type": "string"},
                    "since_iso": {"type": "string", "description": "Window start, ISO 8601"},
                    "limit":     {"type": "integer", "default": 30, "minimum": 1, "maximum": 100},
                },
                "required": ["user_id", "since_iso"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_usage_stats",
            "description": (
                "Return aggregate stats: trace count, total tokens, cost in USD, "
                "and top models for a user in a window."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "user_id":   {"type": "string"},
                    "since_iso": {"type": "string"},
                },
                "required": ["user_id", "since_iso"],
            },
        },
    },
]


def _get_chat_titles(user_id: str, since_iso: str, limit: int = 30) -> dict[str, Any]:
    since = datetime.fromisoformat(since_iso)
    page = _lf_client().api.trace.list(user_id=user_id, from_timestamp=since, limit=limit)
    return {
        "count": len(page.data),
        "items": [
            {"title": t.name or "conversation", "tags": t.tags or []}
            for t in page.data
        ],
    }


def _get_usage_stats(user_id: str, since_iso: str) -> dict[str, Any]:
    since = datetime.fromisoformat(since_iso)
    page = _lf_client().api.trace.list(user_id=user_id, from_timestamp=since, limit=500)
    tokens = 0
    cost = 0.0
    models: dict[str, int] = {}
    for t in page.data:
        tokens += getattr(t, "total_tokens", 0) or 0
        cost += getattr(t, "total_cost", 0.0) or 0.0
        m = getattr(t, "model", None) or "unknown"
        models[m] = models.get(m, 0) + 1
    top = sorted(models.items(), key=lambda kv: kv[1], reverse=True)[:3]
    return {
        "trace_count": len(page.data),
        "total_tokens": tokens,
        "cost_usd": round(cost, 4),
        "top_models": [{"name": n, "count": c} for n, c in top],
    }


_REGISTRY: dict[str, Callable[..., dict[str, Any]]] = {
    "get_chat_titles": _get_chat_titles,
    "get_usage_stats": _get_usage_stats,
}


def call_tool(name: str, arguments_json: str) -> str:
    """Dispatch a tool call and return its JSON-serialised result."""
    fn = _REGISTRY.get(name)
    if fn is None:
        return json.dumps({"error": f"unknown tool: {name}"})
    try:
        args = json.loads(arguments_json or "{}")
        result = fn(**args)
        return json.dumps(result)
    except Exception as exc:  # noqa: BLE001
        return json.dumps({"error": str(exc)})
