#!/bin/bash

# Scenario Selector for PKO Testing
# Determines testing scenario based on cluster state and user preferences
# Sets configuration flags that control which phases run

set -e

OPERATOR_DIR="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load configuration
source "$SCRIPT_DIR/load-config.sh"
load_config "$OPERATOR_DIR"

# Load cluster validation
source "$SCRIPT_DIR/validate-cluster-connection.sh"

echo "========================================================================"
echo "  PKO Testing - Scenario Selection"
echo "========================================================================"
echo ""

# ============================================================================
# Step 1: Validate Cluster Connection (SAFETY CHECK)
# ============================================================================

# CRITICAL: Validate we're connected to the correct cluster
# This cannot be bypassed - will exit if cluster mismatch
# OCM integration provides authoritative cluster data (id, name, external_id, api.url)
validate_cluster_connection "$CLUSTER_ID" "$CLUSTER_SERVER" "scenario-selector.sh" "$OPERATOR_DIR"

# ============================================================================
# Step 2: Check Current Cluster State
# ============================================================================

echo "Step 2: Checking Deployment State"
echo "=================================="
echo ""

# Check if Hive is paused
echo "Checking Hive status..."
HIVE_PAUSED="unknown"
if oc get clusterversion version &>/dev/null; then
    # Check if hive operator exists and is scaled down
    if oc get deployment hive-operator -n hive &>/dev/null; then
        HIVE_REPLICAS=$(oc get deployment hive-operator -n hive -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        if [ "$HIVE_REPLICAS" = "0" ]; then
            HIVE_PAUSED="yes"
            echo "✓ Hive is PAUSED (replicas=0)"
        else
            HIVE_PAUSED="no"
            echo "⚠️  Hive is ACTIVE (replicas=$HIVE_REPLICAS)"
            echo "   Note: Active Hive may reconcile/override manual changes"
        fi
    else
        HIVE_PAUSED="not-installed"
        echo "ℹ️  Hive operator not found (not a Hive-managed cluster)"
    fi
else
    echo "ℹ️  Cannot determine Hive status"
fi
echo ""

# Check current operator deployment state
echo "Checking operator deployment state..."
DEPLOYMENT_STATE="none"
DEPLOYMENT_METHOD="none"

# Check for namespace
if oc get namespace "$OPERATOR_NAMESPACE" &>/dev/null; then
    echo "✓ Namespace exists: $OPERATOR_NAMESPACE"
    
    # Check for PKO ClusterPackage
    if oc get clusterpackage "$CLUSTERPACKAGE_NAME" &>/dev/null 2>&1; then
        DEPLOYMENT_STATE="deployed"
        DEPLOYMENT_METHOD="pko"
        PKO_VERSION=$(oc get clusterpackage "$CLUSTERPACKAGE_NAME" -o jsonpath='{.status.version}' 2>/dev/null || echo "unknown")
        echo "✓ PKO ClusterPackage found: $CLUSTERPACKAGE_NAME (version: $PKO_VERSION)"
    fi
    
    # Check for OLM CSV
    if oc get csv -n "$OPERATOR_NAMESPACE" --no-headers 2>/dev/null | grep -q "$CSV_NAME_PATTERN"; then
        CSV_NAME=$(oc get csv -n "$OPERATOR_NAMESPACE" --no-headers 2>/dev/null | grep "$CSV_NAME_PATTERN" | awk '{print $1}' | head -1)
        CSV_PHASE=$(oc get csv "$CSV_NAME" -n "$OPERATOR_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
        
        if [ "$DEPLOYMENT_STATE" = "deployed" ]; then
            echo "⚠️  BOTH PKO and OLM detected!"
            echo "   PKO: $CLUSTERPACKAGE_NAME"
            echo "   OLM CSV: $CSV_NAME (phase: $CSV_PHASE)"
            DEPLOYMENT_STATE="both"
            DEPLOYMENT_METHOD="both"
        else
            DEPLOYMENT_STATE="deployed"
            DEPLOYMENT_METHOD="olm"
            echo "✓ OLM CSV found: $CSV_NAME (phase: $CSV_PHASE)"
        fi
    fi
    
    # Check for operator deployment (might be manual deployment)
    if oc get deployment "$OPERATOR_NAME" -n "$OPERATOR_NAMESPACE" &>/dev/null 2>/dev/null; then
        if [ "$DEPLOYMENT_STATE" = "none" ]; then
            DEPLOYMENT_STATE="deployed"
            DEPLOYMENT_METHOD="manual"
            echo "✓ Operator deployment found (no OLM/PKO - manual deployment)"
        fi
    fi
else
    echo "✗ Namespace does not exist: $OPERATOR_NAMESPACE"
    DEPLOYMENT_STATE="none"
    DEPLOYMENT_METHOD="none"
fi

echo ""
echo "Current State Summary:"
echo "  Hive Status: $HIVE_PAUSED"
echo "  Deployment State: $DEPLOYMENT_STATE"
echo "  Deployment Method: $DEPLOYMENT_METHOD"
echo ""

# ============================================================================
# Step 3: Present Testing Scenarios
# ============================================================================

echo "Step 3: Select Testing Scenario"
echo "================================"
echo ""

echo "Available Testing Scenarios:"
echo ""
echo "1. Fresh PKO Deployment (no OLM)"
echo "   - Build local PKO images"
echo "   - Deploy directly with PKO"
echo "   - Best for: Testing PKO deployment only"
echo ""
echo "2. OLM → PKO Migration (using local built images)"
echo "   - Build local operator + PKO images"
echo "   - Deploy via OLM (simulated)"
echo "   - Migrate to PKO with cleanup"
echo "   - Best for: Full migration testing with custom code"
echo ""
echo "3. OLM → PKO Migration (using production quay.io images)"
echo "   - Use existing quay.io images"
echo "   - Deploy via OLM template (production-like)"
echo "   - Build PKO image locally"
echo "   - Migrate to PKO with cleanup"
echo "   - Best for: Testing migration with stable images"
echo ""
echo "4. Test PKO Cleanup Only (OLM already deployed)"
echo "   - Skip OLM deployment (already exists)"
echo "   - Build PKO image only"
echo "   - Run migration phases"
echo "   - Best for: Testing cleanup logic with existing OLM"
echo ""

# Smart defaults based on current state
DEFAULT_SCENARIO=""
if [ "$DEPLOYMENT_METHOD" = "olm" ]; then
    DEFAULT_SCENARIO="4"
    echo "💡 Recommended: Scenario 4 (OLM already deployed)"
elif [ "$DEPLOYMENT_METHOD" = "pko" ]; then
    echo "⚠️  Warning: PKO already deployed!"
    echo "   You may want to clean it up first before testing"
elif [ "$DEPLOYMENT_STATE" = "none" ]; then
    DEFAULT_SCENARIO="3"
    echo "💡 Recommended: Scenario 3 (production-like migration)"
fi
echo ""

read -p "Choose scenario (1-4)${DEFAULT_SCENARIO:+ [default: $DEFAULT_SCENARIO]}: " SCENARIO
SCENARIO=${SCENARIO:-$DEFAULT_SCENARIO}

# Validate input
if [[ ! "$SCENARIO" =~ ^[1-4]$ ]]; then
    echo "❌ Invalid scenario: $SCENARIO"
    exit 1
fi

echo ""
echo "Selected: Scenario $SCENARIO"
echo ""

# ============================================================================
# Step 4: Configure Scenario Flags
# ============================================================================

echo "Step 4: Configuring Workflow"
echo "============================="
echo ""

# Initialize flags
SKIP_BUILD_OPERATOR="false"
SKIP_BUILD_PKO="false"
SKIP_PUSH_IMAGES="false"
SKIP_OLM_DEPLOYMENT="false"
USE_PRODUCTION_OLM="false"
USE_SIMULATED_OLM="false"
CLEANUP_EXISTING_PKO="false"

# Set flags based on scenario
case "$SCENARIO" in
    1)
        # Fresh PKO - skip OLM phases
        SKIP_OLM_DEPLOYMENT="true"
        echo "Workflow:"
        echo "  ✓ Build operator image"
        echo "  ✓ Build PKO package image"
        echo "  ✓ Push images to registry"
        echo "  ✗ Skip OLM deployment"
        echo "  ✓ Deploy PKO ClusterPackage"
        echo "  ✓ Monitor and test"
        ;;
    2)
        # OLM → PKO with local images
        USE_SIMULATED_OLM="true"
        echo "Workflow:"
        echo "  ✓ Build operator image"
        echo "  ✓ Build PKO package image"
        echo "  ✓ Push images to registry"
        echo "  ✓ Deploy OLM (simulated with local images)"
        echo "  ✓ Migrate to PKO with cleanup"
        echo "  ✓ Monitor and test"
        ;;
    3)
        # OLM → PKO with production images
        USE_PRODUCTION_OLM="true"
        SKIP_BUILD_OPERATOR="true"
        SKIP_PUSH_IMAGES="true"  # Only push PKO image
        echo "Workflow:"
        echo "  ✗ Skip operator image build (use quay.io)"
        echo "  ✓ Build PKO package image"
        echo "  ✓ Push PKO image to registry"
        echo "  ✓ Deploy OLM from quay.io template"
        echo "  ✓ Migrate to PKO with cleanup"
        echo "  ✓ Monitor and test"
        ;;
    4)
        # PKO cleanup only - OLM already exists
        SKIP_BUILD_OPERATOR="true"
        SKIP_OLM_DEPLOYMENT="true"
        echo "Workflow:"
        echo "  ✗ Skip operator image build"
        echo "  ✓ Build PKO package image"
        echo "  ✓ Push PKO image to registry"
        echo "  ✗ Skip OLM deployment (already exists)"
        echo "  ✓ Migrate to PKO with cleanup"
        echo "  ✓ Monitor and test"
        ;;
