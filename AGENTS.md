# AGENTS.md

Instructions for AI coding agents working in this repository.

## Project scope

This repository is a **Konflux Tekton catalog** for Java build and release workflows.
It is **not** a Java application repo. You author Tekton Tasks and Pipelines that are
delivered as OCI bundles to `quay.io/konflux-ci/tekton-catalog`.

**Boundaries:**

| Author here | Do not duplicate |
|-------------|------------------|
| Java-specific tasks in `task/` | Shared tasks from [build-definitions](https://github.com/konflux-ci/build-definitions) |
| Pipelines in `pipelines/` (kustomize) | Upstream `template-build` and shared tasks |
| Bundle pointers in `external-task/` | `git-clone`, `prefetch-dependencies`, `init`, `summary`, etc. |

Never fork shared build-definitions tasks into `task/`. Add an `external-task/` bundle
pointer instead. See [external-task/README.md](external-task/README.md).

For the full layout table, see [README.md](README.md).

## Repository map

| Directory | Purpose |
|-----------|---------|
| `task/` | Java-specific Tekton Tasks (versioned, bundled to Quay) |
| `pipelines/` | Tekton Pipelines composed via kustomize |
| `external-task/` | Pointers to task bundles built in build-definitions |
| `hack/` | Build, validation, and bundle publishing scripts |
| `policies/` | Enterprise Contract (Conforma) policy configuration |
| `.github/` | GitHub Actions CI (from task-repo-shared-ci) |
| `.tekton/` | Konflux self-CI PipelineRuns (requires onboarding) |

## What kind of change are you making?

### Task YAML or behavior

1. Edit the task source YAML under `task/<name>/`.
2. If releasing the change, bump `metadata.labels.app.kubernetes.io/version`.
3. Update `CHANGELOG.md` when the change is user-visible.
4. Add or update integration tests under `task/<name>/tests/test-*.yaml`.
5. For breaking interface changes, add `migrations/<new-version>.sh` using `pmt modify`
   (not `yq -i`). See [SHARED-CI.md](SHARED-CI.md#task-migration).

Preferred layout:

```
task/<name>/<name>.yaml
task/<name>/CHANGELOG.md
task/<name>/tests/test-*.yaml
```

The version label controls the release version, not the directory name.

### Pipeline composition

1. Edit `pipelines/<name>/kustomization.yaml` and `patch.yaml` only.
2. Register new pipelines in `pipelines/kustomization.yaml`.
3. Run `./hack/build-manifests.sh` (or `./hack/generate-everything.sh`) to regenerate
   `pipelines/<name>/<name>.yaml`.
4. Follow patterns in [pipelines/README.md](pipelines/README.md) and
   [build-definitions/pipelines](https://github.com/konflux-ci/build-definitions/tree/main/pipelines).

Pipelines author abstract task references (`taskRef.name` + `taskRef.version`). Bundle
resolution happens at publish time in `hack/build-and-push.sh`.

### Trusted Artifacts (TA) variant

1. Edit `recipe.yaml` in `task/<name>-oci-ta/`.
2. Run `hack/generate-ta-tasks.sh` to regenerate `*-oci-ta.yaml`.
3. Do not hand-edit generated TA task YAML.

See [SHARED-CI.md](SHARED-CI.md#trusted-artifacts).

### Shared task dependency

Add a bundle digest pointer under `external-task/`, not a copy in `task/`.

```yaml
task_bundle: quay.io/konflux-ci/tekton-catalog/task-git-clone-oci-ta:0.1@sha256:...
```

## Do not edit directly

| File | Edit instead | Regenerate with |
|------|--------------|-----------------|
| `pipelines/<name>/<name>.yaml` | `kustomization.yaml`, `patch.yaml` | `./hack/build-manifests.sh` |
| `task/<name>-oci-ta/<name>-oci-ta.yaml` | `recipe.yaml` | `hack/generate-ta-tasks.sh` |
| Files marked `TEMPLATED FILE!` | Upstream [task-repo-shared-ci](https://github.com/konflux-ci/task-repo-shared-ci) | `cruft update` (see [SHARED-CI.md](SHARED-CI.md)) |

Generated pipeline manifests include a warning header. Commit regenerated output
after editing kustomize sources.

## Security and Tekton lint rules

- **Never use `$(params.*)` inside `script:` blocks.** Pass parameters via `env`,
  `args`, or other step fields. CI enforces this (arbitrary code execution risk).
- Never commit secrets or credentials. Never log sensitive values.
- Shell embedded in YAML must pass Checkton (ShellCheck).

## Validation before finishing

Run checks relevant to your change:

| Check | Command |
|-------|---------|
| Versioning | `hack/versioning.py check` |
| Regenerate manifests | `./hack/build-manifests.sh` then review `git diff pipelines/` |
| TA variants up to date | `hack/generate-ta-tasks.sh` then review diff |
| Shell in YAML | `hack/checkton-local.sh` (requires podman) |
| Task integration tests | `make test TASK=task/<name>/...` (requires prior `make setup`) |
| Full local CI | `make ci TASK=...` |
| EC policy (optional) | `hack/ec-checks.sh` |

**Local testing prerequisites:** `kubectl`, `kind`, `tkn`, `jq`, `yq`, `git`, `openssl`.
Install `tkn` with `make install-tkn`. See `make help` and [CONTRIBUTING.md](CONTRIBUTING.md).

**Trap:** `make validate-tasks` strips `taskRef.version` from pipeline YAML in-place.
Revert with `git checkout -- pipelines/` if you run it locally.

Integration test conventions (from SHARED-CI):

- Tests live in `task/<name>/tests/test-*.yaml` as Tekton `Pipeline` objects.
- Each test pipeline must declare a workspace named `tests-workspace`.
- Optional `pre-apply-task-hook.sh` runs before the task is applied.

## Pull request and commit expectations

- Commit subject ≤50 characters; body lines ≤72 characters.
- Sign off commits per the [Developer Certificate of Origin](https://developercertificate.org).
- Add `Assisted-by: <tool-name>` when AI-assisted.
- PR description must explain changes and how they were tested.
- All CI checks must pass: Checkton, versioning, kustomize build, TA check, task-lint,
  task integration tests.
- Breaking task changes require migration scripts validated by CI.

Before opening a PR, check [.github/pull_request_template.md](.github/pull_request_template.md)
for coordination with open e2e-tests update PRs.

## Further reading

- [CONTRIBUTING.md](CONTRIBUTING.md) — local testing, PR process
- [SHARED-CI.md](SHARED-CI.md) — CI workflows, migrations, TA, integration tests
- [pipelines/README.md](pipelines/README.md) — pipeline authoring
- [task/README.md](task/README.md) — task layout
- [build-definitions/pipelines](https://github.com/konflux-ci/build-definitions/tree/main/pipelines) — reference patterns
