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

# Private Link target for all origins — the internal Container App Environment.
# Front Door Premium reaches the CAE's private LB via a managed PE; each origin
# creates one PE connection on the CAE that must be approved before traffic flows.
variable "origin_location" { type = string }
variable "private_link_target_id" { type = string }

# Per-client opt-in to exempt profile_image_url from the DRS XSS rule group.
# Required for OpenWebUI's local signup flow (base64 avatar trips 941130/941170);
# leave false for clients that sign in via OAuth only or whose compliance posture
# forbids managed-rule exclusions.
variable "allow_signup_avatar_xss" {
  type    = bool
  default = false
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
    request_type        = "GET"
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

  private_link {
    request_message        = "FD -> CAE"
    target_type            = "managedEnvironments"
    location               = var.origin_location
    private_link_target_id = var.private_link_target_id
  }
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
    request_type        = "GET"
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

  private_link {
    request_message        = "FD -> CAE"
    target_type            = "managedEnvironments"
    location               = var.origin_location
    private_link_target_id = var.private_link_target_id
  }
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

    # OpenWebUI's signup POST includes a base64 data: URI avatar in
    # `profile_image_url`, which DRS 2.1 XSS rules 941130/941170 score as an
    # injection attempt (combined score ≥ 10 → 949110 blocks with 403).
    # Per-client opt-in — scoped to the XSS rule group only so SQLi / RCE /
    # LFI categories still evaluate the field.
    dynamic "override" {
      for_each = var.allow_signup_avatar_xss ? [1] : []
      content {
        rule_group_name = "XSS"

        exclusion {
          match_variable = "RequestBodyJsonArgNames"
          operator       = "Equals"
          selector       = "profile_image_url"
        }
      }
    }
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

# Test surface — exposed so tftest can assert the DRS override flips with the flag.
output "drs_override_count" {
  value = length([
    for m in azurerm_cdn_frontdoor_firewall_policy.this.managed_rule :
    m.override if m.type == "Microsoft_DefaultRuleSet"
  ][0])
}
