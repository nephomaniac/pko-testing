#!/bin/bash
set -e

# Phase 3: Prepare Test Cluster
# This script verifies cluster access and current CAMO OLM deployment

echo "===================================="
echo "Phase 3: Prepare Test Cluster"
echo "===================================="
echo

# Load configuration
CONFIG_FILE="$(cd "$(dirname "$0")" && pwd)/.camo-pko-test-config"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    echo "Please run phase1-build-images.sh first"
    exit 1
fi

source "$CONFIG_FILE"

echo "Configuration loaded:"
echo "  Operator Image: $OPERATOR_IMAGE"
echo "  PKO Package Image: $PKO_IMAGE"
echo

# Source shared cluster verification functions
# Script runs from operator directory (camo/, rmo/, etc.)
OPERATOR_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/cluster-verification.sh"

echo "===================================="
echo "Cluster Setup and Verification"
echo "===================================="
echo

# Prompt for cluster info
read -p "Enter cluster ID or name: " CLUSTER_ID
if [ -z "$CLUSTER_ID" ]; then
    echo "ERROR: Cluster ID is required"
    exit 1
fi

echo
echo "Verifying connection to cluster: $CLUSTER_ID"
echo

# Save cluster info (including UUID) to config
save_cluster_info "$CLUSTER_ID" "$CONFIG_FILE"
echo

# Reload config with new cluster info
source "$CONFIG_FILE"

# Verify we're on the correct cluster
verify_cluster "Phase 3 start - after cluster ID entry"

echo
echo "===================================="
echo "Step 3.2: Check Current CAMO Deployment (OLM)"
echo "===================================="
echo

echo "Checking for CAMO resources in openshift-monitoring namespace..."
echo

echo "CSV (ClusterServiceVersion):"
oc get csv -n openshift-monitoring | grep configure-alertmanager || echo "  None found"
echo

echo "Subscription:"
oc get subscription -n openshift-monitoring | grep configure-alertmanager || echo "  None found"
echo

echo "CatalogSource:"
oc get catalogsource -n openshift-monitoring | grep configure-alertmanager || echo "  None found"
echo

echo "Deployment:"
oc get deployment -n openshift-monitoring configure-alertmanager-operator 2>/dev/null || echo "  Not found"
echo

echo "Pods:"
oc get pods -n openshift-monitoring | grep configure-alertmanager || echo "  None found"
echo

# Save current state
BACKUP_DIR="$OPERATOR_DIR/backups/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "Backing up current CAMO resources to: $BACKUP_DIR"

oc get csv -n openshift-monitoring -o yaml | grep -A 9999 "configure-alertmanager" > "$BACKUP_DIR/csv.yaml" 2>/dev/null || true
oc get subscription -n openshift-monitoring configure-alertmanager-operator -o yaml > "$BACKUP_DIR/subscription.yaml" 2>/dev/null || true
oc get catalogsource -n openshift-monitoring configure-alertmanager-operator-registry -o yaml > "$BACKUP_DIR/catalogsource.yaml" 2>/dev/null || true
oc get deployment -n openshift-monitoring configure-alertmanager-operator -o yaml > "$BACKUP_DIR/deployment.yaml" 2>/dev/null || true

echo "✓ Backup complete"
echo

echo "===================================="
echo "Step 3.3: PAUSE HIVE SYNC (MANUAL)"
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

echo "===================================="
echo "Preparation Complete!"
echo "===================================="
echo
echo "Cluster: $CLUSTER_ID"
echo "Current CAMO deployment: OLM-based"
echo "Backup location: $BACKUP_DIR"
echo "Hive sync: PAUSED"
echo
echo "Next step: Run phase4-remove-olm.sh"
