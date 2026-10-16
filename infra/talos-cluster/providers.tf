# API token comes from PROXMOX_VE_API_TOKEN (injected by ./tf).
# TLS is verified: pve01 has a Let's Encrypt certificate (Proxmox ACME, guide/03-proxmox.md).
provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = false
}

provider "talos" {}

# Only used for `helm_template` (renders charts locally; never talks to a cluster).
provider "helm" {}
