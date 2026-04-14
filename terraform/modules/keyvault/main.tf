variable "name_prefix" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "private_endpoint_subnet_id" { type = string }
variable "private_dns_zone_id" { type = string }
variable "log_analytics_id" { type = string }
variable "tags" { type = map(string) }

data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 5
  lower   = true
  numeric = true
  upper   = false
  special = false
}

resource "azurerm_key_vault" "this" {
  name                       = substr("kv${replace(var.name_prefix, "-", "")}${random_string.suffix.result}", 0, 24)
  resource_group_name        = var.resource_group_name
  location                   = var.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = true
  soft_delete_retention_days = 30
  enable_rbac_authorization  = true

  public_network_access_enabled = false
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  tags = var.tags
}

resource "azurerm_role_assignment" "deployer_admin" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_private_endpoint" "this" {
  name                = "pe-${azurerm_key_vault.this.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "kv"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  name                       = "diag"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log { category = "AuditEvent" }
  enabled_log { category = "AzurePolicyEvaluationDetails" }
  metric { category = "AllMetrics" }
}

# Generated secrets consumed by langfuse + litellm
resource "random_password" "langfuse_nextauth" {
  length  = 48
  special = true
}
resource "random_password" "langfuse_salt" {
  length  = 32
  special = false
}
resource "random_password" "langfuse_pk" {
  length  = 32
  special = false
}
resource "random_password" "langfuse_sk" {
  length  = 48
  special = false
}
resource "random_password" "litellm_master" {
  length  = 48
  special = false
}

resource "azurerm_key_vault_secret" "langfuse_nextauth_secret" {
  name         = "langfuse-nextauth-secret"
  value        = random_password.langfuse_nextauth.result
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [azurerm_role_assignment.deployer_admin]
}
resource "azurerm_key_vault_secret" "langfuse_salt" {
  name         = "langfuse-salt"
  value        = random_password.langfuse_salt.result
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [azurerm_role_assignment.deployer_admin]
}
resource "azurerm_key_vault_secret" "langfuse_pk" {
  name         = "langfuse-public-key"
  value        = random_password.langfuse_pk.result
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [azurerm_role_assignment.deployer_admin]
}
resource "azurerm_key_vault_secret" "langfuse_sk" {
  name         = "langfuse-secret-key"
  value        = random_password.langfuse_sk.result
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [azurerm_role_assignment.deployer_admin]
}
resource "azurerm_key_vault_secret" "litellm_master_key" {
  name         = "litellm-master-key"
  value        = "sk-${random_password.litellm_master.result}"
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [azurerm_role_assignment.deployer_admin]
}

# Entra app registration secrets (placeholder — rotated outside of TF or via AAD app module)
resource "azurerm_key_vault_secret" "entra_client_id" {
  name         = "entra-client-id"
  value        = "REPLACE_ME_VIA_PIPELINE"
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [azurerm_role_assignment.deployer_admin]
  lifecycle { ignore_changes = [value] }
}
resource "azurerm_key_vault_secret" "entra_client_secret" {
  name         = "entra-client-secret"
  value        = "REPLACE_ME_VIA_PIPELINE"
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [azurerm_role_assignment.deployer_admin]
  lifecycle { ignore_changes = [value] }
}

output "id" { value = azurerm_key_vault.this.id }
output "uri" { value = azurerm_key_vault.this.vault_uri }

# Container App secret refs are of the form  keyvaultref:https://<vault>/secrets/<name>,identityref:<mi-id>
# We emit just the KV URIs; the container_app module wires the identity.
output "langfuse_nextauth_secret_ref" { value = azurerm_key_vault_secret.langfuse_nextauth_secret.versionless_id }
output "langfuse_salt_ref"            { value = azurerm_key_vault_secret.langfuse_salt.versionless_id }
output "langfuse_pk_ref"              { value = azurerm_key_vault_secret.langfuse_pk.versionless_id }
output "langfuse_sk_ref"              { value = azurerm_key_vault_secret.langfuse_sk.versionless_id }
output "litellm_master_key_ref"       { value = azurerm_key_vault_secret.litellm_master_key.versionless_id }
output "entra_client_id_ref"          { value = azurerm_key_vault_secret.entra_client_id.versionless_id }
output "entra_client_secret_ref"      { value = azurerm_key_vault_secret.entra_client_secret.versionless_id }
