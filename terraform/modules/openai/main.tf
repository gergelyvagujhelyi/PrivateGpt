variable "name_prefix" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "private_endpoint_subnet_id" { type = string }
variable "private_dns_zone_id" { type = string }
variable "log_analytics_id" { type = string }
variable "model_deployments" {
  type = list(object({
    name     = string
    version  = string
    sku_name = string
    capacity = number
  }))
}
variable "tags" { type = map(string) }

resource "azurerm_cognitive_account" "this" {
  name                = "aoai-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "OpenAI"
  sku_name            = "S0"
  custom_subdomain_name = "aoai-${var.name_prefix}"

  public_network_access_enabled = false

  identity {
    type = "SystemAssigned"
  }

  network_acls {
    default_action = "Deny"
  }

  tags = var.tags
}

resource "azurerm_cognitive_deployment" "models" {
  for_each             = { for m in var.model_deployments : m.name => m }
  name                 = each.value.name
  cognitive_account_id = azurerm_cognitive_account.this.id

  model {
    format  = "OpenAI"
    name    = each.value.name
    version = each.value.version
  }

  sku {
    name     = each.value.sku_name
    capacity = each.value.capacity
  }

  rai_policy_name = "Microsoft.DefaultV2"
}

resource "azurerm_private_endpoint" "this" {
  name                = "pe-${azurerm_cognitive_account.this.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc"
    private_connection_resource_id = azurerm_cognitive_account.this.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "openai"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  name                       = "diag"
  target_resource_id         = azurerm_cognitive_account.this.id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log { category = "Audit" }
  enabled_log { category = "RequestResponse" }
  enabled_log { category = "Trace" }
  metric { category = "AllMetrics" }
}

output "id" { value = azurerm_cognitive_account.this.id }
output "endpoint" { value = azurerm_cognitive_account.this.endpoint }
output "key_vault_secret_ref" {
  value     = azurerm_cognitive_account.this.primary_access_key
  sensitive = true
}
output "principal_id" {
  value = azurerm_cognitive_account.this.identity[0].principal_id
}
