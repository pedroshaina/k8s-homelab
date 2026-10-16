# 10 — Releasing your own apps

**What you'll have at the end:** a template repository for your apps, a GitHub App that is the
release identity, and a first app whose every merge to `main` is tested, built, pushed to GHCR,
pinned in `apps-gitops` and deployed by Argo CD — with no manual step and no long-lived
credential that can write to the cluster's repositories.

```
app repo: pull request → review → merge to main
  └─ release workflow (one release at a time per repository, in merge order)
      1. test     the app's tests
      2. build    one job per image → ghcr.io/your-github-user/<image>:<commit sha>
      3. promote  GitHub App token (1 hour, apps-gitops only)
                  → kustomize edit set image <image>:<sha>@<digest> in apps/<app>/kustomization.yaml
                  → commit "release(<app>): <sha7>" as your-release-app[bot] → push to main
apps-gitops main → Argo CD syncs apps/<app>/ → the node pulls the private image with its own token
```

**Why a GitHub App:** the release job needs to write to `apps-gitops`. A GitHub App installed on
that one repository mints a token that expires within an hour and can't reach anything else; its
commits are clearly attributed to the bot. Pinning by digest means what runs is exactly what Git
names, and a rollback is a `git revert`.

## Steps

### 1. The template repository

```bash
cp -R ~/k8s-homelab/app-template ~/app-template
cd ~/app-template && git init -q -b main && git add -A && git commit -qm "Initial commit"
gh repo create app-template --private --source . --push
gh repo edit app-template --template
```

Its `promote` job is skipped in the template repository itself, so the template never releases.

### 2. The GitHub App

1. GitHub → Settings → Developer settings → GitHub Apps → **New GitHub App**. Name: something
   unique such as `alice-apps-release` (it replaces `your-release-app` in the docs). Homepage
   URL: the template repository. **Webhook: Active off** (the App is an identity, it receives no
   events). Repository permissions: **Contents: Read and write**, nothing else. "Only on this
   account". Create.
2. Note the **Client ID** (an identifier, not a secret). **Generate a private key**: a `.pem`
   downloads. Store it in 1Password, then delete the download.
3. **Install App** → Only select repositories → **`apps-gitops`**. Never widen it: the App can
   write any folder of the repositories it's installed on.

### 3. A new app from the template

Pick the app's name (chapter 09: it's also the folder, namespace and hostname). Here: `myapp`.

1. GitHub → New repository → template `app-template` → name `myapp`. Private works: the node
   pulls private images with its own GHCR token (chapter 05).
2. Replace the placeholder app (`main.go`, `go.mod`, `Dockerfile`) with yours, keeping the
   deployment contract in its `README.md`: `/health` and `/ready`, clean shutdown on `SIGTERM`,
   JSON logs, non-root, `linux/amd64`.
3. In `.github/workflows/release.yaml`, edit only the two CONFIG blocks — `APP: myapp` and one
   `image` entry per image (`{name: myapp, context: ., file: Dockerfile, build-args: ""}`) — and
   replace the `test` job's steps with your tests.
4. The release credentials (templates don't copy secrets):
   ```bash
   gh variable set RELEASE_APP_CLIENT_ID --repo alice/myapp --body <Client ID>
   gh secret set RELEASE_APP_PRIVATE_KEY --repo alice/myapp < <path to the .pem>
   ```
5. Open a pull request with these changes: its run tests and builds without pushing. Don't merge
   yet.

### 4. The app's folder in `apps-gitops`

A pull request adding `apps/myapp/` with a Deployment, a Service and an HTTPRoute (copy podinfo's
and adapt: the template app listens on `8080` and runs as user `65532`). Name your own images
**without a tag** — the release pins them:

```yaml
          image: ghcr.io/alice/myapp     # no tag: the release pins it in kustomization.yaml
```

```bash
cd apps/myapp && kustomize create --resources "$(ls *.yaml | paste -sd, -)"
```

There is no `images:` entry yet: the first release adds it. Merge. Nothing deploys: the app isn't
onboarded.

### 5. The first release, then onboarding

1. Merge the app's pull request from step 3. Its run tests, builds and pushes
   `ghcr.io/alice/myapp:<sha>`, then commits `release(myapp): <sha7>` to `apps-gitops`.
2. Add `- {name: myapp}` under team `apps` in `platform-gitops` `components/teams/values.yaml`,
   pull request, merge. Argo CD deploys the app, already pinned.

This order means the cluster never sees an app without exact image versions.

## Check

```bash
cd ~/apps-gitops && git pull -q
git log -1 --format='%an | %s' -- apps/myapp      # your-release-app[bot] | release(myapp): <sha7>
yq '.images' apps/myapp/kustomization.yaml        # newTag: <sha>, digest: sha256:...
kubectl -n argocd annotate application myapp argocd.argoproj.io/refresh=hard --overwrite
kubectl -n myapp get pods -o jsonpath='{.items[*].spec.containers[*].image}'; echo   # ghcr.io/alice/myapp:<sha>@sha256:...
curl -s https://myapp.example.com/                # hello from app-template
```

From now on every merge to the app's `main` is a release, about five minutes end to end.

## Rolling back, pausing, troubleshooting

- **Roll back:** first make sure no newer release of the app is queued or running
  (`gh run list --repo alice/myapp --workflow release.yaml --limit 5`), or it would land after
  your revert. Then revert the `release(myapp)` commit in `apps-gitops` through a pull request.
  The old images are still in GHCR and on the node, so the rollback builds nothing and takes
  well under a minute. Fix forward in the app repository; the next merge releases again. A
  database migration that already ran is not undone.
- **Pause:** `gh workflow disable release.yaml --repo alice/myapp` (and `enable` to resume).
  Meanwhile, release by hand with `kustomize edit set image` in a pull request to `apps-gitops`.
- **A release didn't arrive** — follow the path; the first step that looks wrong is where it
  stopped:
  1. The run (`gh run list --repo alice/myapp --workflow release.yaml`): red `test` or `build`
     means nothing changed in the cluster.
  2. The `promote` step (`gh run view <id> --log-failed`): a failing token step means the App's
     key, Client ID or installation is wrong; `kustomization.yaml is missing` or `no manifest
     uses <image>` means the folder or the `image:` field doesn't match the workflow's image list.
  3. `apps-gitops`: the release commit is on `main`.
  4. Argo CD: `kubectl -n argocd get application myapp` shows that revision, Synced and Healthy.
  5. The pull: `ImagePullBackOff` with `401`/`403` means the node's GHCR token expired or lost
     `read:packages` (chapter 11).

  Re-run a failed release only if it is the latest release run of that repository: re-running an
  older one pins older images again — a silent rollback.

## Alternatives

- **Image Updater instead of commits:** Argo CD Image Updater or Flux's image automation can
  watch the registry and write the pins; the pipeline here keeps the decision in the app's CI,
  where the tests run.

Next: [11 — Day 2](11-day-2.md).
