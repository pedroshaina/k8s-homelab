# app-template

The release pipeline for your own apps. Create an app repository from this folder and it gets the
pipeline from its first commit. Part of
[k8s-homelab](https://github.com/your-github-user/k8s-homelab) (guide chapter 10).

## What this is

```
PR → review → merge to main
  → test, build and push every image to GHCR (tag = commit SHA)
  → release commit in apps-gitops: apps/<APP>/kustomization.yaml pins the new
    <image>:<sha>@sha256:<digest>
  → Argo CD deploys it
```

The release job (`promote` in `.github/workflows/release.yaml`) acts as a GitHub App (here
`your-release-app`): an identity, not a service. Each run exchanges the App's private key for a
1-hour token that can write to `apps-gitops` only, and its commits show as
`your-release-app[bot]`. Nothing runs outside GitHub Actions. Pull requests test and build the
images without pushing them. `.github/workflows/lint.yaml` checks the workflows themselves
(actionlint and shellcheck).

## New app checklist

1. Create a repository from this folder (or from your own template repository made from it).
   Public or private: private images are pulled with the cluster node's own GHCR credentials,
   nothing per app.
2. Replace the placeholder app (`main.go`) and the `Dockerfile`; keep the deployment contract
   (below).
3. In `.github/workflows/release.yaml`, edit only the two CONFIG blocks: `APP` (the app's folder
   in `apps-gitops`, which is also its onboarded name) and the `image` matrix (one entry per
   image, published as `ghcr.io/your-github-user/<name>`). Replace the `test` job's steps with
   your app's tests.
4. Settings → Secrets and variables → Actions: variable `RELEASE_APP_CLIENT_ID` and secret
   `RELEASE_APP_PRIVATE_KEY` (the App's Client ID and private key). Templates don't copy secrets
   or variables.
5. In `apps-gitops`, a pull request adding `apps/<APP>/`: the manifests, naming your images
   without tag (`image: ghcr.io/your-github-user/<name>`), and a `kustomization.yaml` made with
   the tool, from the folder:

   ```bash
   kustomize create --resources "$(ls *.yaml | paste -sd, -)"
   ```

   No `images:` entry yet: the first release adds it. Rules: that repository's
   `CLUSTER-POLICIES.md` (conventions 8, 11 and 12).
6. Merge to `main` here: the first release pins the images in that `kustomization.yaml`.
7. The onboarding line in `platform-gitops` `components/teams/values.yaml` — only now does Argo CD
   deploy the app, already pinned.

## Releasing, rolling back, pausing

- **Release:** merge to `main`. Releases of one repository run one at a time, in merge order; a
  newer pending release replaces an older pending one.
- **Roll back:** revert the release commit in `apps-gitops` (a pull request there). Then fix
  forward here; the next merge releases again. A database migration that already ran is not
  undone.
- **Pause:** Actions → release → Disable workflow. Release by hand meanwhile with
  `kustomize edit set image` in `apps-gitops`.
- **A release didn't arrive:** the run's summary lists the published images and the release
  commit; a red `promote` names the missing folder or image.

## Deployment contract

- `GET /health` (alive) and `GET /ready` (can serve traffic).
- Graceful shutdown on SIGTERM.
- JSON logs on stdout.
- Runs as a non-root user; `linux/amd64` images.
- Configuration through environment variables.

## Updating a copy

The header comments (`release v1`, `lint v1`) tell which template version a repository carries.
To update, copy the newer workflow and keep your CONFIG blocks and `test` steps.
