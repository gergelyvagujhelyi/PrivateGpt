// Plan-only tests for the feature-flag gating on the RAG feature.
// Mirrors digest_gating.tftest.hcl — same shape, different flag.

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

run "rag_disabled_by_default" {
  command = plan

  assert {
    condition     = length(module.rag_ingest) == 0
    error_message = "rag_ingest must not exist when feature is disabled"
  }
  assert {
    condition     = length(azurerm_role_assignment.rag_blob_reader) == 0
    error_message = "rag_blob_reader role assignment must not exist when feature is disabled"
  }
}

run "rag_enabled_provisions_job_and_role" {
  command = plan

  variables {
    rag_image = "test.azurecr.io/rag:t"
    features = {
      rag = {
        enabled          = true
        ingest_cron      = "*/15 * * * *"
        namespace_prefix = ""
      }
    }
  }

  assert {
    condition     = length(module.rag_ingest) == 1
    error_message = "rag_ingest must be provisioned when enabled"
  }
  assert {
    condition     = length(azurerm_role_assignment.rag_blob_reader) == 1
    error_message = "rag_blob_reader role assignment must be provisioned when enabled"
  }
}
