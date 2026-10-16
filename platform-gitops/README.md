# platform-gitops

The cluster platform, reconciled by Argo CD from this repo's `main` branch: Argo CD itself, Cilium
(features on top of the Talos bootstrap base), LB IPAM and L2 announcements, the shared Gateway,
certificates, internal and public DNS, the Cloudflare Tunnel, Proxmox CSI storage, External
Secrets, monitoring and logs, and the onboarding of teams and their apps.

Part of [k8s-homelab](https://github.com/your-github-user/k8s-homelab): copy this folder into its
own repository (guide chapter 01) and bootstrap it (chapter 07).

## Layout

- `bootstrap/` — applied once by hand: the `root` Application and the SOPS-encrypted bootstrap
  Secrets (three deploy keys and the 1Password platform token). Every other Secret comes from
  1Password through External Secrets Operator.
- `apps/` — the AppProjects and one Argo CD Application per platform component. `root` watches
  this folder (app-of-apps); the `argocd.argoproj.io/sync-wave` annotation orders them: CRDs
  first, then operators, then their configuration.
- `components/` — Helm values and plain manifests per component, plus three small local charts:
  `teams` (an AppProject per team, a Namespace and Application per app), `public-apps`
  (cloudflared and public DNS records for apps marked `public: true`) and `alert-routing`
  (Alertmanager routes per team).
- `scripts/check-sops-encrypted.sh` — the pre-commit hook that refuses a plaintext secret.

## Changing the platform

Edit, open a pull request, merge: Argo CD applies `main` within about three minutes. A component
whose health depends on another one goes in a later sync wave than it (for example HTTPRoutes
after the Gateway).

**Onboarding a team or an app:** `components/teams/values.yaml`. Merge the app's folder in the
team's repository first, then add the app here.

## Checks

`pre-commit install` runs yamllint, gitleaks, the SOPS check and kubeconform on every commit.
`.github/workflows/ci.yaml` runs the same checks on every pull request, plus `promtool` unit tests
for the alert rules and gitleaks over the full history. It needs no secrets or settings.
