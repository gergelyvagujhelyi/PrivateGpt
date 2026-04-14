client      = "acme"
environment = "prod"
location    = "westeurope"
cost_center = "CC-ACME-AI"

openwebui_image = "acroopenwebuishared.azurecr.io/openwebui:stable"
litellm_image   = "acroopenwebuishared.azurecr.io/litellm:stable"
langfuse_image  = "langfuse/langfuse:2"
digest_image    = "acroopenwebuishared.azurecr.io/digest:stable"
rag_image       = "acroopenwebuishared.azurecr.io/rag:stable"
admin_image     = "acroopenwebuishared.azurecr.io/admin:stable"

entra_admin_app_client_id = "00000000-0000-0000-0000-000000000000"

features = {
  digest = {
    enabled        = true
    daily_cron     = "0 6 * * *"
    weekly_cron    = "0 6 * * MON"
    sender_local   = "assistant"
    default_opt_in = false
  }
  rag = {
    enabled          = true
    ingest_cron      = "*/15 * * * *"
    namespace_prefix = ""
  }
  admin_ui = {
    enabled = true
  }
}

foundry_deployments = {
  "claude-sonnet-4-5"      = { provider = "anthropic", model = "claude-sonnet-4-5", version = "1" }
  "claude-haiku-4-5"       = { provider = "anthropic", model = "claude-haiku-4-5",  version = "1" }
  "text-embedding-3-large" = { provider = "openai",    model = "text-embedding-3-large", version = "1", sku_name = "Standard", capacity = 100 }
}

entra_group_admins_object_id = "00000000-0000-0000-0000-000000000000"

allowed_ip_ranges = ["203.0.113.0/24"]

tags = {
  owner = "platform-ai"
}
