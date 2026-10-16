# 06 — Secrets in 1Password

**What you'll have at the end:** every secret the cluster needs, stored in 1Password, and two
read-only service accounts that External Secrets Operator (ESO) will use to copy them into
Kubernetes Secrets. Nothing secret is ever committed in plaintext.

**How it fits together:** ESO runs in the cluster with a `ClusterSecretStore` per vault. The
`platform` store reads vault `k8s-platform` and only platform namespaces may use it; the `apps`
store reads vault `k8s-apps` and only team `apps`' namespaces may use it. Each
`ExternalSecret` in Git names an item and a field; ESO creates the Secret and refreshes it every
hour. The only credential that can't come from 1Password is the token to read 1Password itself
("secret zero"): it is encrypted with SOPS in chapter 07.

## Steps

### 1. Vaults and service accounts

In 1Password:

1. Create two vaults: `k8s-platform` and `k8s-apps`.
2. Developer → Service accounts: create `k8s-platform-eso` with **read** access to
   `k8s-platform` only, and `k8s-apps-eso` with **read** access to `k8s-apps` only; no expiry.
   Each token is shown once: keep `k8s-platform-eso`'s in your private vault (chapter 07 needs
   it) and put `k8s-apps-eso`'s into item `apps-svc-acc-token` (step 2).

### 2. Items in `k8s-platform`

Each item holds one **concealed** field with the name shown. Concealed fields flatten newlines,
so store every value on a single line.

| Item | Field | Value | Ends up as |
|---|---|---|---|
| `cert-manager-cloudflare-api-token` | `api-token` | Cloudflare token `cert-manager` (chapter 02) | `cert-manager/cloudflare-api-token` |
| `external-dns-public-cloudflare-api-token` | `api-token` | Cloudflare token `external-dns-public` (chapter 02) | `external-dns-public/cloudflare-api-token` |
| `cloudflared-credentials` | `credentials.json` | the tunnel credentials, one line (chapter 02) | `cloudflared/credentials` |
| `external-dns-tsig` | `secretValue` | `TSIG_EXTERNAL_DNS_SECRET` (chapter 04) | `external-dns/tsig` |
| `proxmox-csi-api-token` | `secretValue` | the storage driver's Proxmox token (step 3) | `csi-proxmox/config` |
| `grafana-admin-password` | `secretValue` | a new password for Grafana's `admin` | `monitoring/grafana-admin-password` |
| `platform-alerts-discord-webhook-uri` | `secretValue` | webhook URL of `#platform-alerts` (step 4) | `monitoring/platform-alerts-discord-webhook-uri` |
| `apps-alerts-discord-webhook-uri` | `secretValue` | webhook URL of `#apps-alerts` (step 4) | `monitoring/apps-alerts-discord-webhook-uri` |
| `apps-svc-acc-token` | `secretValue` | the `k8s-apps-eso` token (step 1) | `external-secrets/apps-svc-acc-token` |

The last one is how a team gets its own store: the platform delivers the team's token into
`external-secrets`, where the team can use the store but never read the credential.

### 3. The storage driver's Proxmox token

In your own terminal, straight to the clipboard (it is printed once):

```bash
ssh pve01 'pveum user token add kubernetes-csi@pve csi --privsep 0 --output-format json' \
  | jq -r .value | tr -d '\n' | pbcopy
# paste into proxmox-csi-api-token → secretValue, then clear the clipboard: pbcopy < /dev/null
```

### 4. Discord webhooks

In your Discord server: channel settings → Integrations → Webhooks → New Webhook, one for
`#platform-alerts` and one for `#apps-alerts`. Copy each URL into its item: anyone holding the
URL can post to the channel.

### 5. Team secrets (later)

Apps get their own secrets from vault `k8s-apps`. Convention: item `apps-<app>-<secret>`, read by
an `ExternalSecret` in the app's folder that uses `ClusterSecretStore/apps` (chapter 09).

## Check

```bash
brew install --cask 1password-cli   # if missing
op signin
op item list --vault k8s-platform --format json | jq -r '.[].title' | sort
# apps-alerts-discord-webhook-uri, apps-svc-acc-token, cert-manager-cloudflare-api-token,
# cloudflared-credentials, external-dns-public-cloudflare-api-token, external-dns-tsig,
# grafana-admin-password, platform-alerts-discord-webhook-uri, proxmox-csi-api-token
```

**Quota:** service accounts share a rate limit (on an individual plan, 1,000 requests a day).
Every `ExternalSecret` refreshes hourly, and a failing one retries and burns quota: fix or delete
it rather than leaving it broken. Check usage with
`op service-account ratelimit k8s-platform-eso`.

## Alternatives

- **Another secret backend:** ESO supports Bitwarden, HashiCorp Vault, AWS/GCP/Azure secret
  managers and more; change the two `ClusterSecretStore`s
  (`platform-gitops/components/external-secrets-config/`, `components/teams/templates/teams.yaml`)
  and keep every `ExternalSecret` as it is (item and field names map to the backend's keys).

Next: [07 — Argo CD and the platform](07-argocd.md).
