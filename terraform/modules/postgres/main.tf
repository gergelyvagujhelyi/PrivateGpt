variable "name_prefix" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "delegated_subnet_id" { type = string }
variable "private_dns_zone_id" { type = string }
variable "key_vault_id" { type = string }
variable "log_analytics_id" { type = string }
variable "sku_name" {
  type    = string
  default = "GP_Standard_D2ds_v5"
}
variable "storage_mb" {
  type    = number
  default = 65536
}
variable "tags" { type = map(string) }

resource "random_password" "admin" {
  length  = 32
  special = false
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                   = "psql-${var.name_prefix}"
  resource_group_name    = var.resource_group_name
  location               = var.location
  version                = "16"
  sku_name               = var.sku_name
  storage_mb             = var.storage_mb
  administrator_login    = "pgadmin"
  administrator_password = random_password.admin.result

  delegated_subnet_id = var.delegated_subnet_id
  private_dns_zone_id = var.private_dns_zone_id

  backup_retention_days         = 14
  geo_redundant_backup_enabled  = false
  public_network_access_enabled = false

  tags = var.tags

  lifecycle {
    ignore_changes = [zone]
  }
}

resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = "VECTOR,UUID-OSSP,PGCRYPTO"
}

resource "azurerm_postgresql_flexible_server_database" "openwebui" {
  name      = "openwebui"
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_postgresql_flexible_server_database" "langfuse" {
  name      = "langfuse"
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_key_vault_secret" "admin_password" {
  name         = "postgres-admin-password"
  value        = random_password.admin.result
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "openwebui_db_url" {
  name         = "openwebui-db-url"
  value        = "postgresql://${local.user}:${local.pw}@${local.host}:5432/openwebui?sslmode=require"
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "langfuse_db_url" {
  name         = "langfuse-db-url"
  value        = "postgresql://${local.user}:${local.pw}@${local.host}:5432/langfuse?sslmode=require"
  key_vault_id = var.key_vault_id
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  name                       = "diag"
  target_resource_id         = azurerm_postgresql_flexible_server.this.id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log { category = "PostgreSQLLogs" }
  metric { category = "AllMetrics" }
}

locals {
  host = azurerm_postgresql_flexible_server.this.fqdn
  user = azurerm_postgresql_flexible_server.this.administrator_login
  pw   = random_password.admin.result
}

output "fqdn" { value = local.host }
output "openwebui_connection_string" {
  value     = "postgresql://${local.user}:${local.pw}@${local.host}:5432/openwebui?sslmode=require"
  sensitive = true
}
output "langfuse_connection_string" {
  value     = "postgresql://${local.user}:${local.pw}@${local.host}:5432/langfuse?sslmode=require"
  sensitive = true
}
output "openwebui_db_url_secret_ref" { value = azurerm_key_vault_secret.openwebui_db_url.versionless_id }
output "langfuse_db_url_secret_ref" { value = azurerm_key_vault_secret.langfuse_db_url.versionless_id }
