## [Toolkit Beta] Unified RDS PostgreSQL

locals {
  default_postgres_params = {
    password_encryption                 = "scram-sha-256"
    log_min_duration_statement          = 1000
    idle_in_transaction_session_timeout = 60000
    statement_timeout                   = 15000
    deadlock_timeout                    = 5000
  }

  # Flat lists for all nested resource types
  replicas = flatten([
    for source_db, db_config in var.rds_databases : [
      for i in range(db_config.read_replica_count) : {
        key        = "${source_db}-replica-${i + 1}"
        source_db  = source_db
        config     = db_config
        replica_id = i + 1
      }
    ]
  ])
  cidr_rules = flatten([
    for source_db, db_config in var.rds_databases : [
      for cidr in db_config.allowed_cidr_blocks : {
        key       = "${source_db}-${cidr}"
        source_db = source_db
        config    = db_config
        cidr      = cidr
      }
    ]
  ])
}

# Subnet groups
resource "aws_db_subnet_group" "gitlab_rds_database" {
  for_each = var.rds_databases

  name = "${var.prefix}-rds-${each.key}-subnet-group"
  subnet_ids = coalesce(
    each.value.subnet_ids,
    local.backend_subnet_ids,
    local.default_network ? slice(tolist(local.default_subnet_ids), 0, each.value.default_subnet_count) : null
  )

  tags = {
    Name = "${var.prefix}-rds-${each.key}-subnet-group"
  }
}

