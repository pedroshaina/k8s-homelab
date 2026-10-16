# 00 — Prerequisites

**What you'll have at the end:** the hardware, the accounts and the list of values you'll change,
so the following chapters can run without stopping.

## Hardware

One machine runs everything. What this blueprint was built on, and the minimum it needs:

| | Used | Minimum |
|---|---|---|
| Host | Mini PC, AMD Ryzen 7 5800H (8 cores) | 8 cores with virtualization (AMD-V / VT-x) |
| Memory | 32 GB | 32 GB (the Kubernetes VM takes 20 GiB) |
| Disk | 1 TB NVMe | 256 GB SSD (the VM disk is 100 GB, plus volumes) |
| Network | wired Ethernet to the home router | wired; a router whose DHCP range you can shrink |

One node means no redundancy: a host reboot or an upgrade is downtime. That trade-off keeps the
hardware cheap; chapter 11 shows how to take an etcd snapshot before any change.

## Accounts

| Account | Used for | Cost |
|---|---|---|
| A domain (any registrar) | names like `argocd.example.com`; its DNS moves to Cloudflare | yearly domain fee |
| Cloudflare | public DNS, HTTPS certificates (DNS-01), the Tunnel for public apps, R2 bucket for OpenTofu state | free plan; R2 is free up to 10 GB |
| GitHub | the four repositories, container images (GHCR), the release pipeline | free |
| 1Password | the cluster's secrets, read by External Secrets Operator through service accounts | any plan with service accounts |
| Discord | a server with two channels for alerts: `#platform-alerts` and `#apps-alerts` | free |

## Network plan

Pick addresses outside your router's DHCP range. The example uses `192.168.1.0/24` with the
router at `.1` and DHCP limited to `.2–.199`:

| Address | Name | What |
|---|---|---|
| `192.168.1.1` | — | Router: gateway and fallback DNS |
| `192.168.1.214` | `pve01.example.com` | Proxmox host |
| `192.168.1.215` | `dns01.example.com` | Internal DNS server (Technitium, a container on Proxmox) |
| `192.168.1.220` | `k8s.example.com` | Kubernetes API address (a virtual IP held by the node) |
| `192.168.1.221` | `talos-cp-01` | The Kubernetes node (a VM on Proxmox) |
| `192.168.1.230` | — | Shared HTTPS Gateway: every web hostname of the cluster |
| `192.168.1.231–.254` | — | Other LoadBalancer services |

## Values to replace

Every value below appears in the code with the example shown. Chapter 01 replaces the first three
for you with one command each; the rest you edit as the chapters reach them.

| Example value | What it is | Where |
|---|---|---|
| `your-github-user` | your GitHub user or organization | repo URLs, GHCR images, release workflow |
| `example.com` | your domain | everywhere a hostname appears |
| `you@example.com` | email for Let's Encrypt | `platform-gitops/components/cert-manager-config/issuers.yaml` |
| `your-state-bucket`, `your-r2-account-id` | R2 bucket and Cloudflare account ID | `infra/*/versions.tf` |
| `age1replace-with-your-public-key` | your SOPS public key | `.sops.yaml`, `platform-gitops/.sops.yaml` |
| `ssh-ed25519 AAAA... you@example.com` | your SSH public key | `infra/dns/terraform.tfvars` |
| `00000000-0000-0000-0000-000000000000` | your Cloudflare Tunnel ID | `platform-gitops/components/public-apps/values.yaml` |
| `192.168.1.x` addresses | your network plan | `infra/*/terraform.tfvars`, `platform-gitops/components/cilium-config/ip-pools.yaml` |
| `replace-me` | secret values | `infra/secrets.sops.yaml` (encrypted, chapter 01) |
| `your-release-app` | the GitHub App that releases your apps | `app-template/` (chapter 10) |

Names of vaults, 1Password items, Discord channels and the GitHub App are examples too: keep them
or choose your own, consistently.

Find every remaining example value in your copies:

```bash
grep -rnE 'example\.com|your-github-user|your-state-bucket|your-r2-account-id|replace-me|age1replace|00000000-0000-0000-0000-000000000000|192\.168\.1\.' \
  ~/k8s-homelab ~/platform-gitops ~/apps-gitops --exclude-dir=.git --exclude-dir=guide
```

## Check

- [ ] The host has virtualization enabled in its firmware and a wired connection.
- [ ] You can log in to Cloudflare, GitHub and 1Password, and your domain is yours.
- [ ] You have chosen the addresses above (or your own) outside the DHCP range.

Next: [01 — Workstation and repositories](01-workstation-and-repos.md).
