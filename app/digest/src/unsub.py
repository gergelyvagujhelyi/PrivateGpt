"""HMAC-signed unsubscribe tokens.

The verifier endpoint (on the OpenWebUI sidecar) validates and sets
user_preferences.unsubscribed_at = NOW() on success.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import os
import time


def sign_token(user_id: str, ttl_seconds: int = 30 * 24 * 3600) -> str:
    key = os.environ["UNSUB_HMAC_KEY"].encode()
    exp = int(time.time()) + ttl_seconds
    payload = f"{user_id}.{exp}".encode()
    sig = hmac.new(key, payload, hashlib.sha256).digest()
    token = base64.urlsafe_b64encode(payload + b"." + sig).decode().rstrip("=")
    return token


def verify_token(token: str) -> str | None:
    key = os.environ["UNSUB_HMAC_KEY"].encode()
    padded = token + "=" * (-len(token) % 4)
    try:
        raw = base64.urlsafe_b64decode(padded)
    except ValueError:
        return None
    try:
        payload, sig = raw.rsplit(b".", 1)
        user_id, exp = payload.decode().split(".")
    except ValueError:
        return None
    expected = hmac.new(key, payload, hashlib.sha256).digest()
    if not hmac.compare_digest(sig, expected):
        return None
    if int(exp) < int(time.time()):
        return None
    return user_id
