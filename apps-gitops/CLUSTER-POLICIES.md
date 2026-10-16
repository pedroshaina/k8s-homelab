# Cluster policies for team apps

Rules for everything under `apps/`. Read them before any change there; reviewers check pull
requests against them. Some rules are enforced by the cluster; the rest are conventions that
nothing checks automatically, so follow them deliberately.

## Enforced by the cluster (for reference)

1. **Kinds:** only ConfigMap, PersistentVolumeClaim, Service, ServiceAccount, Deployment,
   StatefulSet, HorizontalPodAutoscaler, CronJob, Job, HTTPRoute, NetworkPolicy,
   PodDisruptionBudget, ExternalSecret, PodMonitor, PrometheusRule and ServiceMonitor; nothing
   cluster-scoped, so no Namespace (the platform creates it) and no Secret (secrets come from
   1Password through ExternalSecrets). *(Argo CD AppProject `apps`)*
2. **Namespaces:** an app deploys only into its onboarded namespaces. *(AppProject destinations)*
3. **Names:** app folders are DNS labels and not platform names. *(platform `teams` chart)*
4. **Secrets store:** ExternalSecrets can't use the `platform` store. *(ESO store conditions)*
5. **Pod Security `restricted`:** non-root, no privilege escalation, `RuntimeDefault` seccomp,
   all capabilities dropped. *(namespace labels)*
6. **Metrics namespace:** Prometheus forces `namespace=<app>` on team metrics.

## Conventions (not enforced)

1. One folder `apps/<app>/` per onboarded app holding top-level `*.yaml` files: plain, or with a
   `kustomization.yaml` (convention 12). No Helm charts, JSON or subfolders.
2. `metadata.namespace` empty or the app's own.
3. Services are `ClusterIP` without `externalIPs`. Expose an app through an HTTPRoute attached to
   `gateway/shared`, listener `https-apps` (`sectionName: https-apps`, as podinfo does; it serves
   `*.example.com`).
4. ExternalSecrets use `ClusterSecretStore/apps` only, no generators, `refreshInterval` ≥ `1h`
   (all teams share one 1Password quota; a failing ExternalSecret burns it — fix or delete it).
5. Monitors (ServiceMonitor/PodMonitor) select only their own namespace, reference no files
   (`*File` fields), and don't relabel `__address__`, `__scheme__`, `__metrics_path__` or
   `__param_*`. No `AlertmanagerConfig` (alert routing is platform-owned).
6. Every PrometheusRule has a promtool test in `tests/rules/<app>/<file>.test.yaml` (CI fails
   otherwise).
7. Dashboards are ConfigMaps labelled `grafana_dashboard: "1"`, annotated `grafana_folder: apps`,
   every dashboard `uid` starting with `apps-`; no `binaryData`.
8. Every image — containers and init containers — runs pinned `tag@sha256:<digest>`: what runs is
   exactly what Git names. Own images (`ghcr.io/your-github-user/*`) are pinned only in the
   folder's `kustomization.yaml` (`images:`) and named without tag in the manifests; third-party
   images (like podinfo) are pinned in the manifest.
9. No credentials on command lines (`args`/`command`); pass them through Secret-backed env vars or
   files, and reference single Secret keys, not whole Secrets.
10. **One node:** no PodDisruptionBudget and no required pod anti-affinity — on the only node a
    drain has nowhere to move pods, so they block every Talos/Kubernetes upgrade.
11. Adding an app: folder PR here first, then the onboarding line in `platform-gitops`
    `components/teams/values.yaml`. With the release pipeline, the folder may name its own images
    without a pin until the app's first release pins them; the onboarding line comes after that.
    Removing an app: the platform offboards it first, then the folder is deleted here; the
    namespace and its data stay until the platform owner deletes them.
12. **kustomization.yaml** holds only `resources:` — every manifest of the folder, by file name —
    and `images:`. No remote resources, patches, generators, components or other fields. A file
    left out of `resources:` is not deployed, and a file dropped from it is pruned. The file is
    written by `kustomize create` / `kustomize edit` (the release job and manual bumps alike),
    which reformats it; edit it with those tools, and keep comments to the head comment (the only
    one that survives).
