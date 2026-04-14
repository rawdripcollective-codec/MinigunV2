module "gitlab_nfs" {
  source = "../gitlab_aws_instance"

  prefix          = var.prefix
  node_type       = "gitlab-nfs"
  node_count      = var.gitlab_nfs_node_count
  additional_tags = var.additional_tags

  instance_type              = var.gitlab_nfs_instance_type
  ami_id                     = var.ami_id != null ? var.ami_id : data.aws_ami.ubuntu_default[0].id
  disk_size                  = coalesce(var.gitlab_nfs_disk_size, var.default_disk_size)
  disk_type                  = coalesce(var.gitlab_nfs_disk_type, var.default_disk_type)
  disk_encrypt               = coalesce(var.gitlab_nfs_disk_encrypt, var.default_disk_encrypt)
  disk_kms_key_arn           = var.gitlab_nfs_disk_kms_key_arn != null ? var.gitlab_nfs_disk_kms_key_arn : (var.default_disk_kms_key_arn != null ? var.default_disk_kms_key_arn : var.default_kms_key_arn)
  disk_delete_on_termination = var.gitlab_nfs_disk_delete_on_termination != null ? var.gitlab_nfs_disk_delete_on_termination : var.default_disk_delete_on_termination
  data_disks                 = var.gitlab_nfs_data_disks
  subnet_ids                 = local.backend_subnet_ids
  user_data_base64           = var.gitlab_nfs_user_data_base64

  iam_instance_policy_arns = flatten([
    var.default_iam_instance_policy_arns,
    var.gitlab_nfs_iam_instance_policy_arns
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

output "gitlab_nfs" {
  value = module.gitlab_nfs
}
