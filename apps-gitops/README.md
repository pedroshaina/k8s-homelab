# apps-gitops

Workloads of team **apps**. Each onboarded folder `apps/<app>/` becomes the Argo CD Application
`<app>` in the team's AppProject `apps`, deployed into namespace `<app>`. The platform creates the
namespace (Pod Security `restricted`) and allows the project to deploy only there.

Part of [k8s-homelab](https://github.com/your-github-user/k8s-homelab): copy this folder into its
own repository (guide chapter 01). The example app is `apps/podinfo/`.

**Rules:** `CLUSTER-POLICIES.md`: what the cluster enforces and the conventions every app follows,
adding and removing apps included.

**Checks:** `pre-commit install` runs kubeconform, yamllint and gitleaks on every commit.
`.github/workflows/ci.yaml` runs the same on every pull request, renders every Kustomize app,
runs promtool unit tests for each app's alert rules (`tests/rules/<app>/`) and gitleaks over the
full history. It needs no secrets or settings.

**Releases:** an app repository created from `app-template` pins its images in
`apps/<app>/kustomization.yaml` on every merge (guide chapter 10).
