variable "name" { type = string }
variable "name_prefix" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "container_app_env_id" { type = string }
variable "image" { type = string }
variable "target_port" { type = number }
variable "ingress_external" {
  type    = bool
  default = false
}
variable "key_vault_id" { type = string }

variable "env" {
  type = list(object({
    name        = string
    value       = optional(string)
    secret_name = optional(string)
  }))
  default = []
}

variable "secrets" {
  type        = map(string)
  description = "Map of container-app secret name → Key Vault secret versionless id"
  default     = {}
}

# Opt-in ACR auth: when both set and `image` starts with `acr_login_server`,
# attach the app's UAMI to the registry and grant it AcrPull. Images on any
# other registry (public upstreams, langfuse) are unaffected.
variable "acr_login_server" {
  type    = string
  default = ""
}

variable "acr_id" {
  type    = string
  default = ""
}

variable "cpu" {
  type    = number
  default = 0.5
}
variable "memory" {
  type    = string
  default = "1Gi"
}
variable "min_replicas" {
  type    = number
  default = 1
}
variable "max_replicas" {
  type    = number
  default = 3
}
variable "tags" { type = map(string) }

resource "azurerm_user_assigned_identity" "this" {
  name                = "id-${var.name_prefix}-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "kv_reader" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

locals {
  uses_acr = var.acr_login_server != "" && var.acr_id != "" && startswith(var.image, var.acr_login_server)
}

resource "azurerm_role_assignment" "acr_pull" {
  count                = local.uses_acr ? 1 : 0
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

resource "azurerm_container_app" "this" {
  # Azure Container App names max at 32 chars.
  name                         = substr("ca-${var.name_prefix}-${var.name}", 0, 32)
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_env_id
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  dynamic "registry" {
    for_each = local.uses_acr ? [1] : []
    content {
      server   = var.acr_login_server
      identity = azurerm_user_assigned_identity.this.id
    }
  }

  dynamic "secret" {
    for_each = var.secrets
    content {
      name                = secret.key
      key_vault_secret_id = secret.value
      identity            = azurerm_user_assigned_identity.this.id
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = var.name
      image  = var.image
      cpu    = var.cpu
      memory = var.memory

      dynamic "env" {
        for_each = var.env
        content {
          name        = env.value.name
          value       = try(env.value.value, null)
          secret_name = try(env.value.secret_name, null)
        }
      }
    }

    http_scale_rule {
      name                = "http"
      concurrent_requests = 50
    }
  }

  ingress {
    external_enabled = var.ingress_external
    target_port      = var.target_port
    transport        = "auto"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  depends_on = [
    azurerm_role_assignment.kv_reader,
    azurerm_role_assignment.acr_pull,
  ]

  tags = var.tags

  lifecycle {
    ignore_changes = [
      template[0].container[0].image,
    ]
  }
}

output "id" { value = azurerm_container_app.this.id }
output "name" { value = azurerm_container_app.this.name }
output "fqdn" { value = azurerm_container_app.this.ingress[0].fqdn }
output "principal_id" { value = azurerm_user_assigned_identity.this.principal_id }
output "identity_id" { value = azurerm_user_assigned_identity.this.id }
