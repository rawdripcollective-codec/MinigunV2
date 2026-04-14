locals {
  total_node_pool_count = var.webservice_node_pool_count + var.sidekiq_node_pool_count + var.supporting_node_pool_count + var.webservice_node_pool_max_count + var.sidekiq_node_pool_max_count + var.supporting_node_pool_max_count + var.gitaly_node_pool_count

  node_pool_locations = var.gke_zones != null ? var.gke_zones : (var.kubernetes_zones != null ? var.kubernetes_zones : var.zones)
}

resource "google_container_cluster" "gitlab_cluster" {
  count = min(local.total_node_pool_count, 1)

  name     = var.prefix
  location = var.gke_location

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1
  enable_shielded_nodes    = true
  node_config {
    # Temporary service account for initial node pool
    service_account = var.gke_enable_workload_identity ? module.gitlab_gke_node_service_account[0].email : module.gitlab_gke_supporting_service_account[0].email

    shielded_instance_config {
      enable_secure_boot = var.machine_secure_boot
    }
  }

  deletion_protection = var.gke_deletion_protection

  network    = local.create_network ? google_compute_network.gitlab_vpc[0].self_link : data.google_compute_network.gitlab_network[0].self_link
  subnetwork = local.create_network ? google_compute_subnetwork.gitlab_vpc_subnet[0].self_link : data.google_compute_subnetwork.gitlab_subnet[0].self_link

  # Require VPC Native cluster
  # https://registry.terraform.io/providers/hashicorp/google/latest/docs/guides/using_gke_with_terraform#vpc-native-clusters
  # Blank block enables this and picks at random
  ip_allocation_policy {}

  datapath_provider = var.gke_datapath_provider

  release_channel {
    channel = var.cluster_release_channel != null ? var.cluster_release_channel : var.gke_release_channel
  }

  dynamic "private_cluster_config" {
    for_each = range(var.gke_enable_private_nodes ? 1 : 0)

    content {
      enable_private_nodes    = var.gke_enable_private_nodes
      enable_private_endpoint = var.gke_enable_private_endpoint # When false *both* Public and Private endpoints are enabled, this would be better named as enable_private_endpoint_only
      master_ipv4_cidr_block  = var.gke_master_ipv4_cidr_block
    }
  }

  # Limit GKE endpoint access via CIDR blocks for both Private and Public endpoints
  # This block being present alone with no settings will enable, which is required for Cluster's with private only endpoints (a CIDR block though is optional)
  dynamic "master_authorized_networks_config" {
    for_each = range(var.gke_enable_private_endpoint || length(var.gke_master_authorized_networks_config_cidr_blocks) > 0 ? 1 : 0)

    content {
      dynamic "cidr_blocks" {
        for_each = var.gke_master_authorized_networks_config_cidr_blocks

        content {
          cidr_block = cidr_blocks.value
        }
      }
    }
  }

  dynamic "workload_identity_config" {
    for_each = range(var.gke_enable_workload_identity || var.cluster_enable_workload_identity ? 1 : 0)

    content {
      workload_pool = "${var.project}.svc.id.goog"
    }
  }

  # Additional secrets envelope additional encryption - https://cloud.google.com/kubernetes-engine/docs/how-to/encrypting-secrets
  dynamic "database_encryption" {
    for_each = range(var.gke_database_encryption_key_name != null ? 1 : 0)

    content {
      state    = "ENCRYPTED"
      key_name = var.gke_database_encryption_key_name
    }
  }

  dynamic "binary_authorization" {
    for_each = range(var.gke_binary_authorization_evaluation_mode != null ? 1 : 0)

    content {
      evaluation_mode = var.gke_binary_authorization_evaluation_mode
    }
  }

  # TODO: var.additional_labels is deprecated and will be removed in 4.x
  resource_labels = merge({
    gitlab_node_prefix = var.prefix
    gitlab_node_type   = "gitlab-cluster"
  }, var.additional_labels, var.custom_labels, var.gke_custom_labels)

  lifecycle {
    ignore_changes = [
      # Ensure avoidance of unexpected rebuilds as location controls Regional / Zonal clusters
      location,
      # Ensure node config is not processed again after initial node pool is deleted on first create
      node_config
    ]
  }
}

