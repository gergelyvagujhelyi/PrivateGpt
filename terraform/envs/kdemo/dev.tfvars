client           = "kdemo"
environment      = "dev"
location         = "westeurope"
foundry_location = "swedencentral"
cost_center      = "CC-KOMPOSE-DEMO"

openwebui_image = "ghcr.io/open-webui/open-webui:main"
litellm_image   = "ghcr.io/berriai/litellm:main-stable"
langfuse_image  = "langfuse/langfuse:2"
digest_image    = "mcr.microsoft.com/azuredocs/aci-helloworld:latest"
rag_image       = "mcr.microsoft.com/azuredocs/aci-helloworld:latest"
admin_image     = "mcr.microsoft.com/azuredocs/aci-helloworld:latest"

entra_admin_app_client_id = "00000000-0000-0000-0000-000000000000"

features = {
  digest = {
    enabled        = false
    daily_cron     = "0 6 * * *"
    weekly_cron    = "0 6 * * MON"
    sender_local   = "assistant"
    default_opt_in = false
  }
  rag = {
    enabled          = false
    ingest_cron      = "*/15 * * * *"
    namespace_prefix = ""
  }
  admin_ui = {
    enabled = false
  }
}

foundry_private_endpoints_enabled = false
foundry_deployments = {
  "gpt-4o"                 = { provider = "openai", model = "gpt-4o", version = "2024-11-20", sku_name = "Standard", capacity = 30 }
  "text-embedding-3-large" = { provider = "openai", model = "text-embedding-3-large", version = "1", sku_name = "Standard", capacity = 50 }
}

entra_group_admins_object_id = "00000000-0000-0000-0000-000000000000"

allowed_ip_ranges = []

tags = {
  owner = "platform-ai"
}
