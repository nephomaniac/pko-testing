#!/bin/bash
set -e

# CAMO PKO Testing - Run All Phases
# This script runs all phases in sequence with confirmation prompts

# Script runs from operator directory (camo/, rmo/, etc.)
OPERATOR_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "===================================="
echo "CAMO PKO Testing - Full Workflow"
echo "===================================="
echo
echo "This script will guide you through all 8 phases:"
echo "  1. Build images locally"
echo "  2. Push images to Quay"
echo "  3. Prepare cluster (requires Hive sync pause)"
echo "  4. Remove OLM deployment"
echo "  5. Deploy via PKO"
echo "  6. Monitor deployment"
echo "  7. Run functional tests"
echo "  8. Cleanup (optional)"
echo

read -p "Continue with full workflow? (y/n): " START
if [ "$START" != "y" ]; then
    echo "Aborted."
    exit 0
fi

# Phase 1
echo
echo "===================================="
echo "Starting Phase 1: Build Images"
echo "===================================="
read -p "Press Enter to continue or Ctrl+C to abort..."
"$SCRIPT_DIR/phase1-build-images.sh"

# Phase 2
echo
echo "===================================="
echo "Starting Phase 2: Push Images"
echo "===================================="
read -p "Press Enter to continue or Ctrl+C to abort..."
"$SCRIPT_DIR/phase2-push-images.sh"

echo
echo "⚠️  IMPORTANT: Before continuing, verify images are PUBLIC in Quay.io:"
echo "    https://quay.io/repository/<your-username>/configure-alertmanager-operator"
echo "    https://quay.io/repository/<your-username>/configure-alertmanager-operator-pko"
read -p "Press Enter when images are PUBLIC..."

# Phase 3
echo
echo "===================================="
echo "Starting Phase 3: Prepare Cluster"
echo "===================================="
read -p "Press Enter to continue or Ctrl+C to abort..."
"$SCRIPT_DIR/phase3-prepare-cluster.sh"

# Phase 4
echo
echo "===================================="
echo "Starting Phase 4: Remove OLM"
echo "===================================="
read -p "Press Enter to continue or Ctrl+C to abort..."
"$SCRIPT_DIR/phase4-remove-olm.sh"

# Phase 5
echo
echo "===================================="
echo "Starting Phase 5: Deploy PKO"
echo "===================================="
read -p "Press Enter to continue or Ctrl+C to abort..."
"$SCRIPT_DIR/phase5-deploy-pko.sh"

# Phase 6
echo
echo "===================================="
echo "Starting Phase 6: Monitor Deployment"
echo "===================================="
read -p "Press Enter to continue or Ctrl+C to abort..."
"$SCRIPT_DIR/phase6-monitor-deployment.sh"

# Phase 7
echo
echo "===================================="
echo "Starting Phase 7: Functional Tests"
echo "===================================="
read -p "Press Enter to continue or Ctrl+C to abort..."
"$SCRIPT_DIR/phase7-functional-test.sh"

# Phase 8 (optional)
echo
echo "===================================="
echo "Phase 8: Cleanup (Optional)"
echo "===================================="
echo
echo "You can now:"
echo "  A. Keep PKO deployment running for extended testing"
echo "  B. Run cleanup to restore OLM deployment"
echo

read -p "Run cleanup now? (y/n): " CLEANUP
if [ "$CLEANUP" = "y" ]; then
    "$SCRIPT_DIR/phase8-cleanup.sh"
fi

echo
echo "===================================="
echo "Workflow Complete!"
echo "===================================="
echo
echo "All phases executed successfully."
echo
if [ "$CLEANUP" = "y" ]; then
    echo "PKO deployment has been cleaned up."
    echo "Remember to resume Hive sync if you haven't already!"
else
    echo "PKO deployment is still running."
    echo "Run phase8-cleanup.sh when ready to remove it."
fi
