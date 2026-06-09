#!/bin/bash
shopt -s nullglob
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=render_pipeline_for_local_test.sh
source "${SCRIPT_DIR}/render_pipeline_for_local_test.sh"

echo ">>> Apply tasks"
for task_folder in task/*/; do
  if [ -d "$task_folder" ]; then
    task="$(basename "$task_folder")"
    echo ">>> Task: $task"
    flat_task_file="${task_folder%/}/${task}.yaml"
    if [ -f "$flat_task_file" ]; then
      kubectl apply -f "$flat_task_file" --dry-run=server
    fi
    (
      cd "$task_folder"
      for version in */; do
        versioned_task_file="${version}${task}.yaml"
        if [ -f "$versioned_task_file" ]; then
          kubectl apply -f "$versioned_task_file" --dry-run=server
        fi
      done
    )
  fi
done

echo ">>> Apply pipelines"

cd pipelines

ignored_pipelines=(
  "template-build"
)

for pipeline in */; do
  if [ -d "$pipeline" ]; then
    pipeline="$(basename "$pipeline")"
    for ignored in "${ignored_pipelines[@]}"; do
      if [ "$ignored" == "$pipeline" ]; then
        echo ">>> Ignoring pipeline: $pipeline"
        continue 2
      fi
    done
    echo ">>> Pipeline: $pipeline"
    to_apply=()
    for yaml in "$pipeline"/*.yaml; do
      if [ -f "$yaml" ] && yq eval -e 'type == "!!map" and .kind == "Pipeline"' "$yaml" > /dev/null 2>&1; then
        to_apply+=("$yaml")
      fi
    done

    for file in "${to_apply[@]}"; do
      rendered_file=$(mktemp /tmp/pipeline-rendered.XXXXXX)
      cleanup() { rm -f "${rendered_file}"; }
      trap cleanup EXIT

      render_pipeline_for_local_test "$file" "$rendered_file"
      kubectl apply -f "$rendered_file" --dry-run=server
      rm -f "${rendered_file}"
      trap - EXIT
    done
  fi
done
