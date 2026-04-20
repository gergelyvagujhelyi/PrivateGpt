locals {
  name_prefix = "owui-${var.client}"
  base_tags = merge(
    { client = var.client, product = "ci-pool", managed_by = "terraform" },
    var.tags,
  )
}

module "pool" {
  source = "../../modules/managed_devops_pool"

  name_prefix          = local.name_prefix
  resource_group_name  = var.resource_group_name
  location             = var.location
  virtual_network_name = var.virtual_network_name
  agent_subnet_cidr    = var.agent_subnet_cidr
  ado_organization_url = var.ado_organization_url
  ado_project_name     = var.ado_project_name

  subscription_scope_for_contributor = "/subscriptions/${var.subscription_id}"

  log_analytics_id = var.log_analytics_id
  tags             = local.base_tags
}

output "pool_name" {
  value = module.pool.pool_name
}

output "pool_id" {
  value = module.pool.pool_id
}
