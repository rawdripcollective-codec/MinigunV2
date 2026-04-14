# IAM Profiles - https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_service_account_iam

# Service Account User Member - serviceAccountUser
## Grants permissions for users to in turn use that Service Account, i.e. Attach it to a VM or to allow SSH OS Login
## Role is strictly only given to the member accounts to either the identity running Terraform or a custom list passed by user to avoid impersonation attacks (https://cloud.google.com/iam/docs/best-practices-service-accounts#project-folder-grants)
locals {
  setup_default_service_account_user_member = local.create_service_account && var.setup_default_service_account_user_member && length(var.service_account_user_members) == 0
  default_service_account_user_member_email = local.setup_default_service_account_user_member ? "${strcontains(data.google_client_openid_userinfo.current_userinfo[0].email, "gserviceaccount") ? "serviceAccount" : "user"}:${data.google_client_openid_userinfo.current_userinfo[0].email}" : null

  service_account_user_members = local.setup_default_service_account_user_member ? [local.default_service_account_user_member_email] : var.service_account_user_members
}

data "google_client_openid_userinfo" "current_userinfo" {
  count = local.setup_default_service_account_user_member ? 1 : 0
}

resource "google_service_account_iam_member" "gitlab_user_members" {
  for_each = local.create_service_account ? toset(local.service_account_user_members) : toset([])

  service_account_id = google_service_account.gitlab[0].name
  role               = "roles/iam.serviceAccountUser"
  member             = each.value
}

# Object Storage - serviceAccountTokenCreator
## Required for the signBlob permission, which is required by GitLab to access Object Storage with the Service Account via Application Default Credentials - https://docs.gitlab.com/ee/administration/object_storage.html#gcs-example-with-adc
## Role is strictly only given to the account directly to avoid impersonation attacks (https://cloud.google.com/iam/docs/best-practices-service-accounts#project-folder-grants)
resource "google_service_account_iam_member" "object_storage_profile_token_creator" {
  count = local.create_service_account && contains(var.service_account_profiles, "object_storage") ? 1 : 0

  service_account_id = google_service_account.gitlab[0].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = google_service_account.gitlab[0].member
}

# GKE Workload Identity - workloadIdentityUser
resource "google_service_account_iam_member" "workload_identity_member" {
  count = local.create_service_account && var.service_account_workload_identity_member != null ? 1 : 0

  service_account_id = google_service_account.gitlab[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = var.service_account_workload_identity_member
}

# GKE Workload Identity - defaultNodeServiceAccount
## Required by GKE - https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster#use_least_privilege_sa
## Project is lowest possible level to be set, following recommendation
resource "google_project_iam_member" "gke_default_node_service_account" {
  count = local.create_service_account && contains(var.service_account_profiles, "gke_node") ? 1 : 0

  project = google_service_account.gitlab[0].project
  role    = "roles/container.defaultNodeServiceAccount"
  member  = google_service_account.gitlab[0].member
}
