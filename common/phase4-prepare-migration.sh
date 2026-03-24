#!/bin/bash
set -e

# Phase 4: Prepare for PKO Migration
# This script checks current state and lets user choose migration mode

PHASE_NUM=4
# Script runs from operator directory (camo/, rmo/, etc.)
OPERATOR_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Setup logging
LOG_DIR="$OPERATOR_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/phase${PHASE_NUM}-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===================================="
echo "Phase 4: Prepare for PKO Migration"
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
verify_cluster "Phase 4 start"

echo "Target cluster: $CLUSTER_ID"
echo

echo "===================================="
echo "Step 4.1: Check Current State"
echo "===================================="
echo

# Check what exists
HAS_SUBSCRIPTION=false
HAS_CSV=false
HAS_CATALOGSOURCE=false
HAS_DEPLOYMENT=false
CSV_NAME=""

echo "Checking for OLM resources..."
echo

if oc get subscription configure-alertmanager-operator -n openshift-monitoring &>/dev/null; then
    HAS_SUBSCRIPTION=true
    echo "  ✓ Subscription: configure-alertmanager-operator"
fi

CSV_NAME=$(oc get csv -n openshift-monitoring -o name 2>/dev/null | grep configure-alertmanager | head -1)
if [ -n "$CSV_NAME" ]; then
    HAS_CSV=true
    CSV_VERSION=$(echo "$CSV_NAME" | sed 's/clusterserviceversion.operators.coreos.com\///')
    echo "  ✓ CSV: $CSV_VERSION"
fi

if oc get catalogsource configure-alertmanager-operator-registry -n openshift-monitoring &>/dev/null; then
    HAS_CATALOGSOURCE=true
    echo "  ✓ CatalogSource: configure-alertmanager-operator-registry"
fi

if oc get deployment configure-alertmanager-operator -n openshift-monitoring &>/dev/null; then
    HAS_DEPLOYMENT=true
    REPLICAS=$(oc get deployment configure-alertmanager-operator -n openshift-monitoring -o jsonpath='{.spec.replicas}')
    echo "  ✓ Deployment: configure-alertmanager-operator (replicas: $REPLICAS)"
fi

echo

if [ "$HAS_SUBSCRIPTION" = false ] && [ "$HAS_CSV" = false ] && [ "$HAS_CATALOGSOURCE" = false ]; then
    echo "ℹ️  No OLM resources found."
    echo "This cluster does not have an OLM-based operator deployment."
    echo
    echo "Options:"
    echo "  1) Install operator via OLM first (for Mode 1 testing)"
    echo "     - Uses operator repo artifacts from deploy/"
    echo "     - Creates mock OLM resources (Subscription, CSV, CatalogSource)"
    echo "     - Deploys operator with your configured image"
    echo "     - Then you can test PKO cleanup phases (Mode 1)"
    echo
    echo "  2) Skip to PKO deployment (Mode 2)"
    echo "     - No OLM cleanup to test"
    echo "     - PKO deploys operator directly"
    echo
    echo "  3) Abort"
    echo
    read -p "Choose option (1/2/3): " INSTALL_CHOICE

    if [ "$INSTALL_CHOICE" = "1" ]; then
        echo
        echo "===================================="
        echo "Installing Operator via OLM"
        echo "===================================="
        echo

        # Check if operator repo is configured
        if [ -z "$CAMO_REPO" ] && [ -z "$RMO_REPO" ] && [ -z "$OME_REPO" ]; then
            echo "ERROR: No operator repository configured"
            echo "Please set CAMO_REPO, RMO_REPO, or OME_REPO in user-config"
            exit 1
        fi

        # Run OLM installation helper
        if [ -f "$SCRIPT_DIR/install-via-olm.sh" ]; then
            bash "$SCRIPT_DIR/install-via-olm.sh" "$OPERATOR_DIR"

            echo
            echo "OLM installation complete!"
            echo
            echo "Next steps:"
            echo "  1. Verify operator is running: oc get pods -n $OPERATOR_NAMESPACE"
            echo "  2. Re-run this script (phase4) and select Mode 1 (PKO cleanup)"
            exit 0
        else
            echo "ERROR: install-via-olm.sh not found"
            exit 1
        fi

    elif [ "$INSTALL_CHOICE" = "2" ]; then
        # Save mode to runtime state
        MIGRATION_MODE=2
        OLM_CLEANUP_METHOD=none
        save_runtime_state "$OPERATOR_DIR" "phase4-prepare-migration" "success"
        echo
        echo "Proceeding to Phase 5 (PKO deployment)..."
        echo "Next step: Run phase5-deploy-pko.sh"
        exit 0

    else
        echo "Aborted."
        exit 0
    fi
fi