esac

echo ""

# Check if we need to cleanup existing PKO
if [ "$DEPLOYMENT_METHOD" = "pko" ] || [ "$DEPLOYMENT_METHOD" = "both" ]; then
    echo "⚠️  Existing PKO deployment detected!"
    read -p "Clean up existing PKO before starting? (y/N): " CLEANUP_PKO
    if [[ "$CLEANUP_PKO" =~ ^[Yy]$ ]]; then
        CLEANUP_EXISTING_PKO="true"
        echo "  → Will delete ClusterPackage: $CLUSTERPACKAGE_NAME"
    fi
    echo ""
fi

# ============================================================================
# Step 5: Write Scenario Configuration
# ============================================================================

echo "Step 5: Saving Configuration"
echo "============================="
echo ""

RUNTIME_STATE="$OPERATOR_DIR/config/runtime-state"

# Create or update runtime-state with scenario config
cat > "$RUNTIME_STATE" <<EOF
# PKO Testing Runtime State
# Generated by scenario-selector.sh at $(date)

# Scenario Configuration
TESTING_SCENARIO=$SCENARIO
HIVE_PAUSED=$HIVE_PAUSED
INITIAL_DEPLOYMENT_STATE=$DEPLOYMENT_STATE
INITIAL_DEPLOYMENT_METHOD=$DEPLOYMENT_METHOD

