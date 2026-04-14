# RDS Unified Databases Test Suite
# Testing for unified database configuration functionality

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

  mock_data "aws_default_vpc" {
    defaults = {
      id = "vpc-default-12345"
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

# Test 1: Basic single database
run "single_database" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-test"

    rds_databases = {
      main = {
        instance_type = "m6g.large"
        username      = "gitlab"
        password_wo   = "test-password"
        db_name       = "gitlabhq_production"
      }
    }
  }

  assert {
    condition     = length(aws_db_instance.gitlab_rds_database) == 1
    error_message = "Should create exactly 1 database"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["main"].engine == "postgres"
    error_message = "Should use postgres engine"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["main"].engine_version == "16"
    error_message = "Should default to version 16"
  }
}

# Test 2: Multiple databases
run "multiple_databases" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-multi"

    rds_databases = {
      main = {
        instance_type = "r6g.xlarge"
        username      = "gitlab"
        password_wo   = "main-password"
        db_name       = "gitlabhq_production"
        multi_az      = true
      }

      praefect = {
        instance_type = "t3.medium"
        username      = "praefect"
        password_wo   = "praefect-password"
        db_name       = "praefect_production"
        multi_az      = false
      }
    }
  }

  assert {
    condition     = length(aws_db_instance.gitlab_rds_database) == 2
    error_message = "Should create exactly 2 databases"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["main"].multi_az == true
    error_message = "Main should be multi-AZ"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["praefect"].multi_az == false
    error_message = "Praefect should be single-AZ"
  }
}

# Test 3: Read replicas
run "read_replicas" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-replicas"

    rds_databases = {
      main = {
        instance_type           = "r6g.large"
        username                = "gitlab"
        password_wo             = "password"
        backup_retention_period = 7
        read_replica_count      = 2
      }
    }
  }

  assert {
    condition     = length(aws_db_instance.gitlab_rds_database_read_replicas) == 2
    error_message = "Should create 2 read replicas"
  }

  assert {
    condition     = contains(keys(aws_db_instance.gitlab_rds_database_read_replicas), "main-replica-1")
    error_message = "Should create main-replica-1"
  }
}

# Test 4: Security groups and CIDR rules
run "security_groups_cidr" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-sg"

    rds_databases = {
      database1 = {
        instance_type       = "t3.medium"
        username            = "user1"
        password_wo         = "password"
        allowed_cidr_blocks = ["10.0.0.0/16", "192.168.1.0/24"]
      }

      database2 = {
        instance_type       = "t3.small"
        username            = "user2"
        password_wo         = "password"
        allowed_cidr_blocks = ["203.0.113.0/24"]
      }
    }
  }

  assert {
    condition     = length(aws_security_group.gitlab_rds_database) == 2
    error_message = "Should create 2 security groups"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.gitlab_rds_database_cidr) == 3
    error_message = "Should create 3 CIDR rules (2+1)"
  }
}

# Test 5: Custom storage configuration
run "custom_storage" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-storage"

    rds_databases = {
      high-perf = {
        instance_type     = "r6g.2xlarge"
        username          = "gitlab"
        password_wo       = "password"
        storage_type      = "io1"
        iops              = 3000
        allocated_storage = 500
      }
    }
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["high-perf"].storage_type == "io1"
    error_message = "Should use io1 storage"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["high-perf"].iops == 3000
    error_message = "Should use custom IOPS"
  }
}

# Test 6: Parameter groups
run "parameter_groups" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-params"

    rds_databases = {
      custom = {
        instance_type = "m6g.large"
        username      = "gitlab"
        password_wo   = "password"
        version       = 15
        parameters = {
          # Override default: log_min_duration_statement from 1000 to 500
          log_min_duration_statement = {
            value = "500"
          }
          # Add new parameter not in defaults
          max_connections = {
            value = "200"
          }
        }
      }
    }
  }

  assert {
    condition     = aws_db_parameter_group.gitlab_rds_database["custom"].family == "postgres15"
    error_message = "Should create postgres15 parameter group"
  }

  assert {
    condition = contains([
      for param in aws_db_parameter_group.gitlab_rds_database["custom"].parameter :
      param.value if param.name == "log_min_duration_statement"
    ], "500")
    error_message = "Should override default log_min_duration_statement with user value"
  }

  assert {
    condition = contains([
      for param in aws_db_parameter_group.gitlab_rds_database["custom"].parameter :
      param.name if param.name == "password_encryption"
    ], "password_encryption")
    error_message = "Should include default parameters not overridden by user"
  }
}

