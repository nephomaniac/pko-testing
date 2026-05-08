#!/bin/bash
#
# Dump the complete OLM deployment state for an operator on a cluster.
# Captures every resource that OLM/SSS created, with ownerReferences,
# labels, and annotations to trace how each resource was created.
#
# Usage:
#   ./dump-olm-state.sh [NAMESPACE] [OPERATOR_NAME] [OUTPUT_DIR]
#
# Defaults:
#   NAMESPACE=openshift-monitoring
#   OPERATOR_NAME=configure-alertmanager-operator
#   OUTPUT_DIR=./olm-state-dump-$(date +%Y%m%d-%H%M%S)
#
# Requires: oc, jq
# For RBAC resources, may need elevated access:
#   ocm backplane elevate "dumping OLM state" -- ./dump-olm-state.sh

set -euo pipefail

NAMESPACE="${1:-openshift-monitoring}"
OPERATOR_NAME="${2:-configure-alertmanager-operator}"
OUTPUT_DIR="${3:-./olm-state-dump-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$OUTPUT_DIR"

echo "=== OLM State Dump ==="
echo "Cluster: $(oc whoami --show-server 2>/dev/null || echo 'unknown')"
echo "User: $(oc whoami 2>/dev/null || echo 'unknown')"
echo "Namespace: $NAMESPACE"
echo "Operator: $OPERATOR_NAME"
echo "Output: $OUTPUT_DIR"
echo "Date: $(date -u)"
echo ""

# Helper to dump a resource with ownership details
dump_resource() {
    local kind="$1"
    local name="$2"
    local ns="${3:-}"
    local file="$OUTPUT_DIR/${kind}-${name}.yaml"

    local ns_flag=""
    if [ -n "$ns" ]; then
        ns_flag="-n $ns"
    fi

    echo "--- $kind/$name ${ns:+(ns: $ns)} ---"
    if oc get $ns_flag "$kind" "$name" &>/dev/null; then
        oc get $ns_flag "$kind" "$name" -o yaml > "$file" 2>/dev/null
        echo "  EXISTS → $file"
        echo "  ownerReferences: $(oc get $ns_flag "$kind" "$name" -o jsonpath='{.metadata.ownerReferences}' 2>/dev/null | jq -c '.' 2>/dev/null || echo 'none')"
        echo "  labels: $(oc get $ns_flag "$kind" "$name" -o jsonpath='{.metadata.labels}' 2>/dev/null | jq -c '.' 2>/dev/null || echo 'none')"
        echo "  annotations: $(oc get $ns_flag "$kind" "$name" -o jsonpath='{.metadata.annotations}' 2>/dev/null | jq -c 'with_entries(select(.key | startswith("package-operator") or startswith("hive") or startswith("olm") or startswith("operators")))' 2>/dev/null || echo 'none')"
    else
        echo "  NOT FOUND"
    fi
    echo ""
}

# Helper to dump elevated resources (roles, rolebindings)
dump_resource_elevated() {
    local kind="$1"
    local name="$2"
    local ns="${3:-}"
    local file="$OUTPUT_DIR/${kind}-${name}.yaml"

    local ns_flag=""
    if [ -n "$ns" ]; then
        ns_flag="-n $ns"
    fi

    echo "--- $kind/$name ${ns:+(ns: $ns)} [elevated] ---"
    if ocm backplane elevate "OLM state dump" -- oc get $ns_flag "$kind" "$name" &>/dev/null; then
        ocm backplane elevate "OLM state dump" -- oc get $ns_flag "$kind" "$name" -o yaml > "$file" 2>/dev/null
        echo "  EXISTS → $file"
        local owner
        owner=$(ocm backplane elevate "OLM state dump" -- oc get $ns_flag "$kind" "$name" -o jsonpath='{.metadata.ownerReferences}' 2>/dev/null || echo "")
        echo "  ownerReferences: $(echo "$owner" | jq -c '.' 2>/dev/null || echo 'none')"
    elif oc get $ns_flag "$kind" "$name" &>/dev/null; then
        oc get $ns_flag "$kind" "$name" -o yaml > "$file" 2>/dev/null
        echo "  EXISTS → $file (non-elevated)"
    else
        echo "  NOT FOUND"
    fi
    echo ""
}

echo "=========================================="
echo "Section 1: OLM SSS Resources"
echo "=========================================="
dump_resource "catalogsource.operators.coreos.com" "${OPERATOR_NAME}-registry" "$NAMESPACE"
dump_resource "subscription.operators.coreos.com" "$OPERATOR_NAME" "$NAMESPACE"
dump_resource "clusterrolebinding" "${OPERATOR_NAME}-prom"

