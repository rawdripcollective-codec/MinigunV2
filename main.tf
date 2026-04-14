terraform {
  required_version = ">= 1.12"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}

locals {
  # Do not create a service account if one has been supplied to GET...
  create_service_account = var.custom_service_account_email == null
}

resource "google_service_account" "gitlab" {
  count = local.create_service_account ? 1 : 0

  account_id   = var.account_id
  display_name = var.display_name
}

# Use a lookup in the case that a service account has been provided
data "google_service_account" "gitlab" {
  count = !local.create_service_account ? 1 : 0

  account_id = var.custom_service_account_email
}
