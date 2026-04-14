# RDS Individual Database Configuration Test Suite
# Testing for individual database variable configuration

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

# Test 1: Basic main database creation
run "main_database_basic" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-main"

    rds_postgres_instance_type = "m5.2xlarge"
    rds_postgres_password      = "test-main-password"
  }

  assert {
    condition     = length(aws_db_instance.gitlab) == 1
    error_message = "Should create exactly 1 main database"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].engine == "postgres"
    error_message = "Should use postgres engine"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].engine_version == "16"
    error_message = "Should default to version 16"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].db_name == "gitlabhq_production"
    error_message = "Should use default GitLab database name"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].username == "gitlab"
    error_message = "Should use default gitlab username"
  }
}

# Test 2: Main database with custom configuration
run "main_database_custom" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-custom"

    rds_postgres_instance_type         = "r6g.xlarge"
    rds_postgres_password              = "custom-password"
    rds_postgres_username              = "custom_user"
    rds_postgres_database_name         = "custom_db"
    rds_postgres_allocated_storage     = 200
    rds_postgres_max_allocated_storage = 2000
    rds_postgres_storage_type          = "gp3"
    rds_postgres_multi_az              = false
    rds_postgres_deletion_protection   = true
  }

  assert {
    condition     = aws_db_instance.gitlab[0].instance_class == "db.r6g.xlarge"
    error_message = "Should use custom instance type"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].username == "custom_user"
    error_message = "Should use custom username"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].allocated_storage == 200
    error_message = "Should use custom storage size"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].storage_type == "gp3"
    error_message = "Should use custom storage type"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].multi_az == false
    error_message = "Should be single-AZ when specified"
  }
}

# Test 3: Praefect database configuration
run "praefect_database" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-praefect"

    rds_praefect_postgres_instance_type = "m5.large"
    rds_praefect_postgres_password      = "praefect-password"
    rds_praefect_postgres_username      = "praefect"
    rds_praefect_postgres_database_name = "praefect_production"
  }

  assert {
    condition     = length(aws_db_instance.gitlab_praefect) == 1
    error_message = "Should create exactly 1 praefect database"
  }

  assert {
    condition     = aws_db_instance.gitlab_praefect[0].instance_class == "db.m5.large"
    error_message = "Should use specified instance type"
  }

  assert {
    condition     = aws_db_instance.gitlab_praefect[0].username == "praefect"
    error_message = "Should use praefect username"
  }

  assert {
    condition     = aws_db_instance.gitlab_praefect[0].db_name == "praefect_production"
    error_message = "Should use praefect database name"
  }
}

# Test 4: Geo tracking database configuration
run "geo_tracking_database" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-geo"

    rds_geo_tracking_postgres_instance_type = "m5.xlarge"
    rds_geo_tracking_postgres_password      = "geo-password"
    rds_geo_tracking_postgres_username      = "gitlab_geo"
    rds_geo_tracking_postgres_database_name = "gitlabhq_geo_production"
  }

  assert {
    condition     = length(aws_db_instance.gitlab_geo_tracking) == 1
    error_message = "Should create exactly 1 geo tracking database"
  }

  assert {
    condition     = aws_db_instance.gitlab_geo_tracking[0].username == "gitlab_geo"
    error_message = "Should use geo username"
  }

  assert {
    condition     = aws_db_instance.gitlab_geo_tracking[0].db_name == "gitlabhq_geo_production"
    error_message = "Should use geo database name"
  }
}

# Test 5: Main database with read replicas
run "main_database_read_replicas" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-replicas"

    rds_postgres_instance_type           = "r6g.large"
    rds_postgres_password                = "main-password"
    rds_postgres_backup_retention_period = 7
    rds_postgres_read_replica_count      = 3
    rds_postgres_read_replica_port       = 5433
    rds_postgres_read_replica_multi_az   = true
  }

  assert {
    condition     = length(aws_db_instance.gitlab_read_replica) == 3
    error_message = "Should create 3 read replicas"
  }

  assert {
    condition     = aws_db_instance.gitlab_read_replica[0].port == 5433
    error_message = "Should use custom replica port"
  }

  assert {
    condition     = aws_db_instance.gitlab_read_replica[0].multi_az == true
    error_message = "Should use multi-AZ for replicas"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].backup_retention_period == 7
    error_message = "Should set backup retention for replica source"
  }
}

# Test 6: Cross-region replication (Geo)
run "cross_region_replication" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-geo-replica"

    rds_postgres_instance_type            = "m5.large"
    rds_postgres_password                 = "geo-password"
    rds_postgres_replication_database_arn = "arn:aws:rds:us-east-1:123456789012:db:primary-main"
    rds_postgres_kms_key_arn              = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].replicate_source_db == "arn:aws:rds:us-east-1:123456789012:db:primary-main"
    error_message = "Should set replication source"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    error_message = "Should use cross-region KMS key"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].storage_encrypted == true
    error_message = "Should be encrypted"
  }
}

