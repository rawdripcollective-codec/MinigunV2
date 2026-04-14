# ElastiCache Redis Test Suite - Lean & Comprehensive
mock_provider "aws" {
  override_during = plan

  # Mock data sources for network scenarios
  override_data {
    target = data.aws_availability_zones.defaults
    values = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }

  override_resource {
    target = aws_default_vpc.default
    values = {
      id         = "vpc-default123"
      cidr_block = "172.31.0.0/16"
    }
  }

  override_resource {
    target = aws_vpc.gitlab_vpc[0]
    values = {
      id         = "vpc-created456"
      cidr_block = "10.0.0.0/16"
    }
  }
}

variables {
  test_prefix  = "gitlab-test"
  test_kms_key = "arn:aws:kms:us-east-1:123456789012:key/test-key-id"
}

# ====== CORE FUNCTIONALITY TESTS ======

# Test 1: Combined Redis deployment (single node and multi-AZ)
run "test_combined_redis_deployment" {
  command = plan
  module { source = "../../../gitlab_ref_arch_aws" }

  variables {
    prefix                          = var.test_prefix
    elasticache_redis_node_count    = 3
    elasticache_redis_instance_type = "t3.micro"
    elasticache_redis_password      = "combinedtest16chars"
    elasticache_redis_multi_az      = true
  }

  # Basic resource creation
  assert {
    condition     = aws_elasticache_subnet_group.gitlab_redis[0].name == "${var.test_prefix}-redis-subnet-group"
    error_message = "Should create subnet group with correct naming"
  }

  assert {
    condition     = aws_elasticache_parameter_group.gitlab_redis[0].family == "redis7"
    error_message = "Should use redis7 parameter family by default"
  }

  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis[0].engine == "redis"
    error_message = "Should use Redis engine by default"
  }

  # Multi-AZ configuration
  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis[0].num_cache_clusters == 3
    error_message = "Should create 3 cache clusters"
  }

  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis[0].multi_az_enabled == true
    error_message = "Multi-node should enable Multi-AZ when specified"
  }

  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis[0].automatic_failover_enabled == true
    error_message = "Multi-node should enable automatic failover"
  }
}

# Test 2: Cache + Persistent deployment pattern
run "test_cache_persistent_deployment" {
  command = plan
  module { source = "../../../gitlab_ref_arch_aws" }

  variables {
    prefix = var.test_prefix
    # Cache: single node, no Multi-AZ
    elasticache_redis_cache_node_count    = 1
    elasticache_redis_cache_instance_type = "t3.small"
    # Persistent: multi-node with Multi-AZ
    elasticache_redis_persistent_node_count    = 2
    elasticache_redis_persistent_instance_type = "m5.large"
    elasticache_redis_persistent_multi_az      = true
    elasticache_redis_password                 = "cachepersistent16char"
  }

  # Shared subnet group
  assert {
    condition     = aws_elasticache_subnet_group.gitlab_redis[0].name == "${var.test_prefix}-redis-subnet-group"
    error_message = "Cache and persistent should share subnet group"
  }

  # Cache configuration
  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis_cache[0].num_cache_clusters == 1
    error_message = "Cache should have 1 cluster"
  }

  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis_cache[0].multi_az_enabled == false
    error_message = "Single cache node should not use Multi-AZ"
  }

  assert {
    condition     = length(regexall("cache", aws_elasticache_replication_group.gitlab_redis_cache[0].replication_group_id)) > 0
    error_message = "Cache replication group ID should contain 'cache'"
  }

  # Persistent configuration
  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis_persistent[0].num_cache_clusters == 2
    error_message = "Persistent should have 2 clusters"
  }

  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis_persistent[0].multi_az_enabled == true
    error_message = "Multi-node persistent should use Multi-AZ"
  }

  assert {
    condition     = length(regexall("persistent", aws_elasticache_replication_group.gitlab_redis_persistent[0].replication_group_id)) > 0
    error_message = "Persistent replication group ID should contain 'persistent'"
  }

  # No combined instance
  assert {
    condition     = length(aws_elasticache_replication_group.gitlab_redis) == 0
    error_message = "Combined Redis should not be created when using cache+persistent"
  }
}

