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
for env in dev test prod; do
  sed -i.bak "s/^client *=.*/client      = \"${CLIENT}\"/" "${ENV_DIR}/${env}.tfvars"
  sed -i.bak "s/^cost_center *=.*/cost_center = \"${CC}\"/" "${ENV_DIR}/${env}.tfvars"
  rm "${ENV_DIR}/${env}.tfvars.bak"
done

echo "Scaffolded ${ENV_DIR}"
echo
echo "Next steps:"
echo "  1. Confirm the client's subscription is Pay-As-You-Go (NOT trial/free) —"
echo "     trial subs block Postgres Flexible, Front Door Premium, and Claude MaaS."
echo "  2. Update envs/${CLIENT}/backend.hcl storage_account_name to your real"
echo "     platform tfstate SA (the default is a placeholder)."
echo "  3. Create ADO service connection 'sc-owui-${CLIENT}' (workload identity federation)."
echo "     Grant its SP Contributor on the client sub + Storage Blob Data Contributor"
echo "     on the platform tfstate SA."
echo "  4. Create ADO variable group 'owui-${CLIENT}'."
echo "  5. Create ADO environments: owui-${CLIENT}-dev, -test, -prod with approvers."
echo "  6. Purchase 1 MS-hosted parallel job OR use a self-hosted agent"
echo "     (new ADO orgs don't get free parallelism automatically)."
echo "  7. Register Entra app for OpenWebUI SSO; store client-id + secret"
echo "     in Key Vault after first apply."
echo "  8. If enabling features.admin_ui:"
echo "       - Register a second Entra app for the admin SPA + API"
echo "       - Set entra_admin_app_client_id in envs/${CLIENT}/*.tfvars"
echo "       - After first apply, register the 'admin_public_url' TF output"
echo "         as the Entra app's reply URL"
echo "  9. Open a PR — the infra pipeline plans dev by default."
echo "     Tick include_test / include_prod in the Run dialog to promote further."
