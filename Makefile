# Local Tekton test environment — mirrors .github/workflows/run-*-tests.yaml
#
# Quick start:
#   make setup              # one-time kind + konflux-ci bootstrap (~15–30 min)
#   make test               # run task integration tests for TASK
#   make test-pipelines     # run pipeline integration tests for PIPELINE
#   make clean              # delete the kind cluster

SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

KONFLUX_CI_REPO ?= https://github.com/konflux-ci/konflux-ci.git
KONFLUX_CI_REF ?= 3a694f8d7b49e74f476bb9414fc3e6d03d50ae37
KONFLUX_CI_DIR ?= .local/konflux-ci

KIND_CLUSTER ?= kind
TASK ?= task/maven-deploy
PIPELINE ?= pipelines/maven-build
TKN_VERSION ?= 0.38.1
TEKTON_DASHBOARD_PORT ?= 9097

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TEST_SCRIPT := $(REPO_ROOT)/.github/scripts/test_tekton_tasks.sh
PIPELINE_TEST_SCRIPT := $(REPO_ROOT)/.github/scripts/test_tekton_pipelines.sh
VALIDATE_SCRIPT := $(REPO_ROOT)/.github/scripts/check_task_and_pipeline_yamls.sh

.PHONY: help check-prereqs install-tkn fetch-konflux-ci kind-up kind-down \
        deploy-deps deploy-konflux setup validate-tasks validate-pipelines \
        test test-pipelines ci ci-pipelines tekton-dashboard clean

.DEFAULT_GOAL := help

help: ## Show targets and key variables
	@printf '%s\n' \
		'Local Tekton test environment (see CONTRIBUTING.md for details)' \
		'' \
		'Targets:' \
		'  setup              Full bootstrap: prereqs, konflux-ci, kind, deps, konflux' \
		'  test               Run task integration tests for $$(TASK)' \
		'  test-pipelines     Run pipeline integration tests for $$(PIPELINE)' \
		'  ci                 setup + validate-tasks + test' \
		'  ci-pipelines       setup + validate-pipelines + test-pipelines' \
		'  tekton-dashboard   Install read-only Tekton Dashboard and port-forward' \
		'  clean              Delete the kind cluster (alias: kind-down)' \
		'' \
		'Bootstrap (individual steps):' \
		'  fetch-konflux-ci   Clone or update konflux-ci at pinned ref' \
		'  kind-up            Create kind cluster if missing' \
		'  kind-down          Delete kind cluster' \
		'  deploy-deps        Deploy konflux-ci dependencies' \
		'  deploy-konflux     Deploy Konflux and test resources' \
		'' \
		'Other:' \
		'  check-prereqs      Verify required tools are installed' \
		'  install-tkn        Download Tekton CLI to ~/.local/bin' \
		'  validate-tasks     Dry-run apply tasks and pipelines' \
		'  validate-pipelines Alias for validate-tasks' \
		'' \
		'Variables:' \
		'  TASK=$(TASK)' \
		'  PIPELINE=$(PIPELINE)' \
		'  KIND_CLUSTER=$(KIND_CLUSTER)' \
		'  KONFLUX_CI_DIR=$(KONFLUX_CI_DIR)' \
		'  KONFLUX_CI_REF=$(KONFLUX_CI_REF)' \
		'  TEKTON_DASHBOARD_PORT=$(TEKTON_DASHBOARD_PORT)'

check-prereqs: ## Verify kubectl, kind, jq, yq, git, openssl, and tkn are available
	@missing=(); \
	for cmd in kubectl kind jq yq git openssl tkn; do \
		if ! command -v "$$cmd" >/dev/null 2>&1; then \
			missing+=("$$cmd"); \
		fi; \
	done; \
	if (($${#missing[@]})); then \
		printf 'Missing required tools: %s\n' "$${missing[*]}"; \
		printf 'Install tkn with: make install-tkn\n'; \
		printf 'See CONTRIBUTING.md for other prerequisites.\n'; \
		exit 1; \
	fi; \
	printf 'All required tools are installed.\n'

install-tkn: ## Download Tekton CLI (v$(TKN_VERSION)) to ~/.local/bin
	@arch=$$(uname -m); \
	case "$$arch" in \
		x86_64)  tkn_arch=Linux-64bit ;; \
		aarch64|arm64) tkn_arch=Linux-ARM64 ;; \
		*) printf 'Unsupported architecture: %s\n' "$$arch"; exit 1 ;; \
	esac; \
	url="https://github.com/tektoncd/cli/releases/download/v$(TKN_VERSION)/tektoncd-cli-$(TKN_VERSION)_$${tkn_arch}.tar.gz"; \
	tmpdir=$$(mktemp -d); \
	trap 'rm -rf "$$tmpdir"' EXIT; \
	printf 'Downloading %s\n' "$$url"; \
	curl -fsSL "$$url" | tar -xz -C "$$tmpdir"; \
	mkdir -p "$$HOME/.local/bin"; \
	install -m 755 "$$tmpdir"/tkn "$$HOME/.local/bin/tkn"; \
	printf 'Installed tkn to ~/.local/bin/tkn\n'; \
	printf 'Ensure ~/.local/bin is on your PATH.\n'

