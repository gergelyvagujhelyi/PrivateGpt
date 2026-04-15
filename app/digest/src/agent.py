"""Tool-calling digest agent.

A small, explicit loop — no framework. The agent sees only the tool schemas
and the window it's asked to summarise. It decides which tools to call, in
what order, and composes the final user-facing summary.

Langfuse captures the full trace (tool calls, tool results, final message)
because LiteLLM's langfuse success_callback is enabled in config.yaml.
"""

from __future__ import annotations

import functools
import json
import os
import time
from datetime import datetime

import structlog
from openai import OpenAI

from .tools import TOOLS, call_tool

log = structlog.get_logger()

MAX_STEPS = 6      # hard cap — prevents pathological loops
MODEL = "claude-haiku-4-5"

SYSTEM_PROMPT = (
    "You write a short, friendly weekly or daily recap of a user's AI assistant usage. "
    "Use the provided tools to retrieve chat titles and usage stats — never guess. "
    "When you have enough context, produce 3 to 5 bullets covering topics and outcomes. "
    "Never echo raw prompts. Never include personal data, email addresses, or credentials. "
    "If the user had no activity, say they had a quiet period. "
    "Stop calling tools once you have what you need."
)


@functools.lru_cache(maxsize=1)
def _client() -> OpenAI:
    return OpenAI(
        base_url=os.environ["OPENAI_BASE_URL"],
        api_key=os.environ["OPENAI_API_KEY"],
    )


def summarise(user_id: str, since: datetime) -> str:
    """Run the agent loop and return the final summary."""
    messages: list[dict] = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {
            "role": "user",
            "content": (
                f"Summarise assistant activity for user_id={user_id} since "
                f"{since.isoformat()}. Call the tools to get data, then write the recap."
            ),
        },
    ]

    for step in range(MAX_STEPS):
        t0 = time.monotonic()
        resp = _client().chat.completions.create(
            model=MODEL,
            temperature=0,
            user=f"digest-agent-{user_id}",
            messages=messages,
            tools=TOOLS,
            tool_choice="auto",
        )
        msg = resp.choices[0].message
        log.debug(
            "agent_step",
            step=step, user_id=user_id,
            tool_calls=len(msg.tool_calls or []),
            elapsed_ms=int((time.monotonic() - t0) * 1000),
        )

        if not msg.tool_calls:
            return (msg.content or "").strip()

        # Preserve the assistant turn verbatim so the model sees its own tool_calls.
        messages.append({
            "role": "assistant",
            "content": msg.content,
            "tool_calls": [
                {
                    "id": tc.id,
                    "type": "function",
                    "function": {"name": tc.function.name, "arguments": tc.function.arguments},
                }
                for tc in msg.tool_calls
            ],
        })

        for tc in msg.tool_calls:
            result = call_tool(tc.function.name, tc.function.arguments)
            messages.append({
                "role": "tool",
                "tool_call_id": tc.id,
                "content": result,
            })

    raise RuntimeError(f"digest agent exceeded {MAX_STEPS} steps for user {user_id}")
