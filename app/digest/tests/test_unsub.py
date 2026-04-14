from __future__ import annotations

import time

import pytest

from src.unsub import sign_token, verify_token


def test_roundtrip() -> None:
    t = sign_token("user-123")
    assert verify_token(t) == "user-123"


def test_tampered_signature_rejected() -> None:
    t = sign_token("user-123")
    assert verify_token(t[:-4] + "XXXX") is None


def test_mutated_payload_rejected() -> None:
    t = sign_token("user-123")
    # Flip a bit in the middle of the token — signature won't match.
    tampered = t[:4] + ("A" if t[4] != "A" else "B") + t[5:]
    assert verify_token(tampered) is None


def test_expired_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    real_time = time.time
    t = sign_token("user-123", ttl_seconds=1)
    monkeypatch.setattr(time, "time", lambda: real_time() + 10)
    assert verify_token(t) is None


def test_wrong_key_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    t = sign_token("user-123")
    monkeypatch.setenv("UNSUB_HMAC_KEY", "different-key")
    assert verify_token(t) is None


def test_garbage_rejected() -> None:
    assert verify_token("not-a-token") is None
    assert verify_token("") is None
