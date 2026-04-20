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

resource "azurerm_storage_account" "this" {
  name                = substr("st${replace(var.name_prefix, "-", "")}${random_string.suffix.result}", 0, 24)
  resource_group_name = var.resource_group_name
  location            = var.location

  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false

  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true

    delete_retention_policy { days = 30 }
    container_delete_retention_policy { days = 30 }
  }

  tags = var.tags
}

# Grant the terraform executor data-plane access so the provider can create
# containers / read blob + queue properties via AAD (shared keys are disabled).
resource "azurerm_role_assignment" "deployer_blob" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "deployer_queue" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "wait_for_role_propagation" {
  depends_on      = [azurerm_role_assignment.deployer_blob, azurerm_role_assignment.deployer_queue]
  create_duration = "60s"
}

resource "azurerm_storage_container" "uploads" {
  name                  = "openwebui-uploads"
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"

  depends_on = [time_sleep.wait_for_role_propagation]
}

resource "azurerm_storage_container" "rag_sources" {
  name                  = "rag-sources"
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"

  depends_on = [time_sleep.wait_for_role_propagation]
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-${azurerm_storage_account.this.name}-blob"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  name                       = "diag"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }
  metric { category = "Transaction" }
}

output "id" { value = azurerm_storage_account.this.id }
output "name" { value = azurerm_storage_account.this.name }
output "blob_endpoint" { value = azurerm_storage_account.this.primary_blob_endpoint }
output "uploads_container_name" { value = azurerm_storage_container.uploads.name }
output "rag_sources_container_name" { value = azurerm_storage_container.rag_sources.name }
