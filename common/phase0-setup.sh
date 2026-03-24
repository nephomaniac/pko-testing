#!/bin/bash

# Phase 0: Setup and Configuration Helper
# This script helps users create, view, and manage configuration files
# and acts as an entry point for running PKO testing scripts

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPERATOR_DIR="$(pwd)"

# Detect operator type from current directory
detect_operator() {
    local dir_name=$(basename "$OPERATOR_DIR")
    case "$dir_name" in
        camo|CAMO)
            echo "configure-alertmanager-operator"
            ;;
        rmo|RMO)
            echo "route-monitor-operator"
            ;;
        ome|OME)
            echo "osd-metrics-exporter"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Display header
show_header() {
    local operator=$(detect_operator)
    echo "========================================================================"
    echo "  PKO Testing Framework - Configuration & Setup (Phase 0)"
    echo "========================================================================"
    echo ""
    if [ "$operator" != "unknown" ]; then
        echo "Operator: $(echo $operator | tr '-' ' ' | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1')"
    else
        echo "⚠️  Unknown operator directory: $OPERATOR_DIR"
        echo "   Please run this script from camo/, rmo/, or ome/ directory"
    fi
    echo "Directory: $OPERATOR_DIR"
    echo ""
}

# Check configuration status
check_config_status() {
    local user_config="$OPERATOR_DIR/config/user-config"
    local runtime_state="$OPERATOR_DIR/config/runtime-state"
    local example_config="$OPERATOR_DIR/config/user-config.example"

    echo "Configuration Status:"
    echo "-------------------"

    # Check user-config
    if [ -f "$user_config" ]; then
        echo "✓ user-config exists"

        # Check if pre-built images are configured
        if grep -q "^OPERATOR_IMAGE=" "$user_config" 2>/dev/null; then
            local operator_image=$(grep "^OPERATOR_IMAGE=" "$user_config" | cut -d'=' -f2)
            local pko_image=$(grep "^PKO_IMAGE=" "$user_config" | cut -d'=' -f2)
            echo "  → Using pre-built images:"
            echo "    - Operator: $operator_image"
            echo "    - PKO: $pko_image"
        else
            echo "  → Will build images locally"
        fi
    else
        echo "✗ user-config NOT FOUND"
        if [ -f "$example_config" ]; then
            echo "  → Example config available: $example_config"
        fi
    fi

    # Check runtime-state
    if [ -f "$runtime_state" ]; then
        echo "✓ runtime-state exists"

        # Extract key information
        local last_phase=$(grep "^LAST_RUN_PHASE=" "$runtime_state" 2>/dev/null | cut -d'=' -f2)
        local last_status=$(grep "^LAST_RUN_STATUS=" "$runtime_state" 2>/dev/null | cut -d'=' -f2)
        local last_timestamp=$(grep "^LAST_RUN_TIMESTAMP=" "$runtime_state" 2>/dev/null | cut -d'=' -f2)

        if [ -n "$last_phase" ]; then
            echo "  → Last phase: $last_phase"
            echo "  → Status: $last_status"
            echo "  → Timestamp: $last_timestamp"
        fi
    else
        echo "✗ runtime-state NOT FOUND (will be created by phase scripts)"
    fi

    echo ""
}

# Get next recommended phase
get_next_phase() {
    local runtime_state="$OPERATOR_DIR/config/runtime-state"

    if [ ! -f "$runtime_state" ]; then
        echo "phase1-build-images"
        return
    fi

    local last_phase=$(grep "^LAST_RUN_PHASE=" "$runtime_state" 2>/dev/null | cut -d'=' -f2)
    local last_status=$(grep "^LAST_RUN_STATUS=" "$runtime_state" 2>/dev/null | cut -d'=' -f2)

    # If last phase failed, suggest re-running it
    if [ "$last_status" = "failed" ]; then
        echo "$last_phase"
        return
    fi

    # Determine next phase
    case "$last_phase" in
        phase1-build-images)
            echo "phase2-push-images"
            ;;
        phase2-push-images)
            echo "phase3-prepare-cluster"
            ;;
        phase3-prepare-cluster)
            echo "phase4-prepare-migration"
            ;;
        phase4-prepare-migration)
            echo "phase5-deploy-pko"
            ;;
        phase5-deploy-pko)
            echo "phase6-monitor-deployment"
            ;;
        phase6-monitor-deployment)
            echo "phase7-functional-test"
            ;;
        *)
            echo "phase1-build-images"
            ;;
    esac
}