# Test 7: Custom parameters
run "custom_parameters" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-params"

    rds_postgres_instance_type = "m5.large"
    rds_postgres_password      = "password"
    rds_postgres_version       = "15"
    rds_postgres_params = {
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

  assert {
    condition     = aws_db_parameter_group.gitlab[0].family == "postgres15"
    error_message = "Should create postgres15 parameter group"
  }

  assert {
    condition = contains([
      for param in aws_db_parameter_group.gitlab[0].parameter :
      param.value if param.name == "log_min_duration_statement"
    ], "500")
    error_message = "Should override default log_min_duration_statement with user value"
  }

  assert {
    condition = contains([
      for param in aws_db_parameter_group.gitlab[0].parameter :
      param.name if param.name == "password_encryption"
    ], "password_encryption")
    error_message = "Should include default parameters not overridden by user"
  }
}

# Test 8: Performance and monitoring
run "performance_monitoring" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-perf"

    rds_postgres_instance_type                         = "r6g.2xlarge"
    rds_postgres_password                              = "password"
    rds_postgres_monitoring_interval                   = 60
    rds_postgres_monitoring_role_arn                   = "arn:aws:iam::123456789012:role/rds-monitoring-role"
    rds_postgres_performance_insights_enabled          = true
    rds_postgres_performance_insights_retention_period = 7
    rds_postgres_enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]
  }

  assert {
    condition     = aws_db_instance.gitlab[0].monitoring_interval == 60
    error_message = "Should set monitoring interval"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].performance_insights_enabled == true
    error_message = "Should enable performance insights"
  }

  assert {
    condition     = length(aws_db_instance.gitlab[0].enabled_cloudwatch_logs_exports) == 2
    error_message = "Should enable CloudWatch log exports"
  }
}

# Test 9: Storage configuration
run "storage_configuration" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-storage"

    rds_postgres_instance_type         = "r6g.xlarge"
    rds_postgres_password              = "password"
    rds_postgres_storage_type          = "io1"
    rds_postgres_iops                  = 3000
    rds_postgres_allocated_storage     = 500
    rds_postgres_max_allocated_storage = 2000
  }

  assert {
    condition     = aws_db_instance.gitlab[0].storage_type == "io1"
    error_message = "Should use io1 storage type"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].iops == 3000
    error_message = "Should use custom IOPS"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].allocated_storage == 500
    error_message = "Should use custom allocated storage"
  }
}

# Test 10: Multiple individual databases together
run "multiple_individual_databases" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-multi-individual"

    # Main database
    rds_postgres_instance_type           = "r6g.xlarge"
    rds_postgres_password                = "main-password"
    rds_postgres_backup_retention_period = 14

    # Praefect database
    rds_praefect_postgres_instance_type = "m5.large"
    rds_praefect_postgres_password      = "praefect-password"

    # Geo tracking database
    rds_geo_tracking_postgres_instance_type = "m5.xlarge"
    rds_geo_tracking_postgres_password      = "geo-password"
  }

  assert {
    condition     = length(aws_db_instance.gitlab) == 1
    error_message = "Should create main database"
  }

  assert {
    condition     = length(aws_db_instance.gitlab_praefect) == 1
    error_message = "Should create praefect database"
  }

  assert {
    condition     = length(aws_db_instance.gitlab_geo_tracking) == 1
    error_message = "Should create geo tracking database"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].backup_retention_period == 14
    error_message = "Should set backup retention on main database"
  }
}

# Test 11: Security groups and networking
run "security_groups_networking" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-security"

    rds_postgres_instance_type               = "m5.large"
    rds_postgres_password                    = "password"
    rds_postgres_allowed_ingress_cidr_blocks = ["10.0.0.0/16", "192.168.1.0/24"]
    rds_postgres_default_subnet_count        = 3
  }

  assert {
    condition     = length(aws_security_group.gitlab_rds) == 1
    error_message = "Should create main database security group"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.gitlab_rds_cidr) == 2
    error_message = "Should create 2 CIDR rules"
  }

  assert {
    condition     = contains(keys(aws_vpc_security_group_ingress_rule.gitlab_rds_cidr), "10.0.0.0/16")
    error_message = "Should create rule for first CIDR block"
  }
}

# Test 12: Version and lifecycle management
run "version_lifecycle" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-version"

    rds_postgres_instance_type              = "m5.large"
    rds_postgres_password                   = "password"
    rds_postgres_version                    = "15"
    rds_postgres_auto_minor_version_upgrade = true
    rds_postgres_lifecycle_support          = "open-source-rds-extended-support"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].engine_version == "15"
    error_message = "Should use specified PostgreSQL version"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].auto_minor_version_upgrade == true
    error_message = "Should enable auto minor version upgrade"
  }

  assert {
    condition     = aws_db_parameter_group.gitlab[0].family == "postgres15"
    error_message = "Should create postgres15 parameter group"
  }
}

