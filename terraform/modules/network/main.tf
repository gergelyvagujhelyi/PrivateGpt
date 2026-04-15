variable "name_prefix" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "address_space" {
  type    = list(string)
  default = ["10.40.0.0/20"]
}
variable "tags" { type = map(string) }

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.address_space
  tags                = var.tags
}

resource "azurerm_subnet" "aca" {
  name                 = "snet-aca"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.40.0.0/23"]

  delegation {
    name = "aca"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "postgres" {
  name                 = "snet-postgres"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.40.2.0/24"]

  delegation {
    name = "postgres"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "pe" {
  name                 = "snet-pe"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.40.3.0/24"]

  private_endpoint_network_policies = "Enabled"
}

locals {
  private_dns_zones = {
    blob              = "privatelink.blob.core.windows.net"
    kv                = "privatelink.vaultcore.azure.net"
    cognitiveservices = "privatelink.cognitiveservices.azure.com"
    ai_services       = "privatelink.services.ai.azure.com"
    postgres          = "privatelink.postgres.database.azure.com"
  }
}

resource "azurerm_private_dns_zone" "zones" {
  for_each            = local.private_dns_zones
  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "links" {
  for_each              = local.private_dns_zones
  name                  = "link-${each.key}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.zones[each.key].name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}

output "vnet_id" { value = azurerm_virtual_network.this.id }
output "aca_subnet_id" { value = azurerm_subnet.aca.id }
output "postgres_subnet_id" { value = azurerm_subnet.postgres.id }
output "pe_subnet_id" { value = azurerm_subnet.pe.id }

output "blob_private_dns_zone_id" { value = azurerm_private_dns_zone.zones["blob"].id }
output "kv_private_dns_zone_id" { value = azurerm_private_dns_zone.zones["kv"].id }
output "cognitiveservices_private_dns_zone_id" { value = azurerm_private_dns_zone.zones["cognitiveservices"].id }
output "ai_services_private_dns_zone_id" { value = azurerm_private_dns_zone.zones["ai_services"].id }
output "postgres_private_dns_zone_id" { value = azurerm_private_dns_zone.zones["postgres"].id }

# Convenience list for PEs that need DNS registration in multiple zones (e.g. AI Foundry).
output "ai_services_private_dns_zone_ids" {
  value = [
    azurerm_private_dns_zone.zones["cognitiveservices"].id,
    azurerm_private_dns_zone.zones["ai_services"].id,
  ]
}
