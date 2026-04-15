from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from src import embed


@pytest.fixture
def stub_llm(monkeypatch: pytest.MonkeyPatch) -> MagicMock:
    mock = MagicMock()
    monkeypatch.setattr(embed, "_client", lambda: mock)
    return mock


def test_batches_inputs(stub_llm: MagicMock):
    def _respond(**kwargs):
        n = len(kwargs["input"])
        return SimpleNamespace(
            data=[SimpleNamespace(embedding=[0.0] * embed.EMBEDDING_DIM) for _ in range(n)]
        )
    stub_llm.embeddings.create.side_effect = _respond
    texts = ["t"] * (embed.BATCH * 2 + 3)
    vectors = embed.embed_batch(texts)

    # Called three times: two full batches + one partial.
    assert stub_llm.embeddings.create.call_count == 3
    assert len(vectors) == len(texts)


def test_dim_mismatch_raises(stub_llm: MagicMock):
    stub_llm.embeddings.create.return_value = SimpleNamespace(
        data=[SimpleNamespace(embedding=[0.0] * (embed.EMBEDDING_DIM - 1))]
    )
    with pytest.raises(RuntimeError, match="embedding dim mismatch"):
        embed.embed_batch(["t"])
