locals {
  node_ips         = [for name in sort(keys(var.nodes)) : var.nodes[name].ip]
  bootstrap_ip     = var.nodes["talos-cp-01"].ip
  cluster_endpoint = "https://${var.cluster_vip}:6443"

  # Talos 1.14 splits configuration into typed documents; each patch targets one of them.
  # (Legacy v1alpha1 `cluster.*` / `machine.install` fields conflict with these documents.)

  # Installer image from our schematic (keeps the guest agent across upgrades).
  install_patch = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "UnattendedInstallConfig"
    installer  = { image = local.installer_image }
    provisioning = {
      diskSelector = { match = "disk.dev_path == \"/dev/sda\"" }
    }
  })

  # No Flannel document = no built-in CNI; Cilium is installed below instead.
  delete_flannel_patch = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "KubeFlannelCNIConfig"
    "$patch"   = "delete"
  })

  # Cilium replaces kube-proxy.
  proxy_patch = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "KubeProxyConfig"
    enabled    = false
  })

  apiserver_patch = yamlencode({
    apiVersion    = "v1alpha1"
    kind          = "KubeAPIServerConfig"
    certExtraSANs = [var.cluster_vip, var.cluster_domain_san]
  })

  # Allow workloads on control planes by removing the control-plane NoSchedule taint.
  schedulable_patch = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "KubeNodeConfig"
    taints = {
      "node-role.kubernetes.io/control-plane" = { "$patch" = "delete" }
    }
  })

  # Topology labels for the Proxmox CSI plugin: region = the name in the plugin config,
  # zone = the Proxmox node. All VMs share one host, so every node has the same zone.
  topology_patch = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "KubeNodeConfig"
    labels = {
      "topology.kubernetes.io/region" = var.proxmox_region
      "topology.kubernetes.io/zone"   = var.proxmox_node
    }
  })

  cilium_manifest_patch = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "KubeInlineManifestConfig"
    name       = "cilium"
    manifest   = data.helm_template.cilium.manifest
  })

  # Stable name "net0" for the single virtio NIC, so the VIP doesn't depend on kernel naming.
  link_alias_patch = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "LinkAliasConfig"
    name       = "net0"
    selector   = { match = "link.driver == \"virtio_net\"" }
  })

  vip_patch = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "Layer2VIPConfig"
    name       = var.cluster_vip
    link       = "net0"
  })

  # Node DNS: dns01 first (recursive, knows the internal zone), the router as fallback. Host DNS
  # stays on and keeps serving CoreDNS (forwardKubeDNSToHost), so the cluster keeps resolving if dns01 is down.
  resolver_patch = yamlencode({
    apiVersion  = "v1alpha1"
    kind        = "ResolverConfig"
    nameservers = [for ip in var.node_nameservers : { address = ip }]
    hostDNS     = { enabled = true, forwardKubeDNSToHost = true }
  })

  # The API VIP and Proxmox resolve even with all DNS down (CSI talks to pve01 by name).
  static_host_patches = [for ip, names in var.static_hosts : yamlencode({
    apiVersion = "v1alpha1"
    kind       = "StaticHostConfig"
    name       = ip
    hostnames  = names
  })]

  # Generated configs contain HostnameConfig{auto: stable}, which conflicts with a static
  # hostname. Delete it here; each node adds its own HostnameConfig in the apply step.
  delete_auto_hostname_patch = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "HostnameConfig"
    "$patch"   = "delete"
  })

  # Talos binds the controller-manager and scheduler metrics to localhost;
  # bind every interface so Prometheus can scrape them (both still require an authorized token).
  controller_manager_patch = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "KubeControllerManagerConfig"
    extraArgs  = { "bind-address" = "0.0.0.0" }
  })
  scheduler_patch = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "KubeSchedulerConfig"
    extraArgs  = { "bind-address" = "0.0.0.0" }
  })

  # etcd is not a pod on Talos: a plain-HTTP metrics listener (metrics only, never data). etcd
  # still has no typed document in Talos 1.14, hence the v1alpha1 cluster.etcd patch.
  etcd_metrics_patch = yamlencode({
    cluster = { etcd = { extraArgs = { "listen-metrics-urls" = "http://0.0.0.0:2381" } } }
  })

  # Kubelets request serving certificates from the cluster CA instead of self-signing;
  # kubelet-serving-cert-approver (platform repo) approves them. metrics-server then verifies
  # kubelet TLS (no --kubelet-insecure-tls).
  kubelet_cert_patch = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "KubeletConfig"
    extraArgs  = { "rotate-server-certificates" = "true" }
  })

  # containerd authenticates to GHCR with a read-only token: private app images pull
  # like public ones. Any pod can pull what the token can read (the node-identity trade-off).
  ghcr_auth_patch = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "RegistryAuthConfig"
    name       = "ghcr.io"
    username   = var.ghcr_username
    password   = var.ghcr_pull_token
  })
}

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  config_patches = concat([
    local.install_patch,
    local.delete_flannel_patch,
    local.proxy_patch,
    local.apiserver_patch,
    local.schedulable_patch,
    local.topology_patch,
    local.cilium_manifest_patch,
    local.link_alias_patch,
    local.vip_patch,
    local.delete_auto_hostname_patch,
    local.resolver_patch,
    local.controller_manager_patch,
    local.scheduler_patch,
    local.etcd_metrics_patch,
    local.kubelet_cert_patch,
    local.ghcr_auth_patch,
  ], local.static_host_patches)
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.node_ips # talosctl talks to nodes directly, never via the VIP
  nodes                = local.node_ips
}

resource "talos_machine_configuration_apply" "cp" {
  for_each   = var.nodes
  depends_on = [proxmox_virtual_environment_vm.cp]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = each.value.ip
  config_patches = [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      hostname   = each.key
    })
  ]
}

# Initializes etcd on the first node. Runs once in the cluster's lifetime.
resource "talos_machine_bootstrap" "this" {
  depends_on           = [talos_machine_configuration_apply.cp]
  node                 = local.bootstrap_ip
  client_configuration = talos_machine_secrets.this.client_configuration
}

# Apply only succeeds once etcd, control-plane components and all nodes are healthy.
# Read on every plan; skip with -var skip_health_check=true while a node is down.
data "talos_cluster_health" "this" {
  count                = var.skip_health_check ? 0 : 1
  depends_on           = [talos_machine_bootstrap.this]
  client_configuration = data.talos_client_configuration.this.client_configuration
  control_plane_nodes  = local.node_ips
  endpoints            = local.node_ips
  timeouts = {
    read = "15m"
  }
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on           = [data.talos_cluster_health.this]
  node                 = local.bootstrap_ip
  client_configuration = talos_machine_secrets.this.client_configuration
}
