#!/bin/bash
set -e

# Phase 4: Remove OLM Artifacts
# This script removes the existing OLM-based CAMO deployment

echo "===================================="
echo "Phase 4: Remove OLM Artifacts"
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
verify_cluster "Phase 4 start"

echo "Target cluster: $CLUSTER_ID"
echo

echo "⚠️  WARNING: This will remove the current CAMO OLM deployment."
echo "Make sure you have:"
echo "  1. Paused the Hive sync"
echo "  2. Backed up the current deployment (phase3 did this)"
echo

read -p "Continue with OLM removal? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "Aborted."
    exit 0
fi

echo
echo "===================================="
echo "Step 4.1: Scale Down Operator"
echo "===================================="
echo

if oc get deployment configure-alertmanager-operator -n openshift-monitoring &>/dev/null; then
    if confirm_operation "SCALE DOWN DEPLOYMENT" \
        "oc scale deployment configure-alertmanager-operator -n openshift-monitoring --replicas=0"; then

        oc scale deployment configure-alertmanager-operator \
          -n openshift-monitoring --replicas=0

        echo "Waiting for pod termination..."
        sleep 5
        echo "✓ Deployment scaled down"
    else
        echo "Aborted scale down"
        exit 0
    fi
else
    echo "⚠️  Deployment not found, skipping scale down"
fi

echo

echo "===================================="
echo "Step 4.2: Delete OLM Resources"
echo "===================================="
echo

# Check which resources exist
COMMANDS=()
HAS_SUBSCRIPTION=false
HAS_CSV=false
HAS_CATALOGSOURCE=false
CSV_NAME=""

if oc get subscription configure-alertmanager-operator -n openshift-monitoring &>/dev/null; then
    COMMANDS+=("oc delete subscription configure-alertmanager-operator -n openshift-monitoring")
    HAS_SUBSCRIPTION=true
fi

CSV_NAME=$(oc get csv -n openshift-monitoring -o name 2>/dev/null | grep configure-alertmanager | head -1)
if [ -n "$CSV_NAME" ]; then
    COMMANDS+=("oc delete $CSV_NAME -n openshift-monitoring")
    HAS_CSV=true
fi

if oc get catalogsource configure-alertmanager-operator-registry -n openshift-monitoring &>/dev/null; then
    COMMANDS+=("oc delete catalogsource configure-alertmanager-operator-registry -n openshift-monitoring")
    HAS_CATALOGSOURCE=true
fi

# Confirm and execute deletions
if [ ${#COMMANDS[@]} -gt 0 ]; then
    if confirm_operation "DELETE OLM RESOURCES" "${COMMANDS[@]}"; then
        # Delete Subscription
        if [ "$HAS_SUBSCRIPTION" = true ]; then
            echo "Deleting Subscription..."
            oc delete subscription configure-alertmanager-operator -n openshift-monitoring
            echo "✓ Subscription deleted"
            echo
        fi

        # Delete CSV
        if [ "$HAS_CSV" = true ]; then
            echo "Deleting ClusterServiceVersion..."
            oc delete "$CSV_NAME" -n openshift-monitoring
            echo "✓ CSV deleted: $CSV_NAME"
            echo
        fi

        # Delete CatalogSource
        if [ "$HAS_CATALOGSOURCE" = true ]; then
            echo "Deleting CatalogSource..."
            oc delete catalogsource configure-alertmanager-operator-registry -n openshift-monitoring
            echo "✓ CatalogSource deleted"
            echo
        fi
    else
        echo "Aborted OLM resource deletion"
        exit 0
    fi
else
    echo "⚠️  No OLM resources found to delete"
    echo
fi

# Wait for cleanup
echo "Waiting for OLM cleanup to complete..."
sleep 10

echo
echo "===================================="
echo "Step 4.3: Verify Cleanup"
echo "===================================="
echo

echo "Checking for remaining OLM resources..."
echo

OLM_CSV=$(oc get csv -n openshift-monitoring 2>/dev/null | grep configure-alertmanager || echo "")
OLM_SUB=$(oc get subscription -n openshift-monitoring 2>/dev/null | grep configure-alertmanager || echo "")
OLM_CAT=$(oc get catalogsource -n openshift-monitoring 2>/dev/null | grep configure-alertmanager || echo "")

if [ -z "$OLM_CSV" ] && [ -z "$OLM_SUB" ] && [ -z "$OLM_CAT" ]; then
    echo "✓ All OLM resources removed successfully"
else
    echo "⚠️  WARNING: Some OLM resources still present:"
    [ -n "$OLM_CSV" ] && echo "  CSV: $OLM_CSV"
    [ -n "$OLM_SUB" ] && echo "  Subscription: $OLM_SUB"
    [ -n "$OLM_CAT" ] && echo "  CatalogSource: $OLM_CAT"
    echo
    read -p "Continue anyway? (y/n): " CONTINUE
    if [ "$CONTINUE" != "y" ]; then
        echo "Aborted."
        exit 1
    fi
fi

echo

echo "Checking if operator deployment still exists..."
if oc get deployment configure-alertmanager-operator -n openshift-monitoring &>/dev/null; then
    echo "⚠️  Deployment still exists (this is expected - it will be replaced by PKO)"
else
    echo "✓ Deployment removed by OLM cleanup"
fi

echo

echo "===================================="
echo "OLM Cleanup Complete!"
echo "===================================="
echo
echo "OLM resources removed:"
echo "  ✓ Subscription"
echo "  ✓ ClusterServiceVersion"
echo "  ✓ CatalogSource"
echo
echo "Remaining resources (managed by PKO):"
echo "  - RBAC (ClusterRole, ClusterRoleBinding, ServiceAccount)"
echo "  - CRD (AlertManager)"
echo "  - Deployment (will be replaced)"
echo
echo "Next step: Run phase5-deploy-pko.sh"
