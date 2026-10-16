{{- /* Never published, whatever the onboarding file says: platform hostnames (the non-wildcard
   Gateway listeners) and static infrastructure records. The teams chart refuses these names too;
   this is the second, independent check. Keep it in sync with gateway.yaml by hand (not checked). */ -}}
{{- define "public-apps.reserved" -}}argocd grafana hubble pve01 k8s dns01 talos-cp-01 talos-cp-02 talos-cp-03{{- end -}}

{{- /* Hostnames of every app marked public: true, across all teams, in onboarding order. */ -}}
{{- define "public-apps.hosts" -}}
{{- $reserved := splitList " " (include "public-apps.reserved" .) -}}
{{- range .Values.teams }}{{ range .apps }}{{ if .public }}
{{- if has .name $reserved }}{{ fail (printf "%s.%s is a platform hostname and is never public" .name $.Values.zone) }}{{ end }}
{{- printf "%s.%s\n" .name $.Values.zone }}{{ end }}{{ end }}{{ end }}
{{- end -}}

{{- /* cloudflared config: an explicit hostname list, then a catch-all 404, so a hostname that
   isn't listed here is never served even if someone adds a public DNS record for it. */ -}}
{{- define "public-apps.config" -}}
tunnel: {{ .Values.tunnelId }}
credentials-file: /etc/cloudflared/creds/credentials.json
metrics: 0.0.0.0:2000
no-autoupdate: true
ingress:
{{- range splitList "\n" (include "public-apps.hosts" .) }}
{{- if . }}
  - hostname: {{ . }}
    service: {{ $.Values.gatewayService }}
    originRequest:
      originServerName: {{ . }}
{{- end }}
{{- end }}
  - service: http_status:404
{{- end -}}
