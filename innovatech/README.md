# Innovatech IaC
This folder documents all of the IaC that is in use at Innovatech. This stack should deploy the entire infrastructure from scratch with just a few commands.
Every command is idempotent so commands can be reran.
It is designed to run on a single Proxmox node for the lab environment, but everything in the k8s cluser should run on real nodes too.
## Bumping ARC Chart Versions

ARC's Helm charts (`gha-runner-scale-set-controller` and `gha-runner-scale-set`) are rendered
to static YAML and committed — they are not installed live with `helm install`/`helm upgrade`.
To pick up a new ARC release, re-render both charts and commit the diff.

### 1. Find the latest chart version

Check the release notes/tags on the ARC repo, or list available tags for the OCI package:

```bash
helm show chart oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
  --version <candidate-version>
```

Controller and runner-set charts are versioned together — bump both to the same version.

### 2. Update the pinned version

Update `--version` in the render commands (or the `Makefile`/script that wraps them, if you have one)
in both places:
- Controller render command
- Runner-set render command

### 3. Re-render

Pull each chart locally before templating — avoids Helm's OCI pull-status JSON leaking into
the rendered YAML when redirected to a file. The controller chart ships its CRDs in a
`crds/` directory, which `helm template` skips unless `--include-crds` is passed explicitly.

\`\`\`bash
helm pull oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
  --version <new-version> --untar --destination ./.chart-cache
helm template arc --namespace arc-systems \
  ./.chart-cache/gha-runner-scale-set-controller \
  --include-crds \
  > base/arc-controller.yaml

helm pull oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --version <new-version> --untar --destination ./.chart-cache
helm template arc-runner-set --namespace arc-runners \
  -f base/values/arc-runner-set.yaml \
  ./.chart-cache/gha-runner-scale-set \
  > base/arc-runner-set.yaml

rm -rf ./.chart-cache
\`\`\`



### 4. Review the diff

```bash
git diff base/arc-controller.yaml base/arc-runner-set.yaml
```

Check specifically for:
- Changed or new CRDs (may need to apply the controller file first on a rollout, see step 5)
- RBAC changes (new permissions the controller/listener requests)
- Changed default values that aren't overridden in `values/arc-runner-set.yaml`

### 5. Apply

\`\`\`bash
kubectl apply -f base/arc-namespaces.yaml

# ARC's CRDs embed a large OpenAPI schema that exceeds kubectl's 256KiB
# last-applied-configuration annotation limit under a normal apply.
# Server-side apply avoids the annotation entirely.
kubectl apply --server-side --force-conflicts -f base/arc-controller.yaml

kubectl apply -f base/arc-runner-set.yaml
\`\`\`

If you script the "apply twice" step from the ordering note above, use
\`kubectl apply --server-side --force-conflicts -f base/\` for both passes to avoid
re-hitting this on the controller file.

### 6. Verify

```bash
kubectl get pods -n arc-systems
kubectl get pods -n arc-runners
kubectl get autoscalingrunnerset -n arc-runners
```

Confirm the controller and listener pods are `Running` and the `AutoscalingRunnerSet` shows the
expected `minRunners`/`maxRunners` before considering the bump complete.