from __future__ import annotations

from langchain_text_splitters import RecursiveCharacterTextSplitter

_splitter = RecursiveCharacterTextSplitter(
    chunk_size=1000,
    chunk_overlap=150,
    separators=["\n\n", "\n", ". ", " ", ""],
    length_function=len,
)


def chunk(text: str) -> list[str]:
    return [c.strip() for c in _splitter.split_text(text) if c.strip()]
