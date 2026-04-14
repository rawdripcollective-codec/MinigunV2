# RDS Mixed Configuration Test Suite
# Testing interaction between individual and unified database configurations

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }

  mock_data "aws_vpc" {
    defaults = {
      id         = "vpc-12345678"
      cidr_block = "10.0.0.0/16"
    }
  }

  mock_data "aws_subnets" {
    defaults = {
      ids = ["subnet-12345", "subnet-67890", "subnet-abcdef"]
    }
  }

  mock_data "aws_kms_key" {
    defaults = {
      id  = "12345678-1234-1234-1234-123456789012"
      arn = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
    }
  }

  override_during = plan
}

# Test 1: Individual main + Unified praefect
run "mixed_main_individual_praefect_unified" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-mixed-1"

    # Individual main database
    rds_postgres_instance_type           = "r6g.xlarge"
    rds_postgres_password                = "main-password"
    rds_postgres_multi_az                = true
    rds_postgres_backup_retention_period = 14

    # Unified praefect database
    rds_databases = {
      praefect = {
        instance_type = "m5.large"
        username      = "praefect"
        password_wo   = "praefect-password"
        db_name       = "praefect_production"
      }
    }
  }

  assert {
    condition     = length(aws_db_instance.gitlab) == 1
    error_message = "Should create individual main database"
  }

  assert {
    condition     = length(aws_db_instance.gitlab_rds_database) == 1
    error_message = "Should create unified praefect database"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].username == "gitlab"
    error_message = "Individual database should use gitlab username"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["praefect"].username == "praefect"
    error_message = "Unified database should use praefect username"
  }
}

# Test 2: Unified main + Individual praefect
run "mixed_main_unified_praefect_individual" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-mixed-2"

    # Unified main database
    rds_databases = {
      main = {
        instance_type = "r6g.xlarge"
        password_wo   = "main-password"
        db_name       = "gitlabhq_production"
        multi_az      = true
      }
    }

    # Individual praefect database
    rds_praefect_postgres_instance_type = "m5.large"
    rds_praefect_postgres_password      = "praefect-password"
  }

  assert {
    condition     = length(aws_db_instance.gitlab_rds_database) == 1
    error_message = "Should create unified main database"
  }

  assert {
    condition     = length(aws_db_instance.gitlab_praefect) == 1
    error_message = "Should create individual praefect database"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["main"].db_name == "gitlabhq_production"
    error_message = "Unified database should use custom db_name"
  }

  assert {
    condition     = aws_db_instance.gitlab_praefect[0].username == "praefect"
    error_message = "Individual praefect should use default username"
  }
}

# Test 3: All databases via different approaches
run "mixed_all_databases_different_approaches" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-mixed-all"

    # Individual main database
    rds_postgres_instance_type           = "r6g.2xlarge"
    rds_postgres_password                = "main-password"
    rds_postgres_read_replica_count      = 2
    rds_postgres_backup_retention_period = 30

    # Individual praefect database
    rds_praefect_postgres_instance_type = "m5.large"
    rds_praefect_postgres_password      = "praefect-password"

    # Unified registry database
    rds_databases = {
      registry = {
        instance_type = "m6g.large"
        username      = "registry"
        password_wo   = "registry-password"
        db_name       = "registry_production"
        custom_tags = {
          Purpose = "Container Registry"
        }
      }

      analytics = {
        instance_type = "r6g.xlarge"
        username      = "analytics"
        password_wo   = "analytics-password"
        db_name       = "analytics_production"
        storage_type  = "io1"
        iops          = 2000
      }
    }
  }

  assert {
    condition     = length(aws_db_instance.gitlab) == 1
    error_message = "Should create individual main database"
  }

  assert {
    condition     = length(aws_db_instance.gitlab_praefect) == 1
    error_message = "Should create individual praefect database"
  }

  assert {
    condition     = length(aws_db_instance.gitlab_rds_database) == 2
    error_message = "Should create 2 unified databases"
  }

  assert {
    condition     = length(aws_db_instance.gitlab_read_replica) == 2
    error_message = "Should create read replicas for individual main database"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["registry"].db_name == "registry_production"
    error_message = "Registry database should have custom name"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["analytics"].storage_type == "io1"
    error_message = "Analytics database should use custom storage type"
  }
}

