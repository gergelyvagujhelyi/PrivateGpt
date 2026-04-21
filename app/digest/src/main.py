"""Per-user activity digest worker.

Runs as a scheduled Container Apps Job. Each invocation:
  1. Ensures the user_preferences schema exists (idempotent).
  2. Finds users opted in for CADENCE (daily | weekly).
  3. Pulls usage data from Langfuse + OpenWebUI Postgres for the window.
  4. Summarises via LiteLLM (gpt-4o-mini) with a deterministic prompt.
  5. Sends HTML email via Azure Communication Services.
  6. Updates last_sent_at to enforce idempotency.
"""

from __future__ import annotations

import os
import sys
from datetime import UTC, datetime, timedelta

import psycopg
import structlog
from jinja2 import Environment, FileSystemLoader, select_autoescape

from .agent import summarise
from .email_sender import EmailSender
from .langfuse_client import fetch_user_activity
from .migrations import ensure_schema
from .unsub import sign_token

log = structlog.get_logger()

tmpl_env = Environment(
    loader=FileSystemLoader("templates"),
    autoescape=select_autoescape(["html", "xml"]),
)


def users_to_notify(conn: psycopg.Connection, cadence: str, window: timedelta) -> list[dict]:
    with conn.cursor(row_factory=psycopg.rows.dict_row) as cur:
        cur.execute(
            """
            SELECT u.id, u.email, u.name
            FROM "user" u
            JOIN user_preferences p ON p.user_id = u.id
            WHERE p.digest_frequency = %s
              AND p.unsubscribed_at IS NULL
              AND (p.last_sent_at IS NULL OR p.last_sent_at < NOW() - %s::interval)
            """,
            (cadence, f"{window.days} days"),
        )
        return cur.fetchall()


def mark_sent(conn: psycopg.Connection, user_id: str) -> None:
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE user_preferences SET last_sent_at = NOW() WHERE user_id = %s",
            (user_id,),
        )


def run() -> int:
    cadence = os.environ["CADENCE"]            # "daily" | "weekly"
    window = timedelta(days=1 if cadence == "daily" else 7)
    database_url = os.environ["DATABASE_URL"]
    public_base_url = os.environ["PUBLIC_BASE_URL"]   # e.g. https://assistant.acme.example

    since = datetime.now(UTC) - window
    sender = EmailSender()
    template = tmpl_env.get_template("digest.html.j2")

    sent = skipped = errored = 0

    with psycopg.connect(database_url, autocommit=False) as conn:
        ensure_schema(conn)
        conn.commit()

        for user in users_to_notify(conn, cadence, window):
            bound = log.bind(user_id=str(user["id"]), cadence=cadence)
            try:
                activity = fetch_user_activity(user_id=str(user["id"]), since=since)
                if not activity.traces:
                    bound.info("skip_no_activity")
                    skipped += 1
                    mark_sent(conn, user["id"])
                    conn.commit()
                    continue

                summary = summarise(user_id=str(user["id"]), since=since)
                unsub_url = f"{public_base_url}/unsubscribe?t={sign_token(str(user['id']))}"

                html = template.render(
                    name=user["name"],
                    window=cadence,
                    unsub_url=unsub_url,
                    summary=summary,
                    stats=activity.stats,
                )
                sender.send(
                    to=user["email"],
                    display_name=user["name"],
                    subject=f"Your {cadence} AI assistant summary",
                    html=html,
                    plain=summary,
                )
                mark_sent(conn, user["id"])
                conn.commit()
                bound.info("sent")
                sent += 1
            except Exception as exc:
                conn.rollback()
                bound.exception("digest_failed", error=str(exc))
                errored += 1

    log.info("digest_run_complete", sent=sent, skipped=skipped, errored=errored)
    return 1 if errored and not sent else 0


if __name__ == "__main__":
    sys.exit(run())
