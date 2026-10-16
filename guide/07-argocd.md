# 07 — Argo CD and the platform

**What you'll have at the end:** Argo CD running in the cluster and managing everything else —
including itself and Cilium — from `platform-gitops`. From here on, the cluster changes only
through pull requests: Argo CD makes the cluster match `main` and undoes any change made by hand.

**GitOps in one paragraph:** one Application, `root`, is applied by hand. It watches
`platform-gitops/apps/`, where every other Application lives (the *app-of-apps* pattern). Each
Application points to a Helm chart or a folder plus values from this repository. Sync waves order
them, so a component starts only after what it depends on is healthy:

| Wave | Applications |
|---|---|
| -2 | `prometheus-operator-crds` (and the AppProjects) |
| -1 | `argocd`, `external-secrets`, `gateway-api-crds` |
| 0 | `cert-manager`, `cilium`, `external-secrets-config`, `kubelet-serving-cert-approver` |
| 1 | `cert-manager-config`, `cilium-config`, `metrics-server` |
| 2 | `external-dns`, `external-dns-public`, `platform-routes`, `proxmox-csi` |
| 3 | `alert-routing`, `alloy`, `kube-prometheus-stack`, `loki`, `public-apps`, `teams` |

## Before you start

Argo CD syncs everything at once, so everything it needs must exist first:

- [ ] Your values are in all three repositories and pushed (chapter 01), including the tunnel ID
      (chapter 02).
- [ ] `cilium_version` in `k8s-homelab/infra/talos-cluster/terraform.tfvars` equals
      `targetRevision` of the Cilium chart in `platform-gitops/apps/cilium.yaml`.
- [ ] Proxmox serves a trusted certificate (chapter 03): the storage driver verifies it.
- [ ] `dns01` accepts signed updates with the `external-dns` TSIG key (chapter 04).
- [ ] The nine items exist in vault `k8s-platform` (chapter 06), and you have the
      `k8s-platform-eso` token at hand.
- [ ] `export KUBECONFIG=~/.kube/config-homelab`, and `kubectl get nodes` shows the node Ready.

## Steps

All steps run from your `platform-gitops` checkout, in your own terminal (they decrypt secrets
into a pipe, never to disk).

### 1. Read-only deploy keys

A deploy key is an SSH key that can read one repository only. Argo CD gets one per repository it
reads; each is stored as a SOPS-encrypted Kubernetes Secret in `bootstrap/`:

```bash
cd ~/platform-gitops
GH_USER=alice
for repo in k8s-homelab platform-gitops apps-gitops; do
  tmp="$(mktemp -d)"
  ssh-keygen -q -t ed25519 -N '' -C "argocd-$repo" -f "$tmp/key"
  gh repo deploy-key add "$tmp/key.pub" --repo "$GH_USER/$repo" --title argocd-read   # read-only by default
  kubectl create secret generic "repo-$repo" -n argocd \
      --from-literal=type=git \
      --from-literal=url="git@github.com:$GH_USER/$repo.git" \
      --from-file=sshPrivateKey="$tmp/key" --dry-run=client -o yaml \
    | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \
    | sops encrypt --filename-override "bootstrap/repo-$repo.sops.yaml" \
        --input-type yaml --output-type yaml /dev/stdin > "bootstrap/repo-$repo.sops.yaml"
  rm -rf "$tmp"
done
```

### 2. Secret zero: the 1Password token

```bash
read -rs OP_TOKEN   # paste the k8s-platform-eso token, then Enter
kubectl create secret generic platform-svc-acc-token -n external-secrets \
    --from-literal=secretValue="$OP_TOKEN" --dry-run=client -o yaml \
  | sops encrypt --filename-override bootstrap/platform-1password-svc-acc-token.sops.yaml \
      --input-type yaml --output-type yaml /dev/stdin > bootstrap/platform-1password-svc-acc-token.sops.yaml
unset OP_TOKEN
```

Commit the four encrypted files through a pull request (pre-commit refuses a file that isn't
fully encrypted) and merge it.

### 3. Install Argo CD and hand over

1. **Right checkout, right cluster.** Argo CD applies `main`, so install from `main`:
   ```bash
   git switch main && git pull --ff-only
   git status --porcelain --untracked-files=no      # prints nothing
   kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'; echo   # https://192.168.1.220:6443
   ```
2. **Bootstrap Secrets**, applied server-side (a client-side apply would copy the decrypted data
   into an annotation):
   ```bash
   for s in repo-k8s-homelab repo-platform-gitops repo-apps-gitops platform-1password-svc-acc-token; do
     ns="$(sops decrypt "bootstrap/$s.sops.yaml" | yq -e '.metadata.namespace')"
     kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply --server-side -f -
     sops decrypt "bootstrap/$s.sops.yaml" | kubectl apply --server-side --field-manager=bootstrap -f -
   done
   ```
3. **Argo CD**, with exactly the chart and values Git declares:
   ```bash
   helm upgrade --install argocd "$(yq '.spec.sources[0].chart' apps/argocd.yaml)" \
     --repo "$(yq '.spec.sources[0].repoURL' apps/argocd.yaml)" \
     --version "$(yq '.spec.sources[0].targetRevision' apps/argocd.yaml)" \
     --namespace argocd -f components/argocd/values.yaml \
     --server-side true --force-conflicts --wait --timeout 10m
   ```
4. **AppProjects, then `root`:**
   ```bash
   kubectl apply --server-side -f apps/projects.yaml
   kubectl apply --server-side -f bootstrap/root.yaml
   ```
5. **Hand over:** delete Helm's release record. Argo CD now owns its own installation, and a
   stray `helm uninstall` can no longer remove it:
   ```bash
   kubectl -n argocd delete secret -l owner=helm,name=argocd --ignore-not-found
   ```

### 4. Watch the platform come up

```bash
kubectl -n argocd get applications -w      # waves -2 → 3; about 10–15 minutes in total
```

Things that take a while on the first pass: cert-manager's DNS-01 challenge for the wildcard
certificate (a few minutes), and Prometheus and Loki pulling images and creating volumes.
Argo CD polls Git every ~3 minutes; to pick up a merge at once:
`kubectl -n argocd annotate application root argocd.argoproj.io/refresh=normal --overwrite`.

### 5. First login

Argo CD's UI is at `https://argocd.example.com` (LAN only: its DNS record exists only on
`dns01`). Change the generated admin password, then delete the initial Secret:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
argocd login --port-forward --port-forward-namespace argocd --plaintext --username admin
argocd account update-password --port-forward --port-forward-namespace argocd --plaintext
kubectl -n argocd delete secret argocd-initial-admin-secret
```

Store the new password in 1Password. The CLI talks to the API through a port-forward; use the
same three flags on every `argocd` command.

## Check

```bash
kubectl -n argocd get applications --no-headers | awk '$2!="Synced" || $3!="Healthy"'   # prints nothing
```

Chapter 08 checks the rest, end to end.

**If an Application is stuck:** `kubectl -n argocd describe application <name>` shows the error.
A wave waits until every Application in the previous wave is Healthy, so one broken component
holds back the waves after it. Auto-sync never retries a revision that already failed: after
fixing the cause, run `argocd app sync <name>` (with the flags above).

## Alternatives

- **Flux** instead of Argo CD: same GitOps model, no UI; the Applications become
  `Kustomization`/`HelmRelease` objects.

Next: [08 — Verify the platform](08-verify.md).
