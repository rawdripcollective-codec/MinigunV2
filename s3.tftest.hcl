# Mock the AWS provider to test S3 object storage configurations
mock_provider "aws" {
  override_during = plan

  override_data {
    target = data.aws_kms_key.aws_s3
    values = {
      id  = "alias/aws/s3"
      arn = "arn:aws:kms:us-east-1:123456789012:key/aws-s3-key"
    }
  }

  override_resource {
    target = aws_s3_bucket.gitlab_object_storage_buckets
    values = {
      id            = "test-bucket"
      bucket        = "test-bucket"
      arn           = "arn:aws:s3:::test-bucket"
      force_destroy = true
    }
  }

  override_resource {
    target = aws_s3_bucket_versioning.gitlab_object_storage_buckets
    values = {
      id     = "test-bucket"
      bucket = "test-bucket"
    }
  }

  override_resource {
    target = aws_s3_bucket_server_side_encryption_configuration.gitlab_object_storage_buckets
    values = {
      id     = "test-bucket"
      bucket = "test-bucket"
    }
  }

  override_resource {
    target = aws_s3_bucket_public_access_block.gitlab_object_storage_buckets
    values = {
      id                      = "test-bucket"
      bucket                  = "test-bucket"
      block_public_acls       = true
      block_public_policy     = true
      ignore_public_acls      = true
      restrict_public_buckets = true
    }
  }

  override_resource {
    target = aws_iam_policy.gitlab_s3_policy
    values = {
      id   = "test-s3-policy"
      name = "test-s3-policy"
      arn  = "arn:aws:iam::123456789012:policy/test-s3-policy"
    }
  }

  override_resource {
    target = aws_iam_policy.gitlab_s3_backups_policy
    values = {
      id   = "test-s3-backups-policy"
      name = "test-s3-backups-policy"
      arn  = "arn:aws:iam::123456789012:policy/test-s3-backups-policy"
    }
  }

  override_resource {
    target = aws_iam_policy.gitlab_s3_registry_policy
    values = {
      id   = "test-s3-registry-policy"
      name = "test-s3-registry-policy"
      arn  = "arn:aws:iam::123456789012:policy/test-s3-registry-policy"
    }
  }

  override_resource {
    target = aws_iam_policy.gitlab_s3_kms_policy
    values = {
      id   = "test-s3-kms-policy"
      name = "test-s3-kms-policy"
      arn  = "arn:aws:iam::123456789012:policy/test-s3-kms-policy"
    }
  }
}

variables {
  default_buckets = ["artifacts", "backups", "dependency-proxy", "lfs", "mr-diffs", "packages", "terraform-state", "uploads", "registry", "ci-secure-files", "pages"]
  test_prefix     = "gitlab-test"
}

run "s3_default_configuration" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = var.test_prefix

    gitlab_rails_node_count    = 1
    gitlab_rails_instance_type = "m5.xlarge"
  }

  assert {
    condition     = length(keys(aws_s3_bucket.gitlab_object_storage_buckets)) == length(var.default_buckets)
    error_message = "Should create ${length(var.default_buckets)} default buckets, but got ${length(keys(aws_s3_bucket.gitlab_object_storage_buckets))}"
  }

  assert {
    condition     = length(keys(aws_s3_bucket_versioning.gitlab_object_storage_buckets)) == 0
    error_message = "Default versioning should create no versioning resources, but got ${length(keys(aws_s3_bucket_versioning.gitlab_object_storage_buckets))}"
  }

  assert {
    condition     = length(keys(aws_s3_bucket_server_side_encryption_configuration.gitlab_object_storage_buckets)) == length(var.default_buckets)
    error_message = "Should create encryption config for all buckets"
  }

  assert {
    condition     = length(keys(aws_s3_bucket_public_access_block.gitlab_object_storage_buckets)) == length(var.default_buckets)
    error_message = "Should block public access for all buckets by default"
  }

  assert {
    condition     = aws_iam_policy.gitlab_s3_policy[0] != null
    error_message = "Should create main S3 IAM policy"
  }

  assert {
    condition     = aws_iam_policy.gitlab_s3_backups_policy[0] != null
    error_message = "Should create backups S3 IAM policy when backups bucket exists"
  }

  assert {
    condition     = aws_iam_policy.gitlab_s3_registry_policy[0] != null
    error_message = "Should create registry S3 IAM policy when registry bucket exists"
  }
}

