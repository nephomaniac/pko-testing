#!/bin/bash
set -e

# Phase 7: Functional Testing
# This script verifies that CAMO is functioning correctly via PKO

echo "===================================="
echo "Phase 7: Functional Testing"
echo "===================================="
echo

# Script runs from operator directory (camo/, rmo/, etc.)
OPERATOR_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load configuration
source "$SCRIPT_DIR/load-config.sh"
load_config "$OPERATOR_DIR"

# Source shared cluster verification functions
source "$SCRIPT_DIR/cluster-verification.sh"

echo "===================================="
echo "Verify Cluster Connection"
echo "===================================="
echo
verify_cluster "Phase 7 start"

echo "Testing CAMO PKO deployment on cluster: $CLUSTER_ID"
echo

echo "===================================="
echo "Test 1: Operator Running and Healthy"
echo "===================================="
echo

DEPLOYMENT=$(oc get deployment configure-alertmanager-operator -n openshift-monitoring -o jsonpath='{.status}' 2>/dev/null)

if [ -z "$DEPLOYMENT" ]; then
    echo "✗ FAILED: Deployment not found"
    exit 1
fi

READY_REPLICAS=$(oc get deployment configure-alertmanager-operator -n openshift-monitoring -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
REPLICAS=$(oc get deployment configure-alertmanager-operator -n openshift-monitoring -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

if [ "$READY_REPLICAS" -eq "$REPLICAS" ]; then
    echo "✓ PASSED: Deployment is healthy ($READY_REPLICAS/$REPLICAS replicas ready)"
else
    echo "✗ FAILED: Deployment not ready ($READY_REPLICAS/$REPLICAS replicas ready)"
fi

echo

echo "===================================="
echo "Test 2: Operator Logs Show Reconciliation"
echo "===================================="
echo

POD_NAME=$(oc get pods -n openshift-monitoring -l name=configure-alertmanager-operator \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD_NAME" ]; then
    echo "✗ FAILED: Operator pod not found"
else
    echo "Checking logs for reconciliation activity..."
    RECONCILE_COUNT=$(oc logs -n openshift-monitoring "$POD_NAME" --tail=200 2>/dev/null | grep -i "reconcil" | wc -l)

    if [ "$RECONCILE_COUNT" -gt 0 ]; then
        echo "✓ PASSED: Operator is reconciling ($RECONCILE_COUNT reconciliation log entries)"
    else
        echo "⚠️  WARNING: No reconciliation logs found"
    fi

    # Check for errors
    ERROR_COUNT=$(oc logs -n openshift-monitoring "$POD_NAME" --tail=200 2>/dev/null | grep -i "error" | wc -l)
    if [ "$ERROR_COUNT" -gt 0 ]; then
        echo "⚠️  WARNING: $ERROR_COUNT error messages in logs"
        echo
        echo "Recent errors:"
        oc logs -n openshift-monitoring "$POD_NAME" --tail=200 2>/dev/null | grep -i "error" | tail -5
    else
        echo "✓ No errors in recent logs"
    fi
fi

echo

echo "===================================="
echo "Test 3: AlertManager CRD Exists"
echo "===================================="
echo

if oc get crd alertmanagers.managed.openshift.io &>/dev/null; then
    echo "✓ PASSED: AlertManager CRD exists"
else
    echo "✗ FAILED: AlertManager CRD not found"
fi

echo

echo "===================================="
echo "Test 4: AlertManager CR Created"
echo "===================================="
echo

AM_COUNT=$(oc get alertmanager -n openshift-monitoring --no-headers 2>/dev/null | wc -l)

if [ "$AM_COUNT" -gt 0 ]; then
    echo "✓ PASSED: AlertManager CRs exist ($AM_COUNT found)"
    oc get alertmanager -n openshift-monitoring
else
    echo "⚠️  WARNING: No AlertManager CRs found (may be expected depending on cluster config)"
fi

echo

echo "===================================="
echo "Test 5: RBAC Permissions"
echo "===================================="
echo

echo "Checking ClusterRole..."
if oc get clusterrole configure-alertmanager-operator &>/dev/null; then
    echo "  ✓ ClusterRole exists"
else
    echo "  ✗ ClusterRole not found"
fi

echo "Checking ClusterRoleBinding..."
if oc get clusterrolebinding configure-alertmanager-operator &>/dev/null; then
    echo "  ✓ ClusterRoleBinding exists"
else
    echo "  ✗ ClusterRoleBinding not found"
fi

echo "Checking Prometheus ClusterRoleBinding..."
if oc get clusterrolebinding configure-alertmanager-operator-prom &>/dev/null; then
    echo "  ✓ Prometheus ClusterRoleBinding exists"
else
    echo "  ✗ Prometheus ClusterRoleBinding not found"
fi

echo

echo "===================================="
echo "Test 6: Secrets/ConfigMaps"
echo "===================================="
echo

echo "Checking for alertmanager-related secrets..."
SECRET_COUNT=$(oc get secrets -n openshift-monitoring 2>/dev/null | grep -i alertmanager | wc -l)
if [ "$SECRET_COUNT" -gt 0 ]; then
    echo "  ✓ Found $SECRET_COUNT alertmanager secret(s)"
else
    echo "  ⚠️  No alertmanager secrets found"
fi

echo

echo "===================================="
echo "Test 7: ClusterPackage Health"
echo "===================================="
echo

PHASE=$(oc get clusterpackage configure-alertmanager-operator -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
AVAILABLE=$(oc get clusterpackage configure-alertmanager-operator -o jsonpath="{.status.conditions[?(@.type=='Available')].status}" 2>/dev/null || echo "Unknown")

if [ "$PHASE" = "Available" ] && [ "$AVAILABLE" = "True" ]; then
    echo "✓ PASSED: ClusterPackage is Available"
else
    echo "✗ FAILED: ClusterPackage not Available (Phase: $PHASE, Available: $AVAILABLE)"
fi

echo

echo "===================================="
echo "Test Summary"
echo "===================================="
echo
echo "Deployment: $([ "$READY_REPLICAS" -eq "$REPLICAS" ] && echo "✓ PASSED" || echo "✗ FAILED")"
echo "Reconciliation: $([ "$RECONCILE_COUNT" -gt 0 ] && echo "✓ PASSED" || echo "⚠️  WARNING")"
echo "CRD: $(oc get crd alertmanagers.managed.openshift.io &>/dev/null && echo "✓ PASSED" || echo "✗ FAILED")"
echo "ClusterPackage: $([ "$PHASE" = "Available" ] && echo "✓ PASSED" || echo "✗ FAILED")"
echo
echo "Overall: $([ "$PHASE" = "Available" ] && [ "$READY_REPLICAS" -eq "$REPLICAS" ] && echo "✓ PASSED" || echo "⚠️  ISSUES DETECTED")"
echo

if [ "$PHASE" = "Available" ] && [ "$READY_REPLICAS" -eq "$REPLICAS" ]; then
    echo "===================================="
    echo "🎉 SUCCESS!"
    echo "===================================="
    echo
    echo "CAMO is successfully deployed via PKO!"
    echo
    echo "Images used:"
    echo "  Operator: $OPERATOR_IMAGE"
    echo "  PKO Package: $PKO_IMAGE"
    echo
    echo "Keep this deployment running for extended testing, or:"
    echo "  - Run phase8-cleanup.sh to remove PKO deployment"
    echo "  - Resume Hive sync to restore OLM deployment"
else
    echo "===================================="
    echo "⚠️  ISSUES DETECTED"
    echo "===================================="
    echo
    echo "Troubleshooting steps:"
    echo "  1. Check ClusterPackage: oc describe clusterpackage configure-alertmanager-operator"
    echo "  2. Check PKO logs: oc logs -n package-operator-system deployment/package-operator-manager"
    echo "  3. Check operator logs: oc logs -n openshift-monitoring deployment/configure-alertmanager-operator"
    echo "  4. Check events: oc get events -n openshift-monitoring --sort-by='.lastTimestamp' | tail -20"
fi
