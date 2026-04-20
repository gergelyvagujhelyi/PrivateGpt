variable "client" {
  type        = string
  description = "Short client identifier — pool is typically per-client for blast-radius isolation."
}

variable "location" {
  type    = string
  default = "westeurope"
}

variable "resource_group_name" {
  type        = string
  description = "Existing RG that holds the spoke VNet for this client's workload."
}

variable "virtual_network_name" {
  type = string
}

variable "agent_subnet_cidr" {
  type    = string
  default = "10.40.4.0/24"
}

variable "ado_organization_url" {
  type = string
}

variable "ado_project_name" {
  type = string
}

variable "subscription_id" {
  type        = string
  description = "Client subscription the pool's MI will apply into."
}

variable "log_analytics_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
