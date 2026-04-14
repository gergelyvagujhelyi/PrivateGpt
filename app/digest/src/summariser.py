from __future__ import annotations

import functools
import os

from openai import OpenAI

from .langfuse_client import Activity

SYSTEM_PROMPT = (
    "You write a short, friendly summary of a user's AI assistant usage. "
    "Write 3 to 5 bullets covering topics and outcomes only. "
    "Never echo raw prompts. Never include personal data, email addresses, or credentials. "
    "If the list is empty, say the user had a quiet period."
)


@functools.lru_cache(maxsize=1)
def _client() -> OpenAI:
    return OpenAI(
        base_url=os.environ["OPENAI_BASE_URL"],
        api_key=os.environ["OPENAI_API_KEY"],
    )


def summarise(activity: Activity) -> str:
    bullets = "\n".join(f"- {t['name']}" for t in activity.traces[:30]) or "(none)"
    resp = _client().chat.completions.create(
        model="gpt-4o-mini",
        temperature=0,
        user="digest-worker",
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": f"Conversations:\n{bullets}"},
        ],
    )
    return (resp.choices[0].message.content or "").strip()