fetch-konflux-ci: ## Clone or update konflux-ci at KONFLUX_CI_REF
	@if [[ -d "$(KONFLUX_CI_DIR)/.git" ]]; then \
		printf 'Updating existing konflux-ci checkout in %s\n' "$(KONFLUX_CI_DIR)"; \
		git -C "$(KONFLUX_CI_DIR)" fetch origin "$(KONFLUX_CI_REF)" --depth 1; \
		git -C "$(KONFLUX_CI_DIR)" checkout FETCH_HEAD; \
	else \
		printf 'Cloning konflux-ci (%s) into %s\n' "$(KONFLUX_CI_REF)" "$(KONFLUX_CI_DIR)"; \
		mkdir -p "$$(dirname "$(KONFLUX_CI_DIR)")"; \
		git clone --depth 1 "$(KONFLUX_CI_REPO)" "$(KONFLUX_CI_DIR)"; \
		git -C "$(KONFLUX_CI_DIR)" fetch origin "$(KONFLUX_CI_REF)" --depth 1; \
		git -C "$(KONFLUX_CI_DIR)" checkout FETCH_HEAD; \
	fi

kind-up: fetch-konflux-ci ## Create kind cluster if it does not exist
	@if kind get clusters 2>/dev/null | grep -qx "$(KIND_CLUSTER)"; then \
		printf 'Kind cluster "%s" already exists.\n' "$(KIND_CLUSTER)"; \
	else \
		printf 'Creating kind cluster "%s"...\n' "$(KIND_CLUSTER)"; \
		kind create cluster \
			--name "$(KIND_CLUSTER)" \
			--config "$(KONFLUX_CI_DIR)/kind-config.yaml"; \
	fi

kind-down clean: ## Delete the kind cluster
	@if kind get clusters 2>/dev/null | grep -qx "$(KIND_CLUSTER)"; then \
		kind delete cluster --name "$(KIND_CLUSTER)"; \
	else \
		printf 'Kind cluster "%s" does not exist.\n' "$(KIND_CLUSTER)"; \
	fi

deploy-deps: kind-up ## Deploy konflux-ci dependencies and wait for readiness
	@cd "$(KONFLUX_CI_DIR)" && ./deploy-deps.sh
	@cd "$(KONFLUX_CI_DIR)" && ./wait-for-all.sh

deploy-konflux: deploy-deps ## Deploy Konflux and test resources
	@cd "$(KONFLUX_CI_DIR)" && ./deploy-konflux.sh
	@cd "$(KONFLUX_CI_DIR)" && ./deploy-test-resources.sh

setup: check-prereqs deploy-konflux ## Full local test environment bootstrap
	@printf '\nSetup complete. Run tests with: make test TASK=%s\n' "$(TASK)"
	@printf 'Or pipeline tests with: make test-pipelines PIPELINE=%s\n' "$(PIPELINE)"

validate-tasks validate-pipelines: check-prereqs ## Dry-run apply tasks and rendered pipelines
	@cd "$(REPO_ROOT)" && "$(VALIDATE_SCRIPT)"

test: check-prereqs ## Run integration tests for TASK
	@cd "$(REPO_ROOT)" && "$(TEST_SCRIPT)" "$(TASK)"

test-pipelines: check-prereqs ## Run integration tests for PIPELINE
	@cd "$(REPO_ROOT)" && "$(PIPELINE_TEST_SCRIPT)" "$(PIPELINE)"

ci: setup validate-tasks test ## CI-equivalent for tasks: bootstrap, validate, and test

ci-pipelines: setup validate-pipelines test-pipelines ## CI-equivalent for pipelines

tekton-dashboard: check-prereqs ## Install Tekton Dashboard (read-only) and port-forward to localhost:9097
	@TEKTON_DASHBOARD_PORT="$(TEKTON_DASHBOARD_PORT)" "$(REPO_ROOT)/hack/deploy-tekton-dashboard.sh"
