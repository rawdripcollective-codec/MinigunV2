# Mock the GCP provider to test without real infrastructure
mock_provider "google" {}

variables {
  expected_consul_node_count   = 3
  expected_consul_machine_type = "n1-highcpu-2"

  expected_gitaly_node_count   = 3
  expected_gitaly_machine_type = "n1-standard-16"

  expected_praefect_node_count   = 3
  expected_praefect_machine_type = "n1-highcpu-2"

  expected_praefect_postgres_node_count   = 1
  expected_praefect_postgres_machine_type = "n1-highcpu-2"

  expected_gitlab_rails_node_count   = 3
  expected_gitlab_rails_machine_type = "n1-highcpu-32"

  expected_haproxy_external_node_count   = 1
  expected_haproxy_external_machine_type = "n1-highcpu-4"

  expected_haproxy_internal_node_count   = 1
  expected_haproxy_internal_machine_type = "n1-highcpu-4"

  expected_monitor_node_count   = 1
  expected_monitor_machine_type = "n1-highcpu-4"

  expected_opensearch_vm_node_count   = 3
  expected_opensearch_vm_machine_type = "n1-highcpu-16"
  expected_opensearch_vm_disk_type    = "pd-balanced"
  expected_opensearch_vm_disk_size    = 100

  expected_pgbouncer_node_count   = 3
  expected_pgbouncer_machine_type = "n1-highcpu-2"

  expected_postgres_node_count   = 3
  expected_postgres_machine_type = "n1-standard-8"

  expected_redis_cache_node_count   = 3
  expected_redis_cache_machine_type = "n1-standard-4"

  expected_redis_persistent_node_count   = 3
  expected_redis_persistent_machine_type = "n1-standard-4"

  expected_sidekiq_node_count   = 4
  expected_sidekiq_machine_type = "n1-standard-4"
}

