#!/bin/bash
set -e

# Phase 5: Deploy via PKO
# This script creates the ClusterPackage to deploy CAMO via Package Operator
# Supports both Mode 1 (PKO cleanup) and Mode 2 (manual cleanup)

PHASE_NUM=5
# Script runs from operator directory (camo/, rmo/, etc.)
OPERATOR_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Setup logging
LOG_DIR="$OPERATOR_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/phase${PHASE_NUM}-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===================================="
echo "Phase 5: Deploy CAMO via PKO"
echo "===================================="
echo "Started at: $(date)"
echo "Log file: $LOG_FILE"
echo

# Load configuration
source "$SCRIPT_DIR/load-config.sh"
load_config "$OPERATOR_DIR"

# Source shared cluster verification functions
source "$SCRIPT_DIR/cluster-verification.sh"

echo "===================================="
echo "Verify Cluster Connection"
echo "===================================="
echo
verify_cluster "Phase 5 start"

echo "Configuration:"
echo "  Cluster: $CLUSTER_ID"
echo "  Operator Image: $OPERATOR_IMAGE"
echo "  PKO Package Image: $PKO_IMAGE"
echo "  Migration Mode: ${MIGRATION_MODE:-unknown}"
echo "  OLM Cleanup Method: ${OLM_CLEANUP_METHOD:-unknown}"
echo

# Check migration mode
if [ -z "$MIGRATION_MODE" ]; then
    echo "ERROR: MIGRATION_MODE not set in config"
    echo "Please run phase4-prepare-migration.sh first"
    exit 1
fi

echo "===================================="
echo "Step 5.1: Pre-Deployment State Check"
echo "===================================="
echo

echo "Checking current OLM state..."
OLM_SUB_EXISTS=false
OLM_CSV_EXISTS=false
OLM_CAT_EXISTS=false

if oc get subscription configure-alertmanager-operator -n openshift-monitoring &>/dev/null; then
    OLM_SUB_EXISTS=true
    echo "  - Subscription: EXISTS"
fi

CSV_NAME=$(oc get csv -n openshift-monitoring -o name 2>/dev/null | grep configure-alertmanager | head -1)
if [ -n "$CSV_NAME" ]; then
    OLM_CSV_EXISTS=true
    echo "  - CSV: EXISTS ($CSV_NAME)"
fi

if oc get catalogsource configure-alertmanager-operator-registry -n openshift-monitoring &>/dev/null; then
    OLM_CAT_EXISTS=true
    echo "  - CatalogSource: EXISTS"
fi

echo

# Verify expected state based on mode
if [ "$MIGRATION_MODE" = "1" ]; then
    echo "Migration Mode 1: PKO will cleanup OLM resources"
    if [ "$OLM_SUB_EXISTS" = false ] && [ "$OLM_CSV_EXISTS" = false ] && [ "$OLM_CAT_EXISTS" = false ]; then
        echo "⚠️  WARNING: No OLM resources found, but Mode 1 was selected."
        echo "Mode 1 is designed to test PKO cleanup of existing OLM resources."
        echo
        read -p "Continue anyway? (y/n): " CONTINUE
        if [ "$CONTINUE" != "y" ]; then
            echo "Aborted."
            exit 0
        fi
    else
        echo "✓ OLM resources present - PKO cleanup will be tested"
    fi
elif [ "$MIGRATION_MODE" = "2" ]; then
    echo "Migration Mode 2: OLM resources already removed manually"
    if [ "$OLM_SUB_EXISTS" = true ] || [ "$OLM_CSV_EXISTS" = true ] || [ "$OLM_CAT_EXISTS" = true ]; then
        echo "⚠️  WARNING: OLM resources still present, but Mode 2 was selected."
        echo "Expected OLM resources to be removed in Phase 4."
        echo
        read -p "Continue with deployment anyway? (y/n): " CONTINUE
        if [ "$CONTINUE" != "y" ]; then
            echo "Aborted."
            exit 0
        fi
    else
        echo "✓ OLM resources removed - clean deployment state"
    fi
fi

echo

echo "===================================="
echo "Step 5.2: Verify Package Operator"
echo "===================================="
echo

echo "Checking for Package Operator..."
if ! oc get deployment -n openshift-package-operator package-operator-manager &>/dev/null; then
    echo "ERROR: Package Operator not found on cluster"
    echo "PKO must be installed before deploying CAMO via ClusterPackage"
    exit 1
fi

echo "✓ Package Operator is running"
echo

PKO_VERSION=$(oc get deployment -n openshift-package-operator package-operator-manager \
  -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "unknown")
echo "Package Operator image: $PKO_VERSION"
echo

echo "Checking ClusterPackage CRD..."
if ! oc api-resources | grep -q clusterpackages; then
    echo "ERROR: ClusterPackage CRD not found"
    exit 1
fi

echo "✓ ClusterPackage CRD exists"
echo

echo "===================================="
echo "Step 5.3: Create ClusterPackage Manifest"
echo "===================================="
echo

MANIFEST_FILE="$OPERATOR_DIR/clusterpackage.yaml"

# Determine operator repository path
OPERATOR_REPO_PATH=""
if [ -n "$CAMO_REPO" ]; then
    OPERATOR_REPO_PATH="$CAMO_REPO"
elif [ -n "$RMO_REPO" ]; then
    OPERATOR_REPO_PATH="$RMO_REPO"
elif [ -n "$OME_REPO" ]; then
    OPERATOR_REPO_PATH="$OME_REPO"
fi

