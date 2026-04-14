client      = "acme"
environment = "prod"
location    = "westeurope"
cost_center = "CC-ACME-AI"

openwebui_image = "acroopenwebuishared.azurecr.io/openwebui:stable"
litellm_image   = "acroopenwebuishared.azurecr.io/litellm:stable"
langfuse_image  = "langfuse/langfuse:2"
digest_image    = "acroopenwebuishared.azurecr.io/digest:stable"

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
  { name = "gpt-4o",                 version = "2024-08-06", sku_name = "Standard", capacity = 100 },
  { name = "gpt-4o-mini",            version = "2024-07-18", sku_name = "Standard", capacity = 200 },
  { name = "text-embedding-3-large", version = "1",          sku_name = "Standard", capacity = 100 },
]

entra_group_admins_object_id = "00000000-0000-0000-0000-000000000000"

allowed_ip_ranges = ["203.0.113.0/24"]

tags = {
  owner = "platform-ai"
}
