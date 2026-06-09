#!/bin/bash -e

script_path="$(dirname -- "${BASH_SOURCE[0]}")"
repo_root="$(cd "${script_path}/.." && pwd)"

TEKTON_DASHBOARD_PORT="${TEKTON_DASHBOARD_PORT:-9097}"
TEKTON_NAMESPACE="${TEKTON_NAMESPACE:-tekton-pipelines}"
MANIFEST="${repo_root}/manifests/tekton-dashboard/tekton-dashboard.yaml"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-240s}"

main() {
    check_cluster
    apply_dashboard
    wait_for_dashboard
    print_access_instructions
    port_forward
}

check_cluster() {
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo "kubectl cannot reach a cluster. Run 'make setup' first." >&2
        exit 1
    fi

    if ! kubectl get tektonconfig config >/dev/null 2>&1; then
        echo "Tekton Operator is not installed. Run 'make setup' or 'make deploy-deps' first." >&2
        exit 1
    fi
}

apply_dashboard() {
    echo "Applying TektonDashboard (read-only)..." >&2
    kubectl apply -f "${MANIFEST}"
}

wait_for_dashboard() {
    echo "Waiting for TektonDashboard to be ready..." >&2
    kubectl wait --for=condition=Ready tektondashboard/dashboard --timeout="${WAIT_TIMEOUT}"

    echo "Waiting for dashboard pods..." >&2
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=dashboard \
        -n "${TEKTON_NAMESPACE}" \
        --timeout="${WAIT_TIMEOUT}"

    if ! kubectl get svc tekton-dashboard -n "${TEKTON_NAMESPACE}" >/dev/null 2>&1; then
        echo "Service tekton-dashboard not found in ${TEKTON_NAMESPACE}." >&2
        exit 1
    fi
}

print_access_instructions() {
    printf '\nTekton Dashboard is ready.\n' >&2
    printf 'Open http://localhost:%s in your browser.\n' "${TEKTON_DASHBOARD_PORT}" >&2
    printf 'Press Ctrl+C to stop port-forwarding.\n\n' >&2
}

port_forward() {
    kubectl port-forward \
        -n "${TEKTON_NAMESPACE}" \
        "svc/tekton-dashboard" \
        "${TEKTON_DASHBOARD_PORT}:9097"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
