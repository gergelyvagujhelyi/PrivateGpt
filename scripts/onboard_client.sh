#!/usr/bin/env bash
# Onboard a new client: scaffolds envs/<client>/{dev,prod}.tfvars and an ADO variable group stub.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <client-id> <cost-center>" >&2
  exit 1
fi

CLIENT="$1"
CC="$2"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_DIR="${REPO_ROOT}/terraform/envs/${CLIENT}"

if [[ -d "${ENV_DIR}" ]]; then
  echo "client ${CLIENT} already onboarded at ${ENV_DIR}" >&2
  exit 1
fi

cp -R "${REPO_ROOT}/terraform/envs/acme" "${ENV_DIR}"
for env in dev prod; do
  sed -i.bak "s/^client *=.*/client      = \"${CLIENT}\"/" "${ENV_DIR}/${env}.tfvars"
  sed -i.bak "s/^cost_center *=.*/cost_center = \"${CC}\"/" "${ENV_DIR}/${env}.tfvars"
  rm "${ENV_DIR}/${env}.tfvars.bak"
done

echo "Scaffolded ${ENV_DIR}"
echo
echo "Next steps:"
echo "  1. Create ADO variable group 'owui-${CLIENT}' with ARM_* service connection credentials."
echo "  2. Create ADO environments: owui-${CLIENT}-dev, -test, -prod with approvers."
echo "  3. Register Entra app for SSO; store client-id + secret in Key Vault after first apply."
echo "  4. Open a PR — the infra pipeline will plan into each env."
