module "pgbouncer" {
  source = "../gitlab_aws_instance"

  prefix     = var.prefix
  node_type  = "pgbouncer"
  node_count = var.pgbouncer_node_count

  # TODO: var.additional_tags is deprecated and will be removed in 4.x
  custom_tags = merge(var.additional_tags, var.custom_tags, var.pgbouncer_custom_tags)

  instance_type              = var.pgbouncer_instance_type
  ami_id                     = var.ami_id != null ? var.ami_id : data.aws_ami.ubuntu_default[0].id
  disk_size                  = coalesce(var.pgbouncer_disk_size, var.default_disk_size)
  disk_type                  = coalesce(var.pgbouncer_disk_type, var.default_disk_type)
  disk_encrypt               = coalesce(var.pgbouncer_disk_encrypt, var.default_disk_encrypt)
  disk_kms_key_arn           = var.pgbouncer_disk_kms_key_arn != null ? var.pgbouncer_disk_kms_key_arn : (var.default_disk_kms_key_arn != null ? var.default_disk_kms_key_arn : var.default_kms_key_arn)
  disk_delete_on_termination = var.pgbouncer_disk_delete_on_termination != null ? var.pgbouncer_disk_delete_on_termination : var.default_disk_delete_on_termination
  data_disks                 = var.pgbouncer_data_disks
  subnet_ids                 = local.backend_subnet_ids
  user_data_base64           = var.pgbouncer_user_data_base64

  iam_instance_policy_arns = flatten([
    var.default_iam_instance_policy_arns,
    var.pgbouncer_iam_instance_policy_arns
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
}

output "pgbouncer" {
  value = module.pgbouncer
}