# Check if we can use operator's ClusterPackage template
TEMPLATE_PATH="$OPERATOR_REPO_PATH/hack/pko/clusterpackage.yaml"
if [ -n "$OPERATOR_REPO_PATH" ] && [ -f "$TEMPLATE_PATH" ]; then
    echo "Using operator's ClusterPackage template: $TEMPLATE_PATH"
    echo

    # Extract image repository and tag from full image URIs
    # PKO_IMAGE format: quay.io/maclark/configure-alertmanager-operator-pko:test-afae58f
    REPO_NAME=$(basename "$OPERATOR_REPO_PATH")
    PKO_IMAGE_REPO=$(echo "$PKO_IMAGE" | cut -d':' -f1)
    IMAGE_TAG=$(echo "$PKO_IMAGE" | cut -d':' -f2)
    OPERATOR_IMAGE_REPO=$(echo "$OPERATOR_IMAGE" | cut -d':' -f1)
    FEDRAMP="${FEDRAMP:-false}"

    # Extract ClusterPackage from template and substitute variables
    # The template has the ClusterPackage nested in a SelectorSyncSet
    # We extract lines 39-49 (the ClusterPackage object) and remove leading spaces/dash
    sed -n '39,49p' "$TEMPLATE_PATH" | \
        sed 's/^        - //' | \
        sed 's/^          //' | \
        sed "s/\${REPO_NAME}/$REPO_NAME/g" | \
        sed "s|\${PKO_IMAGE}:\${IMAGE_TAG}|$PKO_IMAGE|g" | \
        sed "s|\${OPERATOR_IMAGE}:\${IMAGE_TAG}|$OPERATOR_IMAGE|g" | \
        sed "s/\${FEDRAMP}/$FEDRAMP/g" > "$MANIFEST_FILE"

    echo "✓ Generated ClusterPackage from operator template"
    echo "  Template variables substituted:"
    echo "    REPO_NAME: $REPO_NAME"
    echo "    PKO_IMAGE: $PKO_IMAGE"
    echo "    OPERATOR_IMAGE: $OPERATOR_IMAGE"
    echo "    FEDRAMP: $FEDRAMP"
else
    echo "⚠️  Operator template not found, using built-in ClusterPackage"
    echo

    # Fallback: generate ClusterPackage directly
    cat > "$MANIFEST_FILE" << EOF
apiVersion: package-operator.run/v1alpha1
kind: ClusterPackage
metadata:
  name: configure-alertmanager-operator
  annotations:
    package-operator.run/collision-protection: IfNoController
spec:
  image: ${PKO_IMAGE}
  config:
    image: ${OPERATOR_IMAGE}
    fedramp: "false"
EOF
fi

echo "ClusterPackage manifest created:"
echo "  File: $MANIFEST_FILE"
echo
cat "$MANIFEST_FILE"
echo

if [ "$MIGRATION_MODE" = "1" ]; then
    echo "ℹ️  MODE 1: PKO will run cleanup phases to remove OLM resources"
    echo "   Expected phases: cleanup-rbac, cleanup-deploy (run before deploy phases)"
    echo
elif [ "$MIGRATION_MODE" = "2" ]; then
    echo "ℹ️  MODE 2: PKO will deploy without cleanup phases"
    echo "   (OLM resources already removed manually)"
    echo
fi

read -p "Deploy this ClusterPackage? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "Aborted."
    echo "Manifest saved to: $MANIFEST_FILE"
    echo "You can manually apply it later with: oc apply -f $MANIFEST_FILE"
    exit 0
fi

echo

echo "===================================="
echo "Step 5.4: Apply ClusterPackage"
echo "===================================="
echo

# Record deployment start time
DEPLOY_START_TIME=$(date +%s)
CLUSTERPACKAGE_NAME=configure-alertmanager-operator
CLUSTERPACKAGE_MANIFEST=$MANIFEST_FILE

# Confirm with cluster context before applying
if confirm_operation "APPLY CLUSTERPACKAGE" \
    "oc apply -f $MANIFEST_FILE"; then

    oc apply -f "$MANIFEST_FILE"

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create ClusterPackage"
        exit 1
    fi

    echo "✓ ClusterPackage created successfully"
else
    echo "Aborted."
    echo "Manifest saved to: $MANIFEST_FILE"
    echo "You can manually apply it later with: oc apply -f $MANIFEST_FILE"
    exit 0
fi

echo

echo "===================================="
echo "Step 5.5: Initial Status Check"
echo "===================================="
echo

echo "Waiting 5 seconds for PKO to start processing..."
sleep 5

echo "ClusterPackage status:"
oc get clusterpackage configure-alertmanager-operator -o yaml 2>/dev/null | grep -A10 "^status:" || echo "  No status yet"

echo

echo "===================================="
echo "Deployment Initiated!"
echo "===================================="
echo
echo "ClusterPackage created: configure-alertmanager-operator"
echo "Manifest saved: $MANIFEST_FILE"
echo "Deployment started at: $(date -r $DEPLOY_START_TIME)"
echo
echo "Package Operator will now:"
echo "  1. Pull the PKO package image: $PKO_IMAGE"
echo "  2. Unpack manifests from the package"

if [ "$MIGRATION_MODE" = "1" ]; then
    echo "  3. Run CLEANUP phases first (cleanup-rbac, cleanup-deploy)"
    echo "     - These will remove OLM Subscription, CSV, CatalogSource"
    echo "  4. Run deployment phases (crds, namespace, rbac, deploy)"
    echo "     - Deploy operator with image: $OPERATOR_IMAGE"
else
    echo "  3. Run deployment phases (crds, namespace, rbac, deploy)"
    echo "     - Deploy operator with image: $OPERATOR_IMAGE"
fi

echo
echo "Next step: Run phase6-monitor-deployment.sh to watch the deployment progress"

# Save runtime state
save_runtime_state "$OPERATOR_DIR" "phase5-deploy-pko" "success"

echo
echo "Phase 5 completed at: $(date)"
echo "Log saved to: $LOG_FILE"
