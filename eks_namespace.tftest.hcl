mock_provider "aws" {
  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }
}

run "mock_eks_custom_namespace" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix                             = "gitlab-test"
    webservice_node_pool_count         = 1
    webservice_node_pool_instance_type = "m5.large"

    # Test new variable takes precedence when deprecated is not set
    eks_gitlab_cloud_native_namespace = "custom-namespace"
  }

  assert {
    condition     = local.eks_gitlab_cloud_native_namespace == "custom-namespace"
    error_message = "When user provides custom namespace, it should be used. Expected 'custom-namespace', got '${local.eks_gitlab_cloud_native_namespace}'"
  }
}

run "mock_eks_deprecated_namespace_variable_backward_compatibility" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix                             = "gitlab-test"
    webservice_node_pool_count         = 1
    webservice_node_pool_instance_type = "m5.large"

    # Test deprecated variable takes precedence when explicitly set
    eks_gitlab_charts_namespace       = "legacy-namespace"
    eks_gitlab_cloud_native_namespace = "new-namespace"
  }

  assert {
    condition     = local.eks_gitlab_cloud_native_namespace == "legacy-namespace"
    error_message = "When deprecated variable is explicitly set, it should take precedence. Expected 'legacy-namespace', got '${local.eks_gitlab_cloud_native_namespace}'"
  }
}

run "mock_eks_default_namespace_behavior" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_aws"
  }

  variables {
    prefix                             = "gitlab-test"
    webservice_node_pool_count         = 1
    webservice_node_pool_instance_type = "m5.large"

    # Test default behavior - neither variable explicitly set
    # This should use the default value of eks_gitlab_cloud_native_namespace
  }

  assert {
    condition     = local.eks_gitlab_cloud_native_namespace == "default"
    error_message = "When no namespace variables are set, should use default namespace. Expected 'default', got '${local.eks_gitlab_cloud_native_namespace}'"
  }
}
