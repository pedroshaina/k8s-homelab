# 03 — Proxmox

**What you'll have at the end:** Proxmox VE on the host with a trusted Let's Encrypt
certificate, least-privilege users for OpenTofu and for the cluster's storage driver, and host
settings that keep a single machine stable under load.

## Steps

### 1. Install Proxmox VE

Install from the [Proxmox VE ISO](https://www.proxmox.com/en/downloads) with the host's address
(`192.168.1.214/24`, gateway `192.168.1.1`) and hostname `pve01.example.com`. The defaults are
what the code expects: bridge `vmbr0`, storage `local` (files) and `local-lvm` (VM disks).

Let storage `local` hold VM disk images to import (Talos) and container templates (`dns01`):

```bash
ssh root@192.168.1.214 'pvesm set local --content iso,vztmpl,backup,import'
```

Add an SSH alias so `ssh pve01` works without DNS, and copy your key:

```bash
printf 'Host pve01\n  HostName 192.168.1.214\n  User root\n' >> ~/.ssh/config
ssh-copy-id pve01
```

### 2. Users and roles

Least privilege: OpenTofu and the storage driver each get their own user with only the
privileges they use. Run on the host (`ssh pve01`); every command is safe to re-run.

1. **OpenTofu** — role `TofuProvisioner` on `/`, user `tofu@pve`:
   ```bash
   P=Datastore.AllocateSpace,Datastore.AllocateTemplate,Datastore.Audit,SDN.Audit,SDN.Use,Sys.Audit,Sys.Modify,VM.Allocate,VM.Audit,VM.PowerMgmt,VM.GuestAgent.Audit,VM.Config.CDROM,VM.Config.CPU,VM.Config.Cloudinit,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options
   pveum role add TofuProvisioner --privs "$P" 2>/dev/null || pveum role modify TofuProvisioner --privs "$P"
   pveum user add tofu@pve --comment "OpenTofu (k8s-homelab)" 2>/dev/null || true
   pveum acl modify / --users tofu@pve --roles TofuProvisioner
   ```
2. **Image datastore** — role `TofuImageDatastore` on `/storage/local` adds `Datastore.Allocate`
   so OpenTofu can delete images it downloaded. A role on a deeper path *replaces* what is
   inherited from `/` for that path, so it repeats the other datastore privileges:
   ```bash
   P=Datastore.Allocate,Datastore.AllocateSpace,Datastore.AllocateTemplate,Datastore.Audit
   pveum role add TofuImageDatastore --privs "$P" 2>/dev/null || pveum role modify TofuImageDatastore --privs "$P"
   pveum acl modify /storage/local --users tofu@pve --roles TofuImageDatastore
   ```
3. **Storage driver** (Proxmox CSI, chapter 07) — role `KubernetesCSI` on VMs and `local-lvm`
   only, user `kubernetes-csi@pve`:
   ```bash
   P=VM.Audit,VM.Config.Disk,Datastore.Allocate,Datastore.AllocateSpace,Datastore.Audit
   pveum role add KubernetesCSI --privs "$P" 2>/dev/null || pveum role modify KubernetesCSI --privs "$P"
   pveum user add kubernetes-csi@pve --comment "Kubernetes Proxmox CSI plugin" 2>/dev/null || true
   pveum acl modify /vms --users kubernetes-csi@pve --roles KubernetesCSI
   pveum acl modify /storage/local-lvm --users kubernetes-csi@pve --roles KubernetesCSI
   ```
4. **OpenTofu's API token**, in your own terminal (the secret is shown once):
   ```bash
   ssh pve01 'pveum user token add tofu@pve homelab --privsep 0'
   ```
   Put `tofu@pve!homelab=<value>` into `infra/secrets.sops.yaml` as `PROXMOX_VE_API_TOKEN`
   (`sops infra/secrets.sops.yaml`).

If a later `apply` fails with `403 ... Permission check failed (..., <Privilege>)`, add that
privilege to `TofuProvisioner` (step 1 with the longer list).

### 3. Host tuning

A single host running everything sits under sustained load. Three settings keep it stable: CPU
boost off (thermal headroom), a hardware watchdog that resets the host if the kernel freezes,
and reboot on kernel panic. Run on `pve01` as root.

1. CPU boost off:
   ```bash
   cat > /etc/systemd/system/cpu-boost-off.service <<'UNIT'
   [Unit]
   Description=Disable CPU boost (thermal headroom)

   [Service]
   Type=oneshot
   ExecStart=/bin/sh -c "echo 0 > /sys/devices/system/cpu/cpufreq/boost"
   RemainAfterExit=yes

   [Install]
   WantedBy=multi-user.target
   UNIT
   systemctl daemon-reload && systemctl enable --now cpu-boost-off.service
   ```
2. Hardware watchdog. The module depends on the board: `sp5100_tco` on AMD, usually `iTCO_wdt`
   on Intel. Proxmox deny-lists watchdog modules (its HA stack manages them), so a unit loads
   it explicitly; then systemd pings it every 30 s:
   ```bash
   WDT=sp5100_tco      # or iTCO_wdt on Intel
   cat > /etc/systemd/system/hw-watchdog.service <<UNIT
   [Unit]
   Description=Load the hardware watchdog module
   DefaultDependencies=no
   Before=sysinit.target

   [Service]
   Type=oneshot
   ExecStart=/sbin/modprobe $WDT
   RemainAfterExit=yes

   [Install]
   WantedBy=sysinit.target
   UNIT
   systemctl daemon-reload && systemctl enable --now hw-watchdog.service
   mkdir -p /etc/systemd/system.conf.d
   printf '[Manager]\nRuntimeWatchdogSec=30s\nRebootWatchdogSec=10min\n' > /etc/systemd/system.conf.d/watchdog.conf
   systemctl daemon-reexec
   ```
3. Reboot on panic:
   ```bash
   printf 'kernel.panic = 10\nkernel.hardlockup_panic = 1\n' > /etc/sysctl.d/90-panic-reboot.conf
   sysctl -q -p /etc/sysctl.d/90-panic-reboot.conf
   ```

### 4. A trusted certificate

OpenTofu and the storage driver verify Proxmox's TLS certificate, so Proxmox gets one from
Let's Encrypt through its built-in ACME client and the Cloudflare DNS plugin; it renews itself
daily. Try Let's Encrypt **staging** first (generous rate limits), then production.

1. Copy the `proxmox-acme` token to the host, over stdin into a root-only file:
   ```bash
   cd ~/k8s-homelab
   sops exec-env infra/secrets.sops.yaml 'printf "CF_Token=%s\n" "$PROXMOX_ACME_CF_TOKEN"' \
     | ssh pve01 'umask 077; cat > /root/.acme-cloudflare.data'
   ```
2. On `pve01`, run with the staging values, check (step 3), then run again with production:
   ```bash
   ACCOUNT=homelab-staging DIR=https://acme-staging-v02.api.letsencrypt.org/directory   # staging
   # ACCOUNT=homelab DIR=https://acme-v02.api.letsencrypt.org/directory                 # production
   EMAIL=you@example.com
   pvenode acme account list | grep -qx "$ACCOUNT" \
     || printf 'y\n' | pvenode acme account register "$ACCOUNT" "$EMAIL" --directory "$DIR"
   pvenode acme plugin set cloudflare --api cf --data /root/.acme-cloudflare.data 2>/dev/null \
     || pvenode acme plugin add dns cloudflare --api cf --data /root/.acme-cloudflare.data
   pvenode config set --acme account="$ACCOUNT" --acmedomain0 "pve01.example.com,plugin=cloudflare"
   pvenode acme cert order --force 1
   ```
   After the production order: `rm -f /root/.acme-cloudflare.data`.
3. `pve01.example.com` resolves only through the internal DNS server you build in chapter 04.
   Until then, add a temporary entry on the workstation (chapter 04 removes it):
   ```bash
   echo '192.168.1.214 pve01.example.com' | sudo tee -a /etc/hosts
   ```

## Check

```bash
ssh pve01 'pveum acl list'      # the ACLs of step 2: /, /storage/local, /vms, /storage/local-lvm
ssh pve01 'cat /sys/devices/system/cpu/cpufreq/boost; ls /dev/watchdog0; sysctl kernel.panic'
# 0   /dev/watchdog0   kernel.panic = 10
ssh pve01 'openssl x509 -noout -issuer -in /etc/pve/local/pveproxy-ssl.pem'
# issuer=... Let's Encrypt ... (without STAGING once production is ordered)
curl -sS -o /dev/null -w '%{http_code}\n' https://pve01.example.com:8006/    # 200: a trusted certificate
```

After the next host reboot, `ssh pve01 'journalctl -b | grep "Using hardware watchdog"'` must
show the watchdog; without it nothing resets a frozen host.

## Alternatives

- **Thermals:** if your host stays cool under load, keep CPU boost on; the watchdog and panic
  settings are worth keeping regardless.

Next: [04 — Internal DNS server](04-dns-server.md).
