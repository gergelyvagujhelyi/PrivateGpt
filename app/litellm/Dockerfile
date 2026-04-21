ARG LITELLM_VERSION=main-v1.83.7-stable
FROM ghcr.io/berriai/litellm:${LITELLM_VERSION}

# Layer security patches on top of the upstream image:
#   - apt-get upgrade: OS CVEs upstream hasn't rolled forward
#     (libgdk-pixbuf, linux-libc-dev kernel headers).
#   - pip install --upgrade: Python CVEs in bundled deps (Brotli).
# Revisit every upstream bump — when upstream catches up, this shrinks.
USER root
RUN apt-get update \
  && apt-get upgrade -y --no-install-recommends \
  && rm -rf /var/lib/apt/lists/* \
  && pip install --no-cache-dir --upgrade 'Brotli>=1.2.0' \
  && rm -rf /root/.cache/pip

COPY config.yaml /app/config.yaml

ENV LITELLM_CONFIG=/app/config.yaml \
    PORT=4000

EXPOSE 4000
CMD ["--config", "/app/config.yaml", "--port", "4000", "--num_workers", "4"]
