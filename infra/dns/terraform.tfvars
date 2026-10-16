# Example values: change every value listed in guide/00-prerequisites.md ("Values to replace").
proxmox_endpoint = "https://pve01.example.com:8006/"
proxmox_node     = "pve01"

dns01 = {
  vm_id     = 215
  ip        = "192.168.1.215"
  gateway   = "192.168.1.1"
  cores     = 1
  memory_mb = 1024
  disk_gb   = 8
}

ssh_public_key = "ssh-ed25519 AAAA... you@example.com"
