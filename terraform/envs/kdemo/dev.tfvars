client      = "kdemo"
environment = "dev"
location    = "westeurope"
cost_center = "CC-KOMPOSE-DEMO"

openwebui_image = "acroopenwebuishared.azurecr.io/openwebui:dev"
litellm_image   = "acroopenwebuishared.azurecr.io/litellm:dev"
langfuse_image  = "langfuse/langfuse:2"
digest_image    = "acroopenwebuishared.azurecr.io/digest:dev"
rag_image       = "acroopenwebuishared.azurecr.io/rag:dev"
admin_image     = "acroopenwebuishared.azurecr.io/admin:dev"

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
  "gpt-35-turbo"           = { provider = "openai", model = "gpt-35-turbo", version = "0125", sku_name = "Standard", capacity = 50 }
  "text-embedding-ada-002" = { provider = "openai", model = "text-embedding-ada-002", version = "2", sku_name = "Standard", capacity = 50 }
}

entra_group_admins_object_id = "00000000-0000-0000-0000-000000000000"

allowed_ip_ranges = []

tags = {
  owner = "platform-ai"
}