echo "=========================================="
echo "Section 2: OLM CSV and Install Strategy"
echo "=========================================="
echo "--- CSV ---"
CSV_NAME=$(oc get csv -n "$NAMESPACE" -l "operators.coreos.com/${OPERATOR_NAME}.${NAMESPACE}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$CSV_NAME" ]; then
    oc get csv -n "$NAMESPACE" "$CSV_NAME" -o yaml > "$OUTPUT_DIR/CSV-${CSV_NAME}.yaml" 2>/dev/null
    echo "  CSV found: $CSV_NAME → $OUTPUT_DIR/CSV-${CSV_NAME}.yaml"
    echo "  finalizers: $(oc get csv -n "$NAMESPACE" "$CSV_NAME" -o jsonpath='{.metadata.finalizers}' 2>/dev/null)"
    echo ""
    echo "  Install strategy resources (what OLM creates):"
    echo "    clusterPermissions:"
    oc get csv -n "$NAMESPACE" "$CSV_NAME" -o json 2>/dev/null | \
        jq -r '.spec.install.spec.clusterPermissions // [] | length | "      count: \(.)"' 2>/dev/null || echo "      unknown"
    oc get csv -n "$NAMESPACE" "$CSV_NAME" -o json 2>/dev/null | \
        jq -r '.spec.install.spec.clusterPermissions // [] | .[].serviceAccountName' 2>/dev/null | \
        sed 's/^/      sa: /' || true
    echo "    permissions:"
    oc get csv -n "$NAMESPACE" "$CSV_NAME" -o json 2>/dev/null | \
        jq -r '.spec.install.spec.permissions // [] | length | "      count: \(.)"' 2>/dev/null || echo "      unknown"
    echo "    deployments:"
    oc get csv -n "$NAMESPACE" "$CSV_NAME" -o json 2>/dev/null | \
        jq -r '.spec.install.spec.deployments // [] | .[].name' 2>/dev/null | \
        sed 's/^/      /' || true
else
    echo "  CSV NOT FOUND (no label match for operators.coreos.com/${OPERATOR_NAME}.${NAMESPACE})"
fi
echo ""

echo "=========================================="
echo "Section 3: Namespace-scoped Resources"
echo "=========================================="
dump_resource "serviceaccount" "$OPERATOR_NAME" "$NAMESPACE"
dump_resource "deployment" "$OPERATOR_NAME" "$NAMESPACE"
dump_resource_elevated "role" "$OPERATOR_NAME" "$NAMESPACE"
dump_resource_elevated "rolebinding" "$OPERATOR_NAME" "$NAMESPACE"

echo "=========================================="
echo "Section 4: Cluster-scoped Resources"
echo "=========================================="
dump_resource "clusterrole" "${OPERATOR_NAME}-view"
dump_resource "clusterrole" "${OPERATOR_NAME}-edit"
dump_resource "clusterrolebinding" "${OPERATOR_NAME}-view"
dump_resource "clusterrolebinding" "${OPERATOR_NAME}-edit"

echo "=========================================="
echo "Section 5: PKO Resources (if present)"
echo "=========================================="
dump_resource "clusterpackage" "$OPERATOR_NAME"
echo "--- ClusterObjectSets ---"
oc get clusterobjectset -l "package-operator.run/package=$OPERATOR_NAME" \
    -o custom-columns='NAME:.metadata.name,LIFECYCLE:.spec.lifecycleState,REVISION:.spec.revision' \
    --no-headers 2>/dev/null || echo "  None"
echo ""
echo "--- Cleanup Jobs ---"
oc get jobs -n "$NAMESPACE" --no-headers 2>/dev/null | grep "olm-cleanup" || echo "  None"
echo ""

echo "=========================================="
echo "Section 6: All resources in namespace with operator labels"
echo "=========================================="
echo "--- Resources with olm.managed=true ---"
for kind in serviceaccount deployment configmap secret role rolebinding; do
    matches=$(oc get "$kind" -n "$NAMESPACE" -l "olm.managed=true" --no-headers 2>/dev/null | grep "$OPERATOR_NAME" || true)
    if [ -n "$matches" ]; then
        echo "  $kind:"
        echo "$matches" | sed 's/^/    /'
    fi
done 2>/dev/null
echo ""
echo "--- Resources with hive.openshift.io/managed=true ---"
for kind in serviceaccount clusterrolebinding; do
    matches=$(oc get "$kind" -l "hive.openshift.io/managed=true" --no-headers 2>/dev/null | grep "$OPERATOR_NAME" || true)
    if [ -n "$matches" ]; then
        echo "  $kind:"
        echo "$matches" | sed 's/^/    /'
    fi
done 2>/dev/null
echo ""
echo "--- Resources with package-operator.run labels ---"
for kind in serviceaccount deployment role rolebinding clusterrole clusterrolebinding; do
    matches=$(oc get "$kind" -l "package-operator.run/package=$OPERATOR_NAME" --no-headers -A 2>/dev/null || true)
    if [ -n "$matches" ]; then
        echo "  $kind:"
        echo "$matches" | sed 's/^/    /'
    fi
done 2>/dev/null
echo ""

echo "=========================================="
echo "Section 7: OperatorGroup"
echo "=========================================="
oc get operatorgroup -n "$NAMESPACE" -o yaml > "$OUTPUT_DIR/OperatorGroup.yaml" 2>/dev/null
oc get operatorgroup -n "$NAMESPACE" -o json 2>/dev/null | \
    jq '.items[] | {name: .metadata.name, targetNamespaces: .spec.targetNamespaces, ownerReferences: .metadata.ownerReferences}' 2>/dev/null || echo "  None or inaccessible"
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Files written to: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"/*.yaml 2>/dev/null | wc -l | xargs echo "Total YAML files:"
echo ""
echo "Deployment method: $(
    has_csv=false
    has_pko=false
    [ -n "$CSV_NAME" ] && has_csv=true
    oc get clusterpackage "$OPERATOR_NAME" &>/dev/null && has_pko=true
    if $has_csv && $has_pko; then echo "BOTH (migration in progress)"
    elif $has_csv; then echo "OLM"
    elif $has_pko; then echo "PKO"
    else echo "NEITHER"
    fi
)"
echo ""
echo "=== Dump Complete ==="
