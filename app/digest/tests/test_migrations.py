from __future__ import annotations

import psycopg
import pytest

from src.migrations import ensure_schema

pytestmark = pytest.mark.integration

try:
    from testcontainers.postgres import PostgresContainer
except ImportError:  # pragma: no cover
    PostgresContainer = None  # type: ignore


@pytest.fixture(scope="module")
def pg_url() -> str:
    assert PostgresContainer is not None, "testcontainers not installed"
    with PostgresContainer("postgres:16-alpine") as pg:
        url = pg.get_connection_url().replace("postgresql+psycopg2://", "postgresql://")
        yield url


def test_ensure_schema_is_idempotent(pg_url: str) -> None:
    with psycopg.connect(pg_url) as conn:
        ensure_schema(conn)
        conn.commit()
        ensure_schema(conn)   # run again — must not fail
        conn.commit()

        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM digest_migrations")
            assert cur.fetchone()[0] == 1

            cur.execute(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_name = 'user_preferences' ORDER BY ordinal_position"
            )
            cols = [r[0] for r in cur.fetchall()]
            assert cols == [
                "user_id",
                "digest_frequency",
                "unsubscribed_at",
                "last_sent_at",
                "created_at",
                "updated_at",
            ]
