"""Document extractors. Returns plain text from common formats."""

from __future__ import annotations

import io

from docx import Document
from pypdf import PdfReader


class UnsupportedFormat(Exception):
    pass


def extract_text(blob_name: str, content_type: str, data: bytes) -> str:
    lower = blob_name.lower()
    if lower.endswith(".pdf") or content_type == "application/pdf":
        reader = PdfReader(io.BytesIO(data))
        return "\n\n".join((p.extract_text() or "") for p in reader.pages)
    if lower.endswith(".docx"):
        doc = Document(io.BytesIO(data))
        return "\n".join(p.text for p in doc.paragraphs if p.text)
    if lower.endswith((".txt", ".md")) or content_type.startswith("text/"):
        return data.decode("utf-8", errors="replace")
    raise UnsupportedFormat(f"no extractor for {blob_name} ({content_type})")
