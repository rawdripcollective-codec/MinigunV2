locals {
  gitlab_vm_node_count = (
    var.consul_node_count + var.gitaly_node_count + var.gitlab_nfs_node_count + var.gitlab_rails_node_count +
    var.haproxy_external_node_count + var.haproxy_internal_node_count + var.monitor_node_count + var.opensearch_vm_node_count +
    var.pgbouncer_node_count + var.postgres_node_count + var.praefect_postgres_node_count + var.praefect_node_count +
    var.redis_node_count + var.redis_cache_node_count + var.redis_persistent_node_count + var.sidekiq_node_count
  )

  gitlab_shell_ssh_port = var.haproxy_external_node_count > 0 && var.gitlab_shell_ssh_port == null ? 2222 : (var.external_ssh_port != 2222 ? var.external_ssh_port : var.gitlab_shell_ssh_port)

  gitlab_vm_ssh_access_firewall_rule_create     = local.gitlab_vm_node_count > 0 && (var.setup_external_ips || length(var.external_ssh_allowed_ingress_cidr_blocks) > 0)
  gitlab_git_ssh_access_firewall_rule_create    = local.gitlab_vm_node_count > 0 && local.gitlab_shell_ssh_port != null && (var.setup_external_ips || length(var.ssh_allowed_ingress_cidr_blocks) > 0)
  gitlab_http_https_access_firewall_rule_create = var.haproxy_external_node_count + var.monitor_node_count + length(var.gitlab_rails_external_ips) > 0 && (var.setup_external_ips || length(var.http_allowed_ingress_cidr_blocks) > 0)
  gitlab_icmp_access_firewall_rule_create       = local.gitlab_vm_node_count > 0 && (var.setup_external_ips || length(var.external_ssh_allowed_ingress_cidr_blocks) > 0)
}

# External Firewall rules
## Create if nodes present and public IPs OR private IPs and specific CIDR range given
resource "google_compute_firewall" "gitlab_vm_ssh_access" {
  count   = local.gitlab_vm_ssh_access_firewall_rule_create ? 1 : 0
  name    = "${var.prefix}-vm-ssh-access"
  network = local.create_network ? google_compute_network.gitlab_vpc[0].self_link : data.google_compute_network.gitlab_network[0].self_link

  description = "Enable SSH access to VMs for GitLab environment '${var.prefix}' on the ${local.vpc_name} network"

  # kics: Terraform GCP - SSH Access Is Not Restricted - False positive, source CIDR is configurable
  # kics-scan ignore-block
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = coalescelist(var.external_ssh_allowed_ingress_cidr_blocks, var.default_allowed_ingress_cidr_blocks)
  target_tags   = [var.prefix]
}

resource "google_compute_firewall" "gitlab_git_ssh_access" {
  count   = local.gitlab_git_ssh_access_firewall_rule_create ? 1 : 0
  name    = "${var.prefix}-git-ssh-access"
  network = local.create_network ? google_compute_network.gitlab_vpc[0].self_link : data.google_compute_network.gitlab_network[0].self_link

  description = "Enable Git SSH access for GitLab environment '${var.prefix}' on the ${local.vpc_name} network"

  allow {
    protocol = "tcp"
    ports    = [local.gitlab_shell_ssh_port]
  }

  source_ranges = coalescelist(var.ssh_allowed_ingress_cidr_blocks, var.default_allowed_ingress_cidr_blocks)
  target_tags   = ["${var.prefix}-ssh"]
}

resource "google_compute_firewall" "gitlab_http_https_access" {
  count   = local.gitlab_http_https_access_firewall_rule_create ? 1 : 0
  name    = "${var.prefix}-http-https-access"
  network = local.create_network ? google_compute_network.gitlab_vpc[0].self_link : data.google_compute_network.gitlab_network[0].self_link

  description = "Enable HTTP / HTTPS access for GitLab environment '${var.prefix}' on the ${local.vpc_name} network"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = coalescelist(var.http_allowed_ingress_cidr_blocks, var.default_allowed_ingress_cidr_blocks)
  target_tags   = ["${var.prefix}-web"]
}