# Parameter groups
resource "aws_db_parameter_group" "gitlab_rds_database" {
  for_each = var.rds_databases

  name_prefix = "${var.prefix}-rds-${each.key}-pg${floor(each.value.version)}-"
  family      = "postgres${floor(each.value.version)}"

  dynamic "parameter" {
    for_each = merge(local.default_postgres_params, each.value.parameters)
    content {
      name         = parameter.key
      value        = try(parameter.value.value, parameter.value)
      apply_method = try(parameter.value.apply_method, null)
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Security groups
resource "aws_security_group" "gitlab_rds_database" {
  for_each = var.rds_databases

  name_prefix = "${var.prefix}-rds-${each.key}-"
  description = "RDS Security Group for internal access to RDS"
  vpc_id      = data.aws_vpc.selected.id

  tags = {
    Name = "${var.prefix}-rds-${each.key}"
  }

  lifecycle {
    create_before_destroy = true
  }
}
## Internal networking security group access
resource "aws_vpc_security_group_ingress_rule" "gitlab_rds_database_internal_networking" {
  for_each = var.rds_databases

  security_group_id = aws_security_group.gitlab_rds_database[each.key].id

  description = "Enable internal access to ${each.key} RDS from ${aws_security_group.gitlab_internal_networking.name} security group"
  from_port   = each.value.port
  to_port     = each.value.port
  ip_protocol = "tcp"

  referenced_security_group_id = aws_security_group.gitlab_internal_networking.id

  tags = {
    Name = "${var.prefix}-rds-${each.key}-internal-networking"
  }
}
## CIDR block access rules
resource "aws_vpc_security_group_ingress_rule" "gitlab_rds_database_cidr" {
  for_each = { for pair in local.cidr_rules : pair.key => pair }

  security_group_id = aws_security_group.gitlab_rds_database[each.value.source_db].id

  description = "Enable access to ${each.value.source_db} RDS from CIDR block ${each.value.cidr}"
  from_port   = each.value.config.port
  to_port     = each.value.config.port
  ip_protocol = "tcp"

  cidr_ipv4 = each.value.cidr

  tags = {
    Name = "${var.prefix}-${each.value.source_db}-rds-cidr-${each.value.cidr}"
  }
}

# Default KMS Key
# aws_db_instance doesn't follow standard null design for kms_key_id and not track changes correctly
# This ensures default key is used
data "aws_kms_key" "rds_default" {
  for_each = { for name, db in var.rds_databases :
    name => db if db.kms_key_arn == null && var.default_kms_key_arn == null
  }
  key_id = "alias/aws/rds"
}

# Primary databases
resource "aws_db_instance" "gitlab_rds_database" {
  for_each = var.rds_databases

  # Basic identification
  identifier     = "${var.prefix}-rds-${each.key}"
  instance_class = "db.${each.value.instance_type}"

  # Engine configuration
  engine                   = each.value.replicate_source_arn == null ? "postgres" : null
  engine_version           = each.value.replicate_source_arn == null ? each.value.version : null
  engine_lifecycle_support = each.value.replicate_source_arn == null ? each.value.lifecycle_support : null

  # Database credentials & connection
  db_name             = each.value.replicate_source_arn == null ? each.value.db_name : null
  username            = each.value.replicate_source_arn == null ? each.value.username : null
  password_wo         = each.value.replicate_source_arn == null ? each.value.password_wo : null
  password_wo_version = each.value.replicate_source_arn == null ? each.value.password_wo_version : null
  port                = each.value.port

  # High availability & deployment
  multi_az = each.value.multi_az

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.gitlab_rds_database[each.key].name
  vpc_security_group_ids = [aws_security_group.gitlab_rds_database[each.key].id]

  # Security & certificates
  ca_cert_identifier                  = each.value.ca_cert_identifier
  iam_database_authentication_enabled = each.value.iam_database_authentication_enabled

  # Storage configuration
  storage_type          = each.value.storage_type
  iops                  = each.value.storage_type == "io1" && each.value.iops == null ? 1000 : each.value.iops
  allocated_storage     = each.value.replicate_source_arn == null ? each.value.allocated_storage : null
  max_allocated_storage = each.value.max_allocated_storage
  storage_encrypted     = true
  kms_key_id = coalesce(
    each.value.kms_key_arn,
    var.default_kms_key_arn,
    try(data.aws_kms_key.rds_default[each.key].arn, null)
  )

  # Database parameters & replication
  parameter_group_name = each.value.replicate_source_arn == null ? aws_db_parameter_group.gitlab_rds_database[each.key].name : null
  replicate_source_db  = each.value.replicate_source_arn

  # Update & maintenance settings
  allow_major_version_upgrade = true
  auto_minor_version_upgrade  = each.value.auto_minor_version_upgrade
  apply_immediately           = true
  maintenance_window          = each.value.maintenance_window

  # Backup configuration (PostgreSQL 14+ only)
  backup_window            = floor(each.value.version) >= 14 ? each.value.backup_window : null
  backup_retention_period  = floor(each.value.version) >= 14 ? each.value.backup_retention_period : null
  delete_automated_backups = floor(each.value.version) >= 14 ? each.value.delete_automated_backups : null

  # Protection & snapshots
  deletion_protection   = each.value.deletion_protection
  snapshot_identifier   = each.value.snapshot_identifier
  skip_final_snapshot   = true
  copy_tags_to_snapshot = true

  # Monitoring & logging
  enabled_cloudwatch_logs_exports       = length(each.value.enabled_cloudwatch_logs_exports) > 0 ? toset(each.value.enabled_cloudwatch_logs_exports) : null
  monitoring_interval                   = each.value.monitoring_interval
  monitoring_role_arn                   = each.value.monitoring_role_arn
  performance_insights_enabled          = each.value.performance_insights
  performance_insights_retention_period = each.value.performance_insights_retention_period

  # Operational settings
  timeouts {
    create = each.value.create_timeout
  }

  tags = merge(var.custom_tags, each.value.custom_tags, {
    gitlab_env_prefix = var.prefix
  })

  lifecycle {
    ignore_changes = [
      storage_encrypted,
      kms_key_id,
      snapshot_identifier
    ]
  }
}

# Read replicas
resource "aws_db_instance" "gitlab_rds_database_read_replicas" {
  for_each = { for pair in local.replicas : pair.key => pair }

  identifier     = "${format("%.47s", var.prefix)}-${each.value.source_db}-read-rep-${each.value.replica_id}"
  instance_class = aws_db_instance.gitlab_rds_database[each.value.source_db].instance_class

  port     = each.value.config.read_replica_port
  multi_az = each.value.config.read_replica_multi_az

  vpc_security_group_ids = [aws_security_group.gitlab_rds_database[each.value.source_db].id]

  ca_cert_identifier = each.value.config.ca_cert_identifier

  # Storage inherited from primary DATABASE
  storage_type          = aws_db_instance.gitlab_rds_database[each.value.source_db].storage_type
  iops                  = aws_db_instance.gitlab_rds_database[each.value.source_db].iops
  max_allocated_storage = aws_db_instance.gitlab_rds_database[each.value.source_db].max_allocated_storage
  storage_encrypted     = true
  kms_key_id            = aws_db_instance.gitlab_rds_database[each.value.source_db].kms_key_id

  parameter_group_name = aws_db_parameter_group.gitlab_rds_database[each.value.source_db].name
  replicate_source_db  = aws_db_instance.gitlab_rds_database[each.value.source_db].identifier
  apply_immediately    = true

  # Version settings inherited from primary DATABASE
  allow_major_version_upgrade = aws_db_instance.gitlab_rds_database[each.value.source_db].allow_major_version_upgrade
  auto_minor_version_upgrade  = aws_db_instance.gitlab_rds_database[each.value.source_db].auto_minor_version_upgrade

  iam_database_authentication_enabled = aws_db_instance.gitlab_rds_database[each.value.source_db].iam_database_authentication_enabled

  # Backup settings
  backup_window            = floor(each.value.config.version) >= 14 ? each.value.config.backup_window : null
  backup_retention_period  = floor(each.value.config.version) >= 14 ? each.value.config.backup_retention_period : null
  delete_automated_backups = floor(each.value.config.version) >= 14 ? each.value.config.delete_automated_backups : null

  deletion_protection = each.value.config.read_replica_deletion_protection

  skip_final_snapshot   = true
  copy_tags_to_snapshot = true

  # Monitoring from variables
  enabled_cloudwatch_logs_exports = length(each.value.config.enabled_cloudwatch_logs_exports) > 0 ? toset(each.value.config.enabled_cloudwatch_logs_exports) : null
  monitoring_interval             = each.value.config.monitoring_interval
  monitoring_role_arn             = each.value.config.monitoring_role_arn

  timeouts {
    create = each.value.config.create_timeout
  }

  tags = merge(var.custom_tags, each.value.config.custom_tags, {
    gitlab_env_prefix = var.prefix
  })

  lifecycle {
    ignore_changes = [
      storage_encrypted,
      kms_key_id
    ]
  }
}

output "rds_databases" {
  value = { for name, db in aws_db_instance.gitlab_rds_database : name => {
    # Connection essentials
    host     = db.address
    port     = db.port
    db_name  = db.db_name
    username = db.username
    arn      = db.arn

    # Key operational details
    version            = db.engine_version_actual
    kms_key_arn        = db.kms_key_id
    multi_az           = db.multi_az
    identifier         = db.identifier
    ca_cert_identifier = db.ca_cert_identifier

    # Read replicas
    read_replica_hosts = [
      for replica_key, replica in aws_db_instance.gitlab_rds_database_read_replicas : replica.address
      if startswith(replica_key, "${name}-replica-")
    ]
  } }
}