"""RAG ingestion worker.

Runs as a scheduled Container Apps Job. Each invocation:
  1. Lists blobs in BLOB_CONTAINER whose "namespace/<key>" prefix matches.
  2. Skips anything already ingested at its current etag.
  3. Extracts text, chunks, embeds via LiteLLM, writes to pgvector.
  4. Langfuse observes the embedding calls (LiteLLM success_callback).
"""

from __future__ import annotations

import os
import sys

import structlog
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

from .chunk import chunk
from .embed import embed_batch
from .extract import UnsupportedFormat, extract_text
from .migrations import ensure_schema
from .store import connect, is_already_ingested, upsert_source, write_chunks

log = structlog.get_logger()

BLOB_ACCOUNT_URL = os.environ["BLOB_ACCOUNT_URL"]
BLOB_CONTAINER = os.environ["BLOB_CONTAINER"]
DATABASE_URL = os.environ["DATABASE_URL"]
NAMESPACE_PREFIX = os.environ.get("NAMESPACE_PREFIX", "")


def _namespace_for(name: str) -> tuple[str, str]:
    """Blob name "<namespace>/<path>" → (namespace, rest)."""
    parts = name.split("/", 1)
    if len(parts) == 1:
        return "default", parts[0]
    return parts[0], parts[1]


def run() -> int:
    cred = DefaultAzureCredential()
    bsc = BlobServiceClient(account_url=BLOB_ACCOUNT_URL, credential=cred)
    container = bsc.get_container_client(BLOB_CONTAINER)

    ingested = skipped = errored = 0

    with connect(DATABASE_URL) as conn:
        ensure_schema(conn)
        conn.commit()

        for blob in container.list_blobs(include=["metadata"]):
            if NAMESPACE_PREFIX and not blob.name.startswith(NAMESPACE_PREFIX):
                continue
            bound = log.bind(blob=blob.name, etag=blob.etag)
            try:
                namespace, _ = _namespace_for(blob.name)
                if is_already_ingested(conn, namespace, blob.name, blob.etag):
                    skipped += 1
                    continue

                data = container.download_blob(blob.name).readall()
                try:
                    text = extract_text(blob.name, blob.content_settings.content_type or "", data)
                except UnsupportedFormat as exc:
                    bound.warning("skip_unsupported", error=str(exc))
                    skipped += 1
                    continue

                chunks = chunk(text)
                if not chunks:
                    bound.info("skip_empty_after_chunking")
                    skipped += 1
                    continue

                vectors = embed_batch(chunks)
                source_id = upsert_source(
                    conn,
                    namespace=namespace,
                    uri=blob.name,
                    etag=blob.etag,
                    content_type=blob.content_settings.content_type,
                    byte_size=blob.size,
                )
                rows = (
                    (i, text_chunk, vec, {"source": blob.name})
                    for i, (text_chunk, vec) in enumerate(zip(chunks, vectors))
                )
                n = write_chunks(conn, source_id, namespace, rows)
                conn.commit()
                bound.info("ingested", chunks=n, namespace=namespace)
                ingested += 1
            except Exception as exc:  # noqa: BLE001
                conn.rollback()
                bound.exception("ingest_failed", error=str(exc))
                errored += 1

    log.info("ingest_run_complete", ingested=ingested, skipped=skipped, errored=errored)
    return 1 if errored and not ingested else 0


if __name__ == "__main__":
    sys.exit(run())
