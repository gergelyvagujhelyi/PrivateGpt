locals {
  name_prefix = "owui-${var.client}-${var.environment}"

  base_tags = merge(
    {
      client      = var.client
      environment = var.environment
      product     = "openwebui"
      cost_center = var.cost_center
      managed_by  = "terraform"
    },
    var.tags,
  )
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.base_tags
}

module "network" {
  source = "../../modules/network"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = local.base_tags
}

module "observability" {
  source = "../../modules/observability"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = local.base_tags
}

module "keyvault" {
  source = "../../modules/keyvault"

  name_prefix            = local.name_prefix
  resource_group_name    = azurerm_resource_group.this.name
  location               = var.location
  private_endpoint_subnet_id = module.network.pe_subnet_id
  private_dns_zone_id    = module.network.kv_private_dns_zone_id
  log_analytics_id       = module.observability.log_analytics_id
  tags                   = local.base_tags
}

module "postgres" {
  source = "../../modules/postgres"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  delegated_subnet_id = module.network.postgres_subnet_id
  private_dns_zone_id = module.network.postgres_private_dns_zone_id
  key_vault_id        = module.keyvault.id
  log_analytics_id    = module.observability.log_analytics_id
  tags                = local.base_tags
}

module "storage" {
  source = "../../modules/storage"

  name_prefix                = local.name_prefix
  resource_group_name        = azurerm_resource_group.this.name
  location                   = var.location
  private_endpoint_subnet_id = module.network.pe_subnet_id
  private_dns_zone_id        = module.network.blob_private_dns_zone_id
  log_analytics_id           = module.observability.log_analytics_id
  tags                       = local.base_tags
}

module "ai_foundry" {
  source = "../../modules/ai_foundry"

  name_prefix                = local.name_prefix
  resource_group_name        = azurerm_resource_group.this.name
  location                   = var.location
  private_endpoint_subnet_id = module.network.pe_subnet_id
  private_dns_zone_ids       = module.network.ai_services_private_dns_zone_ids
  blob_private_dns_zone_id   = module.network.blob_private_dns_zone_id
  log_analytics_id           = module.observability.log_analytics_id
  key_vault_id               = module.keyvault.id
  application_insights_id    = module.observability.app_insights_id
  deployments                = var.foundry_deployments
  tags                       = local.base_tags
}

# Per-MaaS-deployment env vars: LiteLLM's azure_ai/* route needs the exact
# inferenceEndpoint.uri for each Claude model. We upper-case the model key
# and hand each one to the LiteLLM container.
locals {
  claude_endpoint_env = [
    for name, uri in module.ai_foundry.claude_endpoints :
    { name = "ENDPOINT_${replace(upper(name), "-", "_")}", value = uri }
  ]
  claude_key_secret_env = [
    for name, _ in module.ai_foundry.claude_key_secret_refs :
    { name = "KEY_${replace(upper(name), "-", "_")}", secret_name = "maas-${name}-key" }
  ]
  claude_key_secret_map = {
    for name, ref in module.ai_foundry.claude_key_secret_refs :
    "maas-${name}-key" => ref
  }
}

module "container_app_env" {
  source = "../../modules/container_app_env"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  infrastructure_subnet_id = module.network.aca_subnet_id
  log_analytics_id    = module.observability.log_analytics_id
  tags                = local.base_tags
}

module "langfuse" {
  source = "../../modules/container_app"

  name                 = "langfuse"
  name_prefix          = local.name_prefix
  resource_group_name  = azurerm_resource_group.this.name
  container_app_env_id = module.container_app_env.id
  image                = var.langfuse_image
  target_port          = 3000
  ingress_external     = false
  key_vault_id         = module.keyvault.id

  env = [
    { name = "DATABASE_URL", secret_name = "langfuse-db-url" },
    { name = "NEXTAUTH_SECRET", secret_name = "langfuse-nextauth-secret" },
    { name = "SALT", secret_name = "langfuse-salt" },
    { name = "NEXTAUTH_URL", value = "https://langfuse.${local.name_prefix}.internal" },
    { name = "TELEMETRY_ENABLED", value = "false" },
  ]

  secrets = {
    "langfuse-db-url"          = module.postgres.langfuse_connection_string
    "langfuse-nextauth-secret" = module.keyvault.langfuse_nextauth_secret_ref
    "langfuse-salt"            = module.keyvault.langfuse_salt_ref
  }

  cpu    = 0.5
  memory = "1Gi"
  min_replicas = 1
  max_replicas = 3

  tags = local.base_tags
}

module "litellm" {
  source = "../../modules/container_app"

  name                 = "litellm"
  name_prefix          = local.name_prefix
  resource_group_name  = azurerm_resource_group.this.name
  container_app_env_id = module.container_app_env.id
  image                = var.litellm_image
  target_port          = 4000
  ingress_external     = false
  key_vault_id         = module.keyvault.id

