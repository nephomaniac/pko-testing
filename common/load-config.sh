#!/bin/bash

# Shared configuration loader for PKO testing scripts
# This script loads user config and runtime state

load_config() {
    local operator_dir="${1:-$(pwd)}"

    # Paths to config files
    local user_config="$operator_dir/config/user-config"
    local runtime_state="$operator_dir/config/runtime-state"

    # Legacy config file (for backwards compatibility)
    local legacy_config="$operator_dir/config/pko-test-config"

    # Load user configuration
    if [ -f "$user_config" ]; then
        echo "Loading user config: $user_config"
        source "$user_config"
    elif [ -f "$legacy_config" ]; then
        echo "Loading legacy config: $legacy_config"
        echo "⚠️  Consider migrating to user-config + runtime-state structure"
        source "$legacy_config"
        return 0
    else
        echo "ERROR: User config not found: $user_config"
        echo
        echo "Create it from the example:"
        echo "  cp $operator_dir/config/user-config.example $user_config"
        echo "  nano $user_config"
        exit 1
    fi

    # Load runtime state (if it exists)
    if [ -f "$runtime_state" ]; then
        echo "Loading runtime state: $runtime_state"
        source "$runtime_state"
    else
        echo "No runtime state found (will be created by phase scripts)"
    fi

    echo "✓ Configuration loaded"
    echo
}

