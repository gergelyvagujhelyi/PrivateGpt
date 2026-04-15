from __future__ import annotations

from src.chunk import chunk


def test_short_text_returns_single_chunk():
    text = "hello world"
    assert chunk(text) == ["hello world"]


def test_long_text_splits_with_overlap():
    paragraph = "Lorem ipsum dolor sit amet. " * 200
    chunks = chunk(paragraph)
    assert len(chunks) > 1
    for c in chunks:
        assert 1 <= len(c) <= 1200  # chunk_size + some slack for boundary behaviour


def test_drops_empty_chunks():
    # Leading/trailing whitespace-only sections must not leak through as empty chunks.
    text = "\n\n\n\nreal content here\n\n\n"
    chunks = chunk(text)
    assert chunks == ["real content here"]


def test_empty_input_returns_empty_list():
    assert chunk("") == []
    assert chunk("   \n\n ") == []
