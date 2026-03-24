#!/bin/bash

# Manual OLM Cleanup Helper
# Provides commands to manually remove OLM artifacts if PKO cleanup fails

OPERATOR_DIR="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load configuration
source "$SCRIPT_DIR/load-config.sh"
load_config "$OPERATOR_DIR"

# Determine operator name
OPERATOR_NAME=""
if [ -n "$CAMO_REPO" ]; then
    OPERATOR_NAME="configure-alertmanager-operator"
elif [ -n "$RMO_REPO" ]; then
    OPERATOR_NAME="route-monitor-operator"
elif [ -n "$OME_REPO" ]; then
    OPERATOR_NAME="osd-metrics-exporter"
else
    echo "ERROR: No operator repository configured"
    exit 1
fi

echo "===================================="
echo "Manual OLM Cleanup Commands"
echo "===================================="
echo
echo "Operator: $OPERATOR_NAME"
echo "Namespace: $OPERATOR_NAMESPACE"
echo

# Check what exists
HAS_SUBSCRIPTION=false
HAS_CSV=false
HAS_CATALOGSOURCE=false
CSV_NAME=""

if oc get subscription $OPERATOR_NAME -n $OPERATOR_NAMESPACE &>/dev/null; then
    HAS_SUBSCRIPTION=true
fi

CSV_NAME=$(oc get csv -n $OPERATOR_NAMESPACE -o name 2>/dev/null | grep -i $(echo $OPERATOR_NAME | sed 's/-operator//') | head -1)
if [ -n "$CSV_NAME" ]; then
    HAS_CSV=true
fi

if oc get catalogsource ${OPERATOR_NAME}-registry -n $OPERATOR_NAMESPACE &>/dev/null; then
    HAS_CATALOGSOURCE=true
fi

if [ "$HAS_SUBSCRIPTION" = false ] && [ "$HAS_CSV" = false ] && [ "$HAS_CATALOGSOURCE" = false ]; then
    echo "✓ No OLM resources found - cleanup not needed"
    exit 0
fi

echo "Current OLM resources:"
[ "$HAS_SUBSCRIPTION" = true ] && echo "  - Subscription: $OPERATOR_NAME"
[ "$HAS_CSV" = true ] && echo "  - CSV: $CSV_NAME"
[ "$HAS_CATALOGSOURCE" = true ] && echo "  - CatalogSource: ${OPERATOR_NAME}-registry"
echo

echo "===================================="
echo "Manual Cleanup Commands"
echo "===================================="
echo
echo "Run these commands to manually remove OLM artifacts:"
echo

if [ "$HAS_SUBSCRIPTION" = true ]; then
    echo "# Delete Subscription"
    echo "oc delete subscription $OPERATOR_NAME -n $OPERATOR_NAMESPACE"
    echo
fi

if [ "$HAS_CSV" = true ]; then
    echo "# Delete ClusterServiceVersion"
    echo "oc delete $CSV_NAME -n $OPERATOR_NAMESPACE"
    echo
fi

if [ "$HAS_CATALOGSOURCE" = true ]; then
    echo "# Delete CatalogSource"
    echo "oc delete catalogsource ${OPERATOR_NAME}-registry -n $OPERATOR_NAMESPACE"
    echo
fi

echo "# Verify cleanup"
echo "oc get subscription,csv,catalogsource -n $OPERATOR_NAMESPACE | grep -i $OPERATOR_NAME"
echo

echo "===================================="
echo "⚠️  IMPORTANT: Hive Sync Warning"
echo "===================================="
echo
echo "If you have Hive managing this cluster:"
echo
echo "1. Hive sync is currently paused (if you ran phase3)"
echo
echo "2. When you unpause Hive, it will restore resources from SelectorSyncSet"
echo
echo "3. Hive will likely restore the operator using its currently configured"
echo "   deployment method (OLM or PKO, depending on what's in app-interface)"
echo
echo "4. Make sure app-interface has been updated to use PKO before unpausing Hive"
echo
echo "To check Hive sync status:"
echo "  oc get syncset,selectorsyncset -A | grep -i $OPERATOR_NAME"
echo
echo "To keep Hive paused:"
echo "  # Ensure the annotation remains on the SyncIdentity"
echo "  oc get syncidentity \$CLUSTER_ID -n uhc-production -o yaml | grep pause"
echo

echo "===================================="
echo "Interactive Cleanup"
echo "===================================="
echo
read -p "Run cleanup commands now? (y/n): " RUN_CLEANUP

if [ "$RUN_CLEANUP" = "y" ]; then
    echo
    echo "Executing cleanup..."
    echo

    if [ "$HAS_SUBSCRIPTION" = true ]; then
        echo "Deleting Subscription..."
        oc delete subscription $OPERATOR_NAME -n $OPERATOR_NAMESPACE
        echo "✓ Subscription deleted"
        echo
    fi

    if [ "$HAS_CSV" = true ]; then
        echo "Deleting ClusterServiceVersion..."
        oc delete $CSV_NAME -n $OPERATOR_NAMESPACE
        echo "✓ CSV deleted"
        echo
    fi

    if [ "$HAS_CATALOGSOURCE" = true ]; then
        echo "Deleting CatalogSource..."
        oc delete catalogsource ${OPERATOR_NAME}-registry -n $OPERATOR_NAMESPACE
        echo "✓ CatalogSource deleted"
        echo
    fi

    echo "Waiting for cleanup to complete..."
    sleep 5

    echo
    echo "Checking for remaining OLM resources..."
    REMAINING=$(oc get subscription,csv,catalogsource -n $OPERATOR_NAMESPACE 2>/dev/null | grep -i $OPERATOR_NAME || echo "")

    if [ -z "$REMAINING" ]; then
        echo "✓ All OLM resources removed successfully"
    else
        echo "⚠️  Some resources may still exist:"
        echo "$REMAINING"
    fi
else
    echo "Cleanup commands not executed. Copy them from above to run manually."
fi

echo
