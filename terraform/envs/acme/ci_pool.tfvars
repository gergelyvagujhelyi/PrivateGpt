client   = "acme"
location = "westeurope"

# Reuse the spoke VNet that the openwebui stack created for this client.
# If not deployed yet, that stack must run first — this stack depends on its VNet.
resource_group_name  = "rg-owui-acme-dev"
virtual_network_name = "vnet-owui-acme-dev"

ado_organization_url = "https://dev.azure.com/YOUR-ADO-ORG"
ado_project_name     = "YOUR-ADO-PROJECT"
subscription_id      = "00000000-0000-0000-0000-000000000000"

log_analytics_id = "/subscriptions/.../resourceGroups/rg-owui-acme-dev/providers/Microsoft.OperationalInsights/workspaces/log-owui-acme-dev"

tags = {
  owner = "platform-ai"
}
