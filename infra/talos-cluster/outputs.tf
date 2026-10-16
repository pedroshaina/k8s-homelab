output "kubeconfig" {
  description = "Admin kubeconfig (API via VIP). Write it out with infra/tf talos-cluster configs."
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "talosconfig" {
  description = "talosctl client config. Write it out with infra/tf talos-cluster configs."
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}
