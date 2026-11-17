data "azuread_client_config" "current" {}

locals {
  suffix               = "uvu-it3200-${var.student_name}"
  storage_account_name = coalesce(var.storage_account_name, "stuvuit3200${var.student_name}")
}

# ---------------------------------------------------------------------------
# Part 1 - Storage
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.suffix}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "this" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Transport security
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  # No anonymous/public blob access, ever
  allow_nested_items_to_be_public = false

  # Identity-based access only: no account keys / key-signed SAS,
  # and the portal defaults to Entra auth instead of keys.
  shared_access_key_enabled       = var.shared_access_key_enabled
  default_to_oauth_authentication = true

  tags = var.tags
}

# Using storage_account_id makes the provider create containers through the
# Azure Resource Manager API (management plane), so creating them does not
# need account keys or a blob data role for the deployer.
resource "azurerm_storage_container" "app" {
  name                  = var.app_container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "restricted" {
  name                  = var.restricted_container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# Part 2 - Application identity
# ---------------------------------------------------------------------------

# Application registration = the global definition of the app (lives in the
# tenant's app registrations; owns the credentials).
resource "azuread_application" "reporting" {
  display_name     = "app-${local.suffix}-reporting"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]
}

# Service principal = the local instance of that app in this tenant. This is
# the security principal that RBAC roles get assigned to.
resource "azuread_service_principal" "reporting" {
  client_id = azuread_application.reporting.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# Short-lived client secret. When the rotation period passes, the next
# `terraform apply` replaces the secret (see Scenario D in the README).
resource "time_rotating" "secret" {
  rotation_days = var.secret_rotation_days
}

resource "azuread_application_password" "reporting" {
  application_id = azuread_application.reporting.id
  display_name   = "terraform-managed-${var.secret_rotation_days}d"
  end_date       = time_rotating.secret.rotation_rfc3339

  rotate_when_changed = {
    rotation = time_rotating.secret.id
  }
}

# ---------------------------------------------------------------------------
# Part 4 - Least-privilege RBAC (data plane, container scope)
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "app_blob_contributor" {
  count = var.grant_blob_access ? 1 : 0

  # Scope = ONE container, not the account, resource group, or subscription.
  scope                = azurerm_storage_container.app.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.reporting.object_id

  # Tells ARM the principal type up front so a just-created SP doesn't fail
  # the directory lookup during Entra replication.
  principal_type = "ServicePrincipal"
  description    = "M9: reporting app may read/write/list/delete blobs in the ${var.app_container_name} container only."
}
