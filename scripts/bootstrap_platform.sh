#!/usr/bin/env bash
# Re-bootstrap the shared PrivateGpt platform from scratch:
#   rg-owui-platform, tfstate storage account, ACR, and the budget killswitch
#   (automation runbook + webhook + action group + consumption budget).
#
# Not in Terraform because it's the thing that *hosts* Terraform state — chicken/egg.
# Idempotent on re-run: reuses the suffix from an existing .env.deploy if present.
#
# Usage:
#   SUBSCRIPTION_ID=<uuid> scripts/bootstrap_platform.sh
#   # optional overrides: LOCATION, PLATFORM_RG, BUDGET_AMOUNT_SEK, SUFFIX, CLIENT_PREFIX

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env.deploy"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}" 2>/dev/null || true
fi

: "${LOCATION:=westeurope}"
: "${PLATFORM_RG:=rg-owui-platform}"
: "${BUDGET_AMOUNT_SEK:=500}"
: "${CLIENT_PREFIX:=kdemo}"
: "${SUFFIX:=$(printf '%05d' $((RANDOM % 100000)))}"
: "${STATE_SA:=stowuistate${SUFFIX}}"
: "${ACR_NAME:=acrowui${SUFFIX}}"

KS_AA="aa-owui-killswitch"
KS_RB="owui-killswitch"
KS_WH="wh-owui-killswitch"
KS_AG="ag-owui-killswitch"
KS_BUDGET="owui-killswitch-budget"

for bin in az jq; do command -v "$bin" >/dev/null || { echo "missing: $bin" >&2; exit 1; }; done
[[ -n "${SUBSCRIPTION_ID:-}" ]] || { echo "SUBSCRIPTION_ID env var required" >&2; exit 1; }

az account set --subscription "$SUBSCRIPTION_ID"
TENANT_ID="$(az account show --query tenantId -o tsv)"

echo "==> subscription=$SUBSCRIPTION_ID tenant=$TENANT_ID"
echo "    location=$LOCATION rg=$PLATFORM_RG"
echo "    state_sa=$STATE_SA  acr=$ACR_NAME  budget=${BUDGET_AMOUNT_SEK} SEK/mo"

# --- 1. Platform resource group ------------------------------------------

az group create -n "$PLATFORM_RG" -l "$LOCATION" --tags purpose=platform -o none

# --- 2. Terraform state storage account (AAD-only) -----------------------
# README gotcha #1: shared-key access must be disabled; executing identity
# needs Storage Blob Data Owner on the SA before the container create works.

az storage account show -n "$STATE_SA" -g "$PLATFORM_RG" -o none 2>/dev/null || \
  az storage account create \
    -n "$STATE_SA" -g "$PLATFORM_RG" -l "$LOCATION" \
    --sku Standard_LRS --kind StorageV2 \
    --allow-blob-public-access false \
    --allow-shared-key-access false \
    --min-tls-version TLS1_2 \
    -o none

CALLER_OID="$(az ad signed-in-user show --query id -o tsv)"
SA_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${PLATFORM_RG}/providers/Microsoft.Storage/storageAccounts/${STATE_SA}"
az role assignment create \
  --assignee-object-id "$CALLER_OID" --assignee-principal-type User \
  --role "Storage Blob Data Owner" --scope "$SA_ID" \
  -o none 2>/dev/null || true

# Role propagation lags — retry the container create for up to ~1 min.
for i in 1 2 3 4 5 6; do
  az storage container create \
    --account-name "$STATE_SA" --name tfstate --auth-mode login \
    -o none 2>/dev/null && break
  echo "  ...waiting for role propagation ($i/6)"
  sleep 10
done

# --- 3. Shared ACR (Basic SKU) -------------------------------------------

az acr show -n "$ACR_NAME" -o none 2>/dev/null || \
  az acr create -n "$ACR_NAME" -g "$PLATFORM_RG" -l "$LOCATION" --sku Basic -o none

