client      = "beta"
environment = "prod"
location    = "westeurope"
cost_center = "CC-BETA-AI"

openwebui_image = "acroopenwebuishared.azurecr.io/openwebui:stable"
litellm_image   = "acroopenwebuishared.azurecr.io/litellm:stable"
langfuse_image  = "langfuse/langfuse:2"

features = {}

foundry_deployments = {
  "claude-sonnet-4-5"      = { provider = "anthropic", model = "claude-sonnet-4-5", version = "1" }
  "claude-haiku-4-5"       = { provider = "anthropic", model = "claude-haiku-4-5",  version = "1" }
  "text-embedding-3-large" = { provider = "openai",    model = "text-embedding-3-large", version = "1", sku_name = "Standard", capacity = 50 }
}

entra_group_admins_object_id = "00000000-0000-0000-0000-000000000000"

allowed_ip_ranges = []

tags = {
  owner = "platform-ai"
}
