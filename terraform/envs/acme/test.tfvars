client      = "acme"
environment = "test"
location    = "westeurope"
cost_center = "CC-ACME-AI"

openwebui_image = "acroopenwebuishared.azurecr.io/openwebui:test"
litellm_image   = "acroopenwebuishared.azurecr.io/litellm:test"
langfuse_image  = "langfuse/langfuse:2"
digest_image    = "acroopenwebuishared.azurecr.io/digest:test"
rag_image       = "acroopenwebuishared.azurecr.io/rag:test"
admin_image     = "acroopenwebuishared.azurecr.io/admin:test"

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
  "text-embedding-3-large" = { provider = "openai",    model = "text-embedding-3-large", version = "1", sku_name = "Standard", capacity = 50 }
}

entra_group_admins_object_id = "00000000-0000-0000-0000-000000000000"

allowed_ip_ranges = []

tags = {
  owner = "platform-ai"
}
