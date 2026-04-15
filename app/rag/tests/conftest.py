from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))


@pytest.fixture(autouse=True)
def _baseline_env(monkeypatch: pytest.MonkeyPatch) -> None:
    defaults = {
        "BLOB_ACCOUNT_URL": "https://blob.test",
        "BLOB_CONTAINER": "rag-sources",
        "DATABASE_URL": "postgresql://owui:owui@localhost/openwebui",
        "NAMESPACE_PREFIX": "",
        "OPENAI_BASE_URL": "http://litellm.test/v1",
        "OPENAI_API_KEY": "sk-test",
    }
    for k, v in defaults.items():
        monkeypatch.setenv(k, v)

    from src import embed
    embed._client.cache_clear()
