variable "name" { type = string }
variable "name_prefix" { type = string }
variable "resource_group_name" { type = string }
variable "container_app_env_id" { type = string }
variable "image" { type = string }
variable "key_vault_id" { type = string }

variable "cron_expression" {
  type        = string
  description = "Cron expression in UTC"
}

variable "replica_timeout_in_seconds" {
  type    = number
  default = 1800
}

variable "replica_retry_limit" {
  type    = number
  default = 2
}

variable "env" {
  type = list(object({
    name        = string
    value       = optional(string)
    secret_name = optional(string)
  }))
  default = []
}

variable "secrets" {
  type    = map(string)
  default = {}
}

variable "cpu" {
  type    = number
  default = 0.5
}

variable "memory" {
  type    = string
  default = "1Gi"
}

variable "location" { type = string }
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

resource "azurerm_container_app_job" "this" {
  # Azure Container App Job names max at 32 chars.
  name                         = substr("caj-${var.name_prefix}-${var.name}", 0, 32)
  resource_group_name          = var.resource_group_name
  location                     = var.location
  container_app_environment_id = var.container_app_env_id

  replica_timeout_in_seconds = var.replica_timeout_in_seconds
  replica_retry_limit        = var.replica_retry_limit

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  schedule_trigger_config {
    cron_expression          = var.cron_expression
    parallelism              = 1
    replica_completion_count = 1
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
  }

  depends_on = [azurerm_role_assignment.kv_reader]
  tags       = var.tags

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }
}

output "id" { value = azurerm_container_app_job.this.id }
output "identity_id" { value = azurerm_user_assigned_identity.this.id }
output "principal_id" { value = azurerm_user_assigned_identity.this.principal_id }
