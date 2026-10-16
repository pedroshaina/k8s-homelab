# API token comes from PROXMOX_VE_API_TOKEN (injected by infra/tf).
# TLS is verified: pve01 has a Let's Encrypt certificate (Proxmox ACME, guide/02-proxmox.md).
provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = false
}
