# k8s-homelab

An opinionated blueprint for a production-style Kubernetes platform on one machine at home.
Everything is code — the VM, the operating system, DNS, the platform, the apps — and every change
is a pull request: OpenTofu builds the infrastructure, Argo CD keeps the cluster equal to Git.

This repository holds the code and a step-by-step [guide](guide/00-prerequisites.md) to build
the same setup with your own domain, accounts and hardware. It is extracted from a homelab that
runs this exact configuration; the code is validated offline (OpenTofu, kubeconform, promtool),
and the guide's commands come from that homelab's runbooks.

## What you'll build

```
                    Internet
                       │  https://podinfo.example.com (public apps only)
                       ▼
              Cloudflare (DNS, Tunnel)
                       │  outbound tunnel — no ports open at home
┌──────────────────────┼──────────────────────────────────────────────┐
│ Home LAN             ▼                                              │
│  ┌─────────────────────────────────────────────┐   ┌─────────────┐  │
│  │ Proxmox host pve01                          │   │ dns01       │  │
│  │  ┌───────────────────────────────────────┐  │   │ internal    │  │
│  │  │ VM talos-cp-01: Talos Linux           │  │   │ DNS         │  │
│  │  │  Kubernetes                           │  │   └─────────────┘  │
│  │  │   ├─ Argo CD ◄── pulls from GitHub    │  │                    │
│  │  │   ├─ Gateway 192.168.1.230 (HTTPS)    │  │   Workstation:     │
│  │  │   ├─ platform services                │  │   kubectl, Argo CD,│
│  │  │   └─ team apps (podinfo, …)           │  │   Grafana          │
│  │  └───────────────────────────────────────┘  │                    │
│  └─────────────────────────────────────────────┘                    │
└─────────────────────────────────────────────────────────────────────┘
```

- **One Kubernetes node** on Proxmox, running Talos Linux: an API-managed OS with no SSH and no
  shell, built and configured by OpenTofu.
- **GitOps:** Argo CD syncs the cluster from two repositories, including its own installation and
  the cluster network. A change is a merged pull request; reverting the commit undoes it.
- **Platform and teams:** the platform repository decides what each team may do (its namespaces,
  the resource kinds it can deploy, its own secrets vault); the team's repository can only deploy
  within those limits.
- **HTTPS everywhere:** one shared Gateway with a Let's Encrypt wildcard certificate; each
  platform hostname has its own listener, so a team can't take it over.
- **Split-horizon DNS:** internal names resolve only on the LAN through `dns01`; public DNS on
  Cloudflare holds only the apps marked public.
- **No secrets in Git:** infrastructure credentials are SOPS-encrypted; cluster secrets come from
  1Password through External Secrets Operator.
- **Observability:** Prometheus, Alertmanager, Grafana and Loki, with alerts routed to Discord per
  owner; teams ship their own monitors, alert rules and dashboards.
- **Releases:** merging to an app repository's `main` tests, builds and pushes its images, and a
  GitHub App pins them by digest in the apps repository; Argo CD deploys. Rollback is a revert.

## Stack

| Layer | Tool | Role |
|---|---|---|
| Hypervisor | Proxmox VE | runs the Kubernetes VM and the DNS container |
| Infrastructure as code | OpenTofu (state in Cloudflare R2, encrypted) | VM, Talos config, DNS container |
| OS | Talos Linux | immutable, API-driven Kubernetes OS |
| Network | Cilium | CNI without kube-proxy, LoadBalancer IPs and L2 announcements, Gateway API, Hubble |
| GitOps | Argo CD | app-of-apps, sync waves, one AppProject per team |
| Storage | Proxmox CSI | volumes as Proxmox disks |
| TLS | cert-manager + Let's Encrypt | wildcard certificate via DNS-01 on Cloudflare |
| DNS | Technitium + external-dns | internal zone updated from HTTPRoutes; public records on Cloudflare |
| Public access | Cloudflare Tunnel | outbound-only, per-app opt-in |
| Secrets | SOPS + age, External Secrets Operator + 1Password | encrypted in Git / synced from vaults |
| Observability | kube-prometheus-stack, Loki, Alloy | metrics (30 days), logs, alerts to Discord |
| CI/CD | GitHub Actions, GHCR, a GitHub App | test, build, pin by digest, deploy |
| Checks | pre-commit, gitleaks, yamllint, kubeconform, promtool | the same checks locally and in CI |

## Repository layout

| Path | What it holds | Becomes |
|---|---|---|
| [`guide/`](guide/) | the step-by-step guide | — |
| [`infra/`](infra/) | OpenTofu: `talos-cluster` (the VM and Kubernetes), `dns` (the DNS container), the `tf` wrapper | stays here |
| [`platform-gitops/`](platform-gitops/) | everything the cluster runs for the platform | your `platform-gitops` repository |
| [`apps-gitops/`](apps-gitops/) | team `apps`' manifests, with podinfo as the example | your `apps-gitops` repository |
| [`app-template/`](app-template/) | a Go placeholder app with the release pipeline | your template for new apps |

## The guide

| Chapter | You end up with |
|---|---|
| [00 — Prerequisites](guide/00-prerequisites.md) | hardware, accounts, network plan, the values to replace |
| [01 — Workstation and repositories](guide/01-workstation-and-repos.md) | tools, your repositories, SOPS key, state bucket, encrypted secrets file |
| [02 — Cloudflare](guide/02-cloudflare.md) | your zone on Cloudflare, API tokens, the tunnel |
| [03 — Proxmox](guide/03-proxmox.md) | Proxmox with a trusted certificate, least-privilege users, host tuning |
| [04 — Internal DNS server](guide/04-dns-server.md) | `dns01` answering for your domain on the LAN |
| [05 — The Kubernetes cluster](guide/05-cluster.md) | a Talos node with Cilium, built by OpenTofu |
| [06 — Secrets in 1Password](guide/06-secrets.md) | vaults, service accounts and every secret the cluster reads |
| [07 — Argo CD and the platform](guide/07-argocd.md) | Argo CD managing the whole platform from Git |
| [08 — Verify the platform](guide/08-verify.md) | a checklist proving every layer, fences included |
| [09 — Your first app](guide/09-first-app.md) | how apps are onboarded, exposed and removed |
| [10 — Releasing your own apps](guide/10-releases.md) | merge-to-deploy for your own code |
| [11 — Day 2](guide/11-day-2.md) | snapshots, upgrades, chart bumps, rotations, break glass |

## Author

Built by Pedro Martins — [github.com/pedroshaina](https://github.com/pedroshaina)

## License

[MIT](LICENSE)