  env = concat(
    [
      { name = "AZURE_API_KEY",       secret_name = "foundry-ai-services-key" },
      { name = "AZURE_API_BASE",      value       = module.ai_foundry.endpoint },
      { name = "AZURE_API_VERSION",   value       = "2024-10-21" },
      { name = "LANGFUSE_PUBLIC_KEY", secret_name = "langfuse-pk" },
      { name = "LANGFUSE_SECRET_KEY", secret_name = "langfuse-sk" },
      { name = "LANGFUSE_HOST",       value       = "https://${module.langfuse.fqdn}" },
      { name = "LITELLM_MASTER_KEY",  secret_name = "litellm-master-key" },
    ],
    local.claude_endpoint_env,
    local.claude_key_secret_env,
  )

  secrets = merge(
    {
      "foundry-ai-services-key" = module.ai_foundry.ai_services_key_secret_ref
      "langfuse-pk"             = module.keyvault.langfuse_pk_ref
      "langfuse-sk"             = module.keyvault.langfuse_sk_ref
      "litellm-master-key"      = module.keyvault.litellm_master_key_ref
    },
    local.claude_key_secret_map,
  )

  cpu    = 0.5
  memory = "1Gi"
  min_replicas = 1
  max_replicas = 10

  tags = local.base_tags
}

module "openwebui" {
  source = "../../modules/container_app"

  name                 = "openwebui"
  name_prefix          = local.name_prefix
  resource_group_name  = azurerm_resource_group.this.name
  container_app_env_id = module.container_app_env.id
  image                = var.openwebui_image
  target_port          = 8080
  ingress_external     = false
  key_vault_id         = module.keyvault.id

  env = [
    { name = "DATABASE_URL",          secret_name = "openwebui-db-url" },
    { name = "OPENAI_API_BASE_URL",   value = "https://${module.litellm.fqdn}/v1" },
    { name = "OPENAI_API_KEY",        secret_name = "litellm-master-key" },
    { name = "WEBUI_AUTH",            value = "true" },
    { name = "ENABLE_OAUTH_SIGNUP",   value = "true" },
    { name = "OAUTH_PROVIDER_NAME",   value = "Microsoft" },
    { name = "OAUTH_CLIENT_ID",       secret_name = "entra-client-id" },
    { name = "OAUTH_CLIENT_SECRET",   secret_name = "entra-client-secret" },
    { name = "OPENID_PROVIDER_URL",   value = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0/.well-known/openid-configuration" },
    { name = "STORAGE_PROVIDER",      value = "s3" },
    { name = "S3_ENDPOINT_URL",       value = module.storage.blob_endpoint },
    { name = "S3_BUCKET_NAME",        value = module.storage.uploads_container_name },
    { name = "VECTOR_DB",             value = "pgvector" },
    { name = "PGVECTOR_DB_URL",       secret_name = "openwebui-db-url" },
  ]

  secrets = {
    "openwebui-db-url"     = module.postgres.openwebui_connection_string
    "litellm-master-key"   = module.keyvault.litellm_master_key_ref
    "entra-client-id"      = module.keyvault.entra_client_id_ref
    "entra-client-secret"  = module.keyvault.entra_client_secret_ref
  }

  cpu    = 1.0
  memory = "2Gi"
  min_replicas = var.environment == "prod" ? 2 : 1
  max_replicas = var.environment == "prod" ? 10 : 3

  tags = local.base_tags
}

module "frontdoor" {
  source = "../../modules/frontdoor"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  origin_host_name    = module.openwebui.fqdn
  origin_host_header  = module.openwebui.fqdn
  allowed_ip_ranges   = var.allowed_ip_ranges
  log_analytics_id    = module.observability.log_analytics_id

  # Each enabled secondary feature that needs public reach gets its own Front Door endpoint.
  secondary_origins = merge(
    local.admin_enabled ? { admin = { host_name = module.admin[0].fqdn } } : {},
  )

  tags = local.base_tags
}

# ─────────────────────────────────────────────────────────────────────
# Optional features
# ─────────────────────────────────────────────────────────────────────

locals {
  digest_enabled = try(var.features.digest.enabled, false)
}

module "communication_services" {
  count  = local.digest_enabled ? 1 : 0
  source = "../../modules/communication_services"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  key_vault_id        = module.keyvault.id
  log_analytics_id    = module.observability.log_analytics_id
  sender_local_part   = try(var.features.digest.sender_local, "assistant")
  tags                = local.base_tags
}

locals {
  digest_env_common = local.digest_enabled ? [
    { name = "DATABASE_URL",          secret_name = "openwebui-db-url" },
    { name = "OPENAI_BASE_URL",       value = "https://${module.litellm.fqdn}/v1" },
    { name = "OPENAI_API_KEY",        secret_name = "litellm-master-key" },
    { name = "LANGFUSE_HOST",         value = "https://${module.langfuse.fqdn}" },
    { name = "LANGFUSE_PUBLIC_KEY",   secret_name = "langfuse-pk" },
    { name = "LANGFUSE_SECRET_KEY",   secret_name = "langfuse-sk" },
    { name = "ACS_CONNECTION_STRING", secret_name = "acs-connection-string" },
    { name = "ACS_SENDER",            value = module.communication_services[0].sender_address },
    { name = "UNSUB_HMAC_KEY",        secret_name = "unsub-hmac-key" },
    { name = "PUBLIC_BASE_URL",       value = module.frontdoor.endpoint },
  ] : []

  digest_secrets_common = local.digest_enabled ? {
    "openwebui-db-url"       = module.postgres.openwebui_connection_string
    "litellm-master-key"     = module.keyvault.litellm_master_key_ref
    "langfuse-pk"            = module.keyvault.langfuse_pk_ref
    "langfuse-sk"            = module.keyvault.langfuse_sk_ref
    "acs-connection-string"  = module.communication_services[0].connection_string_secret_ref
    "unsub-hmac-key"         = module.communication_services[0].unsub_hmac_secret_ref
  } : {}
}

module "digest_daily" {
  count  = local.digest_enabled ? 1 : 0
  source = "../../modules/container_app_job"

