ARG LITELLM_VERSION=main-v1.83.7-stable
FROM ghcr.io/berriai/litellm:${LITELLM_VERSION}

COPY config.yaml /app/config.yaml

ENV LITELLM_CONFIG=/app/config.yaml \
    PORT=4000

EXPOSE 4000
CMD ["--config", "/app/config.yaml", "--port", "4000", "--num_workers", "4"]
