#!/bin/bash
set -e

# Phase 3: Prepare Test Cluster
# This script verifies cluster access and current CAMO OLM deployment

echo "===================================="
echo "Phase 3: Prepare Test Cluster"
echo "===================================="
echo

# Script runs from operator directory (camo/, rmo/, etc.)
OPERATOR_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load configuration
source "$SCRIPT_DIR/load-config.sh"
load_config "$OPERATOR_DIR"

echo "Configuration loaded:"
echo "  Operator Image: $OPERATOR_IMAGE"
echo "  PKO Package Image: $PKO_IMAGE"
echo

# Source shared cluster verification functions
source "$SCRIPT_DIR/cluster-verification.sh"

echo "===================================="
echo "Step 3.1: Verify Cluster Connection"
echo "===================================="
echo

# Check if already have cluster ID from config
if [ -z "$CLUSTER_ID" ]; then
    read -p "Enter cluster ID or name: " CLUSTER_ID_INPUT
    if [ -z "$CLUSTER_ID_INPUT" ]; then
        echo "ERROR: Cluster ID is required"
        exit 1
    fi
    CLUSTER_ID="$CLUSTER_ID_INPUT"
    echo
fi

echo "Target cluster: $CLUSTER_ID"
echo

# Verify we're connected to the correct cluster
verify_cluster "Phase 3 start"

echo
echo "===================================="
echo "Step 3.2: Check Current OLM Deployment"
echo "===================================="
echo

echo "Checking for ${OPERATOR_NAME} resources in ${OPERATOR_NAMESPACE} namespace..."
echo

# Check for CSV
echo "CSV (ClusterServiceVersion):"
CSV_FOUND=false
CSV_NAME=""
if CSV_LINE=$(oc get csv -n "$OPERATOR_NAMESPACE" 2>/dev/null | grep "$CSV_NAME_PATTERN"); then
    echo "$CSV_LINE"
    CSV_FOUND=true
    CSV_NAME=$(echo "$CSV_LINE" | awk '{print $1}')
else
    echo "  None found"
fi
echo

# Check for Subscription
echo "Subscription:"
SUBSCRIPTION_FOUND=false
if oc get subscription -n "$OPERATOR_NAMESPACE" "$SUBSCRIPTION_NAME" &>/dev/null; then
    oc get subscription -n "$OPERATOR_NAMESPACE" | grep "$OPERATOR_RESOURCE_PREFIX"
    SUBSCRIPTION_FOUND=true
else
    echo "  None found"
fi
echo

# Check for CatalogSource
echo "CatalogSource:"
CATALOGSOURCE_FOUND=false
if oc get catalogsource -n "$OPERATOR_NAMESPACE" "$CATALOGSOURCE_NAME" &>/dev/null; then
    oc get catalogsource -n "$OPERATOR_NAMESPACE" | grep "$OPERATOR_RESOURCE_PREFIX"
    CATALOGSOURCE_FOUND=true
else
    echo "  None found"
fi
echo

# Check for Deployment
echo "Deployment:"
DEPLOYMENT_FOUND=false
if oc get deployment -n "$OPERATOR_NAMESPACE" "$OPERATOR_NAME" &>/dev/null; then
    oc get deployment -n "$OPERATOR_NAMESPACE" "$OPERATOR_NAME"
    DEPLOYMENT_FOUND=true
else
    echo "  Not found"
fi
echo

# Check for Pods
echo "Pods:"
PODS_RUNNING=false
if POD_COUNT=$(oc get pods -n "$OPERATOR_NAMESPACE" 2>/dev/null | grep -c "${OPERATOR_RESOURCE_PREFIX}.*Running" || echo 0); then
    if [ "$POD_COUNT" -gt 0 ]; then
        oc get pods -n "$OPERATOR_NAMESPACE" | grep "$OPERATOR_RESOURCE_PREFIX"
        PODS_RUNNING=true
    else
        echo "  None found"
    fi
else
    echo "  None found"
fi
echo

# Save current state
BACKUP_DIR="$OPERATOR_DIR/backups/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "Backing up current ${OPERATOR_NAME} resources to: $BACKUP_DIR"

oc get csv -n "$OPERATOR_NAMESPACE" -o yaml | grep -A 9999 "$CSV_NAME_PATTERN" > "$BACKUP_DIR/csv.yaml" 2>/dev/null || true
oc get subscription -n "$OPERATOR_NAMESPACE" "$SUBSCRIPTION_NAME" -o yaml > "$BACKUP_DIR/subscription.yaml" 2>/dev/null || true
oc get catalogsource -n "$OPERATOR_NAMESPACE" "$CATALOGSOURCE_NAME" -o yaml > "$BACKUP_DIR/catalogsource.yaml" 2>/dev/null || true
oc get deployment -n "$OPERATOR_NAMESPACE" "$OPERATOR_NAME" -o yaml > "$BACKUP_DIR/deployment.yaml" 2>/dev/null || true

