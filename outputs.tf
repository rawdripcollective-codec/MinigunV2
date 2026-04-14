output "id" {
  description = "ID of the service account"
  value       = local.create_service_account ? google_service_account.gitlab[0].id : data.google_service_account.gitlab[0].id
}

output "account_id" {
  description = "AccountID of the service account"
  value       = local.create_service_account ? google_service_account.gitlab[0].account_id : data.google_service_account.gitlab[0].account_id
}

output "email" {
  description = "Email address of the service account"
  value       = local.create_service_account ? google_service_account.gitlab[0].email : data.google_service_account.gitlab[0].email
}

output "member" {
  description = "Member format reference for the service account"
  value       = local.create_service_account ? google_service_account.gitlab[0].member : data.google_service_account.gitlab[0].member
}

output "details" {
  value = {
    unique_id = local.create_service_account ? google_service_account.gitlab[0].unique_id : data.google_service_account.gitlab[0].unique_id
    name      = local.create_service_account ? google_service_account.gitlab[0].name : data.google_service_account.gitlab[0].name
    email     = local.create_service_account ? google_service_account.gitlab[0].email : data.google_service_account.gitlab[0].email
    member    = local.create_service_account ? google_service_account.gitlab[0].member : data.google_service_account.gitlab[0].member
  }
}
