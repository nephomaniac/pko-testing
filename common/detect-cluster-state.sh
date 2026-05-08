#!/bin/bash
#
# Detect the current deployment state of an operator on a cluster.
# Returns: "olm", "pko", "both", "neither"
#
# Usage:
#   source detect-cluster-state.sh
#   state=$(detect_deployment_state "$NAMESPACE" "$OPERATOR_NAME")
#
# Also provides:
#   list_olm_resources "$NAMESPACE" "$OPERATOR_NAME"
#   list_pko_resources "$OPERATOR_NAME"
#   verify_expected_state "$NAMESPACE" "$OPERATOR_NAME" "$EXPECTED_STATE"

detect_deployment_state() {
    local namespace="$1"
    local operator_name="$2"
    local has_olm=false
    local has_pko=false

    # Check for OLM artifacts
    local csv_count
    csv_count=$(oc get csv -n "$namespace" -l "operators.coreos.com/${operator_name}.${namespace}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$csv_count" -gt 0 ]; then
        has_olm=true
    fi

    # Check for PKO artifacts
    if oc get clusterpackage "$operator_name" &>/dev/null; then
        has_pko=true
    fi

    if $has_olm && $has_pko; then
        echo "both"
    elif $has_olm; then
        echo "olm"
    elif $has_pko; then
        echo "pko"
    else
        echo "neither"
    fi
}

# List all OLM-related resources for an operator
list_olm_resources() {
    local namespace="$1"
    local operator_name="$2"

    echo "=== OLM Resources for $operator_name ==="

    echo "--- CSV ---"
    oc get csv -n "$namespace" -l "operators.coreos.com/${operator_name}.${namespace}" --no-headers 2>/dev/null || echo "  None"

    echo "--- Subscription ---"
    oc get subscription.operators.coreos.com -n "$namespace" "$operator_name" --no-headers 2>/dev/null || echo "  None"

    echo "--- CatalogSource ---"
    oc get catalogsource -n "$namespace" "${operator_name}-registry" --no-headers 2>/dev/null || echo "  None"

    echo "--- SSS-synced ClusterRoleBinding ---"
    oc get clusterrolebinding "${operator_name}-prom" --no-headers 2>/dev/null || echo "  None"

    echo "--- Deployment ---"
    oc get deployment -n "$namespace" "$operator_name" --no-headers 2>/dev/null || echo "  None"

    echo "--- ServiceAccount ---"
    oc get serviceaccount -n "$namespace" "$operator_name" --no-headers 2>/dev/null || echo "  None"

    echo "--- Deployment ownerReferences ---"
    oc get deployment -n "$namespace" "$operator_name" -o jsonpath='{.metadata.ownerReferences}' 2>/dev/null | jq . 2>/dev/null || echo "  None or inaccessible"

    echo "--- ServiceAccount ownerReferences ---"
    oc get serviceaccount -n "$namespace" "$operator_name" -o jsonpath='{.metadata.ownerReferences}' 2>/dev/null | jq . 2>/dev/null || echo "  None or inaccessible"
}

# List all PKO-related resources for an operator
list_pko_resources() {
    local operator_name="$1"

    echo "=== PKO Resources for $operator_name ==="

    echo "--- ClusterPackage ---"
    oc get clusterpackage "$operator_name" --no-headers 2>/dev/null || echo "  None"

    echo "--- ClusterPackage conditions ---"
    oc get clusterpackage "$operator_name" -o jsonpath='{.status.conditions}' 2>/dev/null | jq '[.[] | {type, status, reason}]' 2>/dev/null || echo "  None"

    echo "--- ClusterObjectSets ---"
    oc get clusterobjectset -l "package-operator.run/package=$operator_name" \
        -o custom-columns='NAME:.metadata.name,LIFECYCLE:.spec.lifecycleState,REVISION:.spec.revision' \
        --no-headers 2>/dev/null || echo "  None"

    echo "--- Cleanup Jobs ---"
    oc get jobs -n openshift-monitoring --no-headers 2>/dev/null | grep "olm-cleanup" || echo "  None"
}

# Verify the cluster is in the expected state, exit with error if not
verify_expected_state() {
    local namespace="$1"
    local operator_name="$2"
    local expected_state="$3"

    local actual_state
    actual_state=$(detect_deployment_state "$namespace" "$operator_name")

    if [ "$actual_state" != "$expected_state" ]; then
        echo "ERROR: Cluster is in '$actual_state' state but expected '$expected_state'"
        echo ""
        echo "Current cluster state:"
        list_olm_resources "$namespace" "$operator_name"
        echo ""
        list_pko_resources "$operator_name"
        echo ""
        echo "To proceed with testing:"
        case "$expected_state" in
            olm)
                echo "  Run: ./common/install-via-olm.sh to deploy OLM resources"
                ;;
            pko)
                echo "  Run: ./common/phase5-deploy-pko.sh to deploy via PKO"
                ;;
            neither)
                echo "  Run: ./common/phase8-cleanup.sh to remove all operator resources"
                ;;
        esac
        return 1
    fi

    echo "Cluster state verified: $actual_state (expected: $expected_state)"
    return 0
}

# Simulate OLM state by creating the resources OLM/SSS would have deployed
simulate_olm_state() {
    local namespace="$1"
    local operator_name="$2"
    local simulation_dir="$3"

    if [ ! -d "$simulation_dir" ]; then
        echo "ERROR: OLM simulation directory not found: $simulation_dir"
        return 1
    fi

    echo "Creating OLM simulation resources from $simulation_dir..."

    for f in "$simulation_dir"/*.yaml; do
        if [ -f "$f" ]; then
            echo "  Applying: $(basename $f)"
            oc apply -f "$f" 2>&1
        fi
    done

    echo ""
    echo "Verifying OLM simulation state..."
    local state
    state=$(detect_deployment_state "$namespace" "$operator_name")
    if [ "$state" != "olm" ]; then
        echo "WARNING: After simulation, state is '$state' (expected 'olm')"
        echo "Some OLM resources may not have been created correctly."
        list_olm_resources "$namespace" "$operator_name"
        return 1
    fi

    echo "OLM simulation state verified successfully"
    return 0
}
