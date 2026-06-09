#!/bin/bash

set -e

# This script runs pipeline integration tests for pipeline directories
# provided as arguments.
#
# Requirements:
# - Connection to a running k8s cluster (e.g. kind)
# - konflux-ci installed on the cluster
# - tkn installed
#
# Examples:
# ./test_tekton_pipelines.sh pipelines/maven-build
# ./test_tekton_pipelines.sh pipelines/maven-build/tests/test-maven-build-happy-path.yaml

KUBECTL_CMD=${KUBECTL_CMD:-kubectl}
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=render_pipeline_for_local_test.sh
source "${SCRIPT_DIR}/render_pipeline_for_local_test.sh"

if [[ $# -eq 0 || ${1} == "-h" ]]; then
  cat <<EOF
Error: No pipeline directories.

Usage:

$0 [item1] [item2] [...]

Example: ./.github/scripts/test_tekton_pipelines.sh pipelines/maven-build

or

$0 pipelines/maven-build/tests/test-maven-build-happy-path.yaml
EOF
  exit 1
fi

TEST_ITEMS=("$@")

for ITEM in "${TEST_ITEMS[@]}"; do
  if [[ "$ITEM" == *tests/test-*.yaml && -f "$ITEM" ]]; then
    true
  elif [[ -d "$ITEM" ]]; then
    true
  else
    echo "Error: Invalid test yaml file or pipeline directory: $ITEM"
    exit 1
  fi
done

apply_local_tasks_for_pipeline() {
  local source_pipeline=$1
  local test_ns=$2
  local task_name task_version local_task_file

  while IFS=$'\t' read -r task_name task_version; do
    [[ -z "$task_name" || -z "$task_version" || "$task_version" == "null" ]] && continue

    if external_task_bundle "$task_name" "$task_version" > /dev/null; then
      echo "INFO: external task ${task_name}@${task_version} resolved via bundle resolver"
      continue
    fi

    if ! local_task_file=$(find_local_task_file "$task_name" "$task_version"); then
      echo "ERROR: unable to resolve task ${task_name}@${task_version}"
      exit 1
    fi

    echo "INFO: Installing local task ${task_name}@${task_version} from ${local_task_file}"
    ${KUBECTL_CMD} apply -f "$local_task_file" -n "$test_ns"
  done < <(
    yq -N -o=tsv '[.spec.tasks[]?, .spec.finally[]?] |
      map(select(.taskRef.name and .taskRef.version)) |
      unique_by(.taskRef.name + ":" + .taskRef.version) |
      .[] | [.taskRef.name, .taskRef.version] | @tsv' "$source_pipeline"
  )
}

for ITEM in "${TEST_ITEMS[@]}"; do
  echo "Test item: $ITEM"

  if [[ "$ITEM" == *tests/test-*.yaml ]]; then
    TESTS_DIR=$(dirname "$ITEM")
    PIPELINE_DIR=$(dirname "$TESTS_DIR")
  else
    PIPELINE_DIR="$ITEM"
    TESTS_DIR="${PIPELINE_DIR}/tests"
  fi

  PIPELINE_NAME=$(basename "$PIPELINE_DIR")
  PIPELINE_PATH="${PIPELINE_DIR}/${PIPELINE_NAME}.yaml"
  TEST_NS="${PIPELINE_NAME}"

  if [ ! -f "$PIPELINE_PATH" ]; then
    echo "ERROR: Pipeline file does not exist: $PIPELINE_PATH"
    exit 1
  fi

  if [ ! -d "$TESTS_DIR" ]; then
    echo "ERROR: tests dir does not exist: $TESTS_DIR"
    exit 1
  fi

  if [[ "$ITEM" == *tests/test-*.yaml ]]; then
    TEST_PATHS=("$ITEM")
  else
    TEST_PATHS=("$TESTS_DIR"/test-*.yaml)
  fi

  if [ ${#TEST_PATHS[@]} -eq 0 ]; then
    echo "WARNING: No tests for test item $ITEM ... Skipping..."
    continue
  fi

  PIPELINE_COPY=$(mktemp /tmp/pipeline.XXXXXX)
  cleanup() { rm -f "${PIPELINE_COPY}"; }
  trap cleanup EXIT

  if ! ${KUBECTL_CMD} get namespace "${TEST_NS}" > /dev/null 2>&1; then
    ${KUBECTL_CMD} create namespace "${TEST_NS}"
  fi

  render_pipeline_for_local_test "$PIPELINE_PATH" "$PIPELINE_COPY"

  if [ -f "${TESTS_DIR}/pre-apply-pipeline-hook.sh" ]; then
    echo "Found pre-apply-pipeline-hook.sh in dir: $TESTS_DIR. Executing..."
    "${TESTS_DIR}/pre-apply-pipeline-hook.sh" "$PIPELINE_COPY" "$TEST_NS"
  fi

  if ! ${KUBECTL_CMD} get sa appstudio-pipeline -n "${TEST_NS}" > /dev/null 2>&1; then
    ${KUBECTL_CMD} create sa appstudio-pipeline -n "${TEST_NS}"
  fi

  apply_local_tasks_for_pipeline "$PIPELINE_PATH" "$TEST_NS"

  echo "INFO: Installing rendered pipeline"
  ${KUBECTL_CMD} apply -f "$PIPELINE_COPY" -n "$TEST_NS"

  for TEST_PATH in "${TEST_PATHS[@]}"; do
    echo "========== Starting PipelineRun test: $TEST_PATH =========="

    if ! yq eval -e 'type == "!!map" and .kind == "PipelineRun"' "$TEST_PATH" > /dev/null 2>&1; then
      echo "ERROR: Test file must be kind PipelineRun: $TEST_PATH"
      exit 1
    fi

    echo "INFO: Applying PipelineRun: $TEST_PATH"
    ${KUBECTL_CMD} -n "${TEST_NS}" apply -f "$TEST_PATH"
    PIPELINERUN=$(yq '.metadata.name' "$TEST_PATH")

    while ! ${KUBECTL_CMD} -n "${TEST_NS}" get pipelinerun "$PIPELINERUN" > /dev/null 2>&1; do
      echo "DEBUG: PipelineRun $PIPELINERUN not ready. Waiting 5s..."
      sleep 5
    done

    PR_STATUS="Unknown"
    while [ "$PR_STATUS" == "Unknown" ]; do
      echo "DEBUG: PipelineRun $PIPELINERUN is in progress (status Unknown). Waiting for update..."
      sleep 5
      PR_STATUS=$(tkn pr describe "$PIPELINERUN" -n "${TEST_NS}" -o json 2>/dev/null \
        | jq -r '.status.conditions[] | select(.type=="Succeeded") | .status // "Unknown"')
    done

    echo "INFO: PipelineRun $PIPELINERUN completed with status: $PR_STATUS"

    if ! timeout 5m tkn pr logs "$PIPELINERUN" -n "${TEST_NS}"; then
      logs_exit=$?
      if [ "$logs_exit" -eq 124 ]; then
        echo "WARNING: tkn pr logs timed out after 5 minutes; continuing with result check"
      else
        exit "$logs_exit"
      fi
    fi

    ASSERT_PIPELINE_FAILURE=$(yq '.metadata.annotations.test/assert-pipeline-failure' < "$TEST_PATH")
    if [ "$ASSERT_PIPELINE_FAILURE" != "null" ]; then
      if [ "$PR_STATUS" == "True" ]; then
        echo "ERROR: PipelineRun $PIPELINERUN succeeded but was expected to fail"
        exit 1
      fi
      echo "INFO: PipelineRun $PIPELINERUN failed as expected"
    else
      if [ "$PR_STATUS" == "True" ]; then
        echo "INFO: PipelineRun $PIPELINERUN succeeded"
      else
        echo "ERROR: PipelineRun $PIPELINERUN failed"
        exit 1
      fi
    fi

    echo "========== Completed: $TEST_PATH =========="
  done

done
