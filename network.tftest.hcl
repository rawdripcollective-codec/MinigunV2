# Mock the GCP provider to test networking configurations
mock_provider "google" {}

run "mock_gcp_default_network" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_gcp"
  }

  variables {
    prefix                    = "gitlab-test"
    project                   = "test-project-12345"
    gitlab_rails_node_count   = 1
    gitlab_rails_machine_type = "n1-standard-8"
  }

  assert {
    condition     = output.network.vpc_name != null
    error_message = "Default network should provide VPC"
  }
}

run "mock_gcp_created_network" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_gcp"
  }

  variables {
    prefix                    = "gitlab-test"
    project                   = "test-project-12345"
    create_network            = true
    gitlab_rails_node_count   = 1
    gitlab_rails_machine_type = "n1-standard-8"
  }

  assert {
    condition     = can(regex("^gitlab-test", output.network.vpc_name))
    error_message = "Created network should use prefix in VPC name, not default network"
  }

  assert {
    condition     = can(cidrhost(output.network.vpc_subnet_cidr_block, 1))
    error_message = "Created network should have valid CIDR block"
  }
}

run "mock_gcp_existing_network" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_gcp"
  }

  variables {
    prefix                    = "gitlab-test"
    project                   = "test-project-12345"
    vpc_name                  = "existing-vpc"
    subnet_name               = "existing-subnet"
    gitlab_rails_node_count   = 1
    gitlab_rails_machine_type = "n1-standard-8"
  }

  assert {
    condition     = output.network.vpc_name == "existing-vpc" && output.network.vpc_subnet_name == "existing-subnet"
    error_message = "Existing network should use specified VPC/subnet names exactly"
  }
}

run "mock_gcp_external_ip_disabled" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_gcp"
  }

  variables {
    prefix                    = "gitlab-test"
    project                   = "test-project-12345"
    setup_external_ips        = false
    gitlab_rails_node_count   = 1
    gitlab_rails_machine_type = "n1-standard-8"
  }

  assert {
    condition     = length(output.gitlab_rails.external_addresses) == 0 && length(output.gitlab_rails.machine_names) > 0
    error_message = "Disabled external IPs should result in no external addresses but instances should still be created"
  }
}

run "mock_gcp_external_ip_enabled" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_gcp"
  }

  variables {
    prefix                    = "gitlab-test"
    project                   = "test-project-12345"
    setup_external_ips        = true
    gitlab_rails_node_count   = 1
    gitlab_rails_machine_type = "n1-standard-8"
  }

  assert {
    condition     = length(output.gitlab_rails.external_addresses) == length(output.gitlab_rails.machine_names) && length(output.gitlab_rails.machine_names) > 0
    error_message = "Enabled external IPs should provide one external address per instance"
  }
}