# Workflow Flags
SKIP_BUILD_OPERATOR=$SKIP_BUILD_OPERATOR
SKIP_BUILD_PKO=$SKIP_BUILD_PKO
SKIP_PUSH_IMAGES=$SKIP_PUSH_IMAGES
SKIP_OLM_DEPLOYMENT=$SKIP_OLM_DEPLOYMENT
USE_PRODUCTION_OLM=$USE_PRODUCTION_OLM
USE_SIMULATED_OLM=$USE_SIMULATED_OLM
CLEANUP_EXISTING_PKO=$CLEANUP_EXISTING_PKO

# Execution Tracking (updated by phase scripts)
LAST_RUN_PHASE=scenario-selector
LAST_RUN_STATUS=success
LAST_RUN_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

echo "✓ Configuration saved to: $RUNTIME_STATE"
echo ""

# ============================================================================
# Step 6: Execute Cleanup if Needed
# ============================================================================

if [ "$CLEANUP_EXISTING_PKO" = "true" ]; then
    echo "Step 6: Cleaning Up Existing PKO"
    echo "================================="
    echo ""
    
    echo "Deleting ClusterPackage: $CLUSTERPACKAGE_NAME"
    oc delete clusterpackage "$CLUSTERPACKAGE_NAME" --ignore-not-found=true
    
    echo "Waiting for resources to be cleaned up..."
    sleep 5
    
    # Clean up any orphaned PKO resources
    if [ -n "$PKO_CLUSTERROLEBINDINGS" ]; then
        for crb in $PKO_CLUSTERROLEBINDINGS; do
            echo "  Deleting ClusterRoleBinding: $crb"
            oc delete clusterrolebinding "$crb" --ignore-not-found=true
        done
    fi
    
    if [ -n "$PKO_CLUSTERROLES" ]; then
        for cr in $PKO_CLUSTERROLES; do
            echo "  Deleting ClusterRole: $cr"
            oc delete clusterrole "$cr" --ignore-not-found=true
        done
    fi
    
    echo "✓ PKO cleanup complete"
    echo ""