# Test 4: Output compatibility test
run "output_compatibility" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-mixed-outputs"

    # Individual main
    rds_postgres_instance_type = "m5.large"
    rds_postgres_password      = "main-password"

    # Unified additional databases
    rds_databases = {
      praefect = {
        instance_type = "m5.medium"
        password_wo   = "praefect-password"
        db_name       = "praefect_production"
      }

      registry = {
        instance_type = "m5.large"
        password_wo   = "registry-password"
        db_name       = "registry_production"
      }
    }
  }

  # Test that both output formats exist
  assert {
    condition     = contains(keys(output.rds_postgres_connection), "rds_host")
    error_message = "Should have individual database outputs"
  }

  assert {
    condition     = contains(keys(output.rds_databases), "praefect")
    error_message = "Should have unified database outputs for praefect"
  }

  assert {
    condition     = contains(keys(output.rds_databases), "registry")
    error_message = "Should have unified database outputs for registry"
  }
}

# Test 5: KMS key interaction between approaches
run "kms_key_interaction" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix              = "gitlab-mixed-kms"
    default_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/shared-default"

    # Individual with custom key
    rds_postgres_instance_type = "m5.large"
    rds_postgres_password      = "main-password"
    rds_postgres_kms_key_arn   = "arn:aws:kms:us-east-1:123456789012:key/individual-custom"

    # Unified with default key
    rds_databases = {
      praefect = {
        instance_type = "m5.medium"
        password_wo   = "praefect-password"
        # Should use default_kms_key_arn
      }
    }
  }

  assert {
    condition     = aws_db_instance.gitlab[0].kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/individual-custom"
    error_message = "Individual database should use its custom KMS key"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["praefect"].kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/shared-default"
    error_message = "Unified database should use shared default KMS key"
  }
}

# Test 6: Security group isolation
run "security_group_isolation" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-mixed-sg"

    # Individual main with CIDR blocks
    rds_postgres_instance_type               = "m5.large"
    rds_postgres_password                    = "main-password"
    rds_postgres_allowed_ingress_cidr_blocks = ["10.0.0.0/16"]

    # Unified with different CIDR blocks
    rds_databases = {
      registry = {
        instance_type       = "m5.medium"
        password_wo         = "registry-password"
        allowed_cidr_blocks = ["192.168.1.0/24", "172.16.0.0/12"]
      }
    }
  }

  assert {
    condition     = length(aws_security_group.gitlab_rds) == 1
    error_message = "Should create individual main security group"
  }

  assert {
    condition     = length(aws_security_group.gitlab_rds_database) == 1
    error_message = "Should create unified database security group"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.gitlab_rds_cidr) == 1
    error_message = "Should create 1 CIDR rule for individual database"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.gitlab_rds_database_cidr) == 2
    error_message = "Should create 2 CIDR rules for unified database"
  }
}

# Test 7: Resource naming collision avoidance
run "resource_naming_no_collision" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-mixed-naming"

    # Individual main
    rds_postgres_instance_type = "m5.large"
    rds_postgres_password      = "main-password"

    # Unified with "main" key (should not collide)
    rds_databases = {
      main = {
        instance_type = "m5.medium"
        password_wo   = "unified-main-password"
        db_name       = "unified_main_db"
      }
    }
  }

  assert {
    condition     = aws_db_instance.gitlab[0].identifier == "gitlab-mixed-naming-rds"
    error_message = "Individual database should use standard identifier"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["main"].identifier == "gitlab-mixed-naming-rds-main"
    error_message = "Unified database should use keyed identifier"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].db_name != aws_db_instance.gitlab_rds_database["main"].db_name
    error_message = "Databases should have different database names"
  }
}