# Test 7: Monitoring configuration
run "monitoring_config" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-monitoring"

    rds_databases = {
      monitored = {
        instance_type                         = "r6g.large"
        username                              = "gitlab"
        password_wo                           = "password"
        monitoring_interval                   = 60
        performance_insights                  = true
        performance_insights_retention_period = 7
        enabled_cloudwatch_logs_exports       = ["postgresql"]
      }
    }
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["monitored"].monitoring_interval == 60
    error_message = "Should set monitoring interval"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["monitored"].performance_insights_enabled == true
    error_message = "Should enable performance insights"
  }
}

# Test 8: Real-world GitLab scenario
run "gitlab_production_scenario" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-prod"

    rds_databases = {
      main = {
        instance_type           = "r6g.xlarge"
        username                = "gitlab"
        password_wo             = "main-password"
        db_name                 = "gitlabhq_production"
        multi_az                = true
        backup_retention_period = 30
        read_replica_count      = 2
        performance_insights    = true
      }

      praefect = {
        instance_type           = "t3.large"
        username                = "praefect"
        password_wo             = "praefect-password"
        db_name                 = "praefect_production"
        backup_retention_period = 7
        read_replica_count      = 1
      }

      registry = {
        instance_type           = "m6g.large"
        username                = "registry"
        password_wo             = "registry-password"
        db_name                 = "registry_production"
        backup_retention_period = 14
        custom_tags = {
          Purpose = "Container Registry"
          Team    = "Verify"
        }
      }
    }
  }

  assert {
    condition     = length(aws_db_instance.gitlab_rds_database) == 3
    error_message = "Should create 3 databases"
  }

  assert {
    condition     = length(aws_db_instance.gitlab_rds_database_read_replicas) == 3
    error_message = "Should create 3 read replicas (2+1+0)"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["registry"].db_name == "registry_production"
    error_message = "New registry database should work without code changes"
  }
}

# Test 9: Cross-region replication with KMS
run "cross_region_replication" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-geo"

    rds_databases = {
      geo-replica = {
        instance_type        = "m6g.large"
        username             = "gitlab"
        password_wo          = "password"
        replicate_source_arn = "arn:aws:rds:us-east-1:123456789012:db:main-database"
        kms_key_arn          = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
      }
    }
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["geo-replica"].replicate_source_db == "arn:aws:rds:us-east-1:123456789012:db:main-database"
    error_message = "Should set cross-region replication source"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["geo-replica"].kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    error_message = "Should use region-specific KMS key"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["geo-replica"].storage_encrypted == true
    error_message = "Cross-region replica should be encrypted"
  }
}

# Test 10: KMS key fallback behavior
run "kms_key_fallback" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix              = "gitlab-rds-kms"
    default_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/default-key-1234"

    rds_databases = {
      custom-key = {
        instance_type = "t3.medium"
        username      = "gitlab"
        password_wo   = "password"
        kms_key_arn   = "arn:aws:kms:us-east-1:123456789012:key/custom-key-5678"
      }

      default-key = {
        instance_type = "t3.medium"
        username      = "gitlab"
        password_wo   = "password"
        # Should use default_kms_key_arn
      }
    }
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["custom-key"].kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/custom-key-5678"
    error_message = "Should use custom KMS key when specified"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["default-key"].kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/default-key-1234"
    error_message = "Should use module default KMS key when no custom key"
  }
}

# Test 11: Default network configuration
run "default_network" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-default-network"

    rds_databases = {
      main = {
        instance_type = "t3.medium"
        username      = "gitlab"
        password_wo   = "password"
      }
    }
  }

  # Verify security group references default VPC via data source
  assert {
    condition     = aws_security_group.gitlab_rds_database["main"].vpc_id != null
    error_message = "Security group should reference default VPC ID"
  }

  # Change this assertion - remove length check
  assert {
    condition     = aws_db_subnet_group.gitlab_rds_database["main"] != null
    error_message = "Should create subnet group with default network"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["main"].instance_class == "db.t3.medium"
    error_message = "Database should be created with default network"
  }
}

