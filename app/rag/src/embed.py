from __future__ import annotations

import functools
import os

from openai import OpenAI

# Keep in lockstep with migrations/001_rag_chunks.sql:VECTOR(3072).
# If the model changes, the DB schema must change too.
MODEL = "text-embedding-3-large"
EMBEDDING_DIM = 3072
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

    # Fail fast if the model is producing a dim that won't fit the column.
    if vectors and len(vectors[0]) != EMBEDDING_DIM:
        raise RuntimeError(
            f"embedding dim mismatch: model {MODEL} returned {len(vectors[0])}, "
            f"schema expects {EMBEDDING_DIM}. Run a migration before deploying a new model."
        )

    return vectors
