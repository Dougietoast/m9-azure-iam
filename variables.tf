variable "subscription_id" {
  description = "Azure subscription ID to deploy into (az account show --query id -o tsv)."
  type        = string
}

variable "student_name" {
  description = "Lowercase name used in the [resource]-uvu-it3200-[studentname] naming convention."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,12}$", var.student_name))
    error_message = "student_name must be 2-12 lowercase letters/numbers (it is reused in the storage account name)."
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "westus2"
}

variable "storage_account_name" {
  description = "Optional override. Storage account names are global: 3-24 lowercase letters/numbers. Defaults to stuvuit3200<student_name>."
  type        = string
  default     = null

  validation {
    condition     = var.storage_account_name == null || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 lowercase letters and numbers only."
  }
}

variable "app_container_name" {
  description = "Private container the application identity is allowed to use."
  type        = string
  default     = "reports"
}

variable "restricted_container_name" {
  description = "Second private container with NO role assignment (used for the negative test)."
  type        = string
  default     = "restricted"
}

variable "grant_blob_access" {
  description = "Toggle for the RBAC role assignment. false = Part 3 (before RBAC) and the bonus 'break it'; true = Part 5 and the bonus 'fix it'."
  type        = bool
  default     = false
}

variable "shared_access_key_enabled" {
  description = "Leave false so storage account keys cannot be used at all. See README troubleshooting if the first apply fails on a data-plane read."
  type        = bool
  default     = false
}

variable "secret_rotation_days" {
  description = "Lifetime of the client secret. Short on purpose; Terraform issues a new one after it rotates."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to Azure resources."
  type        = map(string)
  default = {
    course     = "IT3200"
    assignment = "M9"
    managed_by = "terraform"
  }
}
