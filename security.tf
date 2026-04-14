locals {
  gitlab_shell_ssh_port = var.haproxy_external_node_count > 0 && var.gitlab_shell_ssh_port == null ? 2222 : (var.external_ssh_port != 2222 ? var.external_ssh_port : var.gitlab_shell_ssh_port)

  gitlab_vm_ssh_access_security_group_create     = (var.subnet_priv_count == 0 && var.subnet_priv_ids == null) && var.ssh_public_key != null
  gitlab_git_ssh_access_security_group_create    = local.gitlab_shell_ssh_port != null
  gitlab_http_https_access_security_group_create = (var.haproxy_external_node_count + var.monitor_node_count + length(var.gitlab_rails_elastic_ip_allocation_ids)) > 0
}

resource "aws_key_pair" "ssh_key" {
  count = var.ssh_public_key != null && var.ssh_key_name == null ? 1 : 0

  key_name   = "${var.prefix}-ssh-key"
  public_key = var.ssh_public_key
}

data "aws_vpc" "selected" {
  id = coalesce(local.vpc_id, local.default_vpc_id)
}

# Internal
resource "aws_security_group" "gitlab_internal_networking" {
  name_prefix = "${var.prefix}-internal-networking"
  vpc_id      = data.aws_vpc.selected.id

  description = "${var.prefix} - Internal Networking Security Group"

  tags = {
    Name = "${var.prefix}-internal-networking"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_internal_networking" {
  security_group_id = aws_security_group.gitlab_internal_networking.id

  description = "Open internal networking for VMs and Node Groups"
  ip_protocol = "-1"

  referenced_security_group_id = aws_security_group.gitlab_internal_networking.id

  tags = {
    Name = "${var.prefix}-internal-networking"
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_internal_networking_security_groups" {
  for_each = toset(var.internal_allowed_ingress_security_group_ids)

  security_group_id = aws_security_group.gitlab_internal_networking.id

  description = "Open internal networking from configured Security Groups"
  ip_protocol = "-1"

  referenced_security_group_id = each.key

  tags = {
    Name = "${var.prefix}-internal-networking-security-groups-${each.key}"
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_internal_networking_peer" {
  count = var.peer_vpc_cidr != null ? 1 : 0

  security_group_id = aws_security_group.gitlab_internal_networking.id

  description = "Open internal peer networking for VMs"
  ip_protocol = "-1"

  cidr_ipv4 = var.peer_vpc_cidr

  tags = {
    Name = "${var.prefix}-internal-networking-peer"
  }
}

resource "aws_vpc_security_group_egress_rule" "gitlab_internal_networking_internet" {
  security_group_id = aws_security_group.gitlab_internal_networking.id

  description = "Open internet access for VMs"
  ip_protocol = "-1"

  cidr_ipv4 = "0.0.0.0/0"

  tags = {
    Name = "${var.prefix}-internal-networking-internet"
  }
}

# External
## VM SSH
resource "aws_security_group" "gitlab_vm_ssh_access" {
  count = local.gitlab_vm_ssh_access_security_group_create ? 1 : 0

  name_prefix = "${var.prefix}-vm-ssh-access-"
  vpc_id      = data.aws_vpc.selected.id

  description = "${var.prefix} - VM SSH Access Security Group"

  tags = {
    Name = "${var.prefix}-vm-ssh-access"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_vm_ssh_access" {
  for_each = local.gitlab_vm_ssh_access_security_group_create ? toset(coalescelist(var.external_ssh_allowed_ingress_cidr_blocks, var.default_allowed_ingress_cidr_blocks)) : toset([])

  security_group_id = aws_security_group.gitlab_vm_ssh_access[0].id

  description = "External SSH access for VMs from CIDR block ${each.key}"
  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"

  cidr_ipv4 = each.key

  tags = {
    Name = "${var.prefix}-vm-ssh-${each.key}"
  }
}

## Git SSH
resource "aws_security_group" "gitlab_git_ssh_access" {
  count = local.gitlab_git_ssh_access_security_group_create ? 1 : 0

  name_prefix = "${var.prefix}-git-ssh-access-"
  vpc_id      = data.aws_vpc.selected.id

  description = "GitLab ${var.prefix} - Git SSH Access Security Group"

  tags = {
    Name = "${var.prefix}-git-ssh-access"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_git_ssh_access" {
  for_each = local.gitlab_git_ssh_access_security_group_create ? toset(coalescelist(var.ssh_allowed_ingress_cidr_blocks, var.default_allowed_ingress_cidr_blocks)) : toset([])

  security_group_id = aws_security_group.gitlab_git_ssh_access[0].id

  description = "External Git SSH access on port ${local.gitlab_shell_ssh_port} for ${var.prefix} from CIDR block ${each.key}"
  from_port   = local.gitlab_shell_ssh_port
  to_port     = local.gitlab_shell_ssh_port
  ip_protocol = "tcp"

  cidr_ipv4 = each.key

  tags = {
    Name = "${var.prefix}-git-ssh-${each.key}"
  }
}

## HTTP / HTTPS
resource "aws_security_group" "gitlab_http_https_access" {
  count = local.gitlab_http_https_access_security_group_create ? 1 : 0

  description = "${var.prefix} - HTTP / HTTPS Access Security Group"

  name_prefix = "${var.prefix}-http-https-access"
  vpc_id      = data.aws_vpc.selected.id

  tags = {
    Name = "${var.prefix}-http-https-access"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_http_access" {
  for_each = local.gitlab_http_https_access_security_group_create ? toset(coalescelist(var.http_allowed_ingress_cidr_blocks, var.default_allowed_ingress_cidr_blocks)) : toset([])

  security_group_id = aws_security_group.gitlab_http_https_access[0].id

  description = "Enable HTTP access for select VMs from CIDR block ${each.key}"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"

  cidr_ipv4 = each.key

  tags = {
    Name = "${var.prefix}-external-http-${each.key}"
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_https_access" {
  for_each = local.gitlab_http_https_access_security_group_create ? toset(coalescelist(var.http_allowed_ingress_cidr_blocks, var.default_allowed_ingress_cidr_blocks)) : toset([])

  security_group_id = aws_security_group.gitlab_http_https_access[0].id

  description = "Enable HTTPS access for select VMs from CIDR block ${each.key}"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  cidr_ipv4 = each.key

  tags = {
    Name = "${var.prefix}-external-https-${each.key}"
  }
}

# Services Security Groups
## AWS RDS
### GitLab
resource "aws_security_group" "gitlab_rds" {
  count = local.rds_postgres_create ? 1 : 0

  name_prefix = "${var.prefix}-rds-"
  description = "RDS Security Group for internal access to RDS"
  vpc_id      = data.aws_vpc.selected.id

  tags = {
    Name = "${var.prefix}-rds"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_rds_internal_networking" {
  count = local.rds_postgres_create ? 1 : 0

  security_group_id = aws_security_group.gitlab_rds[0].id

  description = "Enable internal access to RDS from ${aws_security_group.gitlab_internal_networking.name} security group"
  from_port   = var.rds_postgres_port
  to_port     = var.rds_postgres_port
  ip_protocol = "tcp"

  referenced_security_group_id = aws_security_group.gitlab_internal_networking.id

  tags = {
    Name = "${var.prefix}-rds-internal-networking"
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_rds_cidr" {
  for_each = local.rds_postgres_create ? toset(var.rds_postgres_allowed_ingress_cidr_blocks) : toset([])

  security_group_id = aws_security_group.gitlab_rds[0].id

  description = "Enable access to RDS from CIDR block ${each.key}"
  from_port   = var.rds_postgres_port
  to_port     = var.rds_postgres_port
  ip_protocol = "tcp"

  cidr_ipv4 = each.key

  tags = {
    Name = "${var.prefix}-rds-cidr-${each.key}"
  }
}

### Praefect
resource "aws_security_group" "gitlab_rds_praefect" {
  count = local.rds_praefect_postgres_create ? 1 : 0

  name_prefix = "${var.prefix}-rds-praefect-"
  vpc_id      = data.aws_vpc.selected.id

  tags = {
    Name = "${var.prefix}-rds-praefect"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_rds_praefect_internal_networking" {
  count = local.rds_praefect_postgres_create ? 1 : 0

  security_group_id = aws_security_group.gitlab_rds_praefect[0].id

  description = "Enable internal access to Praefect RDS from ${aws_security_group.gitlab_internal_networking.name} security group"
  from_port   = var.rds_praefect_postgres_port
  to_port     = var.rds_praefect_postgres_port
  ip_protocol = "tcp"

  referenced_security_group_id = aws_security_group.gitlab_internal_networking.id

  tags = {
    Name = "${var.prefix}-rds-praefect-internal-networking"
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_rds_praefect_cidr" {
  for_each = local.rds_praefect_postgres_create ? toset(var.rds_praefect_postgres_allowed_ingress_cidr_blocks) : toset([])

  security_group_id = aws_security_group.gitlab_rds_praefect[0].id

  description = "Enable access to Praefect RDS from CIDR block ${each.key}"
  from_port   = var.rds_praefect_postgres_port
  to_port     = var.rds_praefect_postgres_port
  ip_protocol = "tcp"

  cidr_ipv4 = each.key

  tags = {
    Name = "${var.prefix}-rds-praefect-cidr-${each.key}"
  }
}

### Geo Tracking
resource "aws_security_group" "gitlab_rds_geo_tracking" {
  count = local.rds_geo_tracking_postgres_create ? 1 : 0

  name_prefix = "${var.prefix}-rds-geo-tracking-"
  vpc_id      = data.aws_vpc.selected.id

  tags = {
    Name = "${var.prefix}-rds-geo-tracking"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_rds_geo_tracking_internal_networking" {
  count = local.rds_geo_tracking_postgres_create ? 1 : 0

  security_group_id = aws_security_group.gitlab_rds_geo_tracking[0].id

  description = "Enable internal access to Geo Tracking RDS from ${aws_security_group.gitlab_internal_networking.name} security group"
  from_port   = var.rds_geo_tracking_postgres_port
  to_port     = var.rds_geo_tracking_postgres_port
  ip_protocol = "tcp"

  referenced_security_group_id = aws_security_group.gitlab_internal_networking.id

  tags = {
    Name = "${var.prefix}-rds-geo-tracking-internal-networking"
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_rds_geo_tracking_cidr" {
  for_each = local.rds_geo_tracking_postgres_create ? toset(var.rds_geo_tracking_postgres_allowed_ingress_cidr_blocks) : toset([])

  security_group_id = aws_security_group.gitlab_rds_geo_tracking[0].id

  description = "Enable access to Geo Tracking RDS from CIDR block ${each.key}"
  from_port   = var.rds_geo_tracking_postgres_port
  to_port     = var.rds_geo_tracking_postgres_port
  ip_protocol = "tcp"

  cidr_ipv4 = each.key

  tags = {
    Name = "${var.prefix}-rds-geo-tracking-cidr-${each.key}"
  }
}

## AWS Elasticache
### Redis (Combined)
resource "aws_security_group" "gitlab_elasticache_redis" {
  count = min(var.elasticache_redis_node_count, 1)

  name_prefix = "${var.prefix}-elasticache-redis-"
  vpc_id      = data.aws_vpc.selected.id

  tags = {
    Name = "${var.prefix}-elasticache-redis"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_elasticache_redis_internal_networking" {
  count = min(var.elasticache_redis_node_count, 1)

  security_group_id = aws_security_group.gitlab_elasticache_redis[0].id

  description = "Enable internal access to ElastiCache Redis from ${aws_security_group.gitlab_internal_networking.name} security group"
  from_port   = var.elasticache_redis_port
  to_port     = var.elasticache_redis_port
  ip_protocol = "tcp"

  referenced_security_group_id = aws_security_group.gitlab_internal_networking.id

  tags = {
    Name = "${var.prefix}-elasticache-redis-internal-networking"
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_elasticache_redis_cidr" {
  for_each = var.elasticache_redis_node_count > 0 ? toset(var.elasticache_redis_allowed_ingress_cidr_blocks) : toset([])

  security_group_id = aws_security_group.gitlab_elasticache_redis[0].id

  description = "Enable access to ElastiCache Redis from CIDR block ${each.key}"
  from_port   = var.elasticache_redis_port
  to_port     = var.elasticache_redis_port
  ip_protocol = "tcp"

  cidr_ipv4 = each.key

  tags = {
    Name = "${var.prefix}-elasticache-redis-cidr-${each.key}"
  }
}

### Redis Cache
locals {
  elasticache_redis_cache_allowed_ingress_cidr_blocks = coalesce(var.elasticache_redis_cache_allowed_ingress_cidr_blocks, var.elasticache_redis_allowed_ingress_cidr_blocks)
}

resource "aws_security_group" "gitlab_elasticache_redis_cache" {
  count = min(var.elasticache_redis_cache_node_count, 1)

  name_prefix = "${var.prefix}-elasticache-redis-cache-"
  vpc_id      = data.aws_vpc.selected.id

  tags = {
    Name = "${var.prefix}-elasticache-redis-cache"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_elasticache_redis_cache_internal_networking" {
  count = min(var.elasticache_redis_cache_node_count, 1)

  security_group_id = aws_security_group.gitlab_elasticache_redis_cache[0].id

  description = "Enable internal access to ElastiCache Redis Cache from ${aws_security_group.gitlab_internal_networking.name} security group"
  from_port   = local.elasticache_redis_cache_port
  to_port     = local.elasticache_redis_cache_port
  ip_protocol = "tcp"

  referenced_security_group_id = aws_security_group.gitlab_internal_networking.id

  tags = {
    Name = "${var.prefix}-elasticache-redis-cache-internal-networking"
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_elasticache_redis_cache_cidr" {
  for_each = var.elasticache_redis_cache_node_count > 0 ? toset(local.elasticache_redis_cache_allowed_ingress_cidr_blocks) : toset([])

  security_group_id = aws_security_group.gitlab_elasticache_redis_cache[0].id

  description = "Enable access to ElastiCache Redis Cache from CIDR block ${each.key}"
  from_port   = local.elasticache_redis_cache_port
  to_port     = local.elasticache_redis_cache_port
  ip_protocol = "tcp"

  cidr_ipv4 = each.key

  tags = {
    Name = "${var.prefix}-elasticache-redis-cache-cidr-${each.key}"
  }
}

### Redis Persistent
locals {
  elasticache_redis_persistent_allowed_ingress_cidr_blocks = coalesce(var.elasticache_redis_persistent_allowed_ingress_cidr_blocks, var.elasticache_redis_allowed_ingress_cidr_blocks)
}

resource "aws_security_group" "gitlab_elasticache_redis_persistent" {
  count = min(var.elasticache_redis_persistent_node_count, 1)

  name_prefix = "${var.prefix}-elasticache-redis-persistent-"
  vpc_id      = data.aws_vpc.selected.id

  tags = {
    Name = "${var.prefix}-elasticache-redis-persistent"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_elasticache_redis_persistent_internal_networking" {
  count = min(var.elasticache_redis_persistent_node_count, 1)

  security_group_id = aws_security_group.gitlab_elasticache_redis_persistent[0].id

  description = "Enable internal access to ElastiCache Redis Persistent from ${aws_security_group.gitlab_internal_networking.name} security group"
  from_port   = local.elasticache_redis_persistent_port
  to_port     = local.elasticache_redis_persistent_port
  ip_protocol = "tcp"

  referenced_security_group_id = aws_security_group.gitlab_internal_networking.id

  tags = {
    Name = "${var.prefix}-elasticache-redis-persistent-internal-networking"
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_elasticache_redis_persistent_cidr" {
  for_each = var.elasticache_redis_persistent_node_count > 0 ? toset(local.elasticache_redis_persistent_allowed_ingress_cidr_blocks) : toset([])

  security_group_id = aws_security_group.gitlab_elasticache_redis_persistent[0].id

  description = "Enable access to ElastiCache Redis Persistent from CIDR block ${each.key}"
  from_port   = local.elasticache_redis_persistent_port
  to_port     = local.elasticache_redis_persistent_port
  ip_protocol = "tcp"

  cidr_ipv4 = each.key

  tags = {
    Name = "${var.prefix}-elasticache-redis-persistent-cidr-${each.key}"
  }
}

## AWS OpenSearch
resource "aws_security_group" "gitlab_opensearch_service" {
  count = min(var.opensearch_service_node_count, 1)

  name_prefix = "${var.prefix}-opensearch-service-"
  vpc_id      = data.aws_vpc.selected.id

  tags = {
    Name = "${var.prefix}-opensearch-service"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_opensearch_service_internal_networking" {
  count = min(var.opensearch_service_node_count, 1)

  security_group_id = aws_security_group.gitlab_opensearch_service[0].id

  description = "Enable internal access to AWS OpenSearch from ${aws_security_group.gitlab_internal_networking.name} security group"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  referenced_security_group_id = aws_security_group.gitlab_internal_networking.id

  tags = {
    Name = "${var.prefix}-opensearch-service-internal-networking"
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_opensearch_service_cidr" {
  for_each = var.opensearch_service_node_count > 0 ? toset(var.opensearch_service_allowed_ingress_cidr_blocks) : toset([])

  security_group_id = aws_security_group.gitlab_opensearch_service[0].id

  description = "Enable access to AWS OpenSearch from CIDR block ${each.key}"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  cidr_ipv4 = each.key

  tags = {
    Name = "${var.prefix}-opensearch-service-cidr-${each.key}"
  }
}

output "security" {
  value = {
    "gitlab_internal_networking_id" = try(aws_security_group.gitlab_internal_networking.id, "")
    "gitlab_rds_id"                 = try(aws_security_group.gitlab_rds[0].id, "")
  }
}

# Moved
moved {
  from = aws_security_group.gitlab_external_ssh[0]
  to   = aws_security_group.gitlab_vm_ssh_access[0]
}
moved {
  from = aws_security_group.gitlab_external_git_ssh[0]
  to   = aws_security_group.gitlab_git_ssh_access[0]
}
moved {
  from = aws_security_group.gitlab_external_http_https[0]
  to   = aws_security_group.gitlab_http_https_access[0]
}
