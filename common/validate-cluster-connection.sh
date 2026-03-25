#!/bin/bash

# Strict Cluster Connection Validation
# This function validates that the current cluster connection matches the configured cluster
# CANNOT be bypassed - exits with error if mismatch detected
# Prevents accidental operations on wrong cluster
# Enhanced with OCM integration for authoritative cluster data

validate_cluster_connection() {
    local config_cluster_id="$1"
    local config_cluster_server="$2"
    local script_name="${3:-script}"
    local operator_dir="${4:-.}"
    
    echo "========================================================================"
    echo "  CLUSTER VALIDATION (SAFETY CHECK)"
    echo "========================================================================"
    echo ""
    
    # Try to fetch authoritative cluster info from OCM
    # This gives us: id (UUID), name, external_id, api.url
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$script_dir/fetch-cluster-from-ocm.sh" ]; then
        source "$script_dir/fetch-cluster-from-ocm.sh"
        # Fetch and cache - suppress output, errors are OK
        fetch_cluster_from_ocm "$config_cluster_id" "$operator_dir/config/runtime-state" 2>/dev/null || true
    fi
    
    # Load OCM cache if available
    if [ -f "$operator_dir/config/runtime-state" ]; then
        source "$operator_dir/config/runtime-state" 2>/dev/null || true
    fi
    
    # Check if connected to any cluster
    if ! oc whoami &>/dev/null; then
        echo "❌ ERROR: Not connected to any cluster!"
        echo ""
        echo "You must be logged in to a cluster to run this script."
        echo ""
        echo "Expected cluster: $config_cluster_id"
        echo "Expected server: $config_cluster_server"
        echo ""
        if [ -n "$OCM_CLUSTER_EXTERNAL_ID" ]; then
            echo "OCM Details:"
            echo "  Name: $OCM_CLUSTER_NAME"
            echo "  External ID: $OCM_CLUSTER_EXTERNAL_ID"
            echo "  ID: $OCM_CLUSTER_ID"
            echo "  API URL: $OCM_CLUSTER_API_URL"
            echo ""
        fi
        echo "Please login:"
        echo "  oc login --server=$config_cluster_server --username=cluster-admin"
        echo ""
        exit 1
    fi
    
    # Get current cluster information from oc
    local current_context=$(oc config current-context 2>/dev/null)
    local current_server=$(oc config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null)
    local current_user=$(oc whoami 2>/dev/null)
    
    # Get cluster ID from current connection (UUID from clusterversion)
    local current_cluster_uuid=""
    if oc get clusterversion version &>/dev/null; then
        current_cluster_uuid=$(oc get clusterversion version -o jsonpath='{.spec.clusterID}' 2>/dev/null)
    fi
    
    # Get cluster name/external_id from infrastructure (ROSA external_id)
    local current_cluster_name=""
    if oc get infrastructure cluster &>/dev/null; then
        current_cluster_name=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}' 2>/dev/null)
    fi
    
    # Fallback: Extract name from server URL (ROSA pattern)
    if [ -z "$current_cluster_name" ]; then
        # ROSA URLs: https://api.CLUSTER_NAME.HASH.REGION.DOMAIN:6443
        if [[ "$current_server" =~ api\.([^.]+)\. ]]; then
            current_cluster_name="${BASH_REMATCH[1]}"
        fi
    fi
    
    echo "Current Connection:"
    echo "  Context: $current_context"
    echo "  Server: $current_server"
    echo "  User: $current_user"
    echo "  Cluster UUID: ${current_cluster_uuid:-unknown}"
    echo "  Cluster Name: ${current_cluster_name:-unknown}"
    echo ""
    
    echo "Expected Configuration:"
    echo "  Cluster ID: $config_cluster_id"
    echo "  Server: $config_cluster_server"
    if [ -n "$OCM_CLUSTER_NAME" ]; then
        echo ""
        echo "OCM Authoritative Data:"
        echo "  UUID: $OCM_CLUSTER_ID"
        echo "  Name: $OCM_CLUSTER_NAME"
        echo "  External ID: $OCM_CLUSTER_EXTERNAL_ID"
        echo "  API URL: $OCM_CLUSTER_API_URL"
    fi
    echo ""
    
    # Enhanced Validation with OCM data
    # config_cluster_id can match: UUID, name, or external_id
    local cluster_match=false
    local match_method=""
    
    if [ -n "$OCM_CLUSTER_ID" ]; then
        # Use OCM authoritative data for validation
        # Check if current connection matches OCM cluster
        
        # Match method 1: UUID comparison
        if [ -n "$current_cluster_uuid" ] && [ "$current_cluster_uuid" = "$OCM_CLUSTER_ID" ]; then
            cluster_match=true
            match_method="UUID"
        fi
        
        # Match method 2: Name comparison
        if [ -n "$current_cluster_name" ] && [ "$current_cluster_name" = "$OCM_CLUSTER_EXTERNAL_ID" ]; then
            cluster_match=true
            match_method="${match_method:+$match_method and }External ID"
        fi
        
        # Match method 3: Server URL comparison
        if [ -n "$current_server" ] && [ -n "$OCM_CLUSTER_API_URL" ]; then
            local current_server_norm=$(echo "$current_server" | tr '[:upper:]' '[:lower:]' | sed 's:/*$::')
            local ocm_server_norm=$(echo "$OCM_CLUSTER_API_URL" | tr '[:upper:]' '[:lower:]' | sed 's:/*$::')
            if [ "$current_server_norm" = "$ocm_server_norm" ]; then
                cluster_match=true
                match_method="${match_method:+$match_method and }API URL"
            fi
        fi
        
        if [ "$cluster_match" = "true" ]; then
            echo "✓ Cluster matches via $match_method"
            echo "  Connected to: $OCM_CLUSTER_NAME (UUID: $OCM_CLUSTER_ID)"
            echo ""
        else
            echo "❌ CLUSTER MISMATCH!"
            echo ""
            echo "Current cluster connection:"
            echo "  UUID: ${current_cluster_uuid:-unknown}"
            echo "  Name: ${current_cluster_name:-unknown}"
            echo "  Server: $current_server"
            echo ""
            echo "Expected cluster (from OCM):"
            echo "  UUID: $OCM_CLUSTER_ID"
            echo "  Name: $OCM_CLUSTER_NAME"
            echo "  External ID: $OCM_CLUSTER_EXTERNAL_ID"
            echo "  Server: $OCM_CLUSTER_API_URL"
            echo ""
        fi
    else
        # Fallback: No OCM data available, use basic validation
        echo "⚠️  OCM data not available - using basic validation"
        echo ""
        
        # Match using configured values
        local id_match="unknown"
        local server_match="unknown"
        
        # Try matching by UUID
        if [ -n "$current_cluster_uuid" ] && [ "$current_cluster_uuid" = "$config_cluster_id" ]; then
            id_match="true"
            cluster_match=true
            match_method="UUID"
        fi
        
        # Try matching by name/external_id
        if [ -n "$current_cluster_name" ] && [ "$current_cluster_name" = "$config_cluster_id" ]; then
            id_match="true"
            cluster_match=true
            match_method="${match_method:+$match_method and }Name"
        fi
        
        # Try matching by server URL
        if [ -n "$current_server" ] && [ -n "$config_cluster_server" ]; then
            local current_server_norm=$(echo "$current_server" | tr '[:upper:]' '[:lower:]' | sed 's:/*$::')
            local config_server_norm=$(echo "$config_cluster_server" | tr '[:upper:]' '[:lower:]' | sed 's:/*$::')
            if [ "$current_server_norm" = "$config_server_norm" ]; then
                server_match="true"
                cluster_match=true
                match_method="${match_method:+$match_method and }Server URL"
            else
                server_match="false"
            fi
        fi
        
        if [ "$cluster_match" = "true" ]; then
            echo "✓ Cluster matches via $match_method"
            echo ""
        elif [ "$id_match" = "false" ] || [ "$server_match" = "false" ]; then
            echo "❌ CLUSTER MISMATCH!"
            echo ""
            if [ "$id_match" = "false" ]; then
                echo "  Cluster ID mismatch:"
                echo "    Current:  ${current_cluster_uuid:-${current_cluster_name:-unknown}}"
                echo "    Expected: $config_cluster_id"
                echo ""
            fi
            if [ "$server_match" = "false" ]; then
                echo "  Server URL mismatch:"
                echo "    Current:  $current_server"
                echo "    Expected: $config_cluster_server"
                echo ""
            fi
        fi
    fi
    
    # Final decision: Fail if no match
    if [ "$cluster_match" != "true" ]; then
        echo "========================================================================"
        echo "  ❌ CLUSTER VALIDATION FAILED!"
        echo "========================================================================"
        echo ""
        echo "You are connected to the WRONG cluster!"
        echo ""
        echo "This is a SAFETY CHECK to prevent accidental operations on the wrong cluster."
        echo "The script CANNOT continue."
        echo ""
        echo "What to do:"
        echo "1. Logout from current cluster:"
        echo "   oc logout"
        echo ""
        echo "2. Login to the correct cluster:"
        if [ -n "$OCM_CLUSTER_API_URL" ]; then
            echo "   oc login --server=$OCM_CLUSTER_API_URL --username=cluster-admin"
        else
            echo "   oc login --server=$config_cluster_server --username=cluster-admin"
        fi
        echo ""
        echo "3. Re-run this script: $script_name"
        echo ""
        echo "Or update your config/user-config if the cluster information is incorrect:"
        if [ -n "$current_cluster_name" ]; then
            echo "   CLUSTER_ID=$current_cluster_name"
        elif [ -n "$current_cluster_uuid" ]; then
            echo "   CLUSTER_ID=$current_cluster_uuid"
        fi
        echo "   CLUSTER_SERVER=$current_server"
        echo ""
        exit 1
    fi
    
    # Validation passed!
    echo "========================================================================"
    echo "  ✓ CLUSTER VALIDATION PASSED"
    echo "========================================================================"
    echo ""
    if [ -n "$OCM_CLUSTER_NAME" ]; then
        echo "Connected to correct cluster: $OCM_CLUSTER_NAME"
        echo "  UUID: $OCM_CLUSTER_ID"
        echo "  External ID: $OCM_CLUSTER_EXTERNAL_ID"
    else
        echo "Connected to cluster: ${current_cluster_name:-$current_cluster_uuid}"
        echo "  Server: $current_server"
    fi
    echo ""
}

# If script is executed directly (for testing)
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    echo "Testing cluster validation..."
    echo ""
    
    # Example usage
    TEST_CLUSTER_ID="${1:-maclarkrosa0323}"
    TEST_CLUSTER_SERVER="${2:-https://api.maclarkrosa0323.ggrv.s1.devshift.org:6443}"
    TEST_OPERATOR_DIR="${3:-.}"
    
    validate_cluster_connection "$TEST_CLUSTER_ID" "$TEST_CLUSTER_SERVER" "validate-cluster-connection.sh" "$TEST_OPERATOR_DIR"
    
    echo "Validation test complete!"
fi