echo "===================================="
echo "Step 4.2: Choose Migration Mode"
echo "===================================="
echo
echo "PKO supports two migration approaches:"
echo
echo "  MODE 1 (RECOMMENDED): PKO-Managed Cleanup"
echo "    - Deploy ClusterPackage with OLM resources still present"
echo "    - PKO's cleanup phases automatically remove OLM artifacts"
echo "    - Tests the complete migration process as designed"
echo "    - Validates PKO cleanup phases work correctly"
echo
echo "  MODE 2: Manual Cleanup"
echo "    - Manually delete OLM resources before PKO deployment"
echo "    - Cleaner starting state for PKO"
echo "    - Faster deployment (no cleanup phases to wait for)"
echo "    - Doesn't test PKO cleanup functionality"
echo
echo "Current OLM resources on cluster:"
[ "$HAS_SUBSCRIPTION" = true ] && echo "  - Subscription"
[ "$HAS_CSV" = true ] && echo "  - ClusterServiceVersion ($CSV_VERSION)"
[ "$HAS_CATALOGSOURCE" = true ] && echo "  - CatalogSource"
[ "$HAS_DEPLOYMENT" = true ] && echo "  - Deployment"
echo
echo "Which mode would you like to use?"
echo "  1) MODE 1 - Let PKO cleanup phases remove OLM (default, recommended)"
echo "  2) MODE 2 - Manually delete OLM resources before PKO deployment"
echo
read -p "Enter choice (1 or 2) [default: 1]: " MODE_CHOICE
MODE_CHOICE=${MODE_CHOICE:-1}

if [ "$MODE_CHOICE" = "1" ]; then
    echo
    echo "===================================="
    echo "MODE 1 Selected: PKO-Managed Cleanup"
    echo "===================================="
    echo
    echo "OLM resources will remain during PKO deployment."
    echo "PKO's cleanup phases will remove them automatically."
    echo
    echo "IMPORTANT: Make sure you have:"
    echo "  1. Paused the Hive sync (to prevent SelectorSyncSet restoration)"
    echo "  2. Backed up the current deployment (phase3 did this)"
    echo
    read -p "Hive sync is paused and ready to proceed? (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ]; then
        echo "Aborted."
        echo "Please pause Hive sync and run this phase again."
        exit 0
    fi

    # Save mode to runtime state
    MIGRATION_MODE=1
    OLM_CLEANUP_METHOD=pko-managed
    save_runtime_state "$OPERATOR_DIR" "phase4-prepare-migration" "success"

    echo
    echo "Configuration saved."
    echo "Proceeding to Phase 5 (PKO deployment with OLM resources present)..."
    echo
    echo "Next step: Run phase5-deploy-pko.sh"

elif [ "$MODE_CHOICE" = "2" ]; then
    echo
    echo "===================================="
    echo "MODE 2 Selected: Manual Cleanup"
    echo "===================================="
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

    # Save mode to runtime state
    MIGRATION_MODE=2
    OLM_CLEANUP_METHOD=manual

    echo
    echo "===================================="
    echo "Step 4.3: Scale Down Operator"
    echo "===================================="
    echo

    if [ "$HAS_DEPLOYMENT" = true ]; then
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
    echo "Step 4.4: Delete OLM Resources"
    echo "===================================="
    echo

    # Build list of resources to delete
    COMMANDS=()
    [ "$HAS_SUBSCRIPTION" = true ] && COMMANDS+=("oc delete subscription configure-alertmanager-operator -n openshift-monitoring")
    [ "$HAS_CSV" = true ] && COMMANDS+=("oc delete $CSV_NAME -n openshift-monitoring")
    [ "$HAS_CATALOGSOURCE" = true ] && COMMANDS+=("oc delete catalogsource configure-alertmanager-operator-registry -n openshift-monitoring")

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
                echo "✓ CSV deleted: $CSV_VERSION"
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
    fi

    # Wait for cleanup
    echo "Waiting for OLM cleanup to complete..."
    sleep 10

    echo
    echo "===================================="
    echo "Step 4.5: Verify Cleanup"
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
        echo "⚠️  Deployment still exists (will be replaced by PKO)"
    else
        echo "✓ Deployment removed by OLM cleanup"
    fi

    # Save mode to runtime state
    save_runtime_state "$OPERATOR_DIR" "phase4-prepare-migration" "success"

    echo
    echo "===================================="
    echo "Manual OLM Cleanup Complete!"
    echo "===================================="
    echo
    echo "OLM resources removed:"
    echo "  ✓ Subscription"
    echo "  ✓ ClusterServiceVersion"
    echo "  ✓ CatalogSource"
    echo
    echo "Remaining resources (will be managed by PKO):"
    echo "  - RBAC (ClusterRole, ClusterRoleBinding, ServiceAccount)"
    echo "  - CRD (AlertManager)"
    echo "  - Deployment (will be replaced)"
    echo
    echo "Next step: Run phase5-deploy-pko.sh"

else
    echo "Invalid choice. Please enter 1 or 2."
    exit 1
fi

echo
echo "Phase 4 completed at: $(date)"
echo "Log saved to: $LOG_FILE"
