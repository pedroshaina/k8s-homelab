# 02 — Cloudflare

**What you'll have at the end:** your domain's public DNS on Cloudflare, three API tokens (one
per consumer) and a Cloudflare Tunnel for public apps. Later chapters use them: Proxmox and
cert-manager get Let's Encrypt certificates through DNS-01 challenges, external-dns publishes
public records, and the tunnel carries internet traffic to the cluster with no port open at home.

## Steps

### 1. Move the domain's DNS to Cloudflare

1. Cloudflare dashboard → **Add a domain** → your domain → free plan. Choose **not** to import
   existing records: the public zone should only ever hold records for public apps, which
   external-dns writes later.
2. At your registrar, set the domain's nameservers to the two Cloudflare gives you.
3. SSL/TLS → Edge Certificates → **Always Use HTTPS**: on.

### 2. Three API tokens

One token per consumer, so each can be rotated or revoked alone. For each: Cloudflare → My
Profile → API Tokens → Create Token → template **Edit zone DNS** → Zone Resources: Include →
Specific zone → your domain.

| Token name | Consumer | Where the value goes |
|---|---|---|
| `cert-manager` | cert-manager: the cluster's wildcard certificate | 1Password, chapter 06 |
| `proxmox-acme` | Proxmox: its own web/API certificate | `infra/secrets.sops.yaml` key `PROXMOX_ACME_CF_TOKEN` |
| `external-dns-public` | external-dns: public records for public apps | 1Password, chapter 06 |

Put the Proxmox token in the secrets file now, in your own terminal (`sops
infra/secrets.sops.yaml`). Keep the other two in your private 1Password vault until chapter 06.

### 3. The tunnel

A locally-managed tunnel: `cloudflared` pods in the cluster dial out to Cloudflare, and Cloudflare
sends your public hostnames through that connection. Created once from the workstation:

```bash
brew install cloudflared
cloudflared tunnel login                 # opens the browser; pick your domain; writes ~/.cloudflared/cert.pem
cloudflared tunnel create homelab        # prints the tunnel ID and writes ~/.cloudflared/<ID>.json
```

- The **tunnel ID** is not a secret: put it in
  `~/platform-gitops/components/public-apps/values.yaml` (`tunnelId:`), commit and push.
- The **credentials file** `<ID>.json` is: store its content as one line
  (`tr -d '\n' < ~/.cloudflared/<ID>.json`) in your private 1Password vault for now; chapter 06
  moves it into the item the cluster reads. Keep `cert.pem` there too, then delete both files
  from disk.

## Check

```bash
dig NS example.com +short                     # the two Cloudflare nameservers (may take a few hours)
cloudflared tunnel list                       # homelab, no connections yet
```

## Alternatives

- **No public apps:** skip the tunnel and the `external-dns-public` token. In `platform-gitops`:
  remove `apps/public-apps.yaml` and `apps/external-dns-public.yaml`, set podinfo to
  `public: false` in `components/teams/values.yaml`, and remove the `cloudflared` rule group from
  `components/kube-prometheus-stack/rules/platform.yaml` together with its tests in
  `platform.test.yaml` (otherwise `CloudflaredTunnelDown` fires forever). In chapter 06, skip the
  items `cloudflared-credentials` and `external-dns-public-cloudflare-api-token`; in chapter 08,
  skip the public checks of item 4.
- **Another DNS provider:** cert-manager, external-dns and Proxmox ACME support many (Route 53,
  Google Cloud DNS, …); each needs its own credentials format.

Next: [03 — Proxmox](03-proxmox.md).
