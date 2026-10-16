variable "state_passphrase" {
  description = "Passphrase for OpenTofu state/plan encryption (from secrets.sops.yaml)."
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.state_passphrase) >= 16
    error_message = "state_passphrase must be at least 16 characters."
  }
}

variable "proxmox_endpoint" {
  description = "Proxmox API URL."
  type        = string
}

variable "proxmox_node" {
  description = "Proxmox node that hosts the VMs."
  type        = string
}

variable "proxmox_region" {
  description = "Region name for topology.kubernetes.io/region; must match the Proxmox CSI config."
  type        = string
}

variable "talos_version" {
  description = "Talos Linux version, e.g. v1.14.1."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version, e.g. 1.37.1."
  type        = string
}

variable "cilium_version" {
  description = "Cilium Helm chart version."
  type        = string
}

variable "cluster_name" {
  type = string
}

variable "cluster_vip" {
  description = "Layer-2 VIP shared by the control planes; the Kubernetes API endpoint."
  type        = string
}

variable "cluster_domain_san" {
  description = "Extra DNS name on the API server certificate."
  type        = string
}

variable "gateway" {
  type = string
}

variable "dns_servers" {
  type = list(string)
}

variable "nodes" {
  description = "Control-plane nodes (they also run workloads): hostname => { ip, vm_id }. 1, or 3 for HA."
  type = map(object({
    ip    = string
    vm_id = number
  }))
  validation {
    condition     = contains([1, 3], length(var.nodes))
    error_message = "1 node, or 3 for etcd quorum: an even count only adds failure points."
  }
}

variable "node_cpu" {
  type = number
}

variable "node_memory_mb" {
  type = number
}

variable "node_disk_gb" {
  type = number
}

variable "skip_health_check" {
  description = <<-EOT
    Skip the cluster health gate. It runs on every plan/apply and blocks for up to 15m when
    a node is down; set to true (-var skip_health_check=true) to plan or repair during an outage.
  EOT
  type        = bool
  default     = false
}

variable "node_nameservers" {
  description = "DNS servers for the Talos nodes, in order (dns01 first, the router as fallback)."
  type        = list(string)
}

variable "static_hosts" {
  description = "Static /etc/hosts entries on the nodes: IP => hostnames."
  type        = map(list(string))
}

# Classic GitHub PAT, read:packages only: containerd's credentials for ghcr.io, so
# private app images pull with no per-app Secret. From SOPS key GITHUB_GHCR_IMAGE_PULL_TOKEN
# (infra/tf maps it for this module only).
# The GitHub user that owns the GHCR token above (the registry login name).
variable "ghcr_username" {
  type = string
}

variable "ghcr_pull_token" {
  type      = string
  sensitive = true
  validation {
    condition     = length(var.ghcr_pull_token) > 0
    error_message = "Add GITHUB_GHCR_IMAGE_PULL_TOKEN to infra/secrets.sops.yaml (guide/05-cluster.md)."
  }
}
