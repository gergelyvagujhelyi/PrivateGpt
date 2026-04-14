client      = "beta"
environment = "test"
location    = "westeurope"
cost_center = "CC-BETA-AI"

openwebui_image = "acroopenwebuishared.azurecr.io/openwebui:test"
litellm_image   = "acroopenwebuishared.azurecr.io/litellm:test"
langfuse_image  = "langfuse/langfuse:2"

features = {}

aoai_models = [
  { name = "gpt-4o-mini",            version = "2024-07-18", sku_name = "Standard", capacity = 30 },
  { name = "text-embedding-3-large", version = "1",          sku_name = "Standard", capacity = 20 },
]

entra_group_admins_object_id = "00000000-0000-0000-0000-000000000000"

allowed_ip_ranges = []

tags = {
  owner = "platform-ai"
}