resource "google_compute_firewall" "gitlab_icmp_access" {
  count   = local.gitlab_icmp_access_firewall_rule_create ? 1 : 0
  name    = "${var.prefix}-icmp-access"
  network = local.create_network ? google_compute_network.gitlab_vpc[0].self_link : data.google_compute_network.gitlab_network[0].self_link

  description = "Enable ICMP access for GitLab environment '${var.prefix}' on the ${local.vpc_name} network"

  allow {
    protocol = "icmp"
  }

  source_ranges = coalescelist(var.icmp_allowed_ingress_cidr_blocks, var.default_allowed_ingress_cidr_blocks)
  target_tags   = [var.prefix]
}

# Internal Firewall rules
resource "google_compute_firewall" "internal" {
  count   = local.create_network || local.existing_network ? 1 : 0
  name    = "${var.prefix}-internal"
  network = local.create_network ? google_compute_network.gitlab_vpc[0].self_link : data.google_compute_network.gitlab_network[0].self_link

  description = "Allow internal traffic on the ${local.vpc_name} network"

  # kics: Terraform GCP - RDP Access Is Not Restricted - False positive, source CIDR is locked down
  # kics-scan ignore-block
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  priority      = 65534
  source_ranges = local.create_network ? [google_compute_subnetwork.gitlab_vpc_subnet[0].ip_cidr_range] : [data.google_compute_subnetwork.gitlab_subnet[0].ip_cidr_range]
  target_tags   = [var.prefix]
}

resource "google_compute_firewall" "gitlab_kubernetes_vms_internal" {
  count   = min(local.total_node_pool_count, local.gitlab_vm_node_count, 1)
  name    = "${var.prefix}-kubernetes-vms-internal"
  network = local.create_network ? google_compute_network.gitlab_vpc[0].self_link : data.google_compute_network.gitlab_network[0].self_link

  description = "Allow internal access between GitLab Kubernetes containers and VMs"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
  }

  source_ranges = [google_container_cluster.gitlab_cluster[0].cluster_ipv4_cidr]
  target_tags   = [var.prefix]
}

# VPC Peering network rules
resource "google_compute_firewall" "internal_peer" {
  count   = local.create_network && var.create_network_peer_subnet_cidr_block != null ? 1 : 0
  name    = "${var.prefix}-internal-peer"
  network = local.create_network ? google_compute_network.gitlab_vpc[0].self_link : data.google_compute_network.gitlab_network[0].self_link

  description = "Allow internal traffic on the ${local.vpc_name} network from peer network with cidr block ${var.create_network_peer_subnet_cidr_block}"

  # kics: Terraform GCP - RDP Access Is Not Restricted - False positive, source CIDR is locked down
  # kics-scan ignore-block
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  priority      = 65534
  source_ranges = [var.create_network_peer_subnet_cidr_block]
  target_tags   = [var.prefix]
}

# IAP access firewall rule
resource "google_compute_firewall" "gitlab_iap_ssh_access" {
  count   = var.setup_iap_ssh_access ? 1 : 0
  name    = "${var.prefix}-iap-ssh-access"
  network = local.create_network ? google_compute_network.gitlab_vpc[0].self_link : data.google_compute_network.gitlab_network[0].self_link

  description = "Allow IAP tunnel SSH access ${local.vpc_name} network"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"] # IAP's IP range
  target_tags   = ["${var.prefix}-iap"]
}

# Moved
moved {
  from = google_compute_firewall.ssh[0]
  to   = google_compute_firewall.gitlab_vm_ssh_access[0]
}
moved {
  from = google_compute_firewall.gitlab_ssh[0]
  to   = google_compute_firewall.gitlab_git_ssh_access[0]
}
moved {
  from = google_compute_firewall.gitlab_http_https[0]
  to   = google_compute_firewall.gitlab_http_https_access[0]
}
moved {
  from = google_compute_firewall.icmp[0]
  to   = google_compute_firewall.gitlab_icmp_access[0]
}
