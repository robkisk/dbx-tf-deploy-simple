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
}

variable "workspace_name" {
  type        = string
  description = "Name of the Databricks workspace"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}