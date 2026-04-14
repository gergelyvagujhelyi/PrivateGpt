resource_group_name  = "rg-tfstate-platform"
storage_account_name = "sttfstateplatform"
container_name       = "tfstate"
key                  = "openwebui/beta/${ENVIRONMENT}.tfstate"
use_azuread_auth     = true
