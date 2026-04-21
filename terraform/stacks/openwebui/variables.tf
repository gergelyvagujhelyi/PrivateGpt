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

variable "foundry_location" {
  type        = string
  description = "Region for AI Foundry + AI Services. Defaults to var.location; override when interactive AOAI quota lives elsewhere."
  default     = ""
}

variable "foundry_private_endpoints_enabled" {
  type        = bool
  description = "Whether to create private endpoints for AI Services + hub storage. Must be false when foundry_location differs from the VNet region (cross-region PE is rejected for these resource types)."
  default     = true
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

variable "foundry_deployments" {
  description = "Model deployments on Azure AI Foundry. provider = openai | anthropic"
  type = map(object({
    provider = string
    model    = string
    version  = string
    sku_name = optional(string, "Standard")
    capacity = optional(number, 50)
  }))
  default = {
    "claude-sonnet-4-5" = {
      provider = "anthropic"
      model    = "claude-sonnet-4-5"
      version  = "1"
    }
    "claude-haiku-4-5" = {
      provider = "anthropic"
      model    = "claude-haiku-4-5"
      version  = "1"
    }
    "text-embedding-3-large" = {
      provider = "openai"
      model    = "text-embedding-3-large"
      version  = "1"
      sku_name = "Standard"
      capacity = 50
    }
  }
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

variable "waf_allow_signup_avatar" {
  type        = bool
  description = "Exempt profile_image_url (OpenWebUI signup avatar) from the DRS XSS rule group (REQUEST-941). Set true only for clients that rely on OpenWebUI's local signup flow with the default base64 avatar; otherwise DRS 2.1 941130/941170 false-positive and WAF returns 403 on /api/v1/auths/signup."
  default     = false
}

variable "digest_image" {
  type        = string
  description = "ACR image ref for the digest worker (only used when features.digest.enabled)"
  default     = ""
}

variable "rag_image" {
  type        = string
  description = "ACR image ref for the RAG ingestion worker (only used when features.rag.enabled)"
  default     = ""
}

variable "admin_image" {
  type        = string
  description = "ACR image ref for the admin UI (only used when features.admin_ui.enabled)"
  default     = ""
}

variable "entra_admin_app_client_id" {
  type        = string
  description = "Entra app registration client ID for the admin UI (audience for API JWTs)"
  default     = ""
}

variable "features" {
  description = "Per-client optional features. Unset features are not provisioned."
  type = object({
    digest = optional(object({
      enabled        = bool
      daily_cron     = optional(string, "0 7 * * *")
      weekly_cron    = optional(string, "0 7 * * MON")
      sender_local   = optional(string, "assistant")
      default_opt_in = optional(bool, false)
    }), { enabled = false })

    rag = optional(object({
      enabled          = bool
      ingest_cron      = optional(string, "*/15 * * * *")
      namespace_prefix = optional(string, "")
    }), { enabled = false })

    admin_ui = optional(object({
      enabled = bool
    }), { enabled = false })
  })
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