# Test 3: Engine and version matrix
run "test_engines_and_versions" {
  command = plan
  module { source = "../../../gitlab_ref_arch_aws" }

  variables {
    prefix = var.test_prefix
    # Combined: Redis 6.x
    elasticache_redis_node_count     = 1
    elasticache_redis_instance_type  = "t3.micro"
    elasticache_redis_engine         = "redis"
    elasticache_redis_engine_version = "6.x"

    # Cache: Valkey 7.0
    elasticache_redis_cache_node_count     = 1
    elasticache_redis_cache_instance_type  = "t3.small"
    elasticache_redis_cache_engine         = "valkey"
    elasticache_redis_cache_engine_version = "7.0"

    # Persistent: Redis 7.0
    elasticache_redis_persistent_node_count     = 1
    elasticache_redis_persistent_instance_type  = "m5.large"
    elasticache_redis_persistent_engine         = "redis"
    elasticache_redis_persistent_engine_version = "7.0"

    elasticache_redis_password = "enginesversions16char"
  }

  # Combined: Redis 6.x
  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis[0].engine == "redis"
    error_message = "Combined should use Redis engine"
  }
  assert {
    condition     = aws_elasticache_parameter_group.gitlab_redis[0].family == "redis6.x"
    error_message = "Combined should use redis6.x parameter family"
  }

  # Cache: Valkey 7.0
  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis_cache[0].engine == "valkey"
    error_message = "Cache should use Valkey engine"
  }
  assert {
    condition     = contains(["valkey7", "valkey"], aws_elasticache_parameter_group.gitlab_redis_cache[0].family)
    error_message = "Cache should use valkey parameter family"
  }

  # Persistent: Redis 7.0
  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis_persistent[0].engine == "redis"
    error_message = "Persistent should use Redis engine"
  }
  assert {
    condition     = aws_elasticache_parameter_group.gitlab_redis_persistent[0].family == "redis7"
    error_message = "Persistent should use redis7 parameter family"
  }
}

# Test 4: Configuration inheritance
run "test_configuration_inheritance" {
  command = plan
  module { source = "../../../gitlab_ref_arch_aws" }

  variables {
    prefix = var.test_prefix
    # Base configuration
    elasticache_redis_engine         = "redis"
    elasticache_redis_engine_version = "7.0"
    elasticache_redis_password       = "inheritance16chars"
    elasticache_redis_port           = 6380

    # Cache inherits from base (no cache-specific engine/version)
    elasticache_redis_cache_node_count    = 1
    elasticache_redis_cache_instance_type = "t3.small"
  }

  # Test inheritance works
  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis_cache[0].engine == "redis"
    error_message = "Cache should inherit Redis engine from base"
  }

  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis_cache[0].engine_version == "7.0"
    error_message = "Cache should inherit version 7.0 from base"
  }

  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis_cache[0].port == 6380
    error_message = "Cache should inherit custom port from base"
  }

  assert {
    condition     = aws_elasticache_parameter_group.gitlab_redis_cache[0].family == "redis7"
    error_message = "Cache parameter group should inherit redis7 family"
  }
}

# ====== ADVANCED FEATURES ======

# Test 5: Security and encryption
run "test_security_encryption" {
  command = plan
  module { source = "../../../gitlab_ref_arch_aws" }

  variables {
    prefix                                     = var.test_prefix
    elasticache_redis_node_count               = 1
    elasticache_redis_instance_type            = "t3.micro"
    elasticache_redis_cache_node_count         = 1
    elasticache_redis_cache_instance_type      = "t3.small"
    elasticache_redis_persistent_node_count    = 1
    elasticache_redis_persistent_instance_type = "m5.large"
    elasticache_redis_kms_key_arn              = var.test_kms_key
    elasticache_redis_password                 = "security16characters"
  }

  # Encryption settings
  assert {
    condition     = tobool(aws_elasticache_replication_group.gitlab_redis[0].at_rest_encryption_enabled) == true
    error_message = "At-rest encryption should always be enabled"
  }

  assert {
    condition     = tobool(aws_elasticache_replication_group.gitlab_redis[0].transit_encryption_enabled) == true
    error_message = "Transit encryption should always be enabled"
  }

  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis[0].kms_key_id == var.test_kms_key
    error_message = "Should use specified KMS key"
  }

  # Security groups created
  assert {
    condition     = length(aws_security_group.gitlab_elasticache_redis) > 0
    error_message = "Combined Redis security group should be created"
  }

  assert {
    condition     = length(aws_security_group.gitlab_elasticache_redis_cache) > 0
    error_message = "Cache security group should be created"
  }

  assert {
    condition     = length(aws_security_group.gitlab_elasticache_redis_persistent) > 0
    error_message = "Persistent security group should be created"
  }

  # Security groups configured
  assert {
    condition     = length(aws_elasticache_replication_group.gitlab_redis[0].security_group_ids) > 0
    error_message = "Combined should have security groups configured"
  }

  assert {
    condition     = length(aws_elasticache_replication_group.gitlab_redis_cache[0].security_group_ids) > 0
    error_message = "Cache should have security groups configured"
  }

  assert {
    condition     = length(aws_elasticache_replication_group.gitlab_redis_persistent[0].security_group_ids) > 0
    error_message = "Persistent should have security groups configured"
  }
}

