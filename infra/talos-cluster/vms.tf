resource "proxmox_virtual_environment_vm" "cp" {
  for_each = var.nodes

  name        = each.key
  vm_id       = each.value.vm_id
  node_name   = var.proxmox_node
  description = "Talos control plane — managed by OpenTofu (infra/talos-cluster)"
  tags        = ["talos", "controlplane", "tofu"]

  on_boot         = true
  stop_on_destroy = true
  scsi_hardware   = "virtio-scsi-single"

  operating_system {
    type = "l26"
  }

  cpu {
    cores = var.node_cpu
    type  = "host"
  }

  memory {
    dedicated = var.node_memory_mb
    floating  = 0 # no ballooning: Kubernetes expects fixed memory
  }

  agent {
    enabled = true
    # IPs are static (cloud-init), so never block apply/refresh waiting for the agent
    # to report one — it may not run until Talos is configured, or the node may be down.
    wait_for_ip {
      disabled = true
    }
  }

  disk {
    interface    = "scsi0"
    datastore_id = "local-lvm"
    import_from  = proxmox_virtual_environment_download_file.talos.id
    size         = var.node_disk_gb
    file_format  = "raw"
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  # Cloud-init drive: Talos (nocloud platform) reads its static IP from here.
  initialization {
    datastore_id = "local-lvm"
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = var.gateway
      }
    }
    dns {
      servers = var.dns_servers
    }
  }

  lifecycle {
    # Talos installs updates itself; the source image must not force VM replacement.
    ignore_changes = [disk[0].import_from]
    # One node: a destroy or replace wipes the only etcd member. Removing a node on
    # purpose (e.g. 3 → 1) means lifting this in that change, deliberately.
    prevent_destroy = true
  }
}
