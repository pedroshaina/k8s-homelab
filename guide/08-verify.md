# 08 — Verify the platform

**What you'll have at the end:** proof that every layer works — node, GitOps, monitoring,
HTTPS, DNS, secrets, alerts and the fences between teams. Run this checklist again after any
upgrade, host reboot or platform change. Each item is a command and what it must print; stop at
the first mismatch.

```bash
export KUBECONFIG=~/.kube/config-homelab TALOSCONFIG=~/.talos/config
```

## Checklist

### 1. Node and Talos

```bash
kubectl get nodes                                    # talos-cp-01 Ready
talosctl -n 192.168.1.221 health --wait-timeout 5m   # every check OK
talosctl -n 192.168.1.221 etcd members               # one member
```

### 2. Argo CD

```bash
kubectl -n argocd get applications --no-headers | awk '$2!="Synced" || $3!="Healthy"'   # nothing
```

If every Application shows `Unknown` (typically after a hard reset of the host), the
repo-server's Git cache is corrupt: `kubectl -n argocd delete pod -l app.kubernetes.io/name=argocd-repo-server`.

### 3. Pods, alerts, monitoring

Prometheus is queried through the API server, so nothing needs to listen on the LAN:

```bash
kubectl get pods -A --no-headers | awk '$4!="Completed" && ($4!="Running" || split($3,r,"/") && r[1]!=r[2])'   # nothing
prom() { kubectl get --raw "/api/v1/namespaces/monitoring/services/prometheus-operated:9090/proxy/api/v1/query?query=$(jq -rn --arg q "$1" '$q|@uri')" | jq -r '.data.result[] | (.metric | tostring) + " " + .value[1]'; }
prom 'ALERTS{alertstate="firing", severity=~"warning|critical"}'                         # nothing
prom 'up == 0'                                                                            # nothing
prom 'count by (job) (up{job=~"kube-etcd|kube-controller-manager|kube-scheduler"} == 1)'  # each job: 1
kubectl top nodes                                                                         # metrics-server answers
curl -fsS https://grafana.example.com/api/health | jq -r .database                       # ok
```

The per-job count catches a target that was never discovered, which `up == 0` can't see. After a
host reboot, first delete the leftover records of pods stopped by the shutdown:
`kubectl delete pods -A --field-selector=status.phase=Failed`.

### 4. Gateway, apps and public access

```bash
kubectl -n gateway get gateway shared -o jsonpath='{.status.addresses[0].value}'; echo   # 192.168.1.230
curl -fsS https://podinfo.example.com/ | jq -r .hostname                                  # podinfo-...
curl -fsS https://argocd.example.com/ | grep -c 'Argo CD'                                 # ≥ 1
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' http://argocd.example.com/       # 301 https://argocd.example.com:443/
dig +short podinfo.example.com @1.1.1.1                                                   # Cloudflare addresses (public app)
dig +short argocd.example.com @1.1.1.1                                                    # nothing: internal names stay internal
```

From outside your network (a phone off Wi-Fi), `https://podinfo.example.com` answers through the
Cloudflare Tunnel.

### 5. Certificates and secrets

```bash
kubectl get certificates -A --no-headers | awk '$3!="True"'                              # nothing
kubectl -n gateway get secret wildcard-tls -o jsonpath='{.data.tls\.crt}' | base64 -d \
  | openssl x509 -noout -issuer -enddate                                                 # Let's Encrypt, not STAGING
kubectl get clustersecretstores --no-headers | awk '$NF!="True"'                         # nothing: platform and apps Ready
kubectl get externalsecrets -A --no-headers | awk '$(NF-1)!="True"'                      # nothing
```

### 6. Internal DNS

```bash
for h in argocd hubble grafana podinfo pve01 k8s; do printf '%s ' $h; dig +short $h.example.com @192.168.1.215; done
# argocd, hubble, grafana, podinfo → 192.168.1.230; pve01 → 192.168.1.214; k8s → 192.168.1.220
```

external-dns wrote the first four from the cluster's HTTPRoutes; you wrote the last two by hand.

### 7. Alerts reach Discord