# Test 6: Output validation
run "test_outputs" {
  command = plan
  module { source = "../../../gitlab_ref_arch_aws" }

  variables {
    prefix                                     = var.test_prefix
    elasticache_redis_node_count               = 1
    elasticache_redis_instance_type            = "t3.micro"
    elasticache_redis_cache_node_count         = 1
    elasticache_redis_cache_instance_type      = "t3.small"
    elasticache_redis_persistent_node_count    = 1
    elasticache_redis_persistent_instance_type = "m5.large"
    elasticache_redis_password                 = "outputs16characters"
  }

  # Output objects and fields exist
  assert {
    condition     = can(output.elasticache_redis_connection) && can(output.elasticache_redis_connection.elasticache_redis_address)
    error_message = "Combined Redis connection output with address field should exist"
  }

  assert {
    condition     = can(output.elasticache_redis_cache_connection) && can(output.elasticache_redis_cache_connection.elasticache_redis_cache_host)
    error_message = "Cache Redis connection output with host field should exist"
  }

  assert {
    condition     = can(output.elasticache_redis_persistent_connection) && can(output.elasticache_redis_persistent_connection.elasticache_redis_persistent_host)
    error_message = "Persistent Redis connection output with host field should exist"
  }
}

# Test 7: Disabled state validation
run "test_disabled_state" {
  command = plan
  module { source = "../../../gitlab_ref_arch_aws" }

  variables {
    prefix = var.test_prefix
  }

  # No resources should be created
  assert {
    condition     = length(aws_elasticache_subnet_group.gitlab_redis) == 0 && length(aws_elasticache_parameter_group.gitlab_redis) == 0 && length(aws_elasticache_replication_group.gitlab_redis) == 0
    error_message = "Should not create any combined Redis resources when disabled"
  }

  assert {
    condition     = length(aws_elasticache_parameter_group.gitlab_redis_cache) == 0 && length(aws_elasticache_replication_group.gitlab_redis_cache) == 0
    error_message = "Should not create any cache Redis resources when disabled"
  }

  assert {
    condition     = length(aws_elasticache_parameter_group.gitlab_redis_persistent) == 0 && length(aws_elasticache_replication_group.gitlab_redis_persistent) == 0
    error_message = "Should not create any persistent Redis resources when disabled"
  }
}

# ====== NETWORK SCENARIOS ======

# Test 8: Default and created network behavior
run "test_default_created_networks" {
  command = plan
  module { source = "../../../gitlab_ref_arch_aws" }

  variables {
    prefix                          = var.test_prefix
    elasticache_redis_node_count    = 1
    elasticache_redis_instance_type = "t3.micro"
    elasticache_redis_password      = "networktest16chars"

    # Created network
    create_network = true
    vpc_cidr_block = "10.0.0.0/16"
  }

  # Basic network functionality
  assert {
    condition     = aws_elasticache_subnet_group.gitlab_redis[0].name == "${var.test_prefix}-redis-subnet-group"
    error_message = "Should create subnet group with created network"
  }

  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis[0].subnet_group_name == aws_elasticache_subnet_group.gitlab_redis[0].name
    error_message = "Should use the created subnet group"
  }

  assert {
    condition     = length(aws_elasticache_subnet_group.gitlab_redis[0].subnet_ids) > 0
    error_message = "Created network should provide subnet IDs"
  }
}

