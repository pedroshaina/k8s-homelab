# Renders the Cilium chart locally; the output is embedded in the Talos config as an
# inline manifest so the cluster has networking the moment the API server starts.
data "helm_template" "cilium" {
  name         = "cilium"
  namespace    = "kube-system"
  repository   = "https://helm.cilium.io"
  chart        = "cilium"
  version      = var.cilium_version
  kube_version = var.kubernetes_version
  values       = [file("${path.module}/cilium-values.yaml")]
}
