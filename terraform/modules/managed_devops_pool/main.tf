variable "name_prefix" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }

variable "virtual_network_name" {
  type        = string
  description = "Name of the spoke VNet the agent subnet lives in."
}

variable "agent_subnet_cidr" {
  type        = string
  description = "CIDR for the delegated subnet Managed DevOps Pools injects agents into."
  default     = "10.40.4.0/24"
}

variable "ado_organization_url" {
  type        = string
  description = "Azure DevOps organization URL, e.g. https://dev.azure.com/contoso"
}

variable "ado_project_name" {
  type        = string
  description = "Azure DevOps project this pool serves."
}

variable "pool_name" {
  type        = string
  description = "Pool name as it appears in Azure DevOps (Agent Pools)."
  default     = "owui-agents"
}

variable "agent_sku" {
  type        = string
  description = "VM SKU for agents (check your ADO Infrastructure quota)."
  default     = "Standard_D2ads_v5"
}

variable "agent_os_image" {
  type        = string
  description = "OS image alias for agents — see Microsoft.DevOpsInfrastructure published images."
  default     = "ubuntu-22.04/latest"
}

variable "max_concurrency" {
  type    = number
  default = 3
}

variable "subscription_scope_for_contributor" {
  type        = string
  description = <<EOT
Scope to grant the pool's system-assigned identity Contributor on —
usually the client's subscription ID, formatted
"/subscriptions/<guid>". Needed so agents can run `terraform apply`
against the per-client stack.
EOT
}

variable "log_analytics_id" { type = string }
variable "tags" { type = map(string) }

data "azurerm_client_config" "current" {}

# ─── Agent subnet delegated to Managed DevOps Pools ───
resource "azurerm_subnet" "agent" {
  name                 = "snet-ado-agents"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.virtual_network_name
  address_prefixes     = [var.agent_subnet_cidr]

  delegation {
    name = "devopsinfra"
    service_delegation {
      name    = "Microsoft.DevOpsInfrastructure/pools"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }

  private_endpoint_network_policies = "Enabled"
}

# ─── DevCenter (required container for Managed DevOps Pool projects) ───
resource "azurerm_dev_center" "this" {
  name                = "devc-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location

  identity { type = "SystemAssigned" }

  tags = var.tags
}

resource "azurerm_dev_center_project" "this" {
  name                = "devproj-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  dev_center_id       = azurerm_dev_center.this.id

  tags = var.tags
}

# ─── Managed DevOps Pool (via azapi — azurerm has no first-class resource yet) ───
resource "azapi_resource" "pool" {
  type      = "Microsoft.DevOpsInfrastructure/pools@2024-10-19"
  parent_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
  name      = "mdp-${var.name_prefix}"
  location  = var.location

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      devCenterProjectResourceId = azurerm_dev_center_project.this.id
      maximumConcurrency         = var.max_concurrency

      organizationProfile = {
        kind = "AzureDevOps"
        organizations = [{
          url         = var.ado_organization_url
          projects    = [var.ado_project_name]
          parallelism = var.max_concurrency
        }]
        permissionProfile = {
          kind = "CreatorOnly"
        }
      }

      agentProfile = {
        kind = "Stateless"
      }

      fabricProfile = {
        kind = "Vmss"
        sku  = { name = var.agent_sku }
        images = [{
          aliases            = [var.agent_os_image]
          wellKnownImageName = var.agent_os_image
          buffer             = "*"
        }]
        osProfile = {
          secretsManagementSettings = {
            observedCertificates = []
            keyExportable        = false
          }
          logonType = "Service"
        }
        networkProfile = {
          subnetId = azurerm_subnet.agent.id
        }
        storageProfile = {
          osDiskStorageAccountType = "Standard"
          dataDisks                = []
        }
      }
    }
  }

  response_export_values = ["identity.principalId"]
}

# ─── Agents can run TF against the client subscription ───
resource "azurerm_role_assignment" "agent_contributor" {
  scope                = var.subscription_scope_for_contributor
  role_definition_name = "Contributor"
  principal_id         = azapi_resource.pool.output.identity.principalId
}

# Observability
resource "azurerm_monitor_diagnostic_setting" "pool" {
  name                       = "diag"
  target_resource_id         = azapi_resource.pool.id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log { category = "DiagnosticLogs" }
  enabled_metric { category = "AllMetrics" }
}

output "pool_id" {
  value = azapi_resource.pool.id
}

output "pool_name" {
  value       = azapi_resource.pool.name
  description = "Reference this in ADO pipeline YAML as `pool: <pool_name>` once it's imported into the org as an agent pool."
}

output "dev_center_project_id" {
  value = azurerm_dev_center_project.this.id
}

output "agent_subnet_id" {
  value = azurerm_subnet.agent.id
}
