{{/*
Teams with their own channel: an alertsWebhook and at least one app. A team without apps would
render namespace=~"" — which matches alerts with no namespace (nodes, etcd) and would steal them
from the platform channel — so it gets no route. Webhook names must be Secret names.
*/}}
{{- define "alert-routing.teams" -}}
{{- $out := list -}}
{{- range .Values.teams -}}
  {{- if .alertsWebhook -}}
    {{- if not (regexMatch "^[a-z0-9]([-a-z0-9]{0,251}[a-z0-9])?$" .alertsWebhook) -}}
      {{- fail (printf "team %q: alertsWebhook must be a Secret name (the 1Password item), not %q" .name .alertsWebhook) -}}
    {{- end -}}
    {{- if .apps -}}{{- $out = append $out . -}}{{- end -}}
  {{- end -}}
{{- end -}}
{{- toYaml $out -}}
{{- end -}}
