{{- /*
Refuses onboarding that would break isolation. Team names must not be a platform project; app
names become Application names in the argocd namespace (next to the platform's), namespace
names and hostnames (<app>.example.com), so they must be DNS labels, unique, and never a
platform Application, namespace or hostname (Gateway listeners, static infrastructure records).
Keep the reserved list in sync with apps/*.yaml by hand (nothing checks it).
*/ -}}
{{- define "teams.validate" -}}
{{- $reservedTeams := list "platform" "default" -}}
{{- $reservedApps := list "root" "teams" "argocd" "cilium" "cilium-config" "gateway-api-crds" "platform-routes" "proxmox-csi" "cert-manager" "cert-manager-config" "external-dns" "external-dns-public" "public-apps" "external-secrets" "external-secrets-config" "cilium-secrets" "csi-proxmox" "default" "gateway" "kube-node-lease" "kube-public" "kube-system" "cloudflared" "hubble" "pve01" "k8s" "dns01" "talos-cp-01" "talos-cp-02" "talos-cp-03" "prometheus-operator-crds" "kubelet-serving-cert-approver" "metrics-server" "kube-prometheus-stack" "alert-routing" "loki" "alloy" "monitoring" "grafana" -}}
{{- $seen := dict -}}
{{- range .Values.teams -}}
  {{- if has .name $reservedTeams -}}{{- fail (printf "team name %q is reserved" .name) -}}{{- end -}}
  {{- if not .repo -}}{{- fail (printf "team %q has no repo" .name) -}}{{- end -}}
  {{- range .apps -}}
    {{- if not (kindIs "map" .) -}}{{- fail (printf "app entries are objects {name, public}, not %q" (toString .)) -}}{{- end -}}
    {{- $name := .name | default "" -}}
    {{- if not $name -}}{{- fail "an app entry has no name" -}}{{- end -}}
    {{- if and (hasKey . "public") (not (kindIs "bool" .public)) -}}{{- fail (printf "app %q: public must be true or false" $name) -}}{{- end -}}
    {{- if not (regexMatch "^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$" $name) -}}{{- fail (printf "app %q is not a DNS label" $name) -}}{{- end -}}
    {{- if has $name $reservedApps -}}{{- fail (printf "app name %q is reserved by the platform" $name) -}}{{- end -}}
    {{- if hasKey $seen $name -}}{{- fail (printf "app %q is onboarded twice" $name) -}}{{- end -}}
    {{- $_ := set $seen $name true -}}
  {{- end -}}
{{- end -}}
{{- end -}}