# Webservice
resource "google_container_node_pool" "gitlab_webservice_pool" {
  count = min(var.webservice_node_pool_count + var.webservice_node_pool_max_count, 1)

  # Max 14 chars, unique_id adds 26 chars, total max 40.
  name_prefix = "gl-webservice-"
  cluster     = google_container_cluster.gitlab_cluster[0].name
  location    = var.gke_location # Cluster location

  node_locations = local.node_pool_locations

  # Node Count(s)
  # Total counts via Autoscaling ensure correct numbers cross zones - https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-autoscaler#minimum_and_maximum_node_pool_size
  initial_node_count = var.webservice_node_pool_min_count > 0 ? var.webservice_node_pool_min_count : var.webservice_node_pool_count
  autoscaling {
    total_max_node_count = var.webservice_node_pool_max_count > 0 ? var.webservice_node_pool_max_count : var.webservice_node_pool_count
    total_min_node_count = var.webservice_node_pool_min_count > 0 ? var.webservice_node_pool_min_count : var.webservice_node_pool_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 2
    max_unavailable = 0
  }

  node_config {
    machine_type = var.webservice_node_pool_machine_type

    disk_type         = coalesce(var.webservice_node_pool_disk_type, var.default_disk_type)
    disk_size_gb      = coalesce(var.webservice_node_pool_disk_size, var.default_disk_size)
    boot_disk_kms_key = var.webservice_node_pool_disk_kms_key != null ? var.webservice_node_pool_disk_kms_key : var.gke_default_disk_kms_key

    service_account = var.gke_enable_workload_identity ? module.gitlab_gke_node_service_account[0].email : module.gitlab_gke_webservice_service_account[0].email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"] # https://cloud.google.com/compute/docs/access/create-enable-service-accounts-for-instances#best_practices

    shielded_instance_config {
      enable_secure_boot = var.machine_secure_boot
    }

    dynamic "workload_metadata_config" {
      for_each = range(var.gke_enable_workload_identity || var.cluster_enable_workload_identity ? 1 : 0)

      content {
        mode = "GKE_METADATA"
      }
    }

    # Added by GCP, if not added here TF will recreate each time
    # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/container_cluster#metadata
    metadata = {
      disable-legacy-endpoints = true
    }

    labels = {
      workload = "webservice"
    }

    # TODO: var.additional_labels is deprecated and will be removed in 4.x
    resource_labels = merge({
      gitlab_node_prefix = var.prefix
      gitlab_node_type   = "gitlab-webservice-node-pool"
    }, var.additional_labels, var.custom_labels, var.webservice_node_pool_custom_labels)

    tags = var.setup_iap_ssh_access ? ["${var.prefix}-iap"] : []
  }

  lifecycle {
    ignore_changes = [
      # Only set at creation, autoscaling takes over after
      initial_node_count,
      # Can only be set for new node pools so ignore any subsequent changes
      node_config[0].boot_disk_kms_key
    ]

    replace_triggered_by = [google_container_cluster.gitlab_cluster[0].id]
  }
}

# Sidekiq
resource "google_container_node_pool" "gitlab_sidekiq_pool" {
  count = min(var.sidekiq_node_pool_count + var.sidekiq_node_pool_max_count, 1)

  # Max 14 chars, unique_id adds 26 chars, total max 40.
  name_prefix = "gl-sidekiq-"
  cluster     = google_container_cluster.gitlab_cluster[0].name
  location    = var.gke_location # Cluster location

  node_locations = local.node_pool_locations

  # Node Count(s)
  # Total counts via Autoscaling ensure correct numbers cross zones - https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-autoscaler#minimum_and_maximum_node_pool_size
  initial_node_count = var.sidekiq_node_pool_min_count > 0 ? var.sidekiq_node_pool_min_count : var.sidekiq_node_pool_count
  autoscaling {
    total_max_node_count = var.sidekiq_node_pool_max_count > 0 ? var.sidekiq_node_pool_max_count : var.sidekiq_node_pool_count
    total_min_node_count = var.sidekiq_node_pool_min_count > 0 ? var.sidekiq_node_pool_min_count : var.sidekiq_node_pool_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 2
    max_unavailable = 0
  }

  node_config {
    machine_type = var.sidekiq_node_pool_machine_type

    disk_type         = coalesce(var.sidekiq_node_pool_disk_type, var.default_disk_type)
    disk_size_gb      = coalesce(var.sidekiq_node_pool_disk_size, var.default_disk_size)
    boot_disk_kms_key = var.sidekiq_node_pool_disk_kms_key != null ? var.sidekiq_node_pool_disk_kms_key : var.gke_default_disk_kms_key

    service_account = var.gke_enable_workload_identity ? module.gitlab_gke_node_service_account[0].email : module.gitlab_gke_sidekiq_service_account[0].email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"] # https://cloud.google.com/compute/docs/access/create-enable-service-accounts-for-instances#best_practices

    shielded_instance_config {
      enable_secure_boot = var.machine_secure_boot
    }

    dynamic "workload_metadata_config" {
      for_each = range(var.gke_enable_workload_identity || var.cluster_enable_workload_identity ? 1 : 0)

      content {
        mode = "GKE_METADATA"
      }
    }

    # Added by GCP, if not added here TF will recreate each time
    # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/container_cluster#metadata
    metadata = {
      disable-legacy-endpoints = true
    }

    labels = {
      workload = "sidekiq"
    }

    # TODO: var.additional_labels is deprecated and will be removed in 4.x
    resource_labels = merge({
      gitlab_node_prefix = var.prefix
      gitlab_node_type   = "gitlab-sidekiq-node-pool"
    }, var.additional_labels, var.custom_labels, var.sidekiq_node_pool_custom_labels)

    tags = var.setup_iap_ssh_access ? ["${var.prefix}-iap"] : []
  }

  lifecycle {
    ignore_changes = [
      # Only set at creation, autoscaling takes over after
      initial_node_count,
      # Can only be set for new node pools so ignore any subsequent changes
      node_config[0].boot_disk_kms_key
    ]

    replace_triggered_by = [google_container_cluster.gitlab_cluster[0].id]
  }
}