  name                 = "digest-daily"
  name_prefix          = local.name_prefix
  resource_group_name  = azurerm_resource_group.this.name
  container_app_env_id = module.container_app_env.id
  key_vault_id         = module.keyvault.id
  image                = var.digest_image
  cron_expression      = try(var.features.digest.daily_cron, "0 7 * * *")

  env     = concat(local.digest_env_common, [{ name = "CADENCE", value = "daily" }])
  secrets = local.digest_secrets_common

  tags = local.base_tags
}

module "digest_weekly" {
  count  = local.digest_enabled ? 1 : 0
  source = "../../modules/container_app_job"

  name                 = "digest-weekly"
  name_prefix          = local.name_prefix
  resource_group_name  = azurerm_resource_group.this.name
  container_app_env_id = module.container_app_env.id
  key_vault_id         = module.keyvault.id
  image                = var.digest_image
  cron_expression      = try(var.features.digest.weekly_cron, "0 7 * * MON")

  env     = concat(local.digest_env_common, [{ name = "CADENCE", value = "weekly" }])
  secrets = local.digest_secrets_common

  tags = local.base_tags
}

# ─── RAG ingestion worker (optional) ───

locals {
  rag_enabled = try(var.features.rag.enabled, false)
}

module "rag_ingest" {
  count  = local.rag_enabled ? 1 : 0
  source = "../../modules/container_app_job"

  name                 = "rag-ingest"
  name_prefix          = local.name_prefix
  resource_group_name  = azurerm_resource_group.this.name
  container_app_env_id = module.container_app_env.id
  key_vault_id         = module.keyvault.id
  image                = var.rag_image
  cron_expression      = try(var.features.rag.ingest_cron, "*/15 * * * *")

  env = [
    { name = "DATABASE_URL",     secret_name = "openwebui-db-url" },
    { name = "BLOB_ACCOUNT_URL", value       = "https://${module.storage.name}.blob.core.windows.net" },
    { name = "BLOB_CONTAINER",   value       = module.storage.rag_sources_container_name },
    { name = "NAMESPACE_PREFIX", value       = try(var.features.rag.namespace_prefix, "") },
    { name = "OPENAI_BASE_URL",  value       = "https://${module.litellm.fqdn}/v1" },
    { name = "OPENAI_API_KEY",   secret_name = "litellm-master-key" },
  ]

  secrets = {
    "openwebui-db-url"   = module.postgres.openwebui_connection_string
    "litellm-master-key" = module.keyvault.litellm_master_key_ref
  }

  cpu    = 1.0
  memory = "2Gi"

  tags = local.base_tags
}

resource "azurerm_role_assignment" "rag_blob_reader" {
  count                = local.rag_enabled ? 1 : 0
  scope                = module.storage.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = module.rag_ingest[0].principal_id
}

# ─── Admin UI (optional TypeScript + React Container App) ───

locals {
  admin_enabled = try(var.features.admin_ui.enabled, false)
}

module "admin" {
  count  = local.admin_enabled ? 1 : 0
  source = "../../modules/container_app"

  name                 = "admin"
  name_prefix          = local.name_prefix
  resource_group_name  = azurerm_resource_group.this.name
  container_app_env_id = module.container_app_env.id
  image                = var.admin_image
  target_port          = 4000
  ingress_external     = false
  key_vault_id         = module.keyvault.id

  env = [
    { name = "DATABASE_URL",         secret_name = "openwebui-db-url" },
    { name = "LANGFUSE_HOST",        value       = "https://${module.langfuse.fqdn}" },
    { name = "LANGFUSE_PUBLIC_KEY",  secret_name = "langfuse-pk" },
    { name = "LANGFUSE_SECRET_KEY",  secret_name = "langfuse-sk" },
    { name = "ENTRA_TENANT_ID",      value       = data.azurerm_client_config.current.tenant_id },
    { name = "ADMIN_API_AUDIENCE",   value       = var.entra_admin_app_client_id },
  ]

  secrets = {
    "openwebui-db-url" = module.postgres.openwebui_connection_string
    "langfuse-pk"      = module.keyvault.langfuse_pk_ref
    "langfuse-sk"      = module.keyvault.langfuse_sk_ref
  }

  cpu    = 0.5
  memory = "1Gi"
  min_replicas = 1
  max_replicas = 3

  tags = local.base_tags
}

data "azurerm_client_config" "current" {}
