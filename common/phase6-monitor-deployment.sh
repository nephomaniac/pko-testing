#!/bin/bash
set -e

# Phase 6: Monitor PKO Deployment
# This script monitors the ClusterPackage deployment and validates cleanup phases

PHASE_NUM=6
# Script runs from operator directory (camo/, rmo/, etc.)
OPERATOR_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Setup logging
LOG_DIR="$OPERATOR_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/phase${PHASE_NUM}-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===================================="
echo "Phase 6: Monitor PKO Deployment"
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
verify_cluster "Phase 6 start"

echo "Configuration:"
echo "  Cluster: $CLUSTER_ID"
echo "  Migration Mode: ${MIGRATION_MODE:-unknown}"
echo "  OLM Cleanup Method: ${OLM_CLEANUP_METHOD:-unknown}"
echo

echo "===================================="
echo "Step 6.1: Check ClusterPackage Exists"
echo "===================================="
echo

if ! oc get clusterpackage "$CLUSTERPACKAGE_NAME" &>/dev/null; then
    echo "ERROR: ClusterPackage not found"
    echo "Please run phase5-deploy-pko.sh first"
    exit 1
fi

echo "✓ ClusterPackage exists"
echo

echo "===================================="
echo "Step 6.2: Monitor Deployment Progress"
echo "===================================="
echo

echo "Monitoring ClusterPackage status (will auto-refresh every 10 seconds)..."
echo "Press Ctrl+C to stop monitoring and proceed to validation"
echo

MAX_WAIT=300  # 5 minutes
ELAPSED=0
INTERVAL=10