# Supporting
resource "google_container_node_pool" "gitlab_supporting_pool" {
  count = min(var.supporting_node_pool_count + var.supporting_node_pool_max_count, 1)

  # Max 14 chars, unique_id adds 26 chars, total max 40.
  name_prefix = "gl-supporting-"
  cluster     = google_container_cluster.gitlab_cluster[0].name
  location    = var.gke_location # Cluster location

  node_locations = local.node_pool_locations

  # Node Count(s)
  # Total counts via Autoscaling ensure correct numbers cross zones - https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-autoscaler#minimum_and_maximum_node_pool_size
  initial_node_count = var.supporting_node_pool_min_count > 0 ? var.supporting_node_pool_min_count : var.supporting_node_pool_count
  autoscaling {
    total_max_node_count = var.supporting_node_pool_max_count > 0 ? var.supporting_node_pool_max_count : var.supporting_node_pool_count
    total_min_node_count = var.supporting_node_pool_min_count > 0 ? var.supporting_node_pool_min_count : var.supporting_node_pool_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 2
    max_unavailable = 0
  }

  node_config {
    machine_type = var.supporting_node_pool_machine_type

    disk_type         = coalesce(var.supporting_node_pool_disk_type, var.default_disk_type)
    disk_size_gb      = coalesce(var.supporting_node_pool_disk_size, var.default_disk_size)
    boot_disk_kms_key = var.supporting_node_pool_disk_kms_key != null ? var.supporting_node_pool_disk_kms_key : var.gke_default_disk_kms_key

    service_account = var.gke_enable_workload_identity ? module.gitlab_gke_node_service_account[0].email : module.gitlab_gke_supporting_service_account[0].email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"] # https://cloud.google.com/compute/docs/access/create-enable-service-accounts-for-instances#best_practices

    shielded_instance_config {
      enable_secure_boot = var.machine_secure_boot
    }

    dynamic "workload_metadata_config" {
      for_each = range(var.gke_enable_workload_identity || var.cluster_enable_workload_identity ? 1 : 0)

      content {
        mode = "GKE_METADATA"
      }
    }

    # Added by GCP, if not added here TF will recreate each time
    # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/container_cluster#metadata
    metadata = {
      disable-legacy-endpoints = true
    }

    labels = {
      workload = "support"
    }

    # TODO: var.additional_labels is deprecated and will be removed in 4.x
    resource_labels = merge({
      gitlab_node_prefix = var.prefix
      gitlab_node_type   = "gitlab-supporting-node-pool"
    }, var.additional_labels, var.custom_labels, var.supporting_node_pool_custom_labels)

    tags = var.setup_iap_ssh_access ? ["${var.prefix}-iap"] : []
  }

  lifecycle {
    ignore_changes = [
      # Only set at creation, autoscaling takes over after
      initial_node_count,
      # Can only be set for new node pools so ignore any subsequent changes
      node_config[0].boot_disk_kms_key
    ]

    replace_triggered_by = [google_container_cluster.gitlab_cluster[0].id]
  }
}

