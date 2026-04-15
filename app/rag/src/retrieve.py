"""CLI helper for manual retrieval checks against the ingested corpus.

Usage:
    python -m src.retrieve "<query>" --namespace default --top-k 5

Also importable by the digest agent (or any other caller) as a tool.
"""

from __future__ import annotations

import argparse
import json
import os

from .embed import embed_batch
from .store import connect, similarity_search


def search(query: str, namespace: str = "default", top_k: int = 5) -> list[dict]:
    [vec] = embed_batch([query])
    with connect(os.environ["DATABASE_URL"]) as conn:
        return similarity_search(conn, namespace=namespace, query_vec=vec, top_k=top_k)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("query")
    ap.add_argument("--namespace", default="default")
    ap.add_argument("--top-k", type=int, default=5)
    args = ap.parse_args()

    hits = search(args.query, namespace=args.namespace, top_k=args.top_k)
    print(json.dumps(hits, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
