// Plan-only tests for the feature-flag gating on the digest feature.
// Runs in the infra pipeline's Validate stage. No real Azure calls.

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

run "digest_disabled_by_default" {
  command = plan

  assert {
    condition     = length(module.digest_daily) == 0
    error_message = "digest_daily must not exist when feature is disabled"
  }
  assert {
    condition     = length(module.digest_weekly) == 0
    error_message = "digest_weekly must not exist when feature is disabled"
  }
  assert {
    condition     = length(module.communication_services) == 0
    error_message = "ACS must not be provisioned when feature is disabled"
  }
}

run "digest_enabled_provisions_jobs_and_acs" {
  command = plan

  variables {
    digest_image = "test.azurecr.io/digest:t"
    features = {
      digest = {
        enabled        = true
        daily_cron     = "0 7 * * *"
        weekly_cron    = "0 7 * * MON"
        sender_local   = "assistant"
        default_opt_in = false
      }
    }
  }

  assert {
    condition     = length(module.digest_daily) == 1
    error_message = "digest_daily must be provisioned when enabled"
  }
  assert {
    condition     = length(module.digest_weekly) == 1
    error_message = "digest_weekly must be provisioned when enabled"
  }
  assert {
    condition     = length(module.communication_services) == 1
    error_message = "ACS must be provisioned when enabled"
  }
}
