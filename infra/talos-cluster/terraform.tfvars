# Example values: change every value listed in guide/00-prerequisites.md ("Values to replace").
proxmox_endpoint = "https://pve01.example.com:8006/"
proxmox_node     = "pve01"
proxmox_region   = "homelab"

talos_version      = "v1.14.1"
kubernetes_version = "1.37.1"
cilium_version     = "1.20.2"

cluster_name       = "homelab"
cluster_vip        = "192.168.1.220"
cluster_domain_san = "k8s.example.com"
gateway            = "192.168.1.1"
dns_servers        = ["192.168.1.1"]

# Nodes resolve via dns01, the router as fallback; static hosts survive any DNS outage.
node_nameservers = ["192.168.1.215", "192.168.1.1"]
static_hosts = {
  "192.168.1.214" = ["pve01.example.com"]
  "192.168.1.220" = ["k8s.example.com"]
}

nodes = {
  "talos-cp-01" = { ip = "192.168.1.221", vm_id = 221 }
}

node_cpu       = 8
node_memory_mb = 20480
node_disk_gb   = 100

ghcr_username = "your-github-user"