run "s3_versioning_enabled" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = var.test_prefix

    object_storage_versioning_status = "Enabled"

    gitlab_rails_node_count    = 1
    gitlab_rails_instance_type = "m5.xlarge"
  }

  assert {
    condition     = length(keys(aws_s3_bucket_versioning.gitlab_object_storage_buckets)) == length(var.default_buckets)
    error_message = "Enabled versioning should create versioning resources for all buckets"
  }

  assert {
    condition = alltrue([
      for k, v in aws_s3_bucket_versioning.gitlab_object_storage_buckets :
      v.versioning_configuration[0].status == "Enabled"
    ])
    error_message = "All versioning resources should have status 'Enabled'"
  }
}

run "s3_versioning_suspended" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = var.test_prefix

    object_storage_versioning_status = "Suspended"

    gitlab_rails_node_count    = 1
    gitlab_rails_instance_type = "m5.xlarge"
  }

  assert {
    condition     = length(keys(aws_s3_bucket_versioning.gitlab_object_storage_buckets)) == length(var.default_buckets)
    error_message = "Suspended versioning should create versioning resources for all buckets"
  }

  assert {
    condition = alltrue([
      for k, v in aws_s3_bucket_versioning.gitlab_object_storage_buckets :
      v.versioning_configuration[0].status == "Suspended"
    ])
    error_message = "All versioning resources should have status 'Suspended'"
  }
}

run "s3_custom_buckets_and_prefix" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = var.test_prefix

    object_storage_buckets = ["artifacts", "lfs", "uploads"]
    object_storage_prefix  = "custom-prefix"

    gitlab_rails_node_count    = 1
    gitlab_rails_instance_type = "m5.xlarge"
  }

  assert {
    condition     = length(keys(aws_s3_bucket.gitlab_object_storage_buckets)) == 3
    error_message = "Should create exactly 3 custom buckets"
  }

  assert {
    condition = alltrue([
      for k, v in aws_s3_bucket.gitlab_object_storage_buckets :
      startswith(v.bucket, "custom-prefix-")
    ])
    error_message = "All buckets should use custom prefix"
  }

  assert {
    condition     = aws_iam_policy.gitlab_s3_backups_policy == []
    error_message = "Should not create backups policy when backups bucket not specified"
  }

  assert {
    condition     = aws_iam_policy.gitlab_s3_registry_policy == []
    error_message = "Should not create registry policy when registry bucket not specified"
  }
}

run "s3_disable_public_access_block" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = var.test_prefix

    object_storage_buckets             = ["artifacts"]
    object_storage_block_public_access = false

    gitlab_rails_node_count    = 1
    gitlab_rails_instance_type = "m5.xlarge"
  }

  assert {
    condition     = length(keys(aws_s3_bucket_public_access_block.gitlab_object_storage_buckets)) == 0
    error_message = "Should not create public access blocks when disabled"
  }
}

run "s3_custom_kms_key" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = var.test_prefix

    object_storage_buckets     = ["artifacts"]
    object_storage_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/custom-key"

    gitlab_rails_node_count    = 1
    gitlab_rails_instance_type = "m5.xlarge"
  }

  assert {
    condition     = aws_iam_policy.gitlab_s3_kms_policy[0] != null
    error_message = "Should create KMS policy when custom KMS key specified"
  }

  assert {
    condition     = output.object_storage_kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/custom-key"
    error_message = "Should output the custom KMS key ARN"
  }
}

run "s3_force_destroy_disabled" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = var.test_prefix

    object_storage_buckets       = ["artifacts"]
    object_storage_force_destroy = false

    gitlab_rails_node_count    = 1
    gitlab_rails_instance_type = "m5.xlarge"
  }

  assert {
    condition = alltrue([
      for k, v in aws_s3_bucket.gitlab_object_storage_buckets :
      v.force_destroy == false
    ])
    error_message = "All buckets should have force_destroy disabled when specified"
  }
}

run "s3_versioning_legacy_boolean_false" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix = var.test_prefix

    object_storage_versioning = false

    gitlab_rails_node_count    = 1
    gitlab_rails_instance_type = "m5.xlarge"
  }

  assert {
    condition     = length(keys(aws_s3_bucket_versioning.gitlab_object_storage_buckets)) == length(var.default_buckets)
    error_message = "Legacy boolean false should create versioning resources with 'Disabled' status"
  }

  assert {
    condition = alltrue([
      for k, v in aws_s3_bucket_versioning.gitlab_object_storage_buckets :
      v.versioning_configuration[0].status == "Disabled"
    ])
    error_message = "Legacy boolean false should set status to 'Disabled'"
  }
}
