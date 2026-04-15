"""HMAC-signed unsubscribe tokens.

Token format: base64url(payload) + "." + base64url(sig)
base64url never contains '.', so splitting on '.' is unambiguous.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import os
import time


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def _unb64(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def sign_token(user_id: str, ttl_seconds: int = 30 * 24 * 3600) -> str:
    key = os.environ["UNSUB_HMAC_KEY"].encode()
    exp = int(time.time()) + ttl_seconds
    payload = f"{user_id}.{exp}".encode()
    sig = hmac.new(key, payload, hashlib.sha256).digest()
    return f"{_b64(payload)}.{_b64(sig)}"


def verify_token(token: str) -> str | None:
    key = os.environ["UNSUB_HMAC_KEY"].encode()
    parts = token.split(".")
    if len(parts) != 2:
        return None
    try:
        payload = _unb64(parts[0])
        sig = _unb64(parts[1])
    except ValueError:
        return None

    expected = hmac.new(key, payload, hashlib.sha256).digest()
    if not hmac.compare_digest(sig, expected):
        return None

    try:
        user_id, exp = payload.decode().split(".")
    except ValueError:
        return None
    if int(exp) < int(time.time()):
        return None
    return user_id