# Test 9: Existing network with ElastiCache-specific override
run "test_existing_network_override" {
  command = plan
  module { source = "../../../gitlab_ref_arch_aws" }

  variables {
    prefix                          = var.test_prefix
    elasticache_redis_node_count    = 1
    elasticache_redis_instance_type = "t3.micro"
    elasticache_redis_password      = "existingoverride16c"

    # ElastiCache-specific subnet override (highest priority)
    elasticache_redis_subnet_ids = ["subnet-redis1", "subnet-redis2"]

    # Base network config (should be overridden)
    create_network = false
    vpc_id         = "vpc-base789"
    subnet_pub_ids = ["subnet-base1", "subnet-base2", "subnet-base3"]
  }

  # Test ElastiCache-specific override
  assert {
    condition     = aws_elasticache_subnet_group.gitlab_redis[0].subnet_ids == toset(["subnet-redis1", "subnet-redis2"])
    error_message = "Should use ElastiCache-specific subnet IDs when provided"
  }

  # Should NOT use base network subnets
  assert {
    condition     = !contains(tolist(aws_elasticache_subnet_group.gitlab_redis[0].subnet_ids), "subnet-base1")
    error_message = "Should not use base network subnets when ElastiCache-specific subnets are provided"
  }

  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis[0].subnet_group_name == aws_elasticache_subnet_group.gitlab_redis[0].name
    error_message = "Should use the overridden subnet group"
  }
}

# Test 10: Network fallback logic with existing network
run "test_network_fallback" {
  command = plan
  module { source = "../../../gitlab_ref_arch_aws" }

  variables {
    prefix                          = var.test_prefix
    elasticache_redis_node_count    = 1
    elasticache_redis_instance_type = "t3.micro"
    elasticache_redis_password      = "fallback16chars1234"

    # Existing network (tests backend_subnet_ids fallback)
    create_network = false
    vpc_id         = "vpc-existing789"
    subnet_pub_ids = ["subnet-exist1", "subnet-exist2", "subnet-exist3"]
  }

  # Should use provided existing subnets
  assert {
    condition     = aws_elasticache_subnet_group.gitlab_redis[0].subnet_ids == toset(["subnet-exist1", "subnet-exist2", "subnet-exist3"])
    error_message = "Should use explicitly provided existing subnet IDs"
  }

  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis[0].subnet_group_name == aws_elasticache_subnet_group.gitlab_redis[0].name
    error_message = "Should use existing network subnet group"
  }
}

# ====== SAFETY TESTS ======

# Test 11: Resource stability (prevent accidental recreation)
run "test_resource_stability" {
  command = plan
  module { source = "../../../gitlab_ref_arch_aws" }

  variables {
    prefix                          = var.test_prefix
    elasticache_redis_node_count    = 2
    elasticache_redis_instance_type = "t3.micro"
    elasticache_redis_password      = "stability16chars"
    elasticache_redis_kms_key_arn   = var.test_kms_key
  }

  # Test replication group ID follows expected pattern (stability for lifecycle ignore_changes)
  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis[0].replication_group_id == "${var.test_prefix}-redis"
    error_message = "Replication group ID should follow predictable pattern for lifecycle stability"
  }

  # Test encryption settings are properly configured (protected by lifecycle ignore_changes)
  assert {
    condition     = tobool(aws_elasticache_replication_group.gitlab_redis[0].at_rest_encryption_enabled) == true
    error_message = "At-rest encryption must be enabled and stable"
  }

  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis[0].kms_key_id == var.test_kms_key
    error_message = "KMS key should be set correctly and remain stable"
  }

  # Test that apply_immediately is true (ensures changes don't cause unexpected maintenance windows)
  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis[0].apply_immediately == true
    error_message = "apply_immediately should be true to avoid unexpected maintenance windows"
  }

  # Test subnet group naming consistency (prevents recreation due to naming changes)
  assert {
    condition     = aws_elasticache_subnet_group.gitlab_redis[0].name == "${var.test_prefix}-redis-subnet-group"
    error_message = "Subnet group naming should be consistent to prevent recreation"
  }
}

