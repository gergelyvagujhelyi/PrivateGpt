"""End-to-end run() test against a real Postgres (Testcontainers),
with Langfuse + LLM + ACS stubbed out. Exercises:
  - schema migration
  - selection by cadence + opt-out
  - last_sent_at idempotency
  - per-user error isolation
"""

from __future__ import annotations

from datetime import UTC, datetime
from unittest.mock import MagicMock

import psycopg
import pytest

from src import main
from src.langfuse_client import Activity, Stats

pytestmark = pytest.mark.integration

try:
    from testcontainers.postgres import PostgresContainer
except ImportError:  # pragma: no cover
    PostgresContainer = None  # type: ignore


@pytest.fixture(scope="module")
def pg_url():
    assert PostgresContainer is not None
    with PostgresContainer("postgres:16-alpine") as pg:
        yield pg.get_connection_url().replace("postgresql+psycopg2://", "postgresql://")


@pytest.fixture
def seeded_db(pg_url: str, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("DATABASE_URL", pg_url)
    monkeypatch.setattr(main, "DATABASE_URL", pg_url)

    with psycopg.connect(pg_url) as conn:
        with conn.cursor() as cur:
            cur.execute('DROP TABLE IF EXISTS "user"')
            cur.execute('DROP TABLE IF EXISTS user_preferences')
            cur.execute('DROP TABLE IF EXISTS digest_migrations')
            cur.execute("""
                CREATE TABLE "user" (
                    id TEXT PRIMARY KEY,
                    email TEXT NOT NULL,
                    name TEXT NOT NULL
                )
            """)
        conn.commit()

    return pg_url


def _seed_user(pg_url: str, user_id: str, email: str, freq: str, unsub: bool = False) -> None:
    with psycopg.connect(pg_url) as conn, conn.cursor() as cur:
        cur.execute(
            'INSERT INTO "user" (id, email, name) VALUES (%s, %s, %s) ON CONFLICT DO NOTHING',
            (user_id, email, f"User {user_id}"),
        )
        cur.execute(
            """
            INSERT INTO user_preferences (user_id, digest_frequency, unsubscribed_at)
            VALUES (%s, %s, %s)
            ON CONFLICT (user_id) DO UPDATE
              SET digest_frequency = EXCLUDED.digest_frequency,
                  unsubscribed_at  = EXCLUDED.unsubscribed_at,
                  last_sent_at     = NULL
            """,
            (user_id, freq, datetime.now(UTC) if unsub else None),
        )
        conn.commit()


@pytest.fixture
def stubbed_externals(monkeypatch: pytest.MonkeyPatch):
    activity = Activity(
        traces=[{"name": "draft email", "tags": []}],
        stats=Stats(trace_count=1, total_tokens=100, cost_usd=0.01),
    )
    monkeypatch.setattr(main, "fetch_user_activity", lambda user_id, since: activity)
    monkeypatch.setattr(main, "summarise", lambda activity: "- worked on email drafting")

    sender = MagicMock()
    monkeypatch.setattr(main, "EmailSender", lambda: sender)
    return sender


def test_sends_to_opted_in_user_and_is_idempotent(seeded_db, stubbed_externals):
    _seed_user(seeded_db, "u-active", "active@example.test", "daily")
    _seed_user(seeded_db, "u-weekly", "weekly@example.test", "weekly")
    _seed_user(seeded_db, "u-unsub", "unsub@example.test", "daily", unsub=True)

    assert main.run() == 0
    assert stubbed_externals.send.call_count == 1
    assert stubbed_externals.send.call_args.kwargs["to"] == "active@example.test"

    # Immediate re-run: already sent in window, nothing new.
    stubbed_externals.send.reset_mock()
    assert main.run() == 0
    assert stubbed_externals.send.call_count == 0


def test_skips_users_with_no_activity(seeded_db, stubbed_externals, monkeypatch):
    _seed_user(seeded_db, "u-idle", "idle@example.test", "daily")

    monkeypatch.setattr(
        main, "fetch_user_activity",
        lambda user_id, since: Activity(traces=[], stats=Stats()),
    )
    assert main.run() == 0
    assert stubbed_externals.send.call_count == 0


def test_one_user_failure_does_not_abort_run(seeded_db, stubbed_externals, monkeypatch):
    _seed_user(seeded_db, "u-ok", "ok@example.test", "daily")
    _seed_user(seeded_db, "u-broken", "broken@example.test", "daily")

    original_send = stubbed_externals.send

    def flaky(**kwargs):
        if kwargs["to"] == "broken@example.test":
            raise RuntimeError("ACS down")
        return original_send(**kwargs)

    stubbed_externals.send.side_effect = flaky

    rc = main.run()
    # At least one success → exit 0 per main.run() contract.
    assert rc == 0
    sent_to = {c.kwargs["to"] for c in stubbed_externals.send.call_args_list if c.kwargs}
    assert "ok@example.test" in sent_to