echo "✓ Backup complete"
echo

echo "===================================="
echo "Step 3.3: Check Cluster Environment"
echo "===================================="
echo

# Get cluster version
echo "Checking OpenShift version..."
CLUSTER_VERSION=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "unknown")
echo "  Version: $CLUSTER_VERSION"
echo

# Check if PKO is installed
echo "Checking for Package Operator..."
PKO_INSTALLED=false
if oc get deployment -n openshift-package-operator package-operator-manager &>/dev/null; then
    PKO_VERSION=$(oc get deployment -n openshift-package-operator package-operator-manager -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "unknown")
    echo "  ✓ Package Operator installed"
    echo "  Image: $PKO_VERSION"
    PKO_INSTALLED=true
else
    echo "  ⚠️  Package Operator not found"
fi
echo

# Get cluster platform info
echo "Checking cluster platform..."
CLUSTER_PLATFORM=$(oc get infrastructure cluster -o jsonpath='{.status.platform}' 2>/dev/null || echo "unknown")
CLUSTER_REGION=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.aws.region}' 2>/dev/null || echo "unknown")
echo "  Platform: $CLUSTER_PLATFORM"
echo "  Region: $CLUSTER_REGION"
echo

echo "===================================="
echo "Step 3.4: PAUSE HIVE SYNC (MANUAL)"
echo "===================================="
echo
echo "⚠️  You must now pause Hive syncing to this cluster."
echo
echo "In a SEPARATE terminal/backplane session connected to the HIVE cluster, run:"
echo
echo "  # Step 1: Find the ClusterDeployment"
echo "  oc get clusterdeployment --all-namespaces | grep $CLUSTER_ID"
echo
echo "  # Step 2: Annotate the ClusterDeployment to pause syncing"
echo "  oc annotate clusterdeployment <clusterDeploymentName> \\"
echo "    -n <namespace> \\"
echo "    hive.openshift.io/syncset-pause=\"true\""
echo
echo "This will pause ALL Hive syncing to cluster $CLUSTER_ID:"
echo "  - SyncSets"
echo "  - SelectorSyncSets (including CAMO deployment)"
echo "  - Remote machinesets"
echo
echo "===================================="
echo

read -p "Have you paused the Hive sync? (y/n): " HIVE_CONFIRM
if [ "$HIVE_CONFIRM" != "y" ]; then
    echo "Please pause the Hive sync before continuing."
    echo "Re-run this script when ready."
    exit 0
fi

echo
echo "✓ Hive sync confirmed paused"
echo

echo "===================================="
echo "Re-verify Target Cluster Connection"
echo "===================================="
echo
echo "⚠️  CRITICAL: Verify you are connected to the TARGET test cluster"
echo "             NOT the Hive management cluster!"
echo
verify_cluster "After Hive pause - returning to target cluster"
echo "⚠️  IMPORTANT REMINDER:"
echo "When testing is complete, you MUST unpause Hive sync to restore CAMO deployment."
echo
echo "Unpause command (save this for later):"
echo "  oc annotate clusterdeployment <clusterDeploymentName> \\"
echo "    -n <namespace> \\"
echo "    hive.openshift.io/syncset-pause-"
echo
echo "This will resume ALL Hive syncing and redeploy CAMO via OLM."
echo

# Export variables for runtime state

# Cluster information
export CLUSTER_ID="$CLUSTER_ID"
export CLUSTER_VERSION="$CLUSTER_VERSION"
export CLUSTER_PLATFORM="$CLUSTER_PLATFORM"
export CLUSTER_REGION="$CLUSTER_REGION"

# Backup information
export BACKUP_DIR="$BACKUP_DIR"
export BACKUP_TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# OLM deployment status
export OLM_CSV_FOUND="$CSV_FOUND"
export OLM_CSV_NAME="$CSV_NAME"
export OLM_SUBSCRIPTION_FOUND="$SUBSCRIPTION_FOUND"
export OLM_CATALOGSOURCE_FOUND="$CATALOGSOURCE_FOUND"
export OLM_DEPLOYMENT_FOUND="$DEPLOYMENT_FOUND"
export OLM_PODS_RUNNING="$PODS_RUNNING"

# Environment checks
export PKO_INSTALLED="$PKO_INSTALLED"
export HIVE_PAUSED=true

# Save runtime state
save_runtime_state "$OPERATOR_DIR" "phase3-prepare-cluster" "success"

echo "===================================="
echo "Preparation Complete!"
echo "===================================="
echo
echo "Operator: $OPERATOR_NAME"
echo "Cluster: $CLUSTER_ID"
echo "Current deployment: OLM-based"
echo "Backup location: $BACKUP_DIR"
echo "Hive sync: PAUSED"
echo
echo "Next step: Run phase4-prepare-migration.sh"
