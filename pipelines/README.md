# Pipelines

Java build and release Tekton Pipelines are composed here using kustomize.

## Pattern

Follow the approach used in
[build-definitions/pipelines](https://github.com/konflux-ci/build-definitions/tree/main/pipelines):

1. Start from a shared template (for example `template-build` in `build-definitions`)
2. Create `pipelines/<name>/kustomization.yaml` and `patch.yaml`
3. Run `./hack/build-manifests.sh` to generate `pipelines/<name>/<name>.yaml`
4. Register the pipeline in `pipelines/kustomization.yaml`

Pipelines author abstract task references:

```yaml
taskRef:
  name: git-clone
  version: "0.1"
```

At bundle publish time, `hack/build-and-push.sh` replaces these with `resolver: bundles`
references pointing at Quay.

## Integration tests

Add pipeline tests under `pipelines/<name>/tests/`:

```
pipelines/<name>/
├── <name>.yaml              # generated pipeline manifest
├── kustomization.yaml
├── patch.yaml
└── tests/
    ├── test-<scenario>.yaml # Tekton PipelineRun
    └── pre-apply-pipeline-hook.sh  # optional
```

Test files must be `kind: PipelineRun` named `test-*.yaml`. They reference the
pipeline via `spec.pipelineRef.name` and include params and workspace bindings.

CI runs these via [`.github/workflows/run-pipeline-tests.yaml`](../.github/workflows/run-pipeline-tests.yaml).
Locally:

```bash
make setup
make test-pipelines PIPELINE=pipelines/<name>
```

The test runner applies the pipeline locally to the test namespace. Local tasks are
installed in-cluster; external tasks resolve via Tekton bundle resolver refs from
`external-task/`.

## Publishing

Pipeline bundles are tagged with the git revision and pushed to
`quay.io/konflux-ci/tekton-catalog/pipeline-<name>`.
