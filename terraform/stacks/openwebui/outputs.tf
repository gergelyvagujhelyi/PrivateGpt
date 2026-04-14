output "frontdoor_endpoint" {
  value       = module.frontdoor.endpoint
  description = "Public HTTPS endpoint for end users"
}

output "resource_group" {
  value = azurerm_resource_group.this.name
}

output "log_analytics_workspace_id" {
  value = module.observability.log_analytics_id
}

output "foundry_endpoint" {
  value     = module.ai_foundry.foundry_endpoint
  sensitive = true
}

output "foundry_deployments" {
  value = module.ai_foundry.deployments
}

output "langfuse_internal_url" {
  value = "https://${module.langfuse.fqdn}"
}

output "digest_enabled" {
  value = local.digest_enabled
}

output "digest_sender_address" {
  value = try(module.communication_services[0].sender_address, null)
}

output "rag_enabled" {
  value = local.rag_enabled
}

output "rag_container_name" {
  value = module.storage.rag_sources_container_name
}

output "admin_enabled" {
  value = local.admin_enabled
}

output "admin_fqdn" {
  value = try(module.admin[0].fqdn, null)
}
