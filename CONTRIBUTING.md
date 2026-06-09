# Contributing to java-pipelines

## Table of Contents

* [Project Overview](#project-overview)
* [How to Report Issues](#how-to-report-issues)
* [How to Submit Pull Requests](#how-to-submit-pull-requests)
  * [Development Workflow](#development-workflow)
  * [Local Task Testing](#local-task-testing)
  * [Local Pipeline Testing](#local-pipeline-testing)
  * [Pull Request Guidelines](#pull-request-guidelines)
  * [Security Best Practices](#security-best-practices)

* [Review Process](#review-process)

## Project Overview

This repository hosts Tekton Tasks and Pipelines for Java build and release workflows
in [Konflux](https://konflux-ci.dev). Follow the Konflux
[Code of Conduct](https://github.com/konflux-ci/community/blob/main/CODE_OF_CONDUCT.md).

Shared build tasks (for example `git-clone`, `prefetch-dependencies`) are consumed from
[build-definitions](https://github.com/konflux-ci/build-definitions) via `external-task/`
bundle references. Java-specific tasks and pipelines live in this repository.

Components are delivered to Konflux via the `konflux-ci/tekton-catalog` Quay organization
as OCI bundles.

## How to Report Issues

- We encourage early communication for all types of contributions.
- Before filing an issue, make sure it is not reported already.
- For non-trivial changes, open an issue to discuss your plans with maintainers.
- Please fill out the included issue templates with all applicable information.

## How to Submit Pull Requests

### Development Workflow

1. **Fork and Clone**: Fork this repository and clone your fork
2. **Create Feature Branch**: Create a new topic branch based on `main`
3. **Make Changes**: Implement your changes
4. **Generate Content**: Run generation scripts if needed
   ```bash
   ./hack/generate-everything.sh
   ```
5. **Commit Changes**: See [commit guidelines](#pull-request-guidelines)

### Local Task Testing

Task integration tests run in CI via [`.github/workflows/run-task-tests.yaml`](.github/workflows/run-task-tests.yaml).
The [Makefile](Makefile) mirrors that workflow for local development.

**Prerequisites:** `kubectl`, `kind`, `tkn`, `jq`, `yq`, `git`, and `openssl`.
Install the Tekton CLI with `make install-tkn` if needed.

```bash
# One-time bootstrap (~15–30 min): kind cluster + konflux-ci dependencies
make setup

# Optional: install read-only Tekton Dashboard (blocks terminal on port-forward)
make tekton-dashboard
# Open http://localhost:9097 in a browser (run in a separate terminal while testing)

# Run tests for the default task (task/maven-deploy)
make test

# Run tests for a specific task directory
make test TASK=task/maven-deploy
make test TASK=task/maven-deploy-oci-ta

# Run a single test pipeline
make test TASK=task/maven-deploy/tests/test-maven-deploy-happy-path.yaml
make test TASK=task/maven-deploy-oci-ta/tests/test-maven-deploy-oci-ta-happy-path.yaml

# Full CI-equivalent run (bootstrap + validate + test)
make ci TASK=task/maven-deploy
make ci TASK=task/maven-deploy-oci-ta

# Tear down the kind cluster
make clean
```

If you already have a [konflux-ci](https://github.com/konflux-ci/konflux-ci) checkout,
point the Makefile at it instead of cloning:

```bash
make setup KONFLUX_CI_DIR=/path/to/konflux-ci
```

`make validate-tasks` dry-runs `kubectl apply` for all tasks and pipelines.
Pipeline YAML is rendered to a temporary copy (local tasks keep name-only refs;
external tasks use Tekton bundle resolver refs). Source files are not modified.

### Local Pipeline Testing

Pipeline integration tests run in CI via
[`.github/workflows/run-pipeline-tests.yaml`](.github/workflows/run-pipeline-tests.yaml).
The [Makefile](Makefile) mirrors that workflow for local development.

```bash
# One-time bootstrap (~15–30 min): kind cluster + konflux-ci dependencies
make setup

# Run tests for the default pipeline (pipelines/maven-build)
make test-pipelines

# Run tests for a specific pipeline directory
make test-pipelines PIPELINE=pipelines/maven-build
make test-pipelines PIPELINE=pipelines/maven-build-oci-ta

# Run a single PipelineRun test
make test-pipelines PIPELINE=pipelines/maven-build/tests/test-maven-build-happy-path.yaml

# Full CI-equivalent run (bootstrap + validate + test)
make ci-pipelines PIPELINE=pipelines/maven-build

# Tear down the kind cluster
make clean
```

Pipeline tests live in `pipelines/<name>/tests/test-*.yaml` as Tekton `PipelineRun`
objects. The pipeline under test is applied locally to the test namespace (not bundled).
Local tasks are applied to the namespace; external tasks are resolved via Tekton's
bundle resolver at runtime.

For troubleshooting (Docker Hub rate limits, inotify limits on Linux, registry setup),
see the [konflux-ci bootstrapping guide](https://github.com/konflux-ci/konflux-ci?tab=readme-ov-file#bootstrapping-the-cluster).

Run `make help` for all targets and configurable variables.


**Commit Requirements:**
- Write clear, descriptive commit titles under 50 characters
- Write meaningful commit descriptions with each line under 72 characters
- Split contributions into logical commits when applicable
- Add `Assisted-by: <name-of-ai-tool>` if you used an AI tool
- Sign-off commits per the [Developer Certificate of Origin](https://developercertificate.org)

**Pull Request Content:**
- **Title**: Clear, descriptive title under 72 characters
- **Description**: Explain the overall changes and their purpose
- **Testing**: Describe how the changes were tested
- **Links**: Reference related issues or upstream stories

### Security Best Practices

- Never commit secrets or keys to the repository
- Never expose or log sensitive information

## Review Process

**Requirements for Approval:**
- All CI checks pass
- Code review approval from maintainers

**Review Criteria:**
- Changes follow established patterns from `build-definitions`
- Changes are tested and documented
- Breaking changes result in a new task version and include migration
- Security best practices are followed

For questions or help, open an issue or reach out to the maintainers.
