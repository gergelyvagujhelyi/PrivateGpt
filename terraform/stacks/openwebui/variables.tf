variable "client" {
  type        = string
  description = "Short client identifier (lowercase, used in resource names)"
  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.client))
    error_message = "client must be 2-10 lowercase alphanumeric chars."
  }
}

variable "environment" {
  type        = string
  description = "Environment: dev | test | prod"
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be one of dev, test, prod."
  }
}

variable "location" {
  type        = string
  description = "Azure region (e.g. westeurope)"
  default     = "westeurope"
}

variable "cost_center" {
  type        = string
  description = "Billing tag"
}

variable "openwebui_image" {
  type        = string
  description = "Fully qualified ACR image ref for OpenWebUI (e.g. acr.azurecr.io/openwebui:sha-abc123)"
}

variable "litellm_image" {
  type        = string
  description = "Fully qualified ACR image ref for LiteLLM proxy"
}

variable "langfuse_image" {
  type        = string
  description = "Fully qualified ACR image ref for Langfuse"
  default     = "langfuse/langfuse:2"
}

variable "aoai_models" {
  type = list(object({
    name     = string
    version  = string
    sku_name = string
    capacity = number
  }))
  description = "Azure OpenAI model deployments"
  default = [
    { name = "gpt-4o", version = "2024-08-06", sku_name = "Standard", capacity = 50 },
    { name = "text-embedding-3-large", version = "1", sku_name = "Standard", capacity = 50 },
  ]
}

variable "entra_group_admins_object_id" {
  type        = string
  description = "Entra ID group granted admin role in OpenWebUI"
}

variable "allowed_ip_ranges" {
  type        = list(string)
  description = "CIDR ranges allowed through Front Door WAF (empty = public)"
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
