// Plan-only tests for the WAF signup-avatar XSS exclusion flag.
// Asserts the module's DRS override block flips with waf_allow_signup_avatar
// so a future refactor of modules/frontdoor can't silently drop the override.

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

run "waf_signup_avatar_disabled_by_default" {
  command = plan

  assert {
    condition     = module.frontdoor.signup_avatar_override_count == 0
    error_message = "profile_image_url exclusion must not be declared when waf_allow_signup_avatar defaults to false"
  }
}

run "waf_signup_avatar_opt_in_adds_override" {
  command = plan

  variables {
    waf_allow_signup_avatar = true
  }

  assert {
    condition     = module.frontdoor.signup_avatar_override_count == 1
    error_message = "profile_image_url exclusion must be declared when waf_allow_signup_avatar = true"
  }
}