# --- 4. Killswitch: automation account + system-assigned MI --------------

az automation account show -n "$KS_AA" -g "$PLATFORM_RG" -o none 2>/dev/null || \
  az automation account create -n "$KS_AA" -g "$PLATFORM_RG" -l "$LOCATION" --sku Basic -o none

AA_ARM="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${PLATFORM_RG}/providers/Microsoft.Automation/automationAccounts/${KS_AA}"
az rest --method patch \
  --url "https://management.azure.com${AA_ARM}?api-version=2023-11-01" \
  --body '{"identity":{"type":"SystemAssigned"}}' -o none

AA_MI_OID="$(az automation account show -n "$KS_AA" -g "$PLATFORM_RG" --query identity.principalId -o tsv)"
az role assignment create \
  --assignee-object-id "$AA_MI_OID" --assignee-principal-type ServicePrincipal \
  --role Owner --scope "/subscriptions/$SUBSCRIPTION_ID" \
  -o none 2>/dev/null || true

# --- 5. Killswitch runbook -----------------------------------------------

TMPPS="$(mktemp -t owui-killswitch.XXXXXX).ps1"
cat > "$TMPPS" <<'PS1'
<# Deletes every rg-owui-* resource group except rg-owui-platform.
   Runs under the automation account's system-assigned managed identity. #>
param()
$ErrorActionPreference = 'Stop'
Connect-AzAccount -Identity | Out-Null
$keep = 'rg-owui-platform'
Get-AzResourceGroup |
  Where-Object { $_.ResourceGroupName -like 'rg-owui-*' -and $_.ResourceGroupName -ne $keep } |
  ForEach-Object {
    Write-Output ("Deleting {0}" -f $_.ResourceGroupName)
    Remove-AzResourceGroup -Name $_.ResourceGroupName -Force -AsJob | Out-Null
  }
PS1

az automation runbook show \
  -g "$PLATFORM_RG" --automation-account-name "$KS_AA" --name "$KS_RB" \
  -o none 2>/dev/null || \
  az automation runbook create \
    -g "$PLATFORM_RG" --automation-account-name "$KS_AA" \
    --name "$KS_RB" --type PowerShell72 \
    --description "Deletes all rg-owui-* client RGs except rg-owui-platform" \
    -o none

az rest --method put \
  --url "https://management.azure.com${AA_ARM}/runbooks/${KS_RB}/draft/content?api-version=2023-11-01" \
  --headers "Content-Type=text/powershell" \
  --body "@${TMPPS}" -o none
rm -f "$TMPPS"

az automation runbook publish \
  -g "$PLATFORM_RG" --automation-account-name "$KS_AA" --name "$KS_RB" -o none

# --- 6. Webhook ----------------------------------------------------------
# URI is only returned when Azure generates it; rotate if the webhook already exists.

az rest --method delete \
  --url "https://management.azure.com${AA_ARM}/webhooks/${KS_WH}?api-version=2023-11-01" \
  -o none 2>/dev/null || true

WH_URI="$(az rest --method post \
  --url "https://management.azure.com${AA_ARM}/webhooks/generateUri?api-version=2023-11-01" \
  --output tsv | tr -d '"')"

if [[ "$(uname)" == "Darwin" ]]; then
  EXPIRY="$(date -u -v+10y +'%Y-%m-%dT%H:%M:%SZ')"
else
  EXPIRY="$(date -u -d '+10 years' +'%Y-%m-%dT%H:%M:%SZ')"
fi

WH_BODY="$(jq -nc \
  --arg uri "$WH_URI" --arg exp "$EXPIRY" --arg rb "$KS_RB" \
  '{properties:{isEnabled:true,uri:$uri,expiryTime:$exp,runbook:{name:$rb}}}')"

WH_ID="$(az rest --method put \
  --url "https://management.azure.com${AA_ARM}/webhooks/${KS_WH}?api-version=2023-11-01" \
  --body "$WH_BODY" --query id -o tsv)"

