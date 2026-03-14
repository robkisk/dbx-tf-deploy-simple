variable "tenant_id" {
  type        = string
  description = "Azure tenant ID"
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
}

variable "location" {
  type        = string
  description = "Azure region for resources"
}

variable "access_connector_name" {
  type        = string
  description = "Name of the Databricks access connector"
}

variable "storage_account_name" {
  type        = string
  description = "Name of the storage account (must be globally unique)"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 characters, lowercase letters and numbers only."
  }
}

variable "workspace_name" {
  type        = string
  description = "Name of the Databricks dev workspace"
}

variable "workspace_name_prod" {
  type        = string
  description = "Name of the Databricks prod workspace"
}

variable "databricks_account_id" {
  type        = string
  description = "Databricks account ID"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}