variable "region" { default = "us-east-1" }
variable "name" {
  default = "delivery-platform"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,23}$", var.name))
    error_message = "Use 3 to 24 lowercase letters, numbers or hyphens, starting with a letter."
  }
}
variable "github_repository" {
  type = string
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use the GitHub owner/repository name."
  }
}
variable "github_environment" { default = "production" }
variable "state_bucket" { type = string }
variable "state_prefix" { default = "delivery-platform/production" }
variable "existing_oidc_provider_arn" {
  type    = string
  default = null
}
variable "certificate_arn" {
  type    = string
  default = null
}
variable "public_hostname" {
  type    = string
  default = null
  validation {
    condition     = var.public_hostname == null ? true : can(regex("^[a-zA-Z0-9.-]+$", var.public_hostname))
    error_message = "Provide a hostname without protocol, path or port."
  }
}
