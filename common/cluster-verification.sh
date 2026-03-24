#!/bin/bash

# Shared cluster verification function for CAMO PKO testing
# This function verifies that the current oc connection matches the expected test cluster

verify_cluster() {
    local context="$1"
    local config_file="${2:-$(cd "$(dirname "$0")" && pwd)/config/.camo-pko-test-config}"

    # Check if connected to any cluster
    if ! oc whoami &>/dev/null; then
        echo "❌ ERROR: Not logged into any OpenShift cluster"
        echo "Please login to your test cluster first"
        exit 1
    fi

    # Get current connection info
    CURRENT_SERVER=$(oc whoami --show-server)
    CURRENT_USER=$(oc whoami)

    # Get current cluster UUID (unique identifier)
    CURRENT_CLUSTER_UUID=$(oc get clusterversion -o jsonpath='{.spec.clusterID}' 2>/dev/null || echo "")

    # Extract cluster name from infrastructure (may contain cluster ID)
    CURRENT_INFRA_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}' 2>/dev/null || echo "")

    # Load saved cluster info if available
    if [ -f "$config_file" ]; then
        source "$config_file"
    fi

    # Verify cluster ID if we have one saved
    if [ -n "$CLUSTER_ID" ]; then
        # Primary check: Compare cluster UUIDs
        if [ -n "$CURRENT_CLUSTER_UUID" ] && [ -n "$CLUSTER_UUID" ]; then
            if [ "$CURRENT_CLUSTER_UUID" != "$CLUSTER_UUID" ]; then
                echo "❌ CLUSTER MISMATCH ERROR!"
                echo
                echo "Expected cluster:"
                echo "  ID: $CLUSTER_ID"
                echo "  UUID: $CLUSTER_UUID"
                echo "  Server: $CLUSTER_SERVER"
                echo
                echo "Current cluster:"
                echo "  UUID: $CURRENT_CLUSTER_UUID"
                echo "  Server: $CURRENT_SERVER"
                echo "  Infrastructure: $CURRENT_INFRA_NAME"
                echo
                echo "You are connected to the WRONG cluster!"
                echo
                if [ -n "$context" ]; then
                    echo "Context: $context"
                    echo
                fi
                echo "Please login to the correct test cluster:"
                echo "  ocm backplane login $CLUSTER_ID"
                echo
                exit 1
            fi
        fi

        # Secondary check: Verify server URL matches
        if [ -n "$CLUSTER_SERVER" ] && [ "$CURRENT_SERVER" != "$CLUSTER_SERVER" ]; then
            echo "❌ CLUSTER MISMATCH ERROR!"
            echo
            echo "Expected cluster: $CLUSTER_ID"
            echo "Expected server:  $CLUSTER_SERVER"
            echo "Current server:   $CURRENT_SERVER"
            echo
            echo "You are connected to the WRONG cluster!"
            echo
            if [ -n "$context" ]; then
                echo "Context: $context"
                echo
            fi
            echo "Please login to the correct test cluster:"
            echo "  ocm backplane login $CLUSTER_ID"
            echo
            exit 1
        fi

        # Tertiary check: Look for cluster ID in infrastructure name
        if [ -n "$CURRENT_INFRA_NAME" ]; then
            if [[ "$CURRENT_INFRA_NAME" != *"$CLUSTER_ID"* ]]; then
                echo "⚠️  WARNING: Cluster ID not found in infrastructure name"
                echo "  Expected cluster ID: $CLUSTER_ID"
                echo "  Current infrastructure: $CURRENT_INFRA_NAME"
                echo
                read -p "Continue anyway? This may be the wrong cluster. (y/n): " CONTINUE
                if [ "$CONTINUE" != "y" ]; then
                    echo "Aborted. Please verify cluster connection."
                    exit 1
                fi
            fi
        fi

        echo "✓ Cluster verification passed"
        echo "  Cluster ID: $CLUSTER_ID"
        echo "  Cluster UUID: $CURRENT_CLUSTER_UUID"
        echo "  Server: $CURRENT_SERVER"
        echo "  User: $CURRENT_USER"
    else
        echo "⚠️  No saved cluster ID in config yet"
        echo "  Current server: $CURRENT_SERVER"
        echo "  Current cluster UUID: $CURRENT_CLUSTER_UUID"
        echo "  Current infrastructure: $CURRENT_INFRA_NAME"
        echo "  User: $CURRENT_USER"
    fi
    echo
}

# Function to save cluster info to config
save_cluster_info() {
    local cluster_id="$1"
    local config_file="${2:-$(cd "$(dirname "$0")" && pwd)/.camo-pko-test-config}"

    if ! oc whoami &>/dev/null; then
        echo "ERROR: Not logged into any cluster"
        return 1
    fi

    CLUSTER_SERVER=$(oc whoami --show-server)
    CLUSTER_USER=$(oc whoami)
    CLUSTER_UUID=$(oc get clusterversion -o jsonpath='{.spec.clusterID}' 2>/dev/null || echo "")

    # Save to config file
    {
        echo "CLUSTER_ID=$cluster_id"
        echo "CLUSTER_SERVER=$CLUSTER_SERVER"
        echo "CLUSTER_USER=$CLUSTER_USER"
        echo "CLUSTER_UUID=$CLUSTER_UUID"
    } >> "$config_file"

    echo "✓ Cluster information saved to config:"
    echo "  ID: $cluster_id"
    echo "  UUID: $CLUSTER_UUID"
    echo "  Server: $CLUSTER_SERVER"
    echo "  User: $CLUSTER_USER"
}

# Function to confirm dangerous operations with cluster context
confirm_operation() {
    local operation_type="$1"
    shift
    local commands=("$@")

    # Get current cluster info
    local current_name=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}' 2>/dev/null | sed 's/-[a-z0-9]*$//' || echo "unknown")
    local current_id="${CLUSTER_ID:-unknown}"
    local current_server=$(oc whoami --show-server 2>/dev/null || echo "unknown")

    echo
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    ⚠️  CONFIRMATION REQUIRED                    ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo
    echo "Operation Type: $operation_type"
    echo
    echo "Target Cluster:"
    echo "  Name: $current_name"
    echo "  ID: $current_id"
    echo "  Server: $current_server"
    echo
    echo "Commands to execute:"
    echo

    for cmd in "${commands[@]}"; do
        echo "  → $cmd"
    done

    echo
    echo "════════════════════════════════════════════════════════════════"
    echo
    read -p "Execute these commands on cluster '$current_id'? (yes/no): " CONFIRM

    if [ "$CONFIRM" = "yes" ]; then
        echo "✓ Confirmed - proceeding with operation"
        echo
        return 0
    else
        echo "✗ Operation cancelled by user"
        echo
        return 1
    fi
}
