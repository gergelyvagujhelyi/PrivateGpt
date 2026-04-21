#!/usr/bin/env bash
# Toggle the main Front Door endpoint for a client on/off.
# Traffic is accepted/rejected within ~30s. Doesn't stop FD billing —
# for that, destroy the stack. Doesn't trigger tf drift — the
# frontdoor module doesn't manage `enabled_state`.
#
#   ./scripts/toggle_frontdoor.sh <client> <env> on|off
#
# Example:
#   ./scripts/toggle_frontdoor.sh kompose dev off
#   ./scripts/toggle_frontdoor.sh kompose dev on
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <client> <env> on|off" >&2
  echo "  e.g. $0 kompose dev off" >&2
  exit 1
fi

CLIENT="$1"
ENV="$2"
STATE_INPUT="$3"

case "$STATE_INPUT" in
  on|enable|Enabled)  STATE=Enabled ;;
  off|disable|Disabled) STATE=Disabled ;;
  *) echo "invalid state '$STATE_INPUT' — use on|off" >&2; exit 1 ;;
esac

PREFIX="owui-${CLIENT}-${ENV}"
RG="rg-${PREFIX}"
PROFILE="afd-${PREFIX}"
ENDPOINT="ep-${PREFIX}"

echo "==> Toggling $ENDPOINT on profile $PROFILE → $STATE"
az afd endpoint update \
  --resource-group "$RG" \
  --profile-name "$PROFILE" \
  --endpoint-name "$ENDPOINT" \
  --enabled-state "$STATE" -o none

HOST=$(az afd endpoint show \
  --resource-group "$RG" \
  --profile-name "$PROFILE" \
  --name "$ENDPOINT" \
  --query hostName -o tsv)

echo "    state:  $STATE"
echo "    url:    https://$HOST"
echo "    propagation: usually <30s"
