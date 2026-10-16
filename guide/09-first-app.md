# 09 — Your first app

**What you'll have at the end:** an understanding of how an app gets from `apps-gitops` to the
cluster, using podinfo (already running since chapter 07), and the steps to add, expose and
remove apps of your own.

## How podinfo got there

Two files, in two repositories, owned by two different roles:

1. **The team** (`apps-gitops`) describes how the app runs: `apps/podinfo/` holds a Deployment and
   Service, an HTTPRoute for `podinfo.example.com`, a ServiceMonitor and a `kustomization.yaml`
   listing them. On its own, this folder deploys nothing.
2. **The platform** (`platform-gitops`) onboards it: `components/teams/values.yaml` lists team
   `apps`, its repository and its apps:
   ```yaml
   teams:
     - name: apps
       repo: git@github.com:your-github-user/apps-gitops.git
       alertsWebhook: apps-alerts-discord-webhook-uri
       apps:
         - {name: podinfo, public: true}
   ```

From that line, the `teams` Application renders:

- an **AppProject** `apps`: only the team's repository, only its apps' namespaces, an allowlist of
  resource kinds, nothing cluster-scoped;
- per app, a **Namespace** (Pod Security `restricted`, labelled with the team) and an Argo CD
  **Application** that deploys `apps/<app>/` from the team's repository;
- the team's **secret store** (`ClusterSecretStore/apps`), usable only from its namespaces.

`public: true` makes `public-apps` route `podinfo.example.com` through the Cloudflare Tunnel and
publish its public DNS record. `alertsWebhook` sends alerts from the team's namespaces to
`#apps-alerts`.

The rules every app follows are in `apps-gitops/CLUSTER-POLICIES.md`: what the cluster enforces
and the conventions reviewers check. Read them before adding an app.

## Steps: add an app

Pick the name first: it becomes the folder `apps/<name>/`, the namespace, the Argo CD Application
and the hostname `<name>.example.com`. It must be a DNS label (lowercase letters, digits, `-`)
and not a platform name (`argocd`, `grafana`, `monitoring`, …: the `teams` chart refuses those).

1. **Apps repository:** a pull request adding `apps/<name>/` with the manifests (podinfo's are a
   good starting point) and a `kustomization.yaml` written by the tool, from the folder:
   ```bash
   kustomize create --resources "$(ls *.yaml | paste -sd, -)"
   kustomize build .                    # renders every manifest
   ```
   Third-party images are pinned `tag@sha256:<digest>` in the manifest. Merge: nothing deploys yet.
2. **Platform repository:** add `- {name: <name>}` under the team in
   `components/teams/values.yaml`, pull request, merge. Argo CD creates the namespace, extends the
   project and creates the Application.

```bash
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=normal --overwrite   # don't wait for the poll
kubectl -n argocd get application <name>             # Synced, Healthy
kubectl -n <name> get pods                           # Running
dig +short <name>.example.com @192.168.1.215         # 192.168.1.230
```

For your own code, with images built and pinned automatically on every merge, see chapter 10.

## Optional pieces

Add the file to the folder, then `kustomize edit add resource <file>`:

- **Secrets:** an item in vault `k8s-apps` named `apps-<app>-<secret>` with one concealed field
  `secretValue`, and an `ExternalSecret` on `ClusterSecretStore/apps` with `refreshInterval: 1h`
  or more. Never a `Secret` in Git.
- **Volumes:** a `PersistentVolumeClaim`; the default StorageClass creates a disk on Proxmox
  (`local-lvm`), which survives pod restarts and node reboots.
- **Metrics:** a `ServiceMonitor` or `PodMonitor` (like podinfo's). Every series gets
  `namespace="<app>"`, whatever the file says.
- **Alerts:** a `PrometheusRule`, with a promtool test in `tests/rules/<app>/<file>.test.yaml`
  (CI fails without one). Prometheus confines its expressions to the app's namespace; firing
  alerts go to `#apps-alerts`.
- **Dashboards:** a ConfigMap labelled `grafana_dashboard: "1"`, annotated `grafana_folder: apps`,
  with a dashboard `uid` starting with `apps-`.

## Steps: make an app public

Public apps are reached at `https://<app>.example.com` through the Cloudflare Tunnel; no port is
opened at home, and only apps you mark public get a public DNS record.

1. Decide on edge protection first: an app with no rate limiting of its own should get a
   Cloudflare rate-limiting rule (Security → WAF → Rate limiting rules; the free plan allows one
   rule, shared by all public hosts).
2. Set `public: true` on its onboarding line, pull request, merge.

```bash
dig +short <name>.example.com @1.1.1.1      # Cloudflare addresses
```

## Steps: remove an app

1. Platform repository: remove its onboarding line. Argo CD removes the Application without
   deleting what it deployed, and the public record goes with `public: true`.
2. Apps repository: delete `apps/<name>/`.
3. Once you're sure the data isn't needed: `kubectl delete namespace <name>` (this deletes its
   volumes too). The namespace is never deleted automatically.

## Adding a team

A team is another entry under `teams:` with its own repository. Before merging it: a read-only
deploy key for that repository (chapter 07, step 1, for one repository), a vault `k8s-<team>`
with a read-only service account whose token goes into item `<team>-svc-acc-token` in
`k8s-platform`, and optionally a Discord webhook item for `alertsWebhook`.

## Alternatives

- **Helm charts for apps:** the convention is plain manifests plus Kustomize, so reviews see
  exactly what deploys. A team that prefers Helm can commit the rendered output.

Next: [10 — Releasing your own apps](10-releases.md).