run "mock_gcp_10k_environment" {
  command = plan

  module {
    source = "../../../gitlab_ref_arch_gcp"
  }

  variables {
    prefix                 = "gitlab-10k-test"
    project                = "test-project-12345"
    service_account_prefix = "gl10k"

    # 10k Reference Architecture Configuration
    consul_node_count   = var.expected_consul_node_count
    consul_machine_type = var.expected_consul_machine_type

    gitaly_node_count   = var.expected_gitaly_node_count
    gitaly_machine_type = var.expected_gitaly_machine_type

    praefect_node_count   = var.expected_praefect_node_count
    praefect_machine_type = var.expected_praefect_machine_type

    praefect_postgres_node_count   = var.expected_praefect_postgres_node_count
    praefect_postgres_machine_type = var.expected_praefect_postgres_machine_type

    gitlab_rails_node_count   = var.expected_gitlab_rails_node_count
    gitlab_rails_machine_type = var.expected_gitlab_rails_machine_type

    haproxy_external_node_count   = var.expected_haproxy_external_node_count
    haproxy_external_machine_type = var.expected_haproxy_external_machine_type

    haproxy_internal_node_count   = var.expected_haproxy_internal_node_count
    haproxy_internal_machine_type = var.expected_haproxy_internal_machine_type

    monitor_node_count   = var.expected_monitor_node_count
    monitor_machine_type = var.expected_monitor_machine_type

    opensearch_vm_node_count   = var.expected_opensearch_vm_node_count
    opensearch_vm_machine_type = var.expected_opensearch_vm_machine_type
    opensearch_vm_disk_type    = var.expected_opensearch_vm_disk_type
    opensearch_vm_disk_size    = var.expected_opensearch_vm_disk_size

    pgbouncer_node_count   = var.expected_pgbouncer_node_count
    pgbouncer_machine_type = var.expected_pgbouncer_machine_type

    postgres_node_count   = var.expected_postgres_node_count
    postgres_machine_type = var.expected_postgres_machine_type

    redis_cache_node_count   = var.expected_redis_cache_node_count
    redis_cache_machine_type = var.expected_redis_cache_machine_type

    redis_persistent_node_count   = var.expected_redis_persistent_node_count
    redis_persistent_machine_type = var.expected_redis_persistent_machine_type

    sidekiq_node_count   = var.expected_sidekiq_node_count
    sidekiq_machine_type = var.expected_sidekiq_machine_type
  }

  # Consul assertions
  assert {
    condition     = length(module.consul.machine_names) == var.expected_consul_node_count
    error_message = "Should create exactly ${var.expected_consul_node_count} Consul compute instance(s), but got ${length(module.consul.machine_names)}"
  }

  assert {
    condition     = module.consul.machine_types[0] == var.expected_consul_machine_type
    error_message = "Consul machine type should be ${var.expected_consul_machine_type}, but got ${module.consul.machine_types[0]}"
  }

  # Gitaly assertions
  assert {
    condition     = length(module.gitaly.machine_names) == var.expected_gitaly_node_count
    error_message = "Should create exactly ${var.expected_gitaly_node_count} Gitaly compute instance(s), but got ${length(module.gitaly.machine_names)}"
  }

  assert {
    condition     = module.gitaly.machine_types[0] == var.expected_gitaly_machine_type
    error_message = "Gitaly machine type should be ${var.expected_gitaly_machine_type}, but got ${module.gitaly.machine_types[0]}"
  }

  # Praefect assertions
  assert {
    condition     = length(module.praefect.machine_names) == var.expected_praefect_node_count
    error_message = "Should create exactly ${var.expected_praefect_node_count} Praefect compute instance(s), but got ${length(module.praefect.machine_names)}"
  }

  assert {
    condition     = module.praefect.machine_types[0] == var.expected_praefect_machine_type
    error_message = "Praefect machine type should be ${var.expected_praefect_machine_type}, but got ${module.praefect.machine_types[0]}"
  }

  # Praefect Postgres assertions
  assert {
    condition     = length(module.praefect_postgres.machine_names) == var.expected_praefect_postgres_node_count
    error_message = "Should create exactly ${var.expected_praefect_postgres_node_count} Praefect Postgres compute instance(s), but got ${length(module.praefect_postgres.machine_names)}"
  }

  assert {
    condition     = module.praefect_postgres.machine_types[0] == var.expected_praefect_postgres_machine_type
    error_message = "Praefect Postgres machine type should be ${var.expected_praefect_postgres_machine_type}, but got ${module.praefect_postgres.machine_types[0]}"
  }

  # GitLab Rails assertions
  assert {
    condition     = length(module.gitlab_rails.machine_names) == var.expected_gitlab_rails_node_count
    error_message = "Should create exactly ${var.expected_gitlab_rails_node_count} GitLab Rails compute instance(s), but got ${length(module.gitlab_rails.machine_names)}"
  }

  assert {
    condition     = module.gitlab_rails.machine_types[0] == var.expected_gitlab_rails_machine_type
    error_message = "GitLab Rails machine type should be ${var.expected_gitlab_rails_machine_type}, but got ${module.gitlab_rails.machine_types[0]}"
  }

  # HAProxy External assertions
  assert {
    condition     = length(module.haproxy_external.machine_names) == var.expected_haproxy_external_node_count
    error_message = "Should create exactly ${var.expected_haproxy_external_node_count} HAProxy External compute instance(s), but got ${length(module.haproxy_external.machine_names)}"
  }

  assert {
    condition     = module.haproxy_external.machine_types[0] == var.expected_haproxy_external_machine_type
    error_message = "HAProxy External machine type should be ${var.expected_haproxy_external_machine_type}, but got ${module.haproxy_external.machine_types[0]}"
  }

  # HAProxy Internal assertions
  assert {
    condition     = length(module.haproxy_internal.machine_names) == var.expected_haproxy_internal_node_count
    error_message = "Should create exactly ${var.expected_haproxy_internal_node_count} HAProxy Internal compute instance(s), but got ${length(module.haproxy_internal.machine_names)}"
  }

  assert {
    condition     = module.haproxy_internal.machine_types[0] == var.expected_haproxy_internal_machine_type
    error_message = "HAProxy Internal machine type should be ${var.expected_haproxy_internal_machine_type}, but got ${module.haproxy_internal.machine_types[0]}"
  }

  # Monitor assertions
  assert {
    condition     = length(module.monitor.machine_names) == var.expected_monitor_node_count
    error_message = "Should create exactly ${var.expected_monitor_node_count} Monitor compute instance(s), but got ${length(module.monitor.machine_names)}"
  }

  assert {
    condition     = module.monitor.machine_types[0] == var.expected_monitor_machine_type
    error_message = "Monitor machine type should be ${var.expected_monitor_machine_type}, but got ${module.monitor.machine_types[0]}"
  }

  # OpenSearch VM assertions
  assert {
    condition     = length(module.opensearch_vm.machine_names) == var.expected_opensearch_vm_node_count
    error_message = "Should create exactly ${var.expected_opensearch_vm_node_count} OpenSearch VM compute instance(s), but got ${length(module.opensearch_vm.machine_names)}"
  }

  assert {
    condition     = module.opensearch_vm.machine_types[0] == var.expected_opensearch_vm_machine_type
    error_message = "OpenSearch VM machine type should be ${var.expected_opensearch_vm_machine_type}, but got ${module.opensearch_vm.machine_types[0]}"
  }

  assert {
    condition     = module.opensearch_vm.machine_boot_disk_types[0] == var.expected_opensearch_vm_disk_type
    error_message = "OpenSearch VM disk type should be ${var.expected_opensearch_vm_disk_type}, but got ${module.opensearch_vm.machine_boot_disk_types[0]}"
  }

  assert {
    condition     = module.opensearch_vm.machine_boot_disk_sizes[0] == var.expected_opensearch_vm_disk_size
    error_message = "OpenSearch VM disk size should be ${var.expected_opensearch_vm_disk_size}, but got ${module.opensearch_vm.machine_boot_disk_sizes[0]}"
  }

  # PgBouncer assertions
  assert {
    condition     = length(module.pgbouncer.machine_names) == var.expected_pgbouncer_node_count
    error_message = "Should create exactly ${var.expected_pgbouncer_node_count} PgBouncer compute instance(s), but got ${length(module.pgbouncer.machine_names)}"
  }

  assert {
    condition     = module.pgbouncer.machine_types[0] == var.expected_pgbouncer_machine_type
    error_message = "PgBouncer machine type should be ${var.expected_pgbouncer_machine_type}, but got ${module.pgbouncer.machine_types[0]}"
  }

  # Postgres assertions
  assert {
    condition     = length(module.postgres.machine_names) == var.expected_postgres_node_count
    error_message = "Should create exactly ${var.expected_postgres_node_count} Postgres compute instance(s), but got ${length(module.postgres.machine_names)}"
  }

  assert {
    condition     = module.postgres.machine_types[0] == var.expected_postgres_machine_type
    error_message = "Postgres machine type should be ${var.expected_postgres_machine_type}, but got ${module.postgres.machine_types[0]}"
  }

  # Redis Cache assertions
  assert {
    condition     = length(module.redis_cache.machine_names) == var.expected_redis_cache_node_count
    error_message = "Should create exactly ${var.expected_redis_cache_node_count} Redis Cache compute instance(s), but got ${length(module.redis_cache.machine_names)}"
  }

  assert {
    condition     = module.redis_cache.machine_types[0] == var.expected_redis_cache_machine_type
    error_message = "Redis Cache machine type should be ${var.expected_redis_cache_machine_type}, but got ${module.redis_cache.machine_types[0]}"
  }

  # Redis Persistent assertions
  assert {
    condition     = length(module.redis_persistent.machine_names) == var.expected_redis_persistent_node_count
    error_message = "Should create exactly ${var.expected_redis_persistent_node_count} Redis Persistent compute instance(s), but got ${length(module.redis_persistent.machine_names)}"
  }

  assert {
    condition     = module.redis_persistent.machine_types[0] == var.expected_redis_persistent_machine_type
    error_message = "Redis Persistent machine type should be ${var.expected_redis_persistent_machine_type}, but got ${module.redis_persistent.machine_types[0]}"
  }

  # Sidekiq assertions
  assert {
    condition     = length(module.sidekiq.machine_names) == var.expected_sidekiq_node_count
    error_message = "Should create exactly ${var.expected_sidekiq_node_count} Sidekiq compute instance(s), but got ${length(module.sidekiq.machine_names)}"
  }

  assert {
    condition     = module.sidekiq.machine_types[0] == var.expected_sidekiq_machine_type
    error_message = "Sidekiq machine type should be ${var.expected_sidekiq_machine_type}, but got ${module.sidekiq.machine_types[0]}"
  }
}
