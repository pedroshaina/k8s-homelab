# Custom Talos image from Image Factory: stock Talos + the QEMU guest agent extension,
# so Proxmox can see VM IPs and shut VMs down cleanly.
resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = ["siderolabs/qemu-guest-agent"]
      }
    }
  })
}

data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "nocloud"
}

locals {
  # Installer image used for upgrades; keeps the extension after upgrades.
  installer_image = data.talos_image_factory_urls.this.urls.installer
  # nocloud = Talos reads network settings from the Proxmox cloud-init drive.
  disk_image_url = "https://factory.talos.dev/image/${talos_image_factory_schematic.this.id}/${var.talos_version}/nocloud-amd64.qcow2"
}

resource "proxmox_virtual_environment_download_file" "talos" {
  node_name    = var.proxmox_node
  datastore_id = "local"
  content_type = "import"
  url          = local.disk_image_url
  # qcow2, not raw.zst: Proxmox can't decompress downloads into "import" storage.
  file_name = "talos-${var.talos_version}-${substr(talos_image_factory_schematic.this.id, 0, 8)}-nocloud-amd64.qcow2"
  # The file name pins version + schematic, so never re-download an existing image.
  overwrite = false
}
