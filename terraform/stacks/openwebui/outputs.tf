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

output "openai_endpoint" {
  value     = module.openai.endpoint
  sensitive = true
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
