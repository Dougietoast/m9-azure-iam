terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

# Terraform itself runs as YOU (your personal `az login` session).
# Only the test scripts run as the service principal.
provider "azurerm" {
  features {}

  # azurerm 4.x requires the subscription to be set explicitly.
  subscription_id = var.subscription_id

  # Shared-key auth is disabled on the storage account, so any data-plane
  # calls the provider makes must use Entra ID instead of account keys.
  storage_use_azuread = true
}

provider "azuread" {
  # Uses the tenant of the current `az login` session.
}