# --- 7. Action group pointing at the webhook -----------------------------

AG_BODY="$(jq -nc \
  --arg aa "$AA_ARM" --arg rb "$KS_RB" --arg wid "$WH_ID" --arg uri "$WH_URI" \
  '{location:"Global",properties:{groupShortName:"owuikill",enabled:true,
    automationRunbookReceivers:[{name:"ks",automationAccountId:$aa,runbookName:$rb,
      webhookResourceId:$wid,isGlobalRunbook:false,serviceUri:$uri,useCommonAlertSchema:true}]}}')"

AG_ID="$(az rest --method put \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${PLATFORM_RG}/providers/Microsoft.Insights/actionGroups/${KS_AG}?api-version=2023-01-01" \
  --body "$AG_BODY" --query id -o tsv)"

# --- 8. Consumption budget at subscription scope -------------------------
# Fires the AG at both 100% forecasted and 100% actual. Billing data lags
# 8-24h, so worst-case overshoot is ~one day at steady-state burn rate.

if [[ "$(uname)" == "Darwin" ]]; then
  NOW_START="$(date -u +'%Y-%m-01T00:00:00Z')"
  BUDGET_END="$(date -u -v+10y +'%Y-%m-01T00:00:00Z')"
else
  NOW_START="$(date -u +'%Y-%m-01T00:00:00Z')"
  BUDGET_END="$(date -u -d '+10 years' +'%Y-%m-01T00:00:00Z')"
fi

BUDGET_BODY="$(jq -nc \
  --argjson amount "$BUDGET_AMOUNT_SEK" \
  --arg start "$NOW_START" --arg end "$BUDGET_END" \
  --arg ag "$AG_ID" \
  '{properties:{category:"Cost",amount:$amount,timeGrain:"Monthly",
    timePeriod:{startDate:$start,endDate:$end},
    notifications:{
      forecast100:{enabled:true,operator:"GreaterThan",threshold:100,thresholdType:"Forecasted",
        contactGroups:[$ag],notificationLanguage:"en-us"},
      actual100:{enabled:true,operator:"GreaterThan",threshold:100,thresholdType:"Actual",
        contactGroups:[$ag],notificationLanguage:"en-us"}
    }}}')"

az rest --method put \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Consumption/budgets/${KS_BUDGET}?api-version=2023-05-01" \
  --body "$BUDGET_BODY" -o none

# --- 9. Emit .env.deploy -------------------------------------------------

cat > "$ENV_FILE" <<ENVF
export LOCATION=${LOCATION}
export PLATFORM_RG=${PLATFORM_RG}
export STATE_SA=${STATE_SA}
export ACR_NAME=${ACR_NAME}
export SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
export TENANT_ID=${TENANT_ID}
export CLIENT_PREFIX=${CLIENT_PREFIX}
export SUFFIX=${SUFFIX}
ENVF

echo
echo "==> bootstrap complete."
echo "    platform RG:    ${PLATFORM_RG}"
echo "    tfstate SA:     ${STATE_SA}  (container: tfstate, AAD-only)"
echo "    ACR:            ${ACR_NAME}  (Basic)"
echo "    killswitch AA:  ${KS_AA}  (budget ${BUDGET_AMOUNT_SEK} SEK/mo, 100% actual + forecast)"
echo "    wrote:          ${ENV_FILE}"
echo
echo "Next steps:"
echo "  1. Update terraform/envs/<client>/backend.hcl so storage_account_name=\"${STATE_SA}\""
echo "  2. Grant the ADO service connection SP (when it exists):"
echo "       Contributor   on /subscriptions/${SUBSCRIPTION_ID}"
echo "       Storage Blob Data Contributor on ${SA_ID}"
echo "       AcrPush       on the ACR"
echo "  3. docker build + az acr login --name ${ACR_NAME} + docker push"
echo "  4. terraform -chdir=terraform/stacks/openwebui init \\"
echo "       -backend-config=../../envs/<client>/backend.hcl"
