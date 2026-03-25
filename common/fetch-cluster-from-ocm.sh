#!/bin/bash

# Fetch Cluster Information from OCM
# Gets authoritative cluster details: id, name, external_id, api.url
# Caches result in runtime-state for validation

fetch_cluster_from_ocm() {
    local cluster_identifier="$1"  # Can be: name, external_id, or UUID
    local cache_file="${2:-config/runtime-state}"
    
    echo "Fetching cluster information from OCM..."
    echo "  Identifier: $cluster_identifier"
    echo ""
    
    # Check if ocm CLI is available
    if ! command -v ocm &>/dev/null; then
        echo "⚠️  OCM CLI not found - skipping OCM fetch"
        echo "   Install: https://github.com/openshift-online/ocm-cli"
        return 1
    fi
    
    # Check if logged in to OCM
    if ! ocm whoami &>/dev/null; then
        echo "⚠️  Not logged in to OCM - skipping OCM fetch"
        echo "   Login: ocm login --token=YOUR_TOKEN"
        return 1
    fi
    
    # Fetch cluster details from OCM
    # Try to find by name, external_id, or id
    local ocm_response=$(ocm get /api/clusters_mgmt/v1/clusters --parameter search="name='$cluster_identifier' or external_id='$cluster_identifier' or id='$cluster_identifier'" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$ocm_response" ]; then
        echo "⚠️  Failed to fetch cluster from OCM"
        return 1
    fi
    
    # Check if we got results
    local total=$(echo "$ocm_response" | jq -r '.total // 0' 2>/dev/null)
    
    if [ "$total" = "0" ]; then
        echo "⚠️  Cluster not found in OCM: $cluster_identifier"
        return 1
    fi
    
    if [ "$total" -gt 1 ]; then
        echo "⚠️  Multiple clusters found matching: $cluster_identifier"
        echo "   Please use a more specific identifier"
        return 1
    fi
    
    # Extract cluster details
    local cluster_id=$(echo "$ocm_response" | jq -r '.items[0].id' 2>/dev/null)
    local cluster_name=$(echo "$ocm_response" | jq -r '.items[0].name' 2>/dev/null)
    local cluster_external_id=$(echo "$ocm_response" | jq -r '.items[0].external_id' 2>/dev/null)
    local cluster_api_url=$(echo "$ocm_response" | jq -r '.items[0].api.url' 2>/dev/null)
    local cluster_state=$(echo "$ocm_response" | jq -r '.items[0].state' 2>/dev/null)
    local cluster_region=$(echo "$ocm_response" | jq -r '.items[0].region.id' 2>/dev/null)
    local cluster_product=$(echo "$ocm_response" | jq -r '.items[0].product.id' 2>/dev/null)
    
    echo "✓ Cluster found in OCM:"
    echo "  ID: $cluster_id"
    echo "  Name: $cluster_name"
    echo "  External ID: $cluster_external_id"
    echo "  API URL: $cluster_api_url"
    echo "  State: $cluster_state"
    echo "  Region: $cluster_region"
    echo "  Product: $cluster_product"
    echo ""
    
    # Cache in runtime-state if cache file provided
    if [ -n "$cache_file" ]; then
        echo "Caching cluster information..."
        
        # Create or update cache file with OCM data
        # Use a unique section marker
        local temp_file=$(mktemp)
        
        # If cache file exists, remove old OCM cache section
        if [ -f "$cache_file" ]; then
            sed '/^# OCM Cluster Cache/,/^# End OCM Cluster Cache/d' "$cache_file" > "$temp_file"
        fi
        
        # Append new OCM cache
        cat >> "$temp_file" <<EOF

# OCM Cluster Cache
# Fetched from OCM at $(date -u +"%Y-%m-%dT%H:%M:%SZ")
OCM_CLUSTER_ID="$cluster_id"
OCM_CLUSTER_NAME="$cluster_name"
OCM_CLUSTER_EXTERNAL_ID="$cluster_external_id"
OCM_CLUSTER_API_URL="$cluster_api_url"
OCM_CLUSTER_STATE="$cluster_state"
OCM_CLUSTER_REGION="$cluster_region"
OCM_CLUSTER_PRODUCT="$cluster_product"
OCM_CACHE_TIMESTAMP=$(date +%s)
# End OCM Cluster Cache
EOF
        
        mv "$temp_file" "$cache_file"
        echo "✓ Cached to: $cache_file"
        echo ""
    fi
    
    # Export for current shell session
    export OCM_CLUSTER_ID="$cluster_id"
    export OCM_CLUSTER_NAME="$cluster_name"
    export OCM_CLUSTER_EXTERNAL_ID="$cluster_external_id"
    export OCM_CLUSTER_API_URL="$cluster_api_url"
    export OCM_CLUSTER_STATE="$cluster_state"
    
    return 0
}

# If script is executed directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    CLUSTER="${1:-maclarkrosa0323}"
    CACHE_FILE="${2:-config/runtime-state}"
    
    fetch_cluster_from_ocm "$CLUSTER" "$CACHE_FILE"
fi
