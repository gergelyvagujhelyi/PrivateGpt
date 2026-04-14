"""Shared fixtures. Ensures the src package is importable and env defaults exist."""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

# Make `src` importable without installing the package.
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))


@pytest.fixture(autouse=True)
def _baseline_env(monkeypatch: pytest.MonkeyPatch) -> None:
    """Provide deterministic env defaults so modules importing os.environ don't blow up."""
    defaults = {
        "CADENCE": "daily",
        "UNSUB_HMAC_KEY": "unit-test-hmac",
        "PUBLIC_BASE_URL": "https://example.test",
        "LANGFUSE_HOST": "http://langfuse.test",
        "LANGFUSE_PUBLIC_KEY": "pk",
        "LANGFUSE_SECRET_KEY": "sk",
        "OPENAI_BASE_URL": "http://litellm.test/v1",
        "OPENAI_API_KEY": "sk-test",
        "ACS_CONNECTION_STRING": "endpoint=https://acs.test/;accesskey=dGVzdA==",
        "ACS_SENDER": "assistant@acs.test",
    }
    for k, v in defaults.items():
        monkeypatch.setenv(k, v)

    # lru_cache in lazy clients would leak state across tests.
    from src import langfuse_client, summariser
    langfuse_client._client.cache_clear()
    summariser._client.cache_clear()