save_runtime_state() {
    local operator_dir="${1:-$(pwd)}"
    local runtime_state="$operator_dir/config/runtime-state"
    local phase_name="$2"
    local phase_status="${3:-success}"

    # Create runtime state file with header
    cat > "$runtime_state" << EOF
# PKO Test Runtime State
# AUTO-GENERATED - DO NOT EDIT MANUALLY
# Last updated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ============================================================================
# Test Execution Tracking
# ============================================================================
LAST_RUN_PHASE=$phase_name
LAST_RUN_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LAST_RUN_STATUS=$phase_status
LAST_RUN_LOG=${LAST_RUN_LOG:-logs/${phase_name}-$(date +%Y%m%d-%H%M%S).log}

# ============================================================================
# Image Information
# ============================================================================
EOF

    # Save image variables
    [ -n "$IMAGE_NAME" ] && echo "IMAGE_NAME=$IMAGE_NAME" >> "$runtime_state"
    [ -n "$IMAGE_TAG_BASE" ] && echo "IMAGE_TAG_BASE=$IMAGE_TAG_BASE" >> "$runtime_state"
    [ -n "$GIT_COMMIT_SHORT" ] && echo "GIT_COMMIT_SHORT=$GIT_COMMIT_SHORT" >> "$runtime_state"
    [ -n "$GIT_COMMIT_LONG" ] && echo "GIT_COMMIT_LONG=$GIT_COMMIT_LONG" >> "$runtime_state"
    [ -n "$IMAGE_TAG" ] && echo "IMAGE_TAG=$IMAGE_TAG" >> "$runtime_state"
    [ -n "$OPERATOR_IMAGE" ] && echo "OPERATOR_IMAGE=$OPERATOR_IMAGE" >> "$runtime_state"
    [ -n "$PKO_IMAGE" ] && echo "PKO_IMAGE=$PKO_IMAGE" >> "$runtime_state"
    [ -n "$BUILD_TIMESTAMP" ] && echo "BUILD_TIMESTAMP=$BUILD_TIMESTAMP" >> "$runtime_state"

    cat >> "$runtime_state" << EOF

# ============================================================================
# Push Information
# ============================================================================
EOF

    # Save push variables
    [ -n "$IMAGES_PUSHED" ] && echo "IMAGES_PUSHED=$IMAGES_PUSHED" >> "$runtime_state"
    [ -n "$PUSH_TIMESTAMP" ] && echo "PUSH_TIMESTAMP=$PUSH_TIMESTAMP" >> "$runtime_state"
    [ -n "$IMAGE_REPOSITORY" ] && echo "IMAGE_REPOSITORY=$IMAGE_REPOSITORY" >> "$runtime_state"
    [ -n "$QUAY_REPOSITORY_OPERATOR" ] && echo "QUAY_REPOSITORY_OPERATOR=$QUAY_REPOSITORY_OPERATOR" >> "$runtime_state"
    [ -n "$QUAY_REPOSITORY_PKO" ] && echo "QUAY_REPOSITORY_PKO=$QUAY_REPOSITORY_PKO" >> "$runtime_state"

    cat >> "$runtime_state" << EOF

# ============================================================================
# Cluster Information
# ============================================================================
EOF

    # Save cluster variables
    [ -n "$CLUSTER_NAME" ] && echo "CLUSTER_NAME=$CLUSTER_NAME" >> "$runtime_state"
    [ -n "$CLUSTER_ID" ] && echo "CLUSTER_ID=$CLUSTER_ID" >> "$runtime_state"
    [ -n "$CLUSTER_UUID" ] && echo "CLUSTER_UUID=$CLUSTER_UUID" >> "$runtime_state"
    [ -n "$CLUSTER_VERSION" ] && echo "CLUSTER_VERSION=$CLUSTER_VERSION" >> "$runtime_state"
    [ -n "$CLUSTER_PLATFORM" ] && echo "CLUSTER_PLATFORM=$CLUSTER_PLATFORM" >> "$runtime_state"
    [ -n "$CLUSTER_REGION" ] && echo "CLUSTER_REGION=$CLUSTER_REGION" >> "$runtime_state"
    [ -n "$CLUSTER_INFRA_NAME" ] && echo "CLUSTER_INFRA_NAME=$CLUSTER_INFRA_NAME" >> "$runtime_state"
    [ -n "$BACKUP_TIMESTAMP" ] && echo "BACKUP_TIMESTAMP=$BACKUP_TIMESTAMP" >> "$runtime_state"
    [ -n "$BACKUP_DIR" ] && echo "BACKUP_DIR=$BACKUP_DIR" >> "$runtime_state"

    cat >> "$runtime_state" << EOF

# ============================================================================
# Migration Configuration
# ============================================================================
EOF

    # Save migration variables
    [ -n "$MIGRATION_MODE" ] && echo "MIGRATION_MODE=$MIGRATION_MODE" >> "$runtime_state"
    [ -n "$OLM_CLEANUP_METHOD" ] && echo "OLM_CLEANUP_METHOD=$OLM_CLEANUP_METHOD" >> "$runtime_state"
    [ -n "$HIVE_PAUSED" ] && echo "HIVE_PAUSED=$HIVE_PAUSED" >> "$runtime_state"

    cat >> "$runtime_state" << EOF

# ============================================================================
# Deployment Information
# ============================================================================
EOF

    # Save deployment variables
    [ -n "$DEPLOY_START_TIME" ] && echo "DEPLOY_START_TIME=$DEPLOY_START_TIME" >> "$runtime_state"
    [ -n "$CLUSTERPACKAGE_NAME" ] && echo "CLUSTERPACKAGE_NAME=$CLUSTERPACKAGE_NAME" >> "$runtime_state"
    [ -n "$CLUSTERPACKAGE_MANIFEST" ] && echo "CLUSTERPACKAGE_MANIFEST=$CLUSTERPACKAGE_MANIFEST" >> "$runtime_state"

    cat >> "$runtime_state" << EOF

# ============================================================================
# Validation Results
# ============================================================================
EOF

    # Save validation variables
    [ -n "$DEPLOYMENT_STATUS" ] && echo "DEPLOYMENT_STATUS=$DEPLOYMENT_STATUS" >> "$runtime_state"
    [ -n "$OLM_CLEANUP_VALIDATED" ] && echo "OLM_CLEANUP_VALIDATED=$OLM_CLEANUP_VALIDATED" >> "$runtime_state"
    [ -n "$PKO_RESOURCES_VALIDATED" ] && echo "PKO_RESOURCES_VALIDATED=$PKO_RESOURCES_VALIDATED" >> "$runtime_state"
    [ -n "$VALIDATION_TIMESTAMP" ] && echo "VALIDATION_TIMESTAMP=$VALIDATION_TIMESTAMP" >> "$runtime_state"

    echo >> "$runtime_state"
    echo "# This file is recreated on each test run" >> "$runtime_state"
    echo "# DO NOT COMMIT THIS FILE TO GIT" >> "$runtime_state"

    echo "✓ Runtime state saved to: $runtime_state"
}

# Allow sourcing this file to get the functions
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    echo "ERROR: This script should be sourced, not executed directly"
    echo "Usage: source $0"
    exit 1
fi
