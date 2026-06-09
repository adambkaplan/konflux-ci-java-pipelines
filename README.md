# java-pipelines

Tekton catalog repository for Java build and release pipelines used in
[Konflux](https://konflux-ci.dev).

Coding agents: see [AGENTS.md](AGENTS.md) for conventions, guardrails, and validation
commands.

This repository follows the same OCI bundle delivery model as
[build-definitions](https://github.com/konflux-ci/build-definitions):

- **Tasks** are pushed to `quay.io/konflux-ci/tekton-catalog/task-<name>` and tagged
  with `<version>` (floating) and `<version>-<git-sha>` (immutable).
- **Pipelines** are pushed to `quay.io/konflux-ci/tekton-catalog/pipeline-<name>` and
  tagged with the git revision.

Shared tasks such as `git-clone` and `prefetch-dependencies` are referenced from
`build-definitions` via `external-task/` bundle pointers. Java-specific tasks and
pipelines are authored in this repository.

## Repository layout

| Directory | Purpose |
|-----------|---------|
| `task/` | Java-specific Tekton Tasks (versioned, bundled to Quay) |
| `pipelines/` | Tekton Pipelines composed via kustomize |
| `external-task/` | Pointers to task bundles built in `build-definitions` |
| `hack/` | Build, validation, and bundle publishing scripts |
| `policies/` | Enterprise Contract (Conforma) policy configuration |
| `.tekton/` | Konflux self-CI PipelineRuns (requires onboarding) |
| `.github/` | GitHub Actions CI from [task-repo-shared-ci](https://github.com/konflux-ci/task-repo-shared-ci) |

See [SHARED-CI.md](SHARED-CI.md) for details on shared CI workflows and task layout
conventions.

## Building bundles locally

Prerequisites: `tkn`, `podman` or `docker`, `oc`, `yq` (mikefarah), `jq`, `git`.

```bash
podman login quay.io
export QUAY_NAMESPACE=<your-quay-user>/tekton-catalog
./hack/build-and-push.sh
```

Set `TEST_REPO_NAME` to push all bundles into a single Quay repository for PR testing
(the approach used by Konflux self-CI).

This repository reuses `quay.io/konflux-ci/appstudio-utils` for bundle build scripts.
A Java-specific utils image can be added later if needed.

## Adding tasks

Place tasks under `task/<name>/` using the flat layout recommended in
[SHARED-CI.md](SHARED-CI.md):

```
task/<name>/<name>.yaml
task/<name>/CHANGELOG.md
task/<name>/README.md
```

Set the version in `metadata.labels.app.kubernetes.io/version`. Interface changes
require a new version, `MIGRATION.md`, and a migration script under `migrations/`.

## Adding pipelines

Pipelines are generated from kustomize bases and patches. See
[pipelines/README.md](pipelines/README.md) and
[build-definitions/pipelines/](https://github.com/konflux-ci/build-definitions/tree/main/pipelines)
for the `template-build` pattern.

After editing `patch.yaml` or kustomization files:

```bash
./hack/build-manifests.sh
```

## Konflux onboarding

The `.tekton/` PipelineRuns will not execute until this repository is onboarded to
Konflux Pipelines-as-Code (same prerequisite as `build-definitions`). Until then,
GitHub Actions provides PR validation.

## License

Apache License 2.0. See [LICENSE](LICENSE).
