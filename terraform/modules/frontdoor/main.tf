variable "name_prefix" { type = string }
variable "resource_group_name" { type = string }
variable "origin_host_name" { type = string }
variable "origin_host_header" { type = string }
variable "allowed_ip_ranges" {
  type    = list(string)
  default = []
}

# Optional secondary origins (e.g. admin UI) get their own Front Door endpoint
# on the same profile. Key is the endpoint slug; value is the internal FQDN.
variable "secondary_origins" {
  type = map(object({
    host_name = string
  }))
  default = {}
}

variable "log_analytics_id" { type = string }
variable "tags" { type = map(string) }

resource "azurerm_cdn_frontdoor_profile" "this" {
  name                = "afd-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  sku_name            = "Premium_AzureFrontDoor"
  tags                = var.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "this" {
  name                     = "ep-${var.name_prefix}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  tags                     = var.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "this" {
  name                     = "og-${var.name_prefix}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  session_affinity_enabled = true

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }

  health_probe {
    path                = "/health"
    request_type        = "HEAD"
    protocol            = "Https"
    interval_in_seconds = 60
  }
}

resource "azurerm_cdn_frontdoor_origin" "this" {
  name                          = "origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this.id

  enabled                        = true
  host_name                      = var.origin_host_name
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = var.origin_host_header
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
}

resource "azurerm_cdn_frontdoor_route" "this" {
  name                          = "route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.this.id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  link_to_default_domain = true
  https_redirect_enabled = true
}

# ─── Secondary origins (each gets its own endpoint on this profile) ───
resource "azurerm_cdn_frontdoor_endpoint" "secondary" {
  for_each                 = var.secondary_origins
  name                     = "ep-${var.name_prefix}-${each.key}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  tags                     = var.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "secondary" {
  for_each                 = var.secondary_origins
  name                     = "og-${var.name_prefix}-${each.key}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  session_affinity_enabled = true

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }

  health_probe {
    path                = "/health"
    request_type        = "HEAD"
    protocol            = "Https"
    interval_in_seconds = 60
  }
}

resource "azurerm_cdn_frontdoor_origin" "secondary" {
  for_each                      = var.secondary_origins
  name                          = "origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.secondary[each.key].id

  enabled                        = true
  host_name                      = each.value.host_name
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = each.value.host_name
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
}

resource "azurerm_cdn_frontdoor_route" "secondary" {
  for_each                      = var.secondary_origins
  name                          = "route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.secondary[each.key].id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.secondary[each.key].id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.secondary[each.key].id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  link_to_default_domain = true
  https_redirect_enabled = true
}

resource "azurerm_cdn_frontdoor_firewall_policy" "this" {
  name                = "waf${replace(var.name_prefix, "-", "")}"
  resource_group_name = var.resource_group_name
  sku_name            = azurerm_cdn_frontdoor_profile.this.sku_name
  enabled             = true
  mode                = "Prevention"

  managed_rule {
    type    = "Microsoft_DefaultRuleSet"
    version = "2.1"
    action  = "Block"
  }

  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.1"
    action  = "Block"
  }

  dynamic "custom_rule" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      name     = "AllowList"
      enabled  = true
      priority = 1
      type     = "MatchRule"
      action   = "Block"

      match_condition {
        match_variable     = "RemoteAddr"
        operator           = "IPMatch"
        negation_condition = true
        match_values       = var.allowed_ip_ranges
      }
    }
  }

  tags = var.tags
}

resource "azurerm_cdn_frontdoor_security_policy" "this" {
  name                     = "sec-${var.name_prefix}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.this.id

      association {
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.this.id
        }
        dynamic "domain" {
          for_each = azurerm_cdn_frontdoor_endpoint.secondary
          content {
            cdn_frontdoor_domain_id = domain.value.id
          }
        }
        patterns_to_match = ["/*"]
      }
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  name                       = "diag"
  target_resource_id         = azurerm_cdn_frontdoor_profile.this.id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log { category = "FrontDoorAccessLog" }
  enabled_log { category = "FrontDoorHealthProbeLog" }
  enabled_log { category = "FrontDoorWebApplicationFirewallLog" }
  metric { category = "AllMetrics" }
}

output "endpoint" { value = "https://${azurerm_cdn_frontdoor_endpoint.this.host_name}" }
output "profile_id" { value = azurerm_cdn_frontdoor_profile.this.id }

output "secondary_endpoints" {
  value = { for k, e in azurerm_cdn_frontdoor_endpoint.secondary : k => "https://${e.host_name}" }
}
