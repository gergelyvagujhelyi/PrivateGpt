"""Document extractors. Returns plain text from common formats."""

from __future__ import annotations

import io

from docx import Document
from pypdf import PdfReader

MAX_INPUT_BYTES = 50 * 1024 * 1024
MAX_OUTPUT_CHARS = 5 * 1024 * 1024


class UnsupportedFormat(Exception):
    pass


class InputTooLarge(Exception):
    pass


def extract_text(blob_name: str, content_type: str, data: bytes) -> str:
    if len(data) > MAX_INPUT_BYTES:
        raise InputTooLarge(
            f"{blob_name}: {len(data)} bytes exceeds {MAX_INPUT_BYTES}"
        )
    lower = blob_name.lower()
    if lower.endswith(".pdf") or content_type == "application/pdf":
        reader = PdfReader(io.BytesIO(data))
        text = "\n\n".join((p.extract_text() or "") for p in reader.pages)
    elif lower.endswith(".docx"):
        doc = Document(io.BytesIO(data))
        text = "\n".join(p.text for p in doc.paragraphs if p.text)
    elif lower.endswith((".txt", ".md")) or content_type.startswith("text/"):
        text = data.decode("utf-8", errors="replace")
    else:
        raise UnsupportedFormat(f"no extractor for {blob_name} ({content_type})")
    return text[:MAX_OUTPUT_CHARS]
