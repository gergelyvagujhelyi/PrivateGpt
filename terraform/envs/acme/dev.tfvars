client      = "acme"
environment = "dev"
location    = "westeurope"
cost_center = "CC-ACME-AI"

openwebui_image = "acroopenwebuishared.azurecr.io/openwebui:dev"
litellm_image   = "acroopenwebuishared.azurecr.io/litellm:dev"
langfuse_image  = "langfuse/langfuse:2"
digest_image    = "acroopenwebuishared.azurecr.io/digest:dev"

features = {
  digest = {
    enabled        = true
    daily_cron     = "0 6 * * *"
    weekly_cron    = "0 6 * * MON"
    sender_local   = "assistant"
    default_opt_in = false
  }
}

aoai_models = [
  { name = "gpt-4o",                 version = "2024-08-06", sku_name = "Standard", capacity = 20 },
  { name = "gpt-4o-mini",            version = "2024-07-18", sku_name = "Standard", capacity = 50 },
  { name = "text-embedding-3-large", version = "1",          sku_name = "Standard", capacity = 50 },
]

entra_group_admins_object_id = "00000000-0000-0000-0000-000000000000"

allowed_ip_ranges = []

tags = {
  owner = "platform-ai"
}
