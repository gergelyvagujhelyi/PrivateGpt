"""Regression guard for H1: the digest email template must HTML-escape the
LLM-produced summary. If someone ever reintroduces `| safe` or templates the
summary without escaping, these tests fail."""

from __future__ import annotations

from markupsafe import Markup, escape

from src.main import tmpl_env


def _render(summary: str) -> str:
    summary_html = Markup("<br>\n").join(escape(line) for line in summary.split("\n"))
    return tmpl_env.get_template("digest.html.j2").render(
        name="Alice",
        window="daily",
        unsub_url="https://example.test/unsubscribe?t=tok",
        summary_html=summary_html,
        stats={"trace_count": 1, "total_tokens": 100, "top_models": []},
    )


def test_escapes_script_tag_in_summary():
    html = _render("<script>alert(1)</script>")
    assert "<script>" not in html
    assert "&lt;script&gt;alert(1)&lt;/script&gt;" in html


def test_escapes_anchor_tag_in_summary():
    html = _render('click <a href="https://phish.example">here</a>')
    assert '<a href="https://phish.example">' not in html
    assert "&lt;a href=" in html


def test_preserves_multiline_with_br():
    html = _render("line one\nline two")
    assert "line one<br>\nline two" in html
