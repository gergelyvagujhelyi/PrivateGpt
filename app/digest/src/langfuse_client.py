from __future__ import annotations

import functools
import os
from dataclasses import dataclass, field
from datetime import datetime

from langfuse import Langfuse


@functools.lru_cache(maxsize=1)
def _client() -> Langfuse:
    return Langfuse(
        host=os.environ["LANGFUSE_HOST"],
        public_key=os.environ["LANGFUSE_PUBLIC_KEY"],
        secret_key=os.environ["LANGFUSE_SECRET_KEY"],
    )


@dataclass
class Stats:
    trace_count: int = 0
    total_tokens: int = 0
    cost_usd: float = 0.0
    top_models: list[tuple[str, int]] = field(default_factory=list)


@dataclass
class Activity:
    traces: list[dict]
    stats: Stats


def fetch_user_activity(user_id: str, since: datetime) -> Activity:
    page = _client().api.trace.list(user_id=user_id, from_timestamp=since, limit=200)
    traces = page.data
    model_counts: dict[str, int] = {}
    tokens = 0
    cost = 0.0

    titles: list[dict] = []
    for t in traces:
        tokens += getattr(t, "total_tokens", 0) or 0
        cost += getattr(t, "total_cost", 0.0) or 0.0
        model = getattr(t, "model", None) or "unknown"
        model_counts[model] = model_counts.get(model, 0) + 1
        titles.append({
            "name": t.name or "conversation",
            "tags": t.tags or [],
        })

    top = sorted(model_counts.items(), key=lambda kv: kv[1], reverse=True)[:3]

    return Activity(
        traces=titles,
        stats=Stats(trace_count=len(traces), total_tokens=tokens, cost_usd=cost, top_models=top),
    )
