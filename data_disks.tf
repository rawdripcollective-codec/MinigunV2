# Data Disks
locals {
  node_data_disks = flatten([
    for i in range(var.node_count) :
    [
      for data_disk in var.data_disks : {
        name                 = data_disk.name
        size                 = coalesce(data_disk.size, var.disk_size)
        storage_account_type = coalesce(data_disk.storage_account_type, var.storage_account_type)
        instance_name        = "${var.prefix}-${var.node_type}-${i + 1}"
        vm_id                = azurerm_linux_virtual_machine.gitlab[i].id
        lun                  = data_disk.lun
        create_option        = "Empty"
        caching              = coalesce(data_disk.caching, "ReadWrite")
        tier                 = try(data_disk.tier, null)
      }
      if data_disk.name != null
    ]
  ])
}

resource "azurerm_managed_disk" "gitlab" {
  for_each = { for d in local.node_data_disks : "${d.instance_name}-${d.name}" => d }

  name                 = each.key
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = each.value.storage_account_type
  create_option        = each.value.create_option
  disk_size_gb         = each.value.size
  tier                 = each.value.tier

  tags = var.custom_tags

  lifecycle {
    ignore_changes = [
      create_option
    ]
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "gitlab" {
  for_each = { for d in local.node_data_disks : "${d.instance_name}-${d.name}" => d }

  managed_disk_id    = azurerm_managed_disk.gitlab[each.key].id
  virtual_machine_id = each.value.vm_id
  lun                = each.value.lun
  caching            = each.value.caching
}
