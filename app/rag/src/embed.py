from __future__ import annotations

import functools
import os

from openai import OpenAI

MODEL = "text-embedding-3-large"
BATCH = 96


@functools.lru_cache(maxsize=1)
def _client() -> OpenAI:
    return OpenAI(
        base_url=os.environ["OPENAI_BASE_URL"],
        api_key=os.environ["OPENAI_API_KEY"],
    )


def embed_batch(texts: list[str]) -> list[list[float]]:
    vectors: list[list[float]] = []
    for i in range(0, len(texts), BATCH):
        resp = _client().embeddings.create(model=MODEL, input=texts[i : i + BATCH])
        vectors.extend(e.embedding for e in resp.data)
    return vectors
