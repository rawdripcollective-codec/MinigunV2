module "gitaly" {
  source = "../gitlab_aws_instance"

  prefix     = var.prefix
  node_type  = "gitaly"
  node_count = var.gitaly_node_count

  # TODO: var.additional_tags is deprecated and will be removed in 4.x
  custom_tags = merge(var.additional_tags, var.custom_tags, var.gitaly_custom_tags)

  instance_type              = var.gitaly_instance_type
  ami_id                     = var.ami_id != null ? var.ami_id : data.aws_ami.ubuntu_default[0].id
  disk_size                  = coalesce(var.gitaly_disk_size, var.default_disk_size)
  disk_type                  = coalesce(var.gitaly_disk_type, var.default_disk_type)
  disk_iops                  = var.gitaly_disk_iops
  disk_encrypt               = coalesce(var.gitaly_disk_encrypt, var.default_disk_encrypt)
  disk_kms_key_arn           = var.gitaly_disk_kms_key_arn != null ? var.gitaly_disk_kms_key_arn : (var.default_disk_kms_key_arn != null ? var.default_disk_kms_key_arn : var.default_kms_key_arn)
  disk_delete_on_termination = var.gitaly_disk_delete_on_termination != null ? var.gitaly_disk_delete_on_termination : var.default_disk_delete_on_termination
  data_disks                 = var.gitaly_data_disks
  subnet_ids                 = local.backend_subnet_ids
  user_data_base64           = var.gitaly_user_data_base64

  iam_instance_policy_arns = flatten([
    var.gitaly_server_side_backups_enable && local.gitlab_s3_backups_policy_create ? [aws_iam_policy.gitlab_s3_backups_policy[0].arn] : [],
    var.default_iam_instance_policy_arns,
    var.gitaly_iam_instance_policy_arns
  ])
  iam_identifier_path          = var.default_iam_identifier_path
  iam_permissions_boundary_arn = var.default_iam_permissions_boundary_arn

  ssh_key_name = var.ssh_key_name != null ? var.ssh_key_name : try(aws_key_pair.ssh_key[0].key_name, null)
  security_group_ids = flatten([
    aws_security_group.gitlab_internal_networking.id,
    local.gitlab_vm_ssh_access_security_group_create ? [aws_security_group.gitlab_vm_ssh_access[0].id] : []
  ])

  geo_site       = var.geo_site
  geo_deployment = var.geo_deployment

  label_secondaries = true
}

output "gitaly" {
  value = module.gitaly
}