# Test 13: Backup and maintenance configuration
run "backup_maintenance" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-backup"

    rds_postgres_instance_type            = "m5.large"
    rds_postgres_password                 = "password"
    rds_postgres_version                  = "16"
    rds_postgres_backup_retention_period  = 30
    rds_postgres_backup_window            = "03:00-04:00"
    rds_postgres_maintenance_window       = "sun:04:00-sun:05:00"
    rds_postgres_delete_automated_backups = false
  }

  assert {
    condition     = aws_db_instance.gitlab[0].backup_retention_period == 30
    error_message = "Should set backup retention period"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].backup_window == "03:00-04:00"
    error_message = "Should set backup window"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].maintenance_window == "sun:04:00-sun:05:00"
    error_message = "Should set maintenance window"
  }
}

# Test 14: KMS key configuration
run "kms_key_configuration" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix              = "gitlab-rds-kms"
    default_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/default-key-1234"

    rds_postgres_instance_type = "m5.large"
    rds_postgres_password      = "password"
    rds_postgres_kms_key_arn   = "arn:aws:kms:us-east-1:123456789012:key/custom-postgres-key"

    rds_praefect_postgres_instance_type = "m5.medium"
    rds_praefect_postgres_password      = "praefect-password"
    # Should use default_kms_key_arn
  }

  assert {
    condition     = aws_db_instance.gitlab[0].kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/custom-postgres-key"
    error_message = "Should use custom KMS key for main database"
  }

  assert {
    condition     = aws_db_instance.gitlab_praefect[0].kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/default-key-1234"
    error_message = "Should use default KMS key for praefect database"
  }
}

# Test 15: Database restoration from snapshot
run "snapshot_restoration" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-snapshot"

    rds_postgres_instance_type = "m5.large"
    rds_postgres_password      = "password"
    rds_snapshot_identifier    = "gitlab-prod-backup-20241201"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].snapshot_identifier == "gitlab-prod-backup-20241201"
    error_message = "Should restore from specified snapshot"
  }

  assert {
    condition     = aws_db_instance.gitlab[0].skip_final_snapshot == true
    error_message = "Should skip final snapshot on destroy"
  }
}

# Test 16: Default network configuration
run "default_network" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-default-network"

    rds_postgres_instance_type = "m5.large"
    rds_postgres_password      = "password"
  }

  # Verify security group references default VPC via data source
  assert {
    condition     = aws_security_group.gitlab_rds[0].vpc_id != null
    error_message = "Security group should reference default VPC ID"
  }

  # Verify subnet group is created with default network
  assert {
    condition     = aws_db_subnet_group.gitlab[0] != null
    error_message = "Should create subnet group with default network"
  }

  # Verify database creation works
  assert {
    condition     = aws_db_instance.gitlab[0].instance_class == "db.m5.large"
    error_message = "Database should be created with default network"
  }
}

# Test 17: Created network configuration  
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

    rds_postgres_instance_type = "m5.large"
    rds_postgres_password      = "password"
  }

  # Verify VPC is created
  assert {
    condition     = length(aws_vpc.gitlab_vpc) == 1
    error_message = "Should create VPC when create_network = true"
  }

  # Verify security group references created VPC
  assert {
    condition     = aws_security_group.gitlab_rds[0].vpc_id != null
    error_message = "Security group should reference created VPC"
  }

  # Verify subnet group uses created subnets
  assert {
    condition     = aws_db_subnet_group.gitlab[0] != null
    error_message = "Should create subnet group with created network"
  }

  # Verify database creation works with created network
  assert {
    condition     = aws_db_instance.gitlab[0].instance_class == "db.m5.large"
    error_message = "Database should be created with created network"
  }
}

# Test 18: Existing network configuration
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

    rds_postgres_instance_type = "m5.large"
    rds_postgres_password      = "password"
  }

  # Verify no VPC is created
  assert {
    condition     = length(aws_vpc.gitlab_vpc) == 0
    error_message = "Should not create VPC when using existing network"
  }

  # Verify security group references existing VPC
  assert {
    condition     = aws_security_group.gitlab_rds[0].vpc_id != null
    error_message = "Security group should reference existing VPC"
  }

  # Verify subnet group is created with existing network
  assert {
    condition     = aws_db_subnet_group.gitlab[0] != null
    error_message = "Should create subnet group with existing network"
  }

  # Verify database creation works with existing network
  assert {
    condition     = aws_db_instance.gitlab[0].instance_class == "db.m5.large"
    error_message = "Database should be created with existing network"
  }
}

# Test 19: Empty configuration (renumbered)
run "no_databases" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = "gitlab-rds-none"
    # No RDS variables set
  }

  assert {
    condition     = length(aws_db_instance.gitlab) == 0
    error_message = "Should create no main databases when not configured"
  }

  assert {
    condition     = length(aws_db_instance.gitlab_praefect) == 0
    error_message = "Should create no praefect databases when not configured"
  }

  assert {
    condition     = length(aws_db_instance.gitlab_geo_tracking) == 0
    error_message = "Should create no geo tracking databases when not configured"
  }
}