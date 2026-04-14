variable "custom_service_account_email" {
  description = "Provided ID for the service account, if it was created outside of GET"
  type        = string
  default     = null
  nullable    = true
}

variable "account_id" {
  description = "Account ID of Service Account to be created if configured. Must be 30 characters or lower to meet GCP limits."
  type        = string
  nullable    = false
}

variable "display_name" {
  description = "Display name of Service Account to be created if configured"
  type        = string
}

variable "service_account_profiles" {
  description = "A set of access types required for this service account (or none)."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for profile in var.service_account_profiles :
      contains([
        "object_storage",
        "gke_node"
      ], profile)
    ])
    error_message = "Service account profile must be one of 'object_storage' or 'gke_node'."
  }
}

# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_service_account_iam#member/members
variable "service_account_user_members" {
  description = "List of optional identity members that will be assigned the Service Account User role on each created Service Account, which is required to attach the service accounts to resources. List must contain the identity running Terraform if given."

  type    = list(string)
  default = []
}
variable "setup_default_service_account_user_member" {
  description = "Sets whether the identity running Terraform is configured with the default Service Account Member User permission on each created Service Account. If not enabled, service_account_user_members must be configured with identity running Terraform else builds will fail."

  type    = bool
  default = false
}

variable "service_account_workload_identity_member" {
  description = "Member identity of a Kubernetes Service Account to be granted the workloadIdentityUser for created Service Account"

  type    = string
  default = null
}