# Test 12: Configuration validation and edge cases
run "test_configuration_safety" {
  command = plan
  module { source = "../../../gitlab_ref_arch_aws" }

  variables {
    prefix                           = "maxlengthprefixtest123456789" # 29 chars - within limit but tests edge case
    elasticache_redis_node_count     = 1
    elasticache_redis_instance_type  = "t3.micro"
    elasticache_redis_engine         = "redis"
    elasticache_redis_engine_version = "6.x"
    elasticache_redis_password       = "configsafety16chars"
  }

  # Test replication group ID length limits (40 char AWS limit)
  assert {
    condition     = length(aws_elasticache_replication_group.gitlab_redis[0].replication_group_id) <= 40
    error_message = "Replication group ID must not exceed 40 characters to avoid AWS errors"
  }

  # Test parameter group family resolution for edge case versions
  assert {
    condition     = aws_elasticache_parameter_group.gitlab_redis[0].family == "redis6.x"
    error_message = "Version 6.x should resolve to redis6.x parameter family, not redis6"
  }

  # Test engine validation through successful resource creation
  assert {
    condition     = contains(["redis", "valkey"], aws_elasticache_replication_group.gitlab_redis[0].engine)
    error_message = "Engine should be validated to redis or valkey only"
  }

  # Test node type format (AWS requires cache. prefix)
  assert {
    condition     = length(regexall("^cache\\.", aws_elasticache_replication_group.gitlab_redis[0].node_type)) > 0
    error_message = "Node type should have cache. prefix for AWS compatibility"
  }

  # Test Multi-AZ logic safety (single node should not enable Multi-AZ)
  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis[0].multi_az_enabled == false
    error_message = "Single node deployment should not enable Multi-AZ to prevent configuration errors"
  }

  # Test automatic failover logic safety (single node should not enable failover)
  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis[0].automatic_failover_enabled == false
    error_message = "Single node deployment should not enable automatic failover"
  }
}

# ====== INTEGRATION TESTS ======

# Test 13: End-to-end mixed scenario
run "test_end_to_end_mixed" {
  command = plan
  module { source = "../../../gitlab_ref_arch_aws" }

  variables {
    prefix = var.test_prefix

    # Mixed deployment: Cache (Valkey) + Persistent (Redis)
    elasticache_redis_cache_node_count          = 1
    elasticache_redis_cache_instance_type       = "t3.small"
    elasticache_redis_cache_engine              = "valkey"
    elasticache_redis_persistent_node_count     = 2
    elasticache_redis_persistent_instance_type  = "m5.large"
    elasticache_redis_persistent_engine         = "redis"
    elasticache_redis_persistent_engine_version = "6.x"
    elasticache_redis_kms_key_arn               = var.test_kms_key
    elasticache_redis_password                  = "endtoend16characters"

    # Existing network with explicit subnets
    create_network = false
    vpc_id         = "vpc-integration123"
    subnet_pub_ids = ["subnet-int1", "subnet-int2"]
  }

  # Mixed engines working together
  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis_cache[0].engine == "valkey" && aws_elasticache_replication_group.gitlab_redis_persistent[0].engine == "redis"
    error_message = "Should support mixed Valkey cache and Redis persistent engines"
  }

  # Shared infrastructure
  assert {
    condition     = aws_elasticache_replication_group.gitlab_redis_cache[0].subnet_group_name == aws_elasticache_replication_group.gitlab_redis_persistent[0].subnet_group_name
    error_message = "Mixed instances should share the same subnet group"
  }

  # Network configuration
  assert {
    condition     = aws_elasticache_subnet_group.gitlab_redis[0].subnet_ids == toset(["subnet-int1", "subnet-int2"])
    error_message = "Should use integration test network subnets"
  }

  # Security and encryption
  assert {
    condition     = tobool(aws_elasticache_replication_group.gitlab_redis_cache[0].at_rest_encryption_enabled) && tobool(aws_elasticache_replication_group.gitlab_redis_persistent[0].at_rest_encryption_enabled)
    error_message = "Both instances should have encryption enabled"
  }

  # Different parameter families
  assert {
    condition     = contains(["valkey7", "valkey"], aws_elasticache_parameter_group.gitlab_redis_cache[0].family) && aws_elasticache_parameter_group.gitlab_redis_persistent[0].family == "redis6.x"
    error_message = "Should use different parameter families for different engines"
  }
}