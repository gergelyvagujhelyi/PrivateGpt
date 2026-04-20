// Plan-only tests for the feature-flag gating on the admin UI feature.
// Covers: admin Container App creation + Front Door secondary endpoint.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000000"
      subscription_id = "00000000-0000-0000-0000-000000000000"
      object_id       = "00000000-0000-0000-0000-000000000000"
    }
  }
}
mock_provider "azuread" {}
mock_provider "azapi" {}
mock_provider "random" {}

variables {
  client                       = "tst"
  environment                  = "dev"
  location                     = "westeurope"
  cost_center                  = "CC-TST"
  openwebui_image              = "test.azurecr.io/openwebui:t"
  litellm_image                = "test.azurecr.io/litellm:t"
  langfuse_image               = "langfuse/langfuse:2"
  entra_group_admins_object_id = "00000000-0000-0000-0000-000000000000"
}

run "admin_ui_disabled_by_default" {
  command = plan

  assert {
    condition     = length(module.admin) == 0
    error_message = "admin Container App must not exist when feature is disabled"
  }
  assert {
    condition     = length(module.frontdoor.secondary_endpoints) == 0
    error_message = "Front Door secondary endpoint must not exist when admin_ui is disabled"
  }
}

run "admin_ui_enabled_provisions_app_and_frontdoor_route" {
  command = plan

  variables {
    admin_image               = "test.azurecr.io/admin:t"
    entra_admin_app_client_id = "00000000-0000-0000-0000-000000000000"
    features = {
      admin_ui = { enabled = true }
    }
  }

  assert {
    condition     = length(module.admin) == 1
    error_message = "admin Container App must be provisioned when feature is enabled"
  }
  assert {
    condition     = contains(keys(module.frontdoor.secondary_endpoints), "admin")
    error_message = "Front Door secondary endpoint 'admin' must be provisioned when feature is enabled"
  }
}
