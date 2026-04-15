variable "name_prefix" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "private_endpoint_subnet_id" { type = string }

variable "private_dns_zone_ids" {
  type        = list(string)
  description = "All DNS zones the AI Services PE should register in (cognitiveservices + services.ai)."
}

variable "log_analytics_id" { type = string }
variable "key_vault_id" { type = string }
variable "application_insights_id" { type = string }

variable "deployments" {
  description = <<EOT
Map of logical name → model deployment.
  - provider = "anthropic" → Claude MaaS serverless endpoint (per-deployment endpoint + key)
  - provider = "openai"    → Azure OpenAI deployment on the hub's AI Services account
EOT
  type = map(object({
    provider = string
    model    = string
    version  = string
    sku_name = optional(string, "Standard")
    capacity = optional(number, 50)
  }))
}

variable "tags" { type = map(string) }

data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 5
  lower   = true
  numeric = true
  upper   = false
  special = false
}

# ─── Storage account backing the Foundry hub ───
resource "azurerm_storage_account" "hub" {
  name                            = substr("sthub${replace(var.name_prefix, "-", "")}${random_string.suffix.result}", 0, 24)
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true

  tags = var.tags
}

# ─── AI Services account ───
resource "azurerm_ai_services" "this" {
  name                  = "ais-${var.name_prefix}"
  resource_group_name   = var.resource_group_name
  location              = var.location
  sku_name              = "S0"
  custom_subdomain_name = "ais-${var.name_prefix}"

  public_network_access = "Disabled"

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# ─── AI Foundry hub + default project ───
resource "azurerm_ai_foundry" "this" {
  name                = "aihub-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location

  storage_account_id      = azurerm_storage_account.hub.id
  key_vault_id            = var.key_vault_id
  application_insights_id = var.application_insights_id

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

resource "azurerm_ai_foundry_project" "this" {
  name               = "aiproj-${var.name_prefix}"
  location           = var.location
  ai_services_hub_id = azurerm_ai_foundry.this.id

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# ─── Model deployments ───
resource "azurerm_cognitive_deployment" "openai" {
  for_each = { for k, v in var.deployments : k => v if v.provider == "openai" }

  name                 = each.key
  cognitive_account_id = azurerm_ai_services.this.id

  model {
    format  = "OpenAI"
    name    = each.value.model
    version = each.value.version
  }

  sku {
    name     = each.value.sku_name
    capacity = each.value.capacity
  }

  rai_policy_name = "Microsoft.DefaultV2"
}

resource "azapi_resource" "claude" {
  for_each = { for k, v in var.deployments : k => v if v.provider == "anthropic" }

  type      = "Microsoft.MachineLearningServices/workspaces/serverlessEndpoints@2024-10-01"
  parent_id = azurerm_ai_foundry_project.this.id
  name      = each.key
  location  = var.location

  body = {
    properties = {
      authMode = "Key"
      modelSettings = {
        modelId = "azureml://registries/azureml-anthropic/models/${each.value.model}/versions/${each.value.version}"
      }
    }
  }

  response_export_values = ["properties.inferenceEndpoint.uri"]
}

data "azapi_resource_action" "claude_keys" {
  for_each = azapi_resource.claude

  type                   = "Microsoft.MachineLearningServices/workspaces/serverlessEndpoints@2024-10-01"
  resource_id            = each.value.id
  action                 = "listKeys"
  response_export_values = ["primaryKey"]
}

# ─── Private endpoint on the AI Services account ───
resource "azurerm_private_endpoint" "this" {
  name                = "pe-ais-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc"
    private_connection_resource_id = azurerm_ai_services.this.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "ai"
    private_dns_zone_ids = var.private_dns_zone_ids
  }

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "ais" {
  name                       = "diag"
  target_resource_id         = azurerm_ai_services.this.id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log { category = "Audit" }
  enabled_log { category = "RequestResponse" }
  metric { category = "AllMetrics" }
}

# ─── KV-backed secrets so callers consume KV refs, never raw keys ───
resource "azurerm_key_vault_secret" "ai_services_key" {
  name         = "foundry-ai-services-key"
  value        = azurerm_ai_services.this.primary_access_key
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "claude_keys" {
  for_each = azapi_resource.claude

  name         = "foundry-maas-${each.key}-key"
  value        = jsondecode(data.azapi_resource_action.claude_keys[each.key].output).primaryKey
  key_vault_id = var.key_vault_id
}

# ─── Outputs ───
output "endpoint" {
  value = azurerm_ai_services.this.endpoint
}

output "foundry_endpoint" {
  value = "https://${azurerm_ai_services.this.custom_subdomain_name}.services.ai.azure.com"
}

output "ai_services_key_secret_ref" {
  value = azurerm_key_vault_secret.ai_services_key.versionless_id
}

output "deployments" {
  value = merge(
    { for k, d in azurerm_cognitive_deployment.openai : k => "openai" },
    { for k, d in azapi_resource.claude : k => "anthropic" },
  )
}

output "claude_endpoints" {
  value     = { for k, d in azapi_resource.claude : k => jsondecode(d.output).properties.inferenceEndpoint.uri }
  sensitive = true
}

output "claude_key_secret_refs" {
  value = { for k, s in azurerm_key_vault_secret.claude_keys : k => s.versionless_id }
}
