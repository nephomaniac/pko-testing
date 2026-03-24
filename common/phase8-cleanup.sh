#!/bin/bash
set -e

# Phase 8: Cleanup / Rollback
# This script removes the PKO deployment and optionally restores OLM

echo "===================================="
echo "Phase 8: Cleanup PKO Deployment"
echo "===================================="
echo

# Load configuration
CONFIG_FILE="$(cd "$(dirname "$0")" && pwd)/.camo-pko-test-config"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

# Source shared cluster verification functions
# Script runs from operator directory (camo/, rmo/, etc.)
OPERATOR_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/cluster-verification.sh"

echo "===================================="
echo "Verify Cluster Connection"
echo "===================================="
echo
verify_cluster "Phase 8 start"

echo "Target cluster: $CLUSTER_ID"
echo

echo "⚠️  WARNING: This will remove the PKO-based CAMO deployment."
echo

read -p "Continue with PKO cleanup? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "Aborted."
    exit 0
fi

echo

echo "===================================="
echo "Step 8.1: Delete ClusterPackage"
echo "===================================="
echo

if oc get clusterpackage configure-alertmanager-operator &>/dev/null; then
    if confirm_operation "DELETE CLUSTERPACKAGE" \
        "oc delete clusterpackage configure-alertmanager-operator"; then

        echo "Deleting ClusterPackage..."
        oc delete clusterpackage configure-alertmanager-operator

        echo "Waiting for PKO to clean up resources..."
        sleep 10

        echo "✓ ClusterPackage deleted"
    else
        echo "Aborted ClusterPackage deletion"
        exit 0
    fi
else
    echo "⚠️  ClusterPackage not found"
fi

echo

echo "===================================="
echo "Step 8.2: Verify Cleanup"
echo "===================================="
echo

echo "Checking for remaining PKO-managed resources..."
echo

if oc get deployment configure-alertmanager-operator -n openshift-monitoring &>/dev/null; then
    echo "  ⚠️  Deployment still exists"
    read -p "Manually delete deployment? (y/n): " DELETE_DEPLOY
    if [ "$DELETE_DEPLOY" = "y" ]; then
        if confirm_operation "DELETE DEPLOYMENT (MANUAL CLEANUP)" \
            "oc delete deployment configure-alertmanager-operator -n openshift-monitoring"; then

            oc delete deployment configure-alertmanager-operator -n openshift-monitoring
            echo "  ✓ Deployment deleted"
        else
            echo "  Skipped deployment deletion"
        fi
    fi
else
    echo "  ✓ Deployment removed"
fi

if oc get clusterrole configure-alertmanager-operator &>/dev/null; then
    echo "  ⚠️  ClusterRole still exists"
else
    echo "  ✓ ClusterRole removed"
fi

if oc get clusterrolebinding configure-alertmanager-operator &>/dev/null; then
    echo "  ⚠️  ClusterRoleBinding still exists"
else
    echo "  ✓ ClusterRoleBinding removed"
fi

echo

echo "===================================="
echo "Step 8.3: Restore Hive Sync (MANUAL)"
echo "===================================="
echo
echo "To restore the OLM-based CAMO deployment, you must resume Hive sync."
echo
echo "In a SEPARATE terminal/backplane session connected to the HIVE cluster, run:"
echo
echo "  # Remove the syncset-pause annotation from ClusterDeployment"
echo "  oc annotate clusterdeployment <clusterDeploymentName> \\"
echo "    -n <namespace> \\"
echo "    hive.openshift.io/syncset-pause-"
echo
echo "This will resume ALL Hive syncing and redeploy CAMO via OLM."
echo
echo "===================================="
echo

read -p "Have you resumed the Hive sync? (y/n): " HIVE_CONFIRM
if [ "$HIVE_CONFIRM" != "y" ]; then
    echo
    echo "Remember to resume Hive sync when ready!"
    echo "The cluster will not have CAMO running until Hive sync is restored."
else
    echo
    echo "===================================="
    echo "Re-verify Target Cluster Connection"
    echo "===================================="
    echo
    echo "⚠️  CRITICAL: Verify you are connected to the TARGET test cluster"
    echo "             NOT the Hive management cluster!"
    echo
    verify_cluster "After Hive sync restoration - returning to target cluster"
fi

echo

echo "===================================="
echo "Cleanup Complete!"
echo "===================================="
echo
echo "PKO deployment removed from cluster: $CLUSTER_ID"
echo
echo "Backup location (for reference):"
BACKUP_DIR=$(ls -dt $(cd "$(dirname "$0")" && pwd)/backups/backup-* 2>/dev/null | head -1)
if [ -n "$BACKUP_DIR" ]; then
    echo "  $BACKUP_DIR"
else
    echo "  No backup found"
fi
echo
echo "Next steps:"
echo "  1. Verify Hive sync is resumed"
echo "  2. Wait for OLM-based CAMO to redeploy (~5-10 minutes)"
echo "  3. Verify OLM deployment: oc get csv,subscription -n openshift-monitoring | grep configure-alertmanager"
echo

read -p "Monitor OLM redeployment now? (y/n): " MONITOR
if [ "$MONITOR" = "y" ]; then
    echo
    echo "Watching for OLM resources to appear..."
    echo "Press Ctrl+C to stop"
    sleep 2

    while true; do
        clear
        echo "Waiting for CAMO OLM deployment..."
        echo "=================================="
        echo
        echo "CSV:"
        oc get csv -n openshift-monitoring 2>/dev/null | grep configure-alertmanager || echo "  Not found yet"
        echo
        echo "Subscription:"
        oc get subscription -n openshift-monitoring 2>/dev/null | grep configure-alertmanager || echo "  Not found yet"
        echo
        echo "CatalogSource:"
        oc get catalogsource -n openshift-monitoring 2>/dev/null | grep configure-alertmanager || echo "  Not found yet"
        echo
        echo "Deployment:"
        oc get deployment -n openshift-monitoring configure-alertmanager-operator 2>/dev/null || echo "  Not found yet"

        sleep 10
    done
fi
