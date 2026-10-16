# bootstrap

Applied once by hand (guide chapter 07), never by Argo CD:

- `root.yaml` — the app-of-apps Application that watches `apps/`.
- `repo-k8s-homelab.sops.yaml`, `repo-platform-gitops.sops.yaml`, `repo-apps-gitops.sops.yaml` —
  read-only deploy keys, one per repository Argo CD reads.
- `platform-1password-svc-acc-token.sops.yaml` — the 1Password service-account token that External
  Secrets Operator uses for the `platform` store.

The four encrypted files are created by you in chapter 07; they are encrypted with your age key
(`.sops.yaml`) and never contain plaintext.
