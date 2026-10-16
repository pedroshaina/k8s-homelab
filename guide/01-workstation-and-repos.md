# 01 — Workstation and repositories

**What you'll have at the end:** the tools installed, your own copies of the repositories on
GitHub with your values in them, an age key for SOPS, a Cloudflare R2 bucket for OpenTofu state,
and an encrypted `infra/secrets.sops.yaml`.

The commands assume macOS with Homebrew and checkouts in your home directory (`~/k8s-homelab`,
`~/platform-gitops`, `~/apps-gitops`). On Linux, install the same tools from their release pages.

## Steps

### 1. Tools

Most tools come from Homebrew:

```bash
git clone <URL of this repository> ~/k8s-homelab
cd ~/k8s-homelab && brew bundle
brew install gh && gh auth login
```

Five tools are pinned to the versions the cluster runs, from their release pages. Download the
asset for your platform, check its SHA-256 against the release's checksum file, and install it
into a directory on your `PATH` (here `~/.local/bin`):

| Tool | Version | Why this version |
|---|---|---|
| [yq](https://github.com/mikefarah/yq/releases) | v4.54.1 | used by the bootstrap commands |
| [kubeconform](https://github.com/yannh/kubeconform/releases) | v0.8.0 | the pre-commit and CI version |
| [argocd](https://github.com/argoproj/argo-cd/releases) | v3.5.3 | same as the Argo CD server |
| [promtool](https://github.com/prometheus/prometheus/releases) (in the Prometheus archive) | v3.15.0 | same as the deployed Prometheus |
| [kustomize](https://github.com/kubernetes-sigs/kustomize/releases) | v5.8.1 | the version Argo CD bundles |

For example, on an Apple Silicon Mac:

```bash
mkdir -p ~/.local/bin && cd "$(mktemp -d)"
curl -fsSLO https://github.com/yannh/kubeconform/releases/download/v0.8.0/kubeconform-darwin-arm64.tar.gz
echo "f84f4dfbebf4a6b0b230385fa065a39ea35e02608c2b50d025dcf64775a69d67  kubeconform-darwin-arm64.tar.gz" | shasum -a 256 -c -   # OK
tar xzf kubeconform-darwin-arm64.tar.gz kubeconform && install -m 0755 kubeconform ~/.local/bin/
```

### 2. An age key for SOPS

SOPS encrypts secret values inside YAML files so they can live in Git; age is the key pair it
uses. The private key never leaves your machine; back it up in your password manager.

```bash
mkdir -p ~/.config/sops/age
[ -f ~/.config/sops/age/keys.txt ] || age-keygen -o ~/.config/sops/age/keys.txt
age-keygen -y ~/.config/sops/age/keys.txt     # your public key: age1...
# macOS: SOPS looks in Application Support, so point that path at the real key
mkdir -p ~/Library/Application\ Support/sops/age
ln -sf ~/.config/sops/age/keys.txt ~/Library/Application\ Support/sops/age/keys.txt
```

### 3. Make the code yours

Replace the example values that appear everywhere — your GitHub user, your domain and your age
public key — in one pass (`perl -pi` edits in place on macOS and Linux alike):

```bash
cd ~/k8s-homelab
GH_USER=alice                      # your GitHub user or organization
DOMAIN=alice.dev                   # your domain
AGE_PUB=age1...                    # the public key from step 2
grep -rlZ your-github-user . --exclude-dir=.git --exclude-dir=guide | xargs -0 perl -pi -e "s/your-github-user/$GH_USER/g"
grep -rlZ 'example\.com' . --exclude-dir=.git --exclude-dir=guide | xargs -0 perl -pi -e "s/example\.com/$DOMAIN/g"
grep -rlZ age1replace-with-your-public-key . --exclude-dir=.git --exclude-dir=guide | xargs -0 perl -pi -e "s/age1replace-with-your-public-key/$AGE_PUB/g"
```

If your network differs from the example plan (chapter 00), edit the addresses now:
`infra/talos-cluster/terraform.tfvars`, `infra/dns/terraform.tfvars`,
`platform-gitops/components/cilium-config/ip-pools.yaml`, and search for any other
`192.168.1.` with the `grep` from chapter 00. Also put your SSH public key in
`infra/dns/terraform.tfvars`.

### 4. Your repositories

You end up with four private repositories. Keeping the platform and the apps apart is a security
boundary: Argo CD lets team `apps` deploy only what its own repository holds, into its own
namespaces, so a team can never change the platform.

| Repository | From | Holds |
|---|---|---|
| `k8s-homelab` | this repository | OpenTofu code (`infra/`) and this guide; Argo CD reads Cilium's base values from it |
| `platform-gitops` | folder `platform-gitops/` | everything the cluster runs for the platform |
| `apps-gitops` | folder `apps-gitops/` | the manifests of team `apps`' applications |
| one per app | folder `app-template/` | an app's code and its release pipeline (chapter 10) |

```bash
cd ~/k8s-homelab
git remote remove origin
git add -A && git commit -m "Make it mine"
gh repo create k8s-homelab --private --source . --push

for r in platform-gitops apps-gitops; do
  cp -R ~/k8s-homelab/$r ~/$r
  (cd ~/$r && git init -q -b main && git add -A && git commit -qm "Initial commit" \
    && gh repo create $r --private --source . --push)
done
```

From now on you work in `~/platform-gitops` and `~/apps-gitops`; the folders of the same name
inside `k8s-homelab` stay behind as the reference copy.

Each GitOps repository carries a CI workflow (`.github/workflows/ci.yaml`) that runs the same
checks as pre-commit on every pull request. It needs no secrets: it starts working with the
first push. Work on branches and merge through pull requests: Argo CD applies `main` as soon as
it changes.

Install the pre-commit hooks in each checkout (yamllint, gitleaks, kubeconform, the OpenTofu
checks and a check that `*.sops.yaml` files are really encrypted):

```bash
for d in ~/k8s-homelab ~/platform-gitops ~/apps-gitops; do (cd $d && pre-commit install); done
```

### 5. R2 bucket for OpenTofu state

OpenTofu keeps a state file describing what it built. It lives in Cloudflare R2 (S3-compatible),
encrypted by OpenTofu with a passphrase, so you can work from any machine and never lose it.

1. Cloudflare dashboard → R2 → create a bucket (e.g. `alice-tf-state`).
2. R2 → Manage API tokens → create a token with **Object Read & Write** on that bucket only.
   Keep the Access Key ID and Secret Access Key in your password manager.
3. Note your Cloudflare **Account ID** (R2 overview page) and set both values in
   `infra/talos-cluster/versions.tf` and `infra/dns/versions.tf`:
   ```bash
   perl -pi -e 's/your-state-bucket/alice-tf-state/; s/your-r2-account-id/<account id>/' infra/*/versions.tf
   ```

### 6. The encrypted secrets file

Every credential OpenTofu and the guide's commands need sits in one SOPS-encrypted file. The
`infra/tf` wrapper decrypts it into the environment of a single `tofu` process; plaintext never
touches the disk. Create it **in your own terminal**:

```bash
cd ~/k8s-homelab
cp infra/secrets.example.yaml infra/secrets.sops.yaml
sops encrypt -i infra/secrets.sops.yaml     # encrypt the placeholders first...
sops infra/secrets.sops.yaml                # ...then fill in values in SOPS' editor
```

Fill in now: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (step 5) and `TF_VAR_state_passphrase`
(`openssl rand -base64 32`; keep a copy in your password manager — without it the state is
unreadable). The other keys get their values in later chapters; leave `replace-me` until then.

## Check

```bash
cd ~/k8s-homelab
sops decrypt infra/secrets.sops.yaml >/dev/null && echo decrypts      # decrypts
pre-commit run --all-files                                              # every hook Passed or Skipped
gh repo list --limit 10 | grep -E 'k8s-homelab|platform-gitops|apps-gitops'   # three private repos
```

## Alternatives

- **State backend:** any S3-compatible store (AWS S3, MinIO on a NAS) works by changing the
  `backend "s3"` block.
- **Secrets on the workstation:** SOPS also supports cloud KMS keys or PGP instead of age.

Next: [02 — Cloudflare](02-cloudflare.md).
