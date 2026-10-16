# Debian 13 LXC template, downloaded once to the "local" datastore and verified against the
# SHA-512 from Proxmox's GPG-signed template index (aplinfo) — it is the root filesystem of the
# resolver the nodes trust. Integrity comes from the checksum: download.proxmox.com is HTTP-only
# (its HTTPS certificate covers only enterprise.proxmox.com and the CDN hosts), as pveam uses it.
resource "proxmox_download_file" "debian13" {
  content_type       = "vztmpl"
  datastore_id       = "local"
  node_name          = var.proxmox_node
  url                = "http://download.proxmox.com/images/system/debian-13-standard_13.6-1_amd64.tar.zst"
  checksum           = "4c0c27ca6ceab5ef0b84db57825a00f26157ef1854bafe97297813e1cbe8ecb8cc9c453cab6b3b0efe1ba193a50c47ece1e41d950e411b8730b835b71e9e754b"
  checksum_algorithm = "sha512"
}

# dns01: Technitium DNS Server, installed and configured by hand (guide/03-dns-server.md).
# Unprivileged, no nesting; outside the cluster so DNS survives cluster rebuilds.
resource "proxmox_virtual_environment_container" "dns01" {
  node_name     = var.proxmox_node
  vm_id         = var.dns01.vm_id
  description   = "Technitium DNS (k8s-homelab, infra/dns)"
  unprivileged  = true
  start_on_boot = true
  started       = true

  operating_system {
    template_file_id = proxmox_download_file.debian13.id
    type             = "debian"
  }

  cpu {
    cores = var.dns01.cores
  }

  memory {
    dedicated = var.dns01.memory_mb
  }

  disk {
    datastore_id = "local-lvm"
    size         = var.dns01.disk_gb
  }

  network_interface {
    name = "eth0"
  }

  initialization {
    hostname = "dns01"
    ip_config {
      ipv4 {
        address = "${var.dns01.ip}/24"
        gateway = var.dns01.gateway
      }
    }
    # Its own upstream until Technitium resolves recursively.
    dns {
      servers = [var.dns01.gateway]
    }
    user_account {
      keys = [var.ssh_public_key]
    }
  }

  # The template only seeds the root filesystem at creation; re-fetching or bumping it must
  # never recreate the running resolver (rebuild deliberately with -replace instead).
  lifecycle {
    ignore_changes = [operating_system[0].template_file_id]
  }
}
