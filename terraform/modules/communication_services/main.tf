variable "name_prefix" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "data_location" {
  type    = string
  default = "Europe"
}
variable "key_vault_id" { type = string }
variable "log_analytics_id" { type = string }
variable "sender_local_part" {
  type    = string
  default = "assistant"
}
variable "tags" { type = map(string) }

resource "azurerm_email_communication_service" "this" {
  name                = "acsmail-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  data_location       = var.data_location
  tags                = var.tags
}

# Azure-managed subdomain on *.azurecomm.net — zero DNS setup.
# Swap to a CustomerManagedDomain once the client completes DNS verification.
resource "azurerm_email_communication_service_domain" "this" {
  name              = "AzureManagedDomain"
  email_service_id  = azurerm_email_communication_service.this.id
  domain_management = "AzureManaged"
  tags              = var.tags
}

resource "azurerm_communication_service" "this" {
  name                = "acs-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  data_location       = var.data_location
  tags                = var.tags
}

resource "azapi_resource" "domain_link" {
  # azurerm has no first-class link resource yet; azapi patches the linked_domains field.
  type      = "Microsoft.Communication/communicationServices@2023-04-01"
  parent_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
  name      = azurerm_communication_service.this.name

  body = {
    location = "global"
    properties = {
      dataLocation  = var.data_location
      linkedDomains = [azurerm_email_communication_service_domain.this.id]
    }
  }

  depends_on = [
    azurerm_communication_service.this,
    azurerm_email_communication_service_domain.this,
  ]
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault_secret" "connection_string" {
  name         = "acs-connection-string"
  value        = azurerm_communication_service.this.primary_connection_string
  key_vault_id = var.key_vault_id
}

resource "random_password" "unsub_hmac" {
  length  = 48
  special = false
}

resource "azurerm_key_vault_secret" "unsub_hmac_key" {
  name         = "unsub-hmac-key"
  value        = random_password.unsub_hmac.result
  key_vault_id = var.key_vault_id
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  name                       = "diag"
  target_resource_id         = azurerm_communication_service.this.id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log { category = "EmailSendMailOperational" }
  enabled_log { category = "EmailStatusUpdateOperational" }
  metric { category = "AllMetrics" }
}

output "sender_address" {
  value = "${var.sender_local_part}@${azurerm_email_communication_service_domain.this.mail_from_sender_domain}"
}

output "connection_string_secret_ref" {
  value = azurerm_key_vault_secret.connection_string.versionless_id
}

output "unsub_hmac_secret_ref" {
  value = azurerm_key_vault_secret.unsub_hmac_key.versionless_id
}
