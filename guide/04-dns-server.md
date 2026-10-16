# 04 — Internal DNS server

**What you'll have at the end:** `dns01`, a small Technitium DNS server in a Proxmox container
that answers for your domain inside the LAN, and a workstation that asks it for those names.

**Why split-horizon DNS:** internal names (`pve01`, `argocd`, `grafana`, …) must never appear in
public DNS. Cloudflare holds only the public apps; `dns01` holds the internal zone. external-dns,
running in the cluster, adds a record here for every web hostname the cluster serves, using a
TSIG key (a shared secret that signs DNS updates).

## Steps

### 1. The container and its secrets

```bash
cd ~/k8s-homelab
infra/tf dns init
infra/tf dns apply          # container 215 at 192.168.1.215, Debian 13
```

`infra/tf <module> <args>` runs `tofu` in that module with the secrets file decrypted into its
environment. Never run `tofu` directly for plan or apply.

In your own terminal, add two secrets with `sops infra/secrets.sops.yaml`:

- `TECHNITIUM_ADMIN_PASSWORD`: a new password for the DNS console (keep a copy in 1Password).
- `TSIG_EXTERNAL_DNS_SECRET`: `openssl rand -base64 32`. Keep a copy: chapter 06 stores the same
  value for the cluster.

### 2. Install Technitium

On `dns01` (`ssh root@192.168.1.215`), install the pinned release and check its SHA-256:

```bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq curl ca-certificates
curl -fsSL -o /tmp/packages-microsoft-prod.deb https://packages.microsoft.com/config/debian/13/packages-microsoft-prod.deb
dpkg -i /tmp/packages-microsoft-prod.deb && apt-get update -qq && apt-get install -y -qq aspnetcore-runtime-10.0
curl -fsSL -o /tmp/technitium.tgz https://download.technitium.com/dns/archive/15.5.1/DnsServerPortable.tar.gz
echo "a8013547b47719bb5868f30c6748539f56b0e343579b3df3da26af8f9bad067f  /tmp/technitium.tgz" | sha256sum -c   # OK
mkdir -p /opt/technitium/dns /etc/dns /var/log/technitium/dns
tar -xzf /tmp/technitium.tgz -C /opt/technitium/dns && echo 15.5.1 > /opt/technitium/dns/.version
id dns-server >/dev/null 2>&1 || useradd --system -M --shell /usr/sbin/nologin --user-group dns-server
chown -R dns-server:dns-server /opt/technitium/dns /etc/dns /var/log/technitium/dns
systemctl disable --now systemd-resolved 2>/dev/null || true   # port 53 must be free
cp /opt/technitium/dns/systemd.service /etc/systemd/system/dns.service
systemctl daemon-reload && systemctl enable dns.service && systemctl restart dns.service
curl -fsS --retry 15 --retry-connrefused --retry-delay 2 -o /dev/null http://127.0.0.1:5380/ && echo running
```

### 3. Configure it

The web console listens on the LAN with a default password until you lock it down, so do a and
b first. Open a tunnel: `ssh -L 5380:127.0.0.1:5380 root@192.168.1.215`, then browse to
`http://localhost:5380`.

- a. Log in as `admin` / `admin` and change the password to `TECHNITIUM_ADMIN_PASSWORD`.
- b. Settings → Web Service: local addresses `127.0.0.1` only. Save. From now on the console is
  reachable only through the SSH tunnel, so the password never crosses the LAN.
- c. Settings → Recursion: **Allow recursion only for private networks**.
- d. Settings → Blocking (optional): enable, block list URL
  `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts`.
- e. Settings → TSIG: add key `external-dns`, algorithm `hmac-sha256`, secret
  `TSIG_EXTERNAL_DNS_SECRET`.
- f. Zones → add a **Primary** zone `example.com`, then A records (TTL 300):
  `pve01` → `192.168.1.214`, `dns01` → `192.168.1.215`, `k8s` → `192.168.1.220`,
  `talos-cp-01` → `192.168.1.221`.
- g. Zone options → Dynamic Updates: **Allow**, security policy: key `external-dns`, domain
  `*.example.com`, types `A, AAAA, TXT, CNAME`. Zone Transfer: **Allow**, TSIG key
  `external-dns` only.

### 4. The workstation asks `dns01` for your domain

Only names under your domain go to `dns01`; everything else keeps using the router.

```bash
# macOS
sudo mkdir -p /etc/resolver
echo 'nameserver 192.168.1.215' | sudo tee /etc/resolver/example.com
# Linux with systemd-resolved: resolvectl dns <interface> 192.168.1.215; resolvectl domain <interface> '~example.com'
```

Remove the temporary `pve01.example.com` line from `/etc/hosts` (chapter 03).

## Check

```bash
dig +short pve01.example.com @192.168.1.215       # 192.168.1.214
dig AXFR example.com @192.168.1.215               # Transfer failed: unsigned transfers refused
printf 'server 192.168.1.215\nzone example.com\nupdate add x.example.com 60 A 192.0.2.1\nsend\n' | nsupdate   # REFUSED
dscacheutil -q host -a name pve01.example.com     # macOS: ip_address: 192.168.1.214 (dig ignores /etc/resolver)
# Linux: resolvectl query pve01.example.com       # 192.168.1.214
infra/tf dns plan -detailed-exitcode; echo $?     # 0: no drift
```

**If `dns01` is down:** names under your domain stop resolving on the workstation (the cluster
keeps working: its node falls back to the router and has static entries for `pve01` and `k8s`).
OpenTofu needs `pve01.example.com`, so put the `/etc/hosts` line back before any `infra/tf`
command, restart the container (`ssh pve01 'pct start 215'`), and remove the line afterwards.

## Alternatives

- **Another DNS server:** anything that supports RFC 2136 dynamic updates with TSIG works with
  external-dns (BIND, PowerDNS); Pi-hole and AdGuard Home don't.

Next: [05 — The Kubernetes cluster](05-cluster.md).