fi

# ============================================================================
# Step 7: Summary and Next Steps
# ============================================================================

echo "========================================================================"
echo "  Scenario Configuration Complete!"
echo "========================================================================"
echo ""
echo "Testing Scenario: $SCENARIO"
echo ""

echo "Next Steps:"
echo ""

if [ "$SKIP_OLM_DEPLOYMENT" = "true" ]; then
    if [ "$SKIP_BUILD_OPERATOR" = "false" ]; then
        echo "1. Run: ../common/phase1-build-images.sh"
        echo "   → Builds operator and PKO images locally"
        echo ""
        echo "2. Run: ../common/phase2-push-images.sh"
        echo "   → Pushes images to your quay.io repository"
    else
        echo "1. Run: ../common/phase1-build-images.sh"
        echo "   → Builds PKO package image only"
        echo ""
        echo "2. Run: ../common/phase2-push-images.sh"
        echo "   → Pushes PKO image to your quay.io repository"
    fi
    echo ""
    echo "3. Run: ../common/phase5-deploy-pko.sh"
    echo "   → Deploys PKO ClusterPackage"
elif [ "$USE_PRODUCTION_OLM" = "true" ]; then
    echo "1. Run: ../common/deploy-olm-from-quay.sh"
    echo "   → Deploys OLM using production quay.io images"
    echo ""
    echo "2. Run: ../common/phase1-build-images.sh"
    echo "   → Builds PKO package image only"
    echo ""
    echo "3. Run: ../common/phase2-push-images.sh"
    echo "   → Pushes PKO image to your quay.io repository"
    echo ""
    echo "4. Run: ../common/phase4-prepare-migration.sh"
    echo "   → Prepares PKO migration and cleanup job"
    echo ""
    echo "5. Run: ../common/phase5-deploy-pko.sh"
    echo "   → Migrates to PKO with OLM cleanup"
elif [ "$USE_SIMULATED_OLM" = "true" ]; then
    echo "1. Run: ../common/phase1-build-images.sh"
    echo "   → Builds operator and PKO images locally"
    echo ""
    echo "2. Run: ../common/phase2-push-images.sh"
    echo "   → Pushes images to your quay.io repository"
    echo ""
    echo "3. Run: ../common/install-via-olm.sh"
    echo "   → Deploys OLM using simulated deployment"
    echo ""
    echo "4. Run: ../common/phase4-prepare-migration.sh"
    echo "   → Prepares PKO migration and cleanup job"
    echo ""
    echo "5. Run: ../common/phase5-deploy-pko.sh"
    echo "   → Migrates to PKO with OLM cleanup"
else
    # Scenario 4 - OLM already deployed
    echo "1. Run: ../common/phase1-build-images.sh"
    echo "   → Builds PKO package image only"
    echo ""
    echo "2. Run: ../common/phase2-push-images.sh"
    echo "   → Pushes PKO image to your quay.io repository"
    echo ""
    echo "3. Run: ../common/phase4-prepare-migration.sh"
    echo "   → Prepares PKO migration and cleanup job"
    echo ""
    echo "4. Run: ../common/phase5-deploy-pko.sh"
    echo "   → Migrates to PKO with OLM cleanup"
fi

echo ""
echo "All phase scripts will automatically respect the scenario configuration."
echo ""
