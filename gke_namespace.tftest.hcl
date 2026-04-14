mock_provider "google" {}

run "mock_gke_custom_namespace" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_gcp"
  }

  variables {
    prefix                            = "gitlab-test"
    project                           = "test-project"
    webservice_node_pool_count        = 1
    webservice_node_pool_machine_type = "n1-standard-2"
    supporting_node_pool_count        = 1
    supporting_node_pool_machine_type = "n1-standard-2"

    # Test new variable takes precedence when deprecated is not set
    gke_gitlab_cloud_native_namespace = "custom-namespace"
  }

  assert {
    condition     = local.gke_gitlab_cloud_native_namespace == "custom-namespace"
    error_message = "When user provides custom namespace, it should be used. Expected 'custom-namespace', got '${local.gke_gitlab_cloud_native_namespace}'"
  }
}

run "mock_gke_deprecated_namespace_variable_backward_compatibility" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_gcp"
  }

  variables {
    prefix                            = "gitlab-test"
    project                           = "test-project"
    webservice_node_pool_count        = 1
    webservice_node_pool_machine_type = "n1-standard-2"
    supporting_node_pool_count        = 1
    supporting_node_pool_machine_type = "n1-standard-2"

    # Test deprecated variable takes precedence when explicitly set
    gke_gitlab_charts_namespace       = "legacy-namespace"
    gke_gitlab_cloud_native_namespace = "new-namespace"
  }

  assert {
    condition     = local.gke_gitlab_cloud_native_namespace == "legacy-namespace"
    error_message = "When deprecated variable is explicitly set, it should take precedence. Expected 'legacy-namespace', got '${local.gke_gitlab_cloud_native_namespace}'"
  }
}

run "mock_gke_default_namespace_behavior" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_gcp"
  }

  variables {
    prefix                            = "gitlab-test"
    project                           = "test-project"
    webservice_node_pool_count        = 1
    webservice_node_pool_machine_type = "n1-standard-2"
    supporting_node_pool_count        = 1
    supporting_node_pool_machine_type = "n1-standard-2"

    # Test default behavior - neither variable explicitly set
    # This should use the default value of gke_gitlab_cloud_native_namespace
  }

  assert {
    condition     = local.gke_gitlab_cloud_native_namespace == "default"
    error_message = "When no namespace variables are set, should use default namespace. Expected 'default', got '${local.gke_gitlab_cloud_native_namespace}'"
  }
}
