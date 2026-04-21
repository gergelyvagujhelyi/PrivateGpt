#!/bin/sh
set -eu
: "${LITELLM_CONFIG_YAML:?LITELLM_CONFIG_YAML env var is required}"
printf '%s\n' "$LITELLM_CONFIG_YAML" > /tmp/litellm-config.yaml
exec litellm \
  --config /tmp/litellm-config.yaml \
  --port "${PORT:-4000}" \
  --num_workers "${LITELLM_NUM_WORKERS:-4}"