# Create user-config from example
create_config() {
    local user_config="$OPERATOR_DIR/config/user-config"
    local example_config="$OPERATOR_DIR/config/user-config.example"

    if [ -f "$user_config" ]; then
        echo "⚠️  user-config already exists: $user_config"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            return
        fi
    fi

    if [ ! -f "$example_config" ]; then
        echo "❌ ERROR: Example config not found: $example_config"
        return 1
    fi

    cp "$example_config" "$user_config"
    echo "✓ Created: $user_config"
    echo ""
    echo "Please edit this file and set:"
    echo "  - IMAGE_REGISTRY (e.g., quay.io)"
    echo "  - IMAGE_REPOSITORY (your quay.io username)"
    echo "  - CLUSTER_ID (your test cluster name)"
    echo "  - CLUSTER_SERVER (cluster API URL)"
    echo ""
    echo "OR uncomment OPERATOR_IMAGE and PKO_IMAGE to use pre-built images"
    echo ""
    read -p "Edit now? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        ${EDITOR:-nano} "$user_config"
    fi
}

# View configuration
view_config() {
    local user_config="$OPERATOR_DIR/config/user-config"

    if [ ! -f "$user_config" ]; then
        echo "❌ user-config not found. Create it first (option 1)."
        return 1
    fi

    echo "Current Configuration:"
    echo "====================="
    cat -n "$user_config"
    echo ""
}

# Edit configuration
edit_config() {
    local user_config="$OPERATOR_DIR/config/user-config"

    if [ ! -f "$user_config" ]; then
        echo "❌ user-config not found. Create it first (option 1)."
        return 1
    fi

    ${EDITOR:-nano} "$user_config"
    echo "✓ Configuration updated"
}

# View runtime state
view_runtime_state() {
    local runtime_state="$OPERATOR_DIR/config/runtime-state"

    if [ ! -f "$runtime_state" ]; then
        echo "❌ runtime-state not found. It will be created when you run phase scripts."
        return 1
    fi

    echo "Current Runtime State:"
    echo "====================="
    cat -n "$runtime_state"
    echo ""
}

# View logs
view_logs() {
    local logs_dir="$OPERATOR_DIR/logs"

    if [ ! -d "$logs_dir" ] || [ -z "$(ls -A "$logs_dir" 2>/dev/null)" ]; then
        echo "❌ No logs found in: $logs_dir"
        return 1
    fi

    echo "Available Logs:"
    echo "==============="
    ls -lht "$logs_dir"
    echo ""

    read -p "View latest log? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        local latest_log=$(ls -t "$logs_dir" | head -1)
        echo ""
        echo "=== $latest_log ==="
        echo ""
        less "$logs_dir/$latest_log"
    fi
}

# Run next phase
run_next_phase() {
    local user_config="$OPERATOR_DIR/config/user-config"

    if [ ! -f "$user_config" ]; then
        echo "❌ user-config not found. Create and configure it first (option 1)."
        return 1
    fi

    local next_phase=$(get_next_phase)
    local phase_script="$SCRIPT_DIR/${next_phase}.sh"

    # Check if using pre-built images - skip build/push phases
    if grep -q "^OPERATOR_IMAGE=" "$user_config" 2>/dev/null; then
        if [ "$next_phase" = "phase1-build-images" ] || [ "$next_phase" = "phase2-push-images" ]; then
            echo "ℹ️  Pre-built images configured - skipping build/push phases"
            next_phase="phase3-prepare-cluster"
            phase_script="$SCRIPT_DIR/${next_phase}.sh"
        fi
    fi

    echo "Next Phase: $next_phase"
    echo ""

    if [ ! -f "$phase_script" ]; then
        echo "❌ Phase script not found: $phase_script"
        return 1
    fi

    read -p "Run $next_phase? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo ""
        echo "========================================================================"
        echo "  Running: $next_phase"
        echo "========================================================================"
        echo ""
        bash "$phase_script"
    fi
}

# Show menu
show_menu() {
    echo "Options:"
    echo "--------"
    echo "1. Create user-config from example"
    echo "2. View current configuration"
    echo "3. Edit configuration"
    echo "4. View runtime state"
    echo "5. View logs"
    echo "6. Run next recommended phase"
    echo ""
    echo "0. Exit"
    echo ""
}

# Main menu loop
main() {
    while true; do
        clear
        show_header
        check_config_status

        local next_phase=$(get_next_phase)
        echo "Next Recommended Phase: $next_phase"
        echo ""

        show_menu

        read -p "Choose an option: " choice
        echo ""

        case "$choice" in
            1)
                create_config
                ;;
            2)
                view_config
                ;;
            3)
                edit_config
                ;;
            4)
                view_runtime_state
                ;;
            5)
                view_logs
                ;;
            6)
                run_next_phase
                ;;
            0)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                echo "Invalid option: $choice"
                ;;
        esac

        echo ""
        read -p "Press Enter to continue..." -r
    done
}

# If script is executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main
fi
