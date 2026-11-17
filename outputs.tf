output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "storage_account_name" {
  value = azurerm_storage_account.this.name
}

output "blob_endpoint" {
  value = azurerm_storage_account.this.primary_blob_endpoint
}

output "app_container_name" {
  value = azurerm_storage_container.app.name
}

output "restricted_container_name" {
  value = azurerm_storage_container.restricted.name
}

output "role_scope" {
  description = "ARM ID of the container the role is scoped to."
  value       = azurerm_storage_container.app.id
}

output "role_assignment_id" {
  value = try(azurerm_role_assignment.app_blob_contributor[0].id, "none (grant_blob_access = false)")
}

output "tenant_id" {
  value = data.azuread_client_config.current.tenant_id
}

output "client_id" {
  description = "Application (client) ID - identifies the app registration."
  value       = azuread_application.reporting.client_id
}

output "application_object_id" {
  description = "Object ID of the app registration object."
  value       = azuread_application.reporting.object_id
}

output "service_principal_object_id" {
  description = "Object ID of the service principal - this is what RBAC assigns roles to."
  value       = azuread_service_principal.reporting.object_id
}

output "client_secret_expires" {
  value = azuread_application_password.reporting.end_date
}

output "client_secret" {
  description = "Never print this in a screenshot. Read it only by piping `terraform output -raw client_secret` into another command."
  value       = azuread_application_password.reporting.value
  sensitive   = true
}
