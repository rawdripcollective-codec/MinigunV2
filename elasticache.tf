locals {
  elasticache_redis_default_subnet_ids = local.default_network ? slice(tolist(local.default_subnet_ids), 0, var.elasticache_redis_default_subnet_count) : null
  elasticache_redis_subnet_ids         = coalesce(var.elasticache_redis_subnet_ids, local.backend_subnet_ids, local.elasticache_redis_default_subnet_ids)
}

resource "aws_elasticache_subnet_group" "gitlab_redis" {
  count = sum([var.elasticache_redis_node_count, var.elasticache_redis_cache_node_count, var.elasticache_redis_persistent_node_count]) > 0 ? 1 : 0

  name       = "${var.prefix}-${var.elasticache_redis_engine}-subnet-group"
  subnet_ids = local.elasticache_redis_subnet_ids

  tags = {
    Name = "${var.prefix}-${var.elasticache_redis_engine}-subnet-group"
  }

  lifecycle {
    ignore_changes = [
      name
    ]
  }
}

# Redis Combined
locals {
  elasticache_redis_major_version = regex("(\\d).", var.elasticache_redis_engine_version)[0]
}

resource "aws_elasticache_parameter_group" "gitlab_redis" {
  count = var.elasticache_redis_node_count > 0 ? 1 : 0

  name = "${var.prefix}-${var.elasticache_redis_engine}-parameter-group-${local.elasticache_redis_major_version}"
  # Family differs depending on version. For 6 it's 'redis6.x' but for 7 it's 'redis7'.
  family = "${var.elasticache_redis_engine}${var.elasticache_redis_engine_version == "6.x" ? var.elasticache_redis_engine_version : local.elasticache_redis_major_version}"

  parameter {
    name  = "maxmemory-policy"
    value = "noeviction"
  }

  parameter {
    name  = "timeout"
    value = "60"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elasticache_replication_group" "gitlab_redis" {
  count = var.elasticache_redis_node_count > 0 ? 1 : 0

  replication_group_id = "${format("%.33s", var.prefix)}-${var.elasticache_redis_engine}" # Must be 40 characters or lower
  description          = "${var.prefix}-${var.elasticache_redis_engine}"
  node_type            = "cache.${var.elasticache_redis_instance_type}"
  num_cache_clusters   = var.elasticache_redis_node_count
  parameter_group_name = aws_elasticache_parameter_group.gitlab_redis[0].name

  engine                     = var.elasticache_redis_engine
  engine_version             = var.elasticache_redis_engine_version
  port                       = var.elasticache_redis_port
  multi_az_enabled           = var.elasticache_redis_node_count > 1 ? var.elasticache_redis_multi_az : false
  automatic_failover_enabled = var.elasticache_redis_node_count > 1 ? true : false
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  kms_key_id                 = var.elasticache_redis_kms_key_arn != null ? var.elasticache_redis_kms_key_arn : var.default_kms_key_arn
  auth_token                 = var.elasticache_redis_password

  apply_immediately = true

  maintenance_window       = var.elasticache_redis_maintenance_window
  snapshot_retention_limit = var.elasticache_redis_snapshot_retention_limit
  snapshot_window          = var.elasticache_redis_snapshot_window

  final_snapshot_identifier = var.elasticache_redis_final_snapshot_identifier
  snapshot_name             = var.elasticache_redis_snapshot_name

  subnet_group_name = aws_elasticache_subnet_group.gitlab_redis[0].name
  security_group_ids = [
    aws_security_group.gitlab_elasticache_redis[0].id
  ]

  ## TODO: var.elasticache_redis_tags is deprecated and will be removed in 4.x
  tags = merge(var.elasticache_redis_tags, var.custom_tags, var.elasticache_redis_custom_tags)

  lifecycle {
    ignore_changes = [
      replication_group_id,
      at_rest_encryption_enabled,
      kms_key_id,
      snapshot_name
    ]
  }
}

output "elasticache_redis_connection" {
  value = {
    "elasticache_redis_address"     = try(aws_elasticache_replication_group.gitlab_redis[0].primary_endpoint_address, "")
    "elasticache_redis_port"        = try(aws_elasticache_replication_group.gitlab_redis[0].port, "")
    "elasticache_redis_kms_key_arn" = try(aws_elasticache_replication_group.gitlab_redis_cache[0].kms_key_id, "")
  }
}

# Redis Separate Cache

locals {
  ## Use default values if specifics aren't specified
  elasticache_redis_cache_engine                   = coalesce(var.elasticache_redis_cache_engine, var.elasticache_redis_engine)
  elasticache_redis_cache_engine_version           = coalesce(var.elasticache_redis_cache_engine_version, var.elasticache_redis_engine_version)
  elasticache_redis_cache_password                 = var.elasticache_redis_cache_password != "" ? var.elasticache_redis_cache_password : var.elasticache_redis_password
  elasticache_redis_cache_port                     = coalesce(var.elasticache_redis_cache_port, var.elasticache_redis_port)
  elasticache_redis_cache_multi_az                 = coalesce(var.elasticache_redis_cache_multi_az, var.elasticache_redis_multi_az)
  elasticache_redis_cache_kms_key_arn              = var.elasticache_redis_cache_kms_key_arn != null ? var.elasticache_redis_cache_kms_key_arn : var.elasticache_redis_kms_key_arn
  elasticache_redis_cache_maintenance_window       = var.elasticache_redis_cache_maintenance_window != null ? var.elasticache_redis_cache_maintenance_window : var.elasticache_redis_maintenance_window
  elasticache_redis_cache_snapshot_retention_limit = var.elasticache_redis_cache_snapshot_retention_limit != null ? var.elasticache_redis_cache_snapshot_retention_limit : var.elasticache_redis_snapshot_retention_limit
  elasticache_redis_cache_snapshot_window          = var.elasticache_redis_cache_snapshot_window != null ? var.elasticache_redis_cache_snapshot_window : var.elasticache_redis_snapshot_window

  elasticache_redis_cache_major_version = regex("(\\d).", local.elasticache_redis_cache_engine_version)[0]
}

resource "aws_elasticache_parameter_group" "gitlab_redis_cache" {
  count = var.elasticache_redis_cache_node_count > 0 ? 1 : 0

  name = "${var.prefix}-${local.elasticache_redis_cache_engine}-cache-parameter-group-${local.elasticache_redis_cache_major_version}"
  # Family differs depending on version. For 6 it's 'redis6.x' but for 7 it's 'redis7'.
  family = "${local.elasticache_redis_cache_engine}${local.elasticache_redis_cache_engine_version == "6.x" ? local.elasticache_redis_cache_engine_version : local.elasticache_redis_cache_major_version}"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  parameter {
    name  = "maxmemory-samples"
    value = "5"
  }

  parameter {
    name  = "timeout"
    value = "60"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elasticache_replication_group" "gitlab_redis_cache" {
  count = var.elasticache_redis_cache_node_count > 0 ? 1 : 0

  replication_group_id = "${format("%.27s", var.prefix)}-${local.elasticache_redis_cache_engine}-cache" # Must be 40 characters or lower
  description          = "${var.prefix}-${local.elasticache_redis_cache_engine}-cache"
  node_type            = "cache.${var.elasticache_redis_cache_instance_type}"
  num_cache_clusters   = var.elasticache_redis_cache_node_count
  parameter_group_name = aws_elasticache_parameter_group.gitlab_redis_cache[0].name

  engine                     = local.elasticache_redis_cache_engine
  engine_version             = local.elasticache_redis_cache_engine_version
  port                       = local.elasticache_redis_cache_port
  multi_az_enabled           = var.elasticache_redis_cache_node_count > 1 ? local.elasticache_redis_cache_multi_az : false
  automatic_failover_enabled = var.elasticache_redis_cache_node_count > 1 ? true : false
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  kms_key_id                 = local.elasticache_redis_cache_kms_key_arn != null ? local.elasticache_redis_cache_kms_key_arn : var.default_kms_key_arn
  auth_token                 = local.elasticache_redis_cache_password

  apply_immediately = true

  maintenance_window       = local.elasticache_redis_cache_maintenance_window
  snapshot_retention_limit = local.elasticache_redis_cache_snapshot_retention_limit
  snapshot_window          = local.elasticache_redis_cache_snapshot_window

  final_snapshot_identifier = var.elasticache_redis_cache_final_snapshot_identifier
  snapshot_name             = var.elasticache_redis_cache_snapshot_name

  subnet_group_name = aws_elasticache_subnet_group.gitlab_redis[0].name
  security_group_ids = [
    aws_security_group.gitlab_elasticache_redis_cache[0].id
  ]

  ## TODO: var.elasticache_redis_cache_tags is deprecated and will be removed in 4.x
  tags = merge(var.elasticache_redis_cache_tags, var.custom_tags, var.elasticache_redis_cache_custom_tags)

  lifecycle {
    ignore_changes = [
      replication_group_id,
      at_rest_encryption_enabled,
      kms_key_id,
      snapshot_name
    ]
  }
}

output "elasticache_redis_cache_connection" {
  value = {
    "elasticache_redis_cache_host"        = try(aws_elasticache_replication_group.gitlab_redis_cache[0].primary_endpoint_address, "")
    "elasticache_redis_cache_port"        = try(aws_elasticache_replication_group.gitlab_redis_cache[0].port, "")
    "elasticache_redis_cache_kms_key_arn" = try(aws_elasticache_replication_group.gitlab_redis_cache[0].kms_key_id, "")
  }
}

# Redis Separate Persistent

locals {
  ## Use default values if specifics aren't specified
  elasticache_redis_persistent_engine                   = coalesce(var.elasticache_redis_persistent_engine, var.elasticache_redis_engine)
  elasticache_redis_persistent_engine_version           = coalesce(var.elasticache_redis_persistent_engine_version, var.elasticache_redis_engine_version)
  elasticache_redis_persistent_password                 = var.elasticache_redis_persistent_password != "" ? var.elasticache_redis_persistent_password : var.elasticache_redis_password
  elasticache_redis_persistent_port                     = coalesce(var.elasticache_redis_persistent_port, var.elasticache_redis_port)
  elasticache_redis_persistent_multi_az                 = coalesce(var.elasticache_redis_persistent_multi_az, var.elasticache_redis_multi_az)
  elasticache_redis_persistent_kms_key_arn              = var.elasticache_redis_persistent_kms_key_arn != null ? var.elasticache_redis_persistent_kms_key_arn : var.elasticache_redis_kms_key_arn
  elasticache_redis_persistent_maintenance_window       = var.elasticache_redis_persistent_maintenance_window != null ? var.elasticache_redis_persistent_maintenance_window : var.elasticache_redis_maintenance_window
  elasticache_redis_persistent_snapshot_retention_limit = var.elasticache_redis_persistent_snapshot_retention_limit != null ? var.elasticache_redis_persistent_snapshot_retention_limit : var.elasticache_redis_snapshot_retention_limit
  elasticache_redis_persistent_snapshot_window          = var.elasticache_redis_persistent_snapshot_window != null ? var.elasticache_redis_persistent_snapshot_window : var.elasticache_redis_snapshot_window

  elasticache_redis_persistent_major_version = regex("(\\d).", local.elasticache_redis_persistent_engine_version)[0]
}

resource "aws_elasticache_parameter_group" "gitlab_redis_persistent" {
  count = var.elasticache_redis_persistent_node_count > 0 ? 1 : 0

  name = "${var.prefix}-${local.elasticache_redis_persistent_engine}-persistent-parameter-group-${local.elasticache_redis_persistent_major_version}"
  # Family differs depending on version. For 6 it's 'redis6.x' but for 7 it's 'redis7'.
  family = "${local.elasticache_redis_persistent_engine}${local.elasticache_redis_persistent_engine_version == "6.x" ? local.elasticache_redis_persistent_engine_version : local.elasticache_redis_persistent_major_version}"

  parameter {
    name  = "maxmemory-policy"
    value = "noeviction"
  }

  parameter {
    name  = "timeout"
    value = "60"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elasticache_replication_group" "gitlab_redis_persistent" {
  count = var.elasticache_redis_persistent_node_count > 0 ? 1 : 0

  replication_group_id = "${format("%.22s", var.prefix)}-${local.elasticache_redis_persistent_engine}-persistent" # Must be 40 characteers or lower
  description          = "${var.prefix}-${local.elasticache_redis_persistent_engine}-persistent"
  node_type            = "cache.${var.elasticache_redis_persistent_instance_type}"
  num_cache_clusters   = var.elasticache_redis_persistent_node_count
  parameter_group_name = aws_elasticache_parameter_group.gitlab_redis_persistent[0].name

  engine                     = local.elasticache_redis_persistent_engine
  engine_version             = local.elasticache_redis_persistent_engine_version
  port                       = local.elasticache_redis_persistent_port
  multi_az_enabled           = var.elasticache_redis_persistent_node_count > 1 ? local.elasticache_redis_persistent_multi_az : false
  automatic_failover_enabled = var.elasticache_redis_persistent_node_count > 1 ? true : false
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  kms_key_id                 = local.elasticache_redis_persistent_kms_key_arn != null ? local.elasticache_redis_persistent_kms_key_arn : var.default_kms_key_arn
  auth_token                 = local.elasticache_redis_persistent_password

  apply_immediately = true

  maintenance_window       = local.elasticache_redis_persistent_maintenance_window
  snapshot_retention_limit = local.elasticache_redis_persistent_snapshot_retention_limit
  snapshot_window          = local.elasticache_redis_persistent_snapshot_window

  final_snapshot_identifier = var.elasticache_redis_persistent_final_snapshot_identifier
  snapshot_name             = var.elasticache_redis_persistent_snapshot_name

  subnet_group_name = aws_elasticache_subnet_group.gitlab_redis[0].name
  security_group_ids = [
    aws_security_group.gitlab_elasticache_redis_persistent[0].id
  ]

  ## TODO: var.elasticache_redis_persistent_tags is deprecated and will be removed in 4.x
  tags = merge(var.elasticache_redis_persistent_tags, var.custom_tags, var.elasticache_redis_persistent_custom_tags)

  lifecycle {
    ignore_changes = [
      replication_group_id,
      at_rest_encryption_enabled,
      kms_key_id,
      snapshot_name
    ]
  }
}

## Moved
moved {
  from = aws_elasticache_subnet_group.gitlab[0]
  to   = aws_elasticache_subnet_group.gitlab_redis[0]
}

output "elasticache_redis_persistent_connection" {
  value = {
    "elasticache_redis_persistent_host"        = try(aws_elasticache_replication_group.gitlab_redis_persistent[0].primary_endpoint_address, "")
    "elasticache_redis_persistent_port"        = try(aws_elasticache_replication_group.gitlab_redis_persistent[0].port, "")
    "elasticache_redis_persistent_kms_key_arn" = try(aws_elasticache_replication_group.gitlab_redis_persistent[0].kms_key_id, "")
  }
}
