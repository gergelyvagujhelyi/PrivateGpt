# Pinned upstream digest — bump via Renovate + CI test in dev
ARG OPENWEBUI_VERSION=v0.6.5
FROM ghcr.io/open-webui/open-webui:${OPENWEBUI_VERSION}

# Layer our config + branding assets on top of the upstream image.
COPY branding/ /app/backend/static/branding/
COPY config/openwebui.env /app/openwebui.env

# Non-root, same as upstream; no privilege escalation needed.
ENV WEBUI_NAME="Client Assistant" \
    ENABLE_SIGNUP=false \
    DEFAULT_USER_ROLE=user \
    ENABLE_COMMUNITY_SHARING=false \
    ENABLE_MESSAGE_RATING=true \
    TASK_MODEL="claude-haiku-4-5" \
    RAG_EMBEDDING_MODEL="text-embedding-3-large"

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -q -O- http://localhost:8080/health || exit 1
