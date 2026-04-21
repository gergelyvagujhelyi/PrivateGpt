from __future__ import annotations

from collections.abc import Iterable

import psycopg
from pgvector.psycopg import register_vector


def connect(database_url: str) -> psycopg.Connection:
    conn = psycopg.connect(database_url)
    register_vector(conn)
    return conn


def is_already_ingested(conn: psycopg.Connection, namespace: str, uri: str, etag: str) -> bool:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT 1 FROM rag_sources WHERE namespace=%s AND source_uri=%s AND etag=%s",
            (namespace, uri, etag),
        )
        return cur.fetchone() is not None


def upsert_source(
    conn: psycopg.Connection,
    namespace: str,
    uri: str,
    etag: str,
    content_type: str | None,
    byte_size: int,
) -> str:
    with conn.cursor() as cur:
        # Replace any previous version of this uri in the namespace.
        cur.execute(
            "DELETE FROM rag_sources WHERE namespace=%s AND source_uri=%s",
            (namespace, uri),
        )
        cur.execute(
            """
            INSERT INTO rag_sources (namespace, source_uri, etag, content_type, byte_size)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING id
            """,
            (namespace, uri, etag, content_type, byte_size),
        )
        row = cur.fetchone()
        assert row is not None, "INSERT ... RETURNING id must produce one row"
        return row[0]


def write_chunks(
    conn: psycopg.Connection,
    source_id: str,
    namespace: str,
    rows: Iterable[tuple[int, str, list[float], dict]],
) -> int:
    with conn.cursor() as cur, cur.copy(
        "COPY rag_chunks (source_id, namespace, chunk_index, content, embedding, metadata) "
        "FROM STDIN (FORMAT BINARY)"
    ) as copy:
        import json

        copy.set_types(["uuid", "text", "int4", "text", "vector", "jsonb"])
        n = 0
        for idx, text, vec, meta in rows:
            copy.write_row((source_id, namespace, idx, text, vec, json.dumps(meta)))
            n += 1
    return n


def similarity_search(
    conn: psycopg.Connection,
    namespace: str,
    query_vec: list[float],
    top_k: int = 5,
) -> list[dict]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT c.content,
                   c.metadata,
                   s.source_uri,
                   1 - (c.embedding <=> %s::vector) AS score
              FROM rag_chunks c
              JOIN rag_sources s ON s.id = c.source_id
             WHERE c.namespace = %s
          ORDER BY c.embedding <=> %s::vector
             LIMIT %s
            """,
            (query_vec, namespace, query_vec, top_k),
        )
        return [
            {"content": row[0], "metadata": row[1], "source_uri": row[2], "score": float(row[3])}
            for row in cur.fetchall()
        ]
