locals {
  gitlab_shell_ssh_port = var.haproxy_external_node_count > 0 && var.gitlab_shell_ssh_port == null ? 2222 : (var.external_ssh_port != 2222 ? var.external_ssh_port : var.gitlab_shell_ssh_port)
}

resource "azurerm_network_security_group" "gitlab" {
  name                = "${var.prefix}-gitlab-network-security-group"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags = {
    gitlab_node_prefix = var.prefix
  }
}

resource "azurerm_subnet_network_security_group_association" "gitlab" {
  subnet_id                 = azurerm_subnet.gitlab.id
  network_security_group_id = azurerm_network_security_group.gitlab.id
}

resource "azurerm_application_security_group" "haproxy" {
  count               = min(var.haproxy_external_node_count, 1)
  name                = "${var.prefix}-haproxy-application-security-group"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags = {
    gitlab_node_prefix = var.prefix
    gitlab_node_type   = "haproxy"
  }
}

resource "azurerm_application_security_group" "gitlab_rails" {
  count               = length(var.gitlab_rails_external_ip_names) > 0 ? 1 : 0
  name                = "${var.prefix}-gitlab-rails-application-security-group"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags = {
    gitlab_node_prefix = var.prefix
    gitlab_node_type   = "gitlab-rails"
  }
}

resource "azurerm_network_security_rule" "icmp_rule" {
  count                                      = min(var.haproxy_external_node_count, 1)
  name                                       = "icmp_rule"
  description                                = "Allow ICMP"
  priority                                   = 1003
  direction                                  = "Inbound"
  access                                     = "Allow"
  protocol                                   = "Icmp"
  source_port_range                          = "*"
  destination_port_range                     = "*"
  source_address_prefixes                    = coalescelist(var.icmp_allowed_ingress_cidr_blocks, var.default_allowed_ingress_cidr_blocks)
  destination_application_security_group_ids = [azurerm_application_security_group.haproxy[0].id]
  resource_group_name                        = var.resource_group_name
  network_security_group_name                = azurerm_network_security_group.gitlab.name
}

resource "azurerm_network_security_rule" "http_rule" {
  count                                      = (var.haproxy_external_node_count + length(var.gitlab_rails_external_ip_names)) > 0 ? 1 : 0
  name                                       = "http_rule"
  description                                = "Allow Web traffic"
  priority                                   = 1004
  direction                                  = "Inbound"
  access                                     = "Allow"
  protocol                                   = "Tcp"
  source_port_range                          = "*"
  destination_port_ranges                    = ["80", "443"]
  source_address_prefixes                    = coalescelist(var.http_allowed_ingress_cidr_blocks, var.default_allowed_ingress_cidr_blocks)
  destination_application_security_group_ids = [length(var.gitlab_rails_external_ip_names) > 0 ? azurerm_application_security_group.gitlab_rails[0].id : azurerm_application_security_group.haproxy[0].id]
  resource_group_name                        = var.resource_group_name
  network_security_group_name                = azurerm_network_security_group.gitlab.name
}

resource "azurerm_network_security_rule" "git_ssh_rule" {
  count                                      = local.gitlab_shell_ssh_port != null ? 1 : 0
  name                                       = "git_ssh_rule"
  description                                = "Allow Git SSH traffic"
  priority                                   = 1005
  direction                                  = "Inbound"
  access                                     = "Allow"
  protocol                                   = "Tcp"
  source_port_range                          = "*"
  destination_port_ranges                    = [local.gitlab_shell_ssh_port]
  source_address_prefixes                    = coalescelist(var.ssh_allowed_ingress_cidr_blocks, var.default_allowed_ingress_cidr_blocks)
  destination_application_security_group_ids = [length(var.gitlab_rails_external_ip_names) > 0 ? azurerm_application_security_group.gitlab_rails[0].id : azurerm_application_security_group.haproxy[0].id]
  resource_group_name                        = var.resource_group_name
  network_security_group_name                = azurerm_network_security_group.gitlab.name
}

resource "azurerm_network_security_rule" "external_ssh_rule" {
  count                                      = var.setup_external_ips && var.haproxy_external_node_count > 0 ? 1 : 0
  name                                       = "external_ssh_rule"
  description                                = "Allow SSH traffic"
  priority                                   = 1006
  direction                                  = "Inbound"
  access                                     = "Allow"
  protocol                                   = "Tcp"
  source_port_range                          = "*"
  destination_port_ranges                    = ["22"]
  source_address_prefixes                    = coalescelist(var.external_ssh_allowed_ingress_cidr_blocks, var.default_allowed_ingress_cidr_blocks)
  destination_application_security_group_ids = [azurerm_application_security_group.haproxy[0].id]
  resource_group_name                        = var.resource_group_name
  network_security_group_name                = azurerm_network_security_group.gitlab.name
}


resource "azurerm_application_security_group" "ssh" {
  name                = "${var.prefix}-ssh-default-application-security-group"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = {
    gitlab_node_prefix = var.prefix
    gitlab_node_type   = "not-haproxy"
  }
}

resource "azurerm_network_security_rule" "ssh_rule" {
  count                                      = var.setup_external_ips ? 1 : 0
  name                                       = "default_ssh"
  description                                = "Allow SSH traffic"
  priority                                   = 1001
  direction                                  = "Inbound"
  access                                     = "Allow"
  protocol                                   = "Tcp"
  source_port_range                          = "*"
  destination_port_ranges                    = ["22"]
  source_address_prefixes                    = coalescelist(var.ssh_allowed_ingress_cidr_blocks, var.default_allowed_ingress_cidr_blocks)
  destination_application_security_group_ids = compact([azurerm_application_security_group.ssh.id, length(var.gitlab_rails_external_ip_names) > 0 ? azurerm_application_security_group.gitlab_rails[0].id : null])
  resource_group_name                        = var.resource_group_name
  network_security_group_name                = azurerm_network_security_group.gitlab.name
}
