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

module "openai" {
  source = "../../modules/openai"

  name_prefix                = local.name_prefix
  resource_group_name        = azurerm_resource_group.this.name
  location                   = var.location
  private_endpoint_subnet_id = module.network.pe_subnet_id
  private_dns_zone_id        = module.network.openai_private_dns_zone_id
  log_analytics_id           = module.observability.log_analytics_id
  model_deployments          = var.aoai_models
  tags                       = local.base_tags
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

  env = [
    { name = "AZURE_API_KEY", secret_name = "aoai-key" },
    { name = "AZURE_API_BASE", value = module.openai.endpoint },
    { name = "AZURE_API_VERSION", value = "2024-08-01-preview" },
    { name = "LANGFUSE_PUBLIC_KEY", secret_name = "langfuse-pk" },
    { name = "LANGFUSE_SECRET_KEY", secret_name = "langfuse-sk" },
    { name = "LANGFUSE_HOST", value = "https://${module.langfuse.fqdn}" },
    { name = "LITELLM_MASTER_KEY", secret_name = "litellm-master-key" },
  ]

  secrets = {
    "aoai-key"           = module.openai.key_vault_secret_ref
    "langfuse-pk"        = module.keyvault.langfuse_pk_ref
    "langfuse-sk"        = module.keyvault.langfuse_sk_ref
    "litellm-master-key" = module.keyvault.litellm_master_key_ref
  }

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
  tags                = local.base_tags
}

data "azurerm_client_config" "current" {}
