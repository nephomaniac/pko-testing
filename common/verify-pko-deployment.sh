#!/bin/bash

# Verify PKO Deployment and Check for OLM Cleanup Issues
# Detects if OLM artifacts remain after PKO deployment completes
# Reports bugs in PKO package cleanup phases
# Provides AI investigation guidance for orphaned resources

set -e

OPERATOR_DIR="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load configuration
source "$SCRIPT_DIR/load-config.sh"
load_config "$OPERATOR_DIR"

echo "========================================================================"
echo "  PKO Deployment Verification"
echo "========================================================================"
echo ""

# Check if PKO ClusterPackage exists
echo "Step 1: Checking PKO Deployment"
echo "================================"
echo ""

if ! oc get clusterpackage "$CLUSTERPACKAGE_NAME" &>/dev/null; then
    echo "❌ PKO ClusterPackage not found: $CLUSTERPACKAGE_NAME"
    echo "   PKO is not deployed yet."
    exit 1
fi

# Get PKO status
PKO_AVAILABLE=$(oc get clusterpackage "$CLUSTERPACKAGE_NAME" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
PKO_PROGRESSING=$(oc get clusterpackage "$CLUSTERPACKAGE_NAME" -o jsonpath='{.status.conditions[?(@.type=="Progressing")].status}' 2>/dev/null)

echo "PKO ClusterPackage: $CLUSTERPACKAGE_NAME"
echo "  Available: ${PKO_AVAILABLE:-unknown}"
echo "  Progressing: ${PKO_PROGRESSING:-unknown}"
echo ""

if [ "$PKO_AVAILABLE" != "True" ]; then
    echo "⚠️  PKO is not yet available"
    echo "   Wait for deployment to complete before verifying cleanup"
    exit 0
fi

if [ "$PKO_PROGRESSING" = "True" ]; then
    echo "⚠️  PKO is still progressing"
    echo "   Wait for deployment to complete before verifying cleanup"
    exit 0
fi

echo "✓ PKO deployment is complete and available"
echo ""

# Check PKO phases
echo "Step 2: Checking PKO Package Phases"
echo "===================================="
echo ""

OBJECTSET_NAME=$(oc get clusterobjectset -l package-operator.run/package="$CLUSTERPACKAGE_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$OBJECTSET_NAME" ]; then
    PHASES=$(oc get clusterobjectset "$OBJECTSET_NAME" -o jsonpath='{.spec.phases[*].name}' 2>/dev/null)
    echo "PKO Package Phases: $PHASES"
    echo ""
    
    # Check if cleanup phase exists
    if echo "$PHASES" | grep -q "cleanup"; then
        echo "✓ Package has cleanup phase"
        HAS_CLEANUP_PHASE=true
    else
        echo "⚠️  Package does NOT have cleanup phase"
        echo "   This may indicate a bug in the PKO package"
        HAS_CLEANUP_PHASE=false
    fi
    echo ""
else
    echo "⚠️  Could not find ClusterObjectSet"
    HAS_CLEANUP_PHASE=unknown
    echo ""
fi

# Check for remaining OLM artifacts
echo "Step 3: Checking for OLM Artifacts"
echo "==================================="
echo ""

OLM_ISSUES=()

# Check for CSV
if oc get csv -n "$OPERATOR_NAMESPACE" --no-headers 2>/dev/null | grep -q "$CSV_NAME_PATTERN"; then
    CSV_NAME=$(oc get csv -n "$OPERATOR_NAMESPACE" --no-headers 2>/dev/null | grep "$CSV_NAME_PATTERN" | awk '{print $1}' | head -1)
    echo "⚠️  OLM CSV still exists: $CSV_NAME"
    OLM_ISSUES+=("CSV:$CSV_NAME")
else
    echo "✓ No OLM CSV found"
fi

# Check for Subscription
if oc get subscription "$SUBSCRIPTION_NAME" -n "$OPERATOR_NAMESPACE" &>/dev/null; then
    echo "⚠️  OLM Subscription still exists: $SUBSCRIPTION_NAME"
    OLM_ISSUES+=("Subscription:$SUBSCRIPTION_NAME")
else
    echo "✓ No OLM Subscription found"
fi

# Check for CatalogSource
if oc get catalogsource "$CATALOGSOURCE_NAME" -n "$OPERATOR_NAMESPACE" &>/dev/null; then
    echo "⚠️  OLM CatalogSource still exists: $CATALOGSOURCE_NAME"
    OLM_ISSUES+=("CatalogSource:$CATALOGSOURCE_NAME")
else
    echo "✓ No OLM CatalogSource found"
fi

# Check for OperatorGroup (if applicable)
if [ -n "$OPERATORGROUP_NAME" ]; then
    if oc get operatorgroup "$OPERATORGROUP_NAME" -n "$OPERATOR_NAMESPACE" &>/dev/null; then
        echo "⚠️  OLM OperatorGroup still exists: $OPERATORGROUP_NAME"
        OLM_ISSUES+=("OperatorGroup:$OPERATORGROUP_NAME")
    else
        echo "✓ No OLM OperatorGroup found"
    fi
fi

echo ""

# Final assessment
echo "========================================================================"
echo "  Verification Results"
echo "========================================================================"
echo ""

if [ ${#OLM_ISSUES[@]} -eq 0 ]; then
    echo "✅ SUCCESS: PKO deployment is clean"
    echo ""
    echo "  ✓ PKO ClusterPackage is available"
    echo "  ✓ All OLM artifacts have been removed"
    echo "  ✓ Migration is complete"
    echo ""
    exit 0
fi

# OLM issues found - report them
echo "⚠️  WARNING: OLM artifacts remain after PKO deployment"
echo ""
echo "Found ${#OLM_ISSUES[@]} OLM artifact(s):"
for issue in "${OLM_ISSUES[@]}"; do
    echo "  - $issue"
done
echo ""

# Determine if this is a bug
if [ "$HAS_CLEANUP_PHASE" = "false" ]; then
    echo "🐛 BUG DETECTED: PKO package is missing cleanup phase"
    echo ""
    echo "The PKO package for this operator does NOT include a cleanup phase."
    echo "This is a bug in the operator's PKO implementation."
    echo ""
    echo "Expected phases:"
    echo "  1. namespace"
    echo "  2. rbac"
    echo "  3. cleanup  ← MISSING!"
    echo "  4. deploy"
    echo ""
    echo "Actual phases: $PHASES"
    echo ""
    echo "Impact:"
    echo "  - OLM resources are not automatically cleaned up"
    echo "  - Manual cleanup required"
    echo "  - May cause resource conflicts or confusion"
    echo ""
fi

# Show manual cleanup commands
echo "Manual Cleanup Commands:"
echo "========================"
echo ""
echo "oc delete csv -n $OPERATOR_NAMESPACE --all"
echo "oc delete subscription $SUBSCRIPTION_NAME -n $OPERATOR_NAMESPACE"
echo "oc delete catalogsource $CATALOGSOURCE_NAME -n $OPERATOR_NAMESPACE"
if [ -n "$OPERATORGROUP_NAME" ]; then
    echo "oc delete operatorgroup $OPERATORGROUP_NAME -n $OPERATOR_NAMESPACE"
fi
echo ""

# AI Investigation Guide
echo "========================================================================"
echo "  🤖 AI ASSISTANT: Orphaned Resource Investigation Guide"
echo "========================================================================"
echo ""
echo "Use these commands to comprehensively search for orphaned OLM artifacts."
echo ""

echo "1. ALL OLM resources in operator namespace:"
echo "   ------------------------------------------"
echo "   oc get csv,subscription,catalogsource,operatorgroup,installplan \\"
echo "     -n $OPERATOR_NAMESPACE"
echo ""

echo "2. Operator-specific resources across ALL namespaces:"
echo "   ----------------------------------------------------"
echo "   # CSVs"
echo "   oc get csv -A | grep '$CSV_NAME_PATTERN'"
echo ""
echo "   # Subscriptions"
echo "   oc get subscription -A | grep '$SUBSCRIPTION_NAME'"
echo ""
echo "   # CatalogSources"
echo "   oc get catalogsource -A | grep '$CATALOGSOURCE_NAME'"
echo ""

echo "3. Orphaned RBAC resources:"
echo "   -------------------------"
echo "   # OLM-created ClusterRoles"
echo "   oc get clusterrole -l olm.owner.kind=ClusterServiceVersion"
echo ""
echo "   # OLM-created ClusterRoleBindings"
echo "   oc get clusterrolebinding -l olm.owner.kind=ClusterServiceVersion"
echo ""
echo "   # Operator-specific RBAC"
echo "   oc get clusterrole,clusterrolebinding | grep '$OPERATOR_RESOURCE_PREFIX'"
echo ""

echo "4. Orphaned ServiceAccounts:"
echo "   --------------------------"
echo "   oc get serviceaccount -n $OPERATOR_NAMESPACE | grep '$OPERATOR_RESOURCE_PREFIX'"
echo ""

echo "5. Check deployment ownership:"
echo "   ----------------------------"
echo "   # Deployment labels (should show package-operator.run, not olm.owner)"
echo "   oc get deployment '$OPERATOR_NAME' -n $OPERATOR_NAMESPACE \\"
echo "     -o jsonpath='{.metadata.labels}' | jq"
echo ""
echo "   # Deployment owner references (should reference ClusterObjectSet, not CSV)"
echo "   oc get deployment '$OPERATOR_NAME' -n $OPERATOR_NAMESPACE \\"
echo "     -o jsonpath='{.metadata.ownerReferences}' | jq"
echo ""

echo "6. InstallPlans (OLM installation artifacts):"
echo "   --------------------------------------------"
echo "   oc get installplan -n $OPERATOR_NAMESPACE"
echo ""

echo "7. Package-operator cleanup logs:"
echo "   --------------------------------"
echo "   oc logs -n package-operator-system \\"
echo "     -l app=package-operator-manager \\"
echo "     --tail=200 | grep -i -E '(cleanup|olm|csv|subscription)'"
echo ""

echo "8. Resources with OLM labels:"
echo "   ---------------------------"
echo "   # In operator namespace"
echo "   oc get all -n $OPERATOR_NAMESPACE \\"
echo "     -l olm.owner.kind=ClusterServiceVersion"
echo ""
echo "   # Cluster-wide"
echo "   oc get clusterrole,clusterrolebinding \\"
echo "     -l olm.owner.kind=ClusterServiceVersion | grep '$OPERATOR_RESOURCE_PREFIX'"
echo ""

echo "9. Full inventory:"
echo "   ----------------"
echo "   oc get all,cm,secret,sa,role,rolebinding \\"
echo "     -n $OPERATOR_NAMESPACE --show-labels"
echo ""

echo "========================================================================"
echo "  🤖 NEXT STEPS FOR AI"
echo "========================================================================"
echo ""
echo "1. Run investigation commands above to find ALL orphaned resources"
echo ""
echo "2. Categorize each found resource:"
echo "   • OLM artifact (should be cleaned up) - has olm.owner labels"
echo "   • PKO artifact (should exist) - has package-operator.run labels"
echo "   • Shared resource (investigate) - no owner labels or unexpected owner"
echo "   • Different operator (don't touch) - different operator name"
echo ""
echo "3. Document findings:"
echo "   • List all orphaned resources with their type and namespace"
echo "   • Note which resources have OLM ownership labels"
echo "   • Identify which should have been removed by cleanup phase"
echo ""
echo "4. Determine root cause:"
echo "   • Missing cleanup phase in PKO package? (check deploy_pko/manifest.yaml)"
echo "   • Cleanup phase exists but failed? (check package-operator logs)"
echo "   • Resources from different operator? (check labels/names)"
echo ""
echo "5. Provide recommendations:"
echo "   • If bug: File issue against operator PKO implementation"
echo "   • If safe: Provide tested cleanup commands"
echo "   • If unclear: Request user confirmation before cleanup"
echo ""
echo "========================================================================"
echo ""

# Exit with appropriate code
if [ "$HAS_CLEANUP_PHASE" = "false" ]; then
    echo "Recommended Action:"
    echo "==================="
    echo ""
    echo "1. File bug report for $OPERATOR_NAME PKO package"
    echo "2. Add cleanup phase to deploy_pko/manifest.yaml"
    echo "3. Create cleanup Job in deploy_pko/ directory"
    echo "4. Test cleanup phase removes all OLM artifacts"
    echo ""
    echo "Reference: configure-alertmanager-operator has complete cleanup implementation"
    echo ""
    exit 2  # Bug detected
else
    echo "Possible Causes:"
    echo "================"
    echo ""
    echo "• Cleanup phase exists but failed to execute"
    echo "• Cleanup phase incomplete (missing some resource types)"
    echo "• Resources belong to different operator"
    echo "• Race condition during cleanup"
    echo ""
    echo "Check package-operator logs for cleanup errors"
    echo ""
    exit 1  # Cleanup incomplete
fi
