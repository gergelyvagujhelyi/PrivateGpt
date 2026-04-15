from __future__ import annotations

from datetime import datetime

from .agent import SYSTEM_PROMPT, summarise as _agent_summarise  # noqa: F401

__all__ = ["SYSTEM_PROMPT", "summarise"]


def summarise(user_id: str, since: datetime) -> str:
    return _agent_summarise(user_id, since)
