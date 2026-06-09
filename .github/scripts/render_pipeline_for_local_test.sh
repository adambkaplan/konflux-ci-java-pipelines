#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Resolve a local task YAML path when taskRef name and version match.
find_local_task_file() {
  local task_name=$1
  local task_version=$2
  local flat_task_file="${REPO_ROOT}/task/${task_name}/${task_name}.yaml"
  local task_version_label

  if [ -f "$flat_task_file" ]; then
    task_version_label=$(yq '.metadata.labels["app.kubernetes.io/version"]' "$flat_task_file")
    if [[ "$task_version_label" == "$task_version" ]]; then
      echo "$flat_task_file"
      return 0
    fi
  fi

  local versioned_task_file="${REPO_ROOT}/task/${task_name}/${task_version}/${task_name}.yaml"
  if [ -f "$versioned_task_file" ]; then
    echo "$versioned_task_file"
    return 0
  fi

  return 1
}

external_task_bundle() {
  local task_name=$1
  local task_version=$2
  local external_task_dir="${REPO_ROOT}/external-task/${task_name}/${task_version}"
  local external_task_file

  if [ ! -d "$external_task_dir" ]; then
    return 1
  fi

  external_task_file="$(find "$external_task_dir" -maxdepth 1 -type f \( -iname "*.yaml" -o -iname "*.yml" \) | head -1)"
  if [ -z "$external_task_file" ]; then
    echo "error: external-task dir exists but has no yaml: ${external_task_dir}" >&2
    return 1
  fi

  yq -e '.task_bundle' "$external_task_file"
}

inject_bundle_ref() {
  local dest_yaml=$1
  local task_name=$2
  local task_version=$3
  local task_bundle=$4
  local bundle_ref task_selector

  bundle_ref="{
    \"resolver\": \"bundles\",
    \"params\": [
      {\"name\": \"name\", \"value\": \"${task_name}\"},
      {\"name\": \"bundle\", \"value\": \"${task_bundle}\"},
      {\"name\": \"kind\", \"value\": \"task\"}
    ]
  }"
  task_selector="select(.name == \"${task_name}\" and .version == \"${task_version}\")"
  yq e "(.spec.tasks[].taskRef | ${task_selector}) |= ${bundle_ref}" -i "$dest_yaml"
  yq e "(.spec.finally[].taskRef | ${task_selector}) |= ${bundle_ref}" -i "$dest_yaml"
}

strip_local_task_version() {
  local dest_yaml=$1
  local task_name=$2
  local task_version=$3
  local task_selector

  task_selector="select(.name == \"${task_name}\" and .version == \"${task_version}\")"
  yq e "(.spec.tasks[].taskRef | ${task_selector}) |= del(.version)" -i "$dest_yaml"
  yq e "(.spec.finally[].taskRef | ${task_selector}) |= del(.version)" -i "$dest_yaml"
}

# Render a pipeline for local apply: local tasks keep name-only taskRef, external
# tasks use Tekton bundle resolver refs. Source YAML is never modified.
render_pipeline_for_local_test() {
  local source_yaml=$1
  local dest_yaml=$2
  local task_name task_version task_bundle

  cp "$source_yaml" "$dest_yaml"

  while IFS=$'\t' read -r task_name task_version; do
    [[ -z "$task_name" || -z "$task_version" || "$task_version" == "null" ]] && continue

    if task_bundle=$(external_task_bundle "$task_name" "$task_version"); then
      echo "INFO: render ${task_name}@${task_version} as bundle resolver"
      inject_bundle_ref "$dest_yaml" "$task_name" "$task_version" "$task_bundle"
    elif find_local_task_file "$task_name" "$task_version" > /dev/null; then
      echo "INFO: render ${task_name}@${task_version} as local name-only taskRef"
      strip_local_task_version "$dest_yaml" "$task_name" "$task_version"
    else
      echo "error: unknown task dependency ${task_name}@${task_version} in ${source_yaml}" >&2
      echo "error: no matching local task or external-task bundle pointer" >&2
      return 1
    fi
  done < <(
    yq -N -o=tsv '[.spec.tasks[]?, .spec.finally[]?] |
      map(select(.taskRef.name and .taskRef.version)) |
      unique_by(.taskRef.name + ":" + .taskRef.version) |
      .[] | [.taskRef.name, .taskRef.version] | @tsv' "$source_yaml"
  )
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <source_pipeline.yaml> <dest_pipeline.yaml>" >&2
    exit 1
  fi
  render_pipeline_for_local_test "$1" "$2"
fi
