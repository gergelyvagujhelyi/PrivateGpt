CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS rag_sources (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    namespace    TEXT NOT NULL,
    source_uri   TEXT NOT NULL,
    etag         TEXT NOT NULL,
    content_type TEXT,
    byte_size    BIGINT,
    ingested_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (namespace, source_uri, etag)
);

-- Dimension 3072 matches text-embedding-3-large (src/embed.py:EMBEDDING_DIM).
-- A model swap needs a schema migration before deploy; embed.py fails fast if
-- the model returns a different dim.
CREATE TABLE IF NOT EXISTS rag_chunks (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id   UUID NOT NULL REFERENCES rag_sources(id) ON DELETE CASCADE,
    namespace   TEXT NOT NULL,
    chunk_index INT NOT NULL,
    content     TEXT NOT NULL,
    metadata    JSONB NOT NULL DEFAULT '{}'::jsonb,
    embedding   VECTOR(3072) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS rag_chunks_namespace_idx    ON rag_chunks (namespace);
CREATE INDEX IF NOT EXISTS rag_chunks_source_idx       ON rag_chunks (source_id);
CREATE INDEX IF NOT EXISTS rag_chunks_embedding_hnsw
    ON rag_chunks USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);
