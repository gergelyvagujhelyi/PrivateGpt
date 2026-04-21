# Pinned upstream digest — bump via Renovate + CI test in dev
ARG OPENWEBUI_VERSION=v0.9.1
FROM ghcr.io/open-webui/open-webui:${OPENWEBUI_VERSION}

# Layer security patches on top of the Debian-12 upstream image.
# Revisit every upstream bump: upstream may catch up and this can shrink.
USER root
RUN apt-get update \
  && apt-get upgrade -y --no-install-recommends \
  && rm -rf /var/lib/apt/lists/* \
  && pip install --no-cache-dir --upgrade \
        'orjson>=3.11.6' \
        'pillow>=12.2.0' \
        'python-multipart>=0.0.22' \
        'Brotli>=1.2.0' \
        'PyJWT>=2.12.0' \
        'aiohttp>=3.13.3' \
        'black>=26.3.1' \
        'jaraco.context>=6.1.0' \
        'wheel>=0.46.2' \
  && rm -rf /root/.cache/pip \
  # setuptools vendors a copy of jaraco.context + wheel inside its own
  # package. pip --upgrade only touches top-level site-packages, so the
  # vendored dist-info files at older versions stay and trivy keeps
  # flagging them. Remove the stale METADATA directories directly.
  && find /usr/local/lib/python*/site-packages/setuptools/_vendor \
       -maxdepth 1 -type d \
       \( -name 'jaraco.context-5.3.0.dist-info' -o -name 'wheel-0.45.1.dist-info' \) \
       -exec rm -rf {} + 2>/dev/null || true

# Runtime is Python + the pre-built SvelteKit static bundle; npm itself
# isn't needed. Its bundled node_modules tree is where the picomatch
# HIGH (CVE-2026-33671) gets flagged. Remove idempotently.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx 2>/dev/null || true

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