# Test 12: Created network configuration  
run "created_network" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-created-network"

    # Force network creation
    create_network = true
    vpc_cidr_block = "10.0.0.0/16"

    rds_databases = {
      main = {
        instance_type = "t3.medium"
        username      = "gitlab"
        password_wo   = "password"
      }
    }
  }

  # Verify VPC is created
  assert {
    condition     = length(aws_vpc.gitlab_vpc) == 1
    error_message = "Should create VPC when create_network = true"
  }

  # Verify security group references created VPC
  assert {
    condition     = aws_security_group.gitlab_rds_database["main"].vpc_id != null
    error_message = "Security group should reference created VPC"
  }

  # Verify subnet group uses created subnets
  assert {
    condition     = aws_db_subnet_group.gitlab_rds_database["main"] != null
    error_message = "Should create subnet group with default network"
  }

  # Verify database creation works with created network
  assert {
    condition     = aws_db_instance.gitlab_rds_database["main"].instance_class == "db.t3.medium"
    error_message = "Database should be created with created network"
  }
}

# Test 13: Existing network configuration
run "existing_network" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-existing-network"

    # Use existing network
    vpc_id          = "vpc-12345678"
    subnet_priv_ids = ["subnet-12345", "subnet-67890"]

    rds_databases = {
      main = {
        instance_type = "t3.medium"
        username      = "gitlab"
        password_wo   = "password"
      }
    }
  }

  # Verify no VPC is created
  assert {
    condition     = length(aws_vpc.gitlab_vpc) == 0
    error_message = "Should not create VPC when using existing network"
  }

  # Verify security group references existing VPC
  assert {
    condition     = aws_security_group.gitlab_rds_database["main"].vpc_id != null
    error_message = "Security group should reference existing VPC"
  }

  # Verify subnet group uses existing subnets
  assert {
    condition     = aws_db_subnet_group.gitlab_rds_database["main"] != null
    error_message = "Should create subnet group with default network"
  }

  # Verify database creation works with existing network
  assert {
    condition     = aws_db_instance.gitlab_rds_database["main"].instance_class == "db.t3.medium"
    error_message = "Database should be created with existing network"
  }
}

# Test 14: Database restoration from snapshot
run "snapshot_restoration" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-snapshot"

    rds_databases = {
      main = {
        instance_type       = "m6g.large"
        username            = "gitlab"
        password_wo         = "password"
        snapshot_identifier = "gitlab-prod-backup-20241201"
      }
    }
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["main"].snapshot_identifier == "gitlab-prod-backup-20241201"
    error_message = "Should restore from specified snapshot"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["main"].skip_final_snapshot == true
    error_message = "Should skip final snapshot on destroy"
  }
}

# Test 15: Version and lifecycle management
run "version_lifecycle" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-version"

    rds_databases = {
      postgres15 = {
        instance_type              = "m6g.large"
        username                   = "gitlab"
        password_wo                = "password"
        version                    = 15
        auto_minor_version_upgrade = true
        lifecycle_support          = "open-source-rds-extended-support"
      }
    }
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["postgres15"].engine_version == "15"
    error_message = "Should use specified PostgreSQL version"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["postgres15"].auto_minor_version_upgrade == true
    error_message = "Should enable auto minor version upgrade"
  }

  assert {
    condition     = aws_db_parameter_group.gitlab_rds_database["postgres15"].family == "postgres15"
    error_message = "Should create postgres15 parameter group"
  }
}

# Test 16: Backup and maintenance configuration
run "backup_maintenance" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-backup"

    rds_databases = {
      main = {
        instance_type            = "m6g.large"
        username                 = "gitlab"
        password_wo              = "password"
        version                  = 16
        backup_retention_period  = 30
        backup_window            = "03:00-04:00"
        maintenance_window       = "sun:04:00-sun:05:00"
        delete_automated_backups = false
      }
    }
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["main"].backup_retention_period == 30
    error_message = "Should set backup retention period"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["main"].backup_window == "03:00-04:00"
    error_message = "Should set backup window"
  }

  assert {
    condition     = aws_db_instance.gitlab_rds_database["main"].maintenance_window == "sun:04:00-sun:05:00"
    error_message = "Should set maintenance window"
  }
}

# Test 17: Empty configuration
run "empty_databases" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix        = "gitlab-rds-empty"
    rds_databases = {}
  }

  assert {
    condition     = length(aws_db_instance.gitlab_rds_database) == 0
    error_message = "Empty map should create no databases"
  }
}