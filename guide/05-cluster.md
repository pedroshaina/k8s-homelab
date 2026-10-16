# 05 — The Kubernetes cluster

**What you'll have at the end:** a one-node Kubernetes cluster, built by OpenTofu: a Talos Linux
VM on Proxmox with Cilium as its network, the API at `https://k8s.example.com:6443`, and a
working `kubectl`.

**Talos Linux** is an operating system that only runs Kubernetes: no SSH, no shell, no package
manager. It is configured entirely through an API from a declarative config, which OpenTofu
generates. **Cilium** is installed with the cluster itself (rendered by OpenTofu into the Talos
config), so the network exists the moment the API server starts; from chapter 07 on, Argo CD
manages it.

## Steps

### 1. GHCR pull token

The node pulls your apps' private images from GitHub Container Registry with its own credential,
so no app ever handles a pull secret. GHCR accepts only a **classic** personal access token for
this:

1. GitHub → Settings → Developer settings → Personal access tokens → **Tokens (classic)** →
   Generate new token. Scope **`read:packages` only**, expiration one year (note the date in
   your calendar: chapter 11 rotates it).
2. In your own terminal: `sops infra/secrets.sops.yaml` → `GITHUB_GHCR_IMAGE_PULL_TOKEN`.
3. Check that `ghcr_username` in `infra/talos-cluster/terraform.tfvars` is your GitHub user.

### 2. Review the cluster's settings

`infra/talos-cluster/terraform.tfvars` holds every choice: versions (Talos, Kubernetes, Cilium),
addresses, and the VM size (8 vCPU, 20 GiB, 100 GB). `nodes` lists one control-plane node that
also runs workloads.

### 3. Build it

```bash
cd ~/k8s-homelab
infra/tf talos-cluster init
infra/tf talos-cluster plan          # a schematic, an image download, one VM, the Talos config, ...
infra/tf talos-cluster apply         # about 10 minutes
```

What `apply` does, in order: builds a Talos image with the QEMU guest agent at the Talos Image
Factory, downloads it to Proxmox, creates the VM, applies the machine config, bootstraps etcd,
then waits for the cluster to be healthy before it hands out the kubeconfig. That health gate
runs on every later `plan` too, so a broken cluster stops OpenTofu from changing it further.

### 4. Client configs

```bash
infra/tf talos-cluster configs       # writes ~/.kube/config-homelab and ~/.talos/config
export KUBECONFIG=~/.kube/config-homelab    # add it to your shell profile
```

## Check

```bash
kubectl get nodes -o wide            # talos-cp-01   Ready   control-plane   ...   192.168.1.221
cilium status --wait                 # Cilium: OK, Operator: OK
talosctl -n 192.168.1.221 health     # every check: OK
infra/tf talos-cluster plan -detailed-exitcode; echo $?    # 0: no drift
```

**One node:** every Talos or Kubernetes upgrade and every host reboot is downtime, and etcd (the
cluster's database) has a single copy. Take a snapshot before any change (chapter 11). The VM is
protected with `prevent_destroy`: a plan that would destroy or replace it stops with an error.
Never remove that protection to get past it — replacing the VM wipes the only etcd member.

## Alternatives

- **Three control planes:** set three entries in `nodes` (one or three only: an even count
  adds failure points without tolerating more); needs about three times the memory.
- **Another OS:** k3s or kubeadm on Debian VMs work with the rest of the platform, but this
  module is Talos-specific.

Next: [06 — Secrets in 1Password](06-secrets.md).
