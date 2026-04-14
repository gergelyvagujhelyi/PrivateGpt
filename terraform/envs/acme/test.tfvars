client      = "acme"
environment = "test"
location    = "westeurope"
cost_center = "CC-ACME-AI"

openwebui_image = "acroopenwebuishared.azurecr.io/openwebui:test"
litellm_image   = "acroopenwebuishared.azurecr.io/litellm:test"
langfuse_image  = "langfuse/langfuse:2"

aoai_models = [
  { name = "gpt-4o",                 version = "2024-08-06", sku_name = "Standard", capacity = 30 },
  { name = "gpt-4o-mini",            version = "2024-07-18", sku_name = "Standard", capacity = 100 },
  { name = "text-embedding-3-large", version = "1",          sku_name = "Standard", capacity = 50 },
]

entra_group_admins_object_id = "00000000-0000-0000-0000-000000000000"

allowed_ip_ranges = []

tags = {
  owner = "platform-ai"
}