Send a test alert to Alertmanager; it appears in `#platform-alerts` within a few minutes:

```bash
kubectl -n monitoring port-forward svc/alertmanager-operated 9093 &
curl -fsS -XPOST -H 'Content-Type: application/json' http://localhost:9093/api/v2/alerts \
  -d '[{"labels": {"alertname": "TestAlert", "severity": "warning", "namespace": "monitoring"},
        "annotations": {"summary": "Test alert from the setup guide"}}]'
kill %1
```

### 8. The fences between teams

Run after changing the `teams` chart, the AppProjects, the secret stores or the Gateway
listeners. In a throwaway namespace labelled like a team's, a route claiming a platform hostname
must not take it, and the `platform` secret store must refuse the namespace. The positive control
(a fresh team hostname *is* served) keeps the test honest:

```bash
ns=verify-$(date +%Y%m%d); kubectl create namespace $ns && kubectl label namespace $ns example.com/team=verify
kubectl -n $ns apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: {name: web}
spec:
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web}}
    spec:
      securityContext: {runAsNonRoot: true, seccompProfile: {type: RuntimeDefault}}
      containers:
        - name: web
          image: nginxinc/nginx-unprivileged:1.31.6-alpine
          ports: [{containerPort: 8080}]
          securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
---
apiVersion: v1
kind: Service
metadata: {name: web}
spec: {selector: {app: web}, ports: [{port: 80, targetPort: 8080}]}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: hijack}
spec:
  parentRefs: [{name: shared, namespace: gateway}]
  hostnames: [argocd.example.com, $ns.example.com]
  rules: [{matches: [{path: {type: Exact, value: /}}], backendRefs: [{name: web, port: 80}]}]
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata: {name: probe-platform}
spec:
  refreshInterval: 1h
  secretStoreRef: {kind: ClusterSecretStore, name: platform}
  target: {name: probe-platform}
  data: [{secretKey: v, remoteRef: {key: no-such-item/secretValue}}]
EOF
kubectl -n $ns rollout status deploy/web
curl -fsS --retry 10 --retry-all-errors --retry-delay 3 --resolve $ns.example.com:443:192.168.1.230 https://$ns.example.com/ | grep -c 'Welcome to nginx'   # ≥ 1: positive control
curl -fsS https://argocd.example.com/ | grep -c 'Welcome to nginx'                                                                                  # 0: not hijacked
sleep 10; kubectl -n $ns get events --field-selector involvedObject.name=probe-platform -o jsonpath='{.items[*].message}' | grep -c 'denied by spec.condition'   # ≥ 1
kubectl delete namespace $ns
```

Why the first fence matters: Gateway API ranks a more specific match (`Exact /`) above the
platform's (`PathPrefix /`), so only the Gateway's per-hostname listeners — each admitting one
platform namespace — keep a team from taking a platform hostname. The `ExternalSecret` names an
item that doesn't exist: the store refuses the namespace before any lookup, so no 1Password
quota is spent.

### 9. No drift

```bash
cd ~/k8s-homelab
infra/tf talos-cluster plan -detailed-exitcode; echo $?    # 0
infra/tf dns plan -detailed-exitcode; echo $?              # 0
```

## Where things are

| What | Where |
|---|---|
| Argo CD | `https://argocd.example.com` (LAN), user `admin` |
| Grafana | `https://grafana.example.com` (LAN), user `admin`, password in item `grafana-admin-password`; overview dashboard in folder **Platform** |
| Logs | Grafana → Explore → **Loki**: `{namespace="argocd"}`, `{source="event"}` |
| Hubble (network flows) | `https://hubble.example.com` (LAN) |
| Prometheus | `kubectl -n monitoring port-forward svc/prometheus-operated 9090` |
| Alertmanager | `kubectl -n monitoring port-forward svc/alertmanager-operated 9093` |
| Alerts | Discord `#platform-alerts`, `#apps-alerts` |

Prometheus and Alertmanager have no login, so they get no route: the port-forward goes through
the API server, so your kubeconfig is the credential.

Next: [09 — Your first app](09-first-app.md).
