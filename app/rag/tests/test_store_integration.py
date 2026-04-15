"""Integration tests against a real Postgres with pgvector.

Uses Testcontainers; requires Docker. Covers: migrations, source upsert,
chunk writes via COPY BINARY, similarity search ordering.
"""

from __future__ import annotations

import pytest

from src.embed import EMBEDDING_DIM
from src.migrations import ensure_schema
from src.store import (
    connect,
    is_already_ingested,
    similarity_search,
    upsert_source,
    write_chunks,
)

pytestmark = pytest.mark.integration

try:
    from testcontainers.postgres import PostgresContainer
except ImportError:  # pragma: no cover
    PostgresContainer = None  # type: ignore


@pytest.fixture(scope="module")
def pg_url():
    assert PostgresContainer is not None
    with PostgresContainer("pgvector/pgvector:pg16") as pg:
        yield pg.get_connection_url().replace("postgresql+psycopg2://", "postgresql://")


def _vec(bias: float) -> list[float]:
    return [bias] + [0.0] * (EMBEDDING_DIM - 1)


def test_ingest_and_search_roundtrip(pg_url: str):
    with connect(pg_url) as conn:
        ensure_schema(conn)
        conn.commit()

        assert not is_already_ingested(conn, "default", "doc.txt", "etag1")
        sid = upsert_source(conn, "default", "doc.txt", "etag1", "text/plain", 42)
        n = write_chunks(
            conn, sid, "default",
            [
                (0, "about cats", _vec(1.0), {"topic": "cats"}),
                (1, "about dogs", _vec(0.5), {"topic": "dogs"}),
                (2, "about fish", _vec(0.0), {"topic": "fish"}),
            ],
        )
        conn.commit()
        assert n == 3
        assert is_already_ingested(conn, "default", "doc.txt", "etag1")

        hits = similarity_search(conn, "default", _vec(1.0), top_k=2)
        assert len(hits) == 2
        assert hits[0]["content"] == "about cats"  # exact match ranks first
        assert hits[0]["score"] > hits[1]["score"]


def test_reingest_same_uri_replaces_previous_version(pg_url: str):
    with connect(pg_url) as conn:
        ensure_schema(conn)
        conn.commit()

        sid1 = upsert_source(conn, "ns2", "doc.txt", "v1", "text/plain", 10)
        write_chunks(conn, sid1, "ns2", [(0, "v1 content", _vec(1.0), {})])
        conn.commit()

        sid2 = upsert_source(conn, "ns2", "doc.txt", "v2", "text/plain", 20)
        write_chunks(conn, sid2, "ns2", [(0, "v2 content", _vec(0.9), {})])
        conn.commit()

        hits = similarity_search(conn, "ns2", _vec(1.0), top_k=5)
        contents = [h["content"] for h in hits]
        assert "v2 content" in contents
        assert "v1 content" not in contents


def test_namespace_isolation(pg_url: str):
    with connect(pg_url) as conn:
        ensure_schema(conn)
        conn.commit()

        sid_a = upsert_source(conn, "tenant-a", "x.txt", "ea", None, 0)
        sid_b = upsert_source(conn, "tenant-b", "x.txt", "eb", None, 0)
        write_chunks(conn, sid_a, "tenant-a", [(0, "a-side", _vec(1.0), {})])
        write_chunks(conn, sid_b, "tenant-b", [(0, "b-side", _vec(1.0), {})])
        conn.commit()

        a = similarity_search(conn, "tenant-a", _vec(1.0), top_k=10)
        b = similarity_search(conn, "tenant-b", _vec(1.0), top_k=10)
        assert all(h["content"] == "a-side" for h in a)
        assert all(h["content"] == "b-side" for h in b)