while [ $ELAPSED -lt $MAX_WAIT ]; do
    echo "--- Status at $(date) (${ELAPSED}s elapsed) ---"

    # Get ClusterPackage status
    CP_STATUS=$(oc get clusterpackage "$CLUSTERPACKAGE_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    echo "ClusterPackage Phase: $CP_STATUS"

    # Get current phase being processed
    CURRENT_PHASE=$(oc get clusterpackage "$CLUSTERPACKAGE_NAME" -o jsonpath='{.status.activePhase}' 2>/dev/null || echo "")
    if [ -n "$CURRENT_PHASE" ]; then
        echo "Active Phase: $CURRENT_PHASE"
    fi

    # Check for conditions
    CONDITIONS=$(oc get clusterpackage "$CLUSTERPACKAGE_NAME" -o jsonpath='{.status.conditions[*].type}' 2>/dev/null || echo "")
    if [ -n "$CONDITIONS" ]; then
        echo "Conditions: $CONDITIONS"
    fi

    # If Available, we're done
    if [[ "$CP_STATUS" == "Available" ]]; then
        echo
        echo "✓ ClusterPackage deployment completed successfully!"
        break
    fi

    # If Failed, abort
    if [[ "$CP_STATUS" == "Failed" ]] || [[ "$CONDITIONS" == *"Failed"* ]]; then
        echo
        echo "❌ ClusterPackage deployment failed!"
        echo
        echo "Full status:"
        oc get clusterpackage "$CLUSTERPACKAGE_NAME" -o yaml
        exit 1
    fi

    echo
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "⚠️  Timeout reached (${MAX_WAIT}s). Deployment may still be in progress."
    echo
    read -p "Continue to validation anyway? (y/n): " CONTINUE
    if [ "$CONTINUE" != "y" ]; then
        echo "Aborted. Check ClusterPackage status manually:"
        echo "  oc get clusterpackage $CLUSTERPACKAGE_NAME -o yaml"
        exit 1
    fi
fi

echo

echo "===================================="
echo "Step 6.3: Validate OLM Cleanup (Mode-Specific)"
echo "===================================="
echo

if [ "$MIGRATION_MODE" = "1" ]; then
    echo "Migration Mode 1: Validating PKO cleanup phases removed OLM resources"
    echo

    # Check that OLM resources are gone
    OLM_CLEANUP_SUCCESS=true

    if oc get subscription "$SUBSCRIPTION_NAME" -n "$OPERATOR_NAMESPACE" &>/dev/null; then
        echo "❌ FAIL: Subscription still exists (should be removed by cleanup-deploy phase)"
        OLM_CLEANUP_SUCCESS=false
    else
        echo "✓ Subscription removed by PKO cleanup"
    fi

    CSV_NAME=$(oc get csv -n "$OPERATOR_NAMESPACE" -o name 2>/dev/null | grep "$CSV_NAME_PATTERN" | head -1)
    if [ -n "$CSV_NAME" ]; then
        echo "❌ FAIL: CSV still exists: $CSV_NAME (should be removed by cleanup-deploy phase)"
        OLM_CLEANUP_SUCCESS=false
    else
        echo "✓ CSV removed by PKO cleanup"
    fi

    if oc get catalogsource "$CATALOGSOURCE_NAME" -n "$OPERATOR_NAMESPACE" &>/dev/null; then
        echo "❌ FAIL: CatalogSource still exists (should be removed by cleanup-deploy phase)"
        OLM_CLEANUP_SUCCESS=false
    else
        echo "✓ CatalogSource removed by PKO cleanup"
    fi

    echo

    if [ "$OLM_CLEANUP_SUCCESS" = false ]; then
        echo "❌ PKO CLEANUP VALIDATION FAILED"
        echo
        echo "PKO's cleanup phases did NOT remove all OLM resources."
        echo "This indicates a problem with the PKO package's cleanup phases."
        echo
        echo "Check the ClusterPackage for cleanup phase status:"
        echo "  oc get clusterpackage $CLUSTERPACKAGE_NAME -o yaml"
        echo
        echo "Manual cleanup option:"
        echo "  Run: ../common/cleanup-olm.sh"
        echo "  This will show you commands to manually delete OLM artifacts."
        echo
        echo "⚠️  IMPORTANT: Remember that when Hive sync is restored/unpaused,"
        echo "   Hive will likely reinstall the operator using its currently"
        echo "   configured deployment method (check app-interface config)."
        echo
        read -p "Continue to PKO deployment validation anyway? (y/n): " CONTINUE
        if [ "$CONTINUE" != "y" ]; then
            exit 1
        fi
    else
        echo "✅ PKO CLEANUP VALIDATION PASSED"
        echo "All OLM resources successfully removed by PKO cleanup phases"
    fi

elif [ "$MIGRATION_MODE" = "2" ]; then
    echo "Migration Mode 2: OLM resources were manually removed in Phase 4"
    echo

    # Just verify they're still gone
    if oc get subscription "$SUBSCRIPTION_NAME" -n "$OPERATOR_NAMESPACE" &>/dev/null || \
       oc get csv -n "$OPERATOR_NAMESPACE" -o name 2>/dev/null | grep -q "$CSV_NAME_PATTERN" || \
       oc get catalogsource "$CATALOGSOURCE_NAME" -n "$OPERATOR_NAMESPACE" &>/dev/null; then
        echo "⚠️  WARNING: OLM resources have reappeared (Hive sync may be active)"
    else
        echo "✓ OLM resources remain removed"
    fi
fi

echo

echo "===================================="
echo "Step 6.4: Validate PKO Deployment"
echo "===================================="
echo

echo "Checking PKO-deployed resources..."
echo

# Check Deployment
if oc get deployment "$OPERATOR_NAME" -n "$OPERATOR_NAMESPACE" &>/dev/null; then
    REPLICAS=$(oc get deployment "$OPERATOR_NAME" -n "$OPERATOR_NAMESPACE" -o jsonpath='{.spec.replicas}')
    READY=$(oc get deployment "$OPERATOR_NAME" -n "$OPERATOR_NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    echo "✓ Deployment exists (replicas: ${REPLICAS}, ready: ${READY:-0})"

    if [ "$READY" != "$REPLICAS" ]; then
        echo "  ⚠️  Not all replicas ready yet"
    fi
else
    echo "❌ Deployment not found"
fi

# Check ServiceAccount
if oc get serviceaccount "$OPERATOR_NAME" -n "$OPERATOR_NAMESPACE" &>/dev/null; then
    echo "✓ ServiceAccount exists"
else
    echo "❌ ServiceAccount not found"
fi

# Check ClusterRole
if oc get clusterrole "$OPERATOR_NAME" &>/dev/null; then
    echo "✓ ClusterRole exists"
else
    echo "❌ ClusterRole not found"
fi

# Check ClusterRoleBinding
if oc get clusterrolebinding "$OPERATOR_NAME" &>/dev/null; then
    echo "✓ ClusterRoleBinding exists"
else
    echo "❌ ClusterRoleBinding not found"
fi

# Check CRD (operator-specific, stored in operator-config)
if [ -n "$OPERATOR_CRD" ]; then
    if oc get crd "$OPERATOR_CRD" &>/dev/null; then
        echo "✓ CRD ($OPERATOR_CRD) exists"
    else
        echo "❌ CRD not found"
    fi
fi

# Check Pods
echo
echo "Operator pods:"
oc get pods -n "$OPERATOR_NAMESPACE" -l app.kubernetes.io/name="$OPERATOR_NAME" 2>/dev/null || \
oc get pods -n "$OPERATOR_NAMESPACE" | grep "$OPERATOR_RESOURCE_PREFIX" || \
echo "  No pods found"

echo

echo "===================================="
echo "Step 6.5: Check ClusterPackage Status"
echo "===================================="
echo

echo "Final ClusterPackage status:"
oc get clusterpackage "$CLUSTERPACKAGE_NAME" -o jsonpath='{.status}' | python3 -m json.tool || \
oc get clusterpackage "$CLUSTERPACKAGE_NAME" -o yaml | grep -A50 "^status:"

echo

echo "===================================="
echo "Deployment Monitoring Complete!"
echo "===================================="
echo

DEPLOY_STATUS=$(oc get clusterpackage "$CLUSTERPACKAGE_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

if [[ "$DEPLOY_STATUS" == "Available" ]]; then
    echo "✅ PKO Deployment: SUCCESS"
    echo
    echo "Summary:"
    echo "  - ClusterPackage phase: $DEPLOY_STATUS"
    echo "  - Migration mode: Mode $MIGRATION_MODE"
    if [ "$MIGRATION_MODE" = "1" ]; then
        echo "  - OLM cleanup: Validated (PKO cleanup phases removed OLM resources)"
    else
        echo "  - OLM cleanup: Manual (removed in Phase 4)"
    fi
    echo
    echo "Next step: Run phase7-functional-test.sh to test operator functionality"
else
    echo "⚠️  PKO Deployment: Status is '$DEPLOY_STATUS' (not Available)"
    echo
    echo "Check ClusterPackage for details:"
    echo "  oc describe clusterpackage $CLUSTERPACKAGE_NAME"
    echo
    read -p "Proceed to functional tests anyway? (y/n): " CONTINUE
    if [ "$CONTINUE" != "y" ]; then
        exit 1
    fi
fi

# Export variables for runtime state tracking
export DEPLOYMENT_STATUS="$DEPLOY_STATUS"
if [ "$MIGRATION_MODE" = "1" ]; then
    export OLM_CLEANUP_VALIDATED="${OLM_CLEANUP_SUCCESS:-unknown}"
fi
export PKO_RESOURCES_VALIDATED=true
export VALIDATION_TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Save runtime state
save_runtime_state "$OPERATOR_DIR" "phase6-monitor-deployment" "success"

echo
echo "Phase 6 completed at: $(date)"
echo "Log saved to: $LOG_FILE"
