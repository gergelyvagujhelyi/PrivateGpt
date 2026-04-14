variable "name_prefix" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "infrastructure_subnet_id" { type = string }
variable "log_analytics_id" { type = string }
variable "tags" { type = map(string) }

data "azurerm_log_analytics_workspace" "this" {
  # Parse RG + name out of the resource ID
  name                = element(split("/", var.log_analytics_id), length(split("/", var.log_analytics_id)) - 1)
  resource_group_name = element(split("/", var.log_analytics_id), 4)
}

resource "azurerm_container_app_environment" "this" {
  name                           = "cae-${var.name_prefix}"
  resource_group_name            = var.resource_group_name
  location                       = var.location
  log_analytics_workspace_id     = var.log_analytics_id
  infrastructure_subnet_id       = var.infrastructure_subnet_id
  internal_load_balancer_enabled = true
  zone_redundancy_enabled        = false

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  tags = var.tags
}

output "id" { value = azurerm_container_app_environment.this.id }
output "default_domain" { value = azurerm_container_app_environment.this.default_domain }
output "static_ip_address" { value = azurerm_container_app_environment.this.static_ip_address }
