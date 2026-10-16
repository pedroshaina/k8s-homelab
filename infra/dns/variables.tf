variable "state_passphrase" {
  description = "Encrypts the state (TF_VAR_state_passphrase, injected by infra/tf)."
  type        = string
  sensitive   = true
}

variable "proxmox_endpoint" {
  description = "Proxmox API URL."
  type        = string
}

variable "proxmox_node" {
  description = "Proxmox node that hosts the container."
  type        = string
}

variable "dns01" {
  description = "Technitium DNS container."
  type = object({
    vm_id     = number
    ip        = string
    gateway   = string
    cores     = number
    memory_mb = number
    disk_gb   = number
  })
}

variable "ssh_public_key" {
  description = "Public key allowed to SSH in as root (guide/04-dns-server.md)."
  type        = string
}