## [Toolkit Beta] Gitaly on Kubernetes. Known limitations, see https://docs.gitlab.com/administration/gitaly/kubernetes/
resource "google_container_node_pool" "gitlab_gitaly_pool" {
  count = min(var.gitaly_node_pool_count + var.gitaly_node_pool_max_count, 1)

  # Max 14 chars, unique_id adds 26 chars, total max 40.
  name_prefix = "gl-gitaly-"
  cluster     = google_container_cluster.gitlab_cluster[0].name
  location    = var.gke_location # Cluster location

  node_locations = local.node_pool_locations

  # Node Count
  # Autoscaling is not supported for Gitaly but ability to set is allowed for testing purposes and the feature always used to ensure correct node count across zones - https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-autoscaler#minimum_and_maximum_node_pool_size
  initial_node_count = var.gitaly_node_pool_min_count > 0 ? var.gitaly_node_pool_min_count : var.gitaly_node_pool_count
  autoscaling {
    total_max_node_count = var.gitaly_node_pool_max_count > 0 ? var.gitaly_node_pool_max_count : var.gitaly_node_pool_count
    total_min_node_count = var.gitaly_node_pool_min_count > 0 ? var.gitaly_node_pool_min_count : var.gitaly_node_pool_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 2
    max_unavailable = 0
  }

  node_config {
    machine_type = var.gitaly_node_pool_machine_type

    disk_type         = coalesce(var.gitaly_node_pool_disk_type, var.default_disk_type)
    disk_size_gb      = coalesce(var.gitaly_node_pool_disk_size, var.default_disk_size)
    boot_disk_kms_key = var.gitaly_node_pool_disk_kms_key != null ? var.gitaly_node_pool_disk_kms_key : var.gke_default_disk_kms_key

    service_account = var.gke_enable_workload_identity ? module.gitlab_gke_node_service_account[0].email : module.gitlab_gke_gitaly_service_account[0].email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"] # https://cloud.google.com/compute/docs/access/create-enable-service-accounts-for-instances#best_practices

    shielded_instance_config {
      enable_secure_boot = var.machine_secure_boot
    }

    dynamic "workload_metadata_config" {
      for_each = range(var.gke_enable_workload_identity || var.cluster_enable_workload_identity ? 1 : 0)

      content {
        mode = "GKE_METADATA"
      }
    }

    # Added by GCP, if not added here TF will recreate each time
    # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/container_cluster#metadata
    metadata = {
      disable-legacy-endpoints = true
    }

    labels = {
      workload = "gitaly"
    }

    # TODO: var.additional_labels is deprecated and will be removed in 4.x
    resource_labels = merge({
      gitlab_node_prefix = var.prefix
      gitlab_node_type   = "gitlab-gitaly-node-pool"
    }, var.additional_labels, var.custom_labels, var.gitaly_node_pool_custom_labels)

    tags = var.setup_iap_ssh_access ? ["${var.prefix}-iap"] : []
  }

  lifecycle {
    ignore_changes = [
      # Only set at creation, autoscaling takes over after
      initial_node_count,
      # Can only be set for new node pools so ignore any subsequent changes
      node_config[0].boot_disk_kms_key
    ]
  }
}

output "kubernetes" {
  value = {
    "kubernetes_cluster_name"    = try(google_container_cluster.gitlab_cluster[0].name, "")
    "kubernetes_cluster_version" = try(google_container_cluster.gitlab_cluster[0].master_version, "")
    "kubernetes_cluster_id"      = try(google_container_cluster.gitlab_cluster[0].id, "")

    # Service Accounts
    # Service Accounts - Node
    "kubernetes_webservice_node_group_service_account_email" = try(module.gitlab_gke_node_service_account[0].email, module.gitlab_gke_webservice_service_account[0].email, "")
    "kubernetes_sidekiq_node_group_service_account_email"    = try(module.gitlab_gke_node_service_account[0].email, module.gitlab_gke_sidekiq_service_account[0].email, "")
    "kubernetes_supporting_node_group_service_account_email" = try(module.gitlab_gke_node_service_account[0].email, module.gitlab_gke_supporting_service_account[0].email, "")
    "kubernetes_gitaly_node_group_service_account_email"     = try(module.gitlab_gke_node_service_account[0].email, module.gitlab_gke_gitaly_service_account[0].email, "")

    # Service Accounts - Workload Identity
    "kubernetes_node_group_service_account_email" = try(module.gitlab_gke_node_service_account[0].email, "")
    "kubernetes_webservice_service_account_email" = try(var.gke_enable_workload_identity ? module.gitlab_gke_webservice_service_account[0].email : "", "")
    "kubernetes_sidekiq_service_account_email"    = try(var.gke_enable_workload_identity ? module.gitlab_gke_sidekiq_service_account[0].email : "", "")
    "kubernetes_toolbox_service_account_email"    = try(module.gitlab_gke_toolbox_service_account[0].email, "")
    "kubernetes_registry_service_account_email"   = try(module.gitlab_gke_registry_service_account[0].email, "")

    # Node Group / Addon Versions
    "kubernetes_webservice_node_group_version" = try(google_container_node_pool.gitlab_webservice_pool[0].version, "")
    "kubernetes_sidekiq_node_group_version"    = try(google_container_node_pool.gitlab_sidekiq_pool[0].version, "")
    "kubernetes_supporting_node_group_version" = try(google_container_node_pool.gitlab_supporting_pool[0].version, "")
    "kubernetes_gitaly_node_group_version"     = try(google_container_node_pool.gitlab_gitaly_pool[0].version, "")
  }
}
