ARG LITELLM_VERSION=main-v1.83.7-stable
FROM ghcr.io/berriai/litellm:${LITELLM_VERSION}

# Layer security patches on top of the upstream image. Upstream is
# Chainguard Wolfi (apk, not apt) — litellm main-v1.83.7-stable.
#   - apk upgrade: OS CVEs upstream hasn't rolled forward.
#   - pip install --upgrade: Python CVEs in bundled deps (Brotli).
# Revisit every upstream bump — when upstream catches up, this shrinks.
USER root
RUN apk --no-cache upgrade \
  && pip install --no-cache-dir --upgrade \
        'Brotli>=1.2.0' \
        'orjson>=3.11.6' \
        'pillow>=12.2.0' \
        'python-multipart>=0.0.22' \
  && rm -rf /root/.cache/pip \
  # picomatch 4.0.3 (CVE-2026-33671) ships inside bundled npm trees in
  # two places:
  #   /usr/local/lib/node_modules/npm                       — system npm
  #   /usr/lib/python*/site-packages/nodejs_wheel/.../npm   — pip's
  #     nodejs_wheel package; litellm proxy doesn't invoke npm at
  #     runtime, so removing both is safe.
  && rm -rf /usr/local/lib/node_modules/npm \
            /usr/local/bin/npm /usr/local/bin/npx \
            /usr/lib/python*/site-packages/nodejs_wheel/lib/node_modules/npm \
            2>/dev/null || true

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV PORT=4000

EXPOSE 4000

USER 1001
ENTRYPOINT ["/entrypoint.sh"]
CMD []
