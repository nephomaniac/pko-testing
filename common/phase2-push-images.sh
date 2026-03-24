#!/bin/bash
set -e

# Phase 2: Push CAMO PKO Images to Quay
# This script pushes both images to your personal Quay repository

# Parse command-line arguments
AUTO_CONFIRM=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-confirm)
            AUTO_CONFIRM=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--auto-confirm]"
            exit 1
            ;;
    esac
done

echo "===================================="
echo "Phase 2: Push Images to Quay"
echo "===================================="
echo

# Script runs from operator directory (camo/, rmo/, etc.)
OPERATOR_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load configuration from phase 1
source "$SCRIPT_DIR/load-config.sh"
load_config "$OPERATOR_DIR"

# Extract repository and image name for Quay URLs
IMAGE_REPOSITORY=$(echo "$OPERATOR_IMAGE" | cut -d'/' -f2)
IMAGE_NAME=$(echo "$OPERATOR_IMAGE" | cut -d'/' -f3 | cut -d':' -f1)

echo "Configuration loaded:"
echo "  Operator Image: $OPERATOR_IMAGE"
echo "  PKO Package Image: $PKO_IMAGE"
echo

# Verify images exist locally
echo "Verifying local images..."
if ! podman images --format "{{.Repository}}:{{.Tag}}" | grep -q "$OPERATOR_IMAGE"; then
    echo "ERROR: Operator image not found locally: $OPERATOR_IMAGE"
    exit 1
fi

if ! podman images --format "{{.Repository}}:{{.Tag}}" | grep -q "$PKO_IMAGE"; then
    echo "ERROR: PKO package image not found locally: $PKO_IMAGE"
    exit 1
fi

echo "✓ Both images found locally"
echo

# Check if already logged into quay
echo "Checking Quay.io authentication..."
if ! podman login --get-login quay.io &>/dev/null; then
    echo "Not logged into Quay.io. Please login:"
    podman login quay.io
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to login to Quay.io"
        exit 1
    fi
else
    echo "✓ Already logged into Quay.io"
fi
echo

if [ "$AUTO_CONFIRM" = false ]; then
    read -p "Push images to Quay.io? (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ]; then
        echo "Aborted."
        exit 0
    fi
fi

echo
echo "===================================="
echo "Pushing Operator Image"
echo "===================================="
echo "Image: $OPERATOR_IMAGE"
echo

podman push "$OPERATOR_IMAGE"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to push operator image"
    exit 1
fi

echo "✓ Operator image pushed successfully"
echo

echo "===================================="
echo "Pushing PKO Package Image"
echo "===================================="
echo "Image: $PKO_IMAGE"
echo

podman push "$PKO_IMAGE"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to push PKO package image"
    exit 1
fi

echo "✓ PKO package image pushed successfully"
echo

# Set environment variables for runtime state tracking
export IMAGES_PUSHED=true
export PUSH_TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
export QUAY_REPOSITORY_OPERATOR="https://quay.io/repository/$IMAGE_REPOSITORY/$IMAGE_NAME"
export QUAY_REPOSITORY_PKO="https://quay.io/repository/$IMAGE_REPOSITORY/${IMAGE_NAME}-pko"
export IMAGE_REPOSITORY="$IMAGE_REPOSITORY"
export IMAGE_NAME="$IMAGE_NAME"

# Save runtime state
save_runtime_state "$OPERATOR_DIR" "phase2-push-images" "success"

echo "===================================="
echo "Push Complete!"
echo "===================================="
echo
echo "Images pushed:"
echo "  - Operator: $OPERATOR_IMAGE"
echo "  - PKO Package: $PKO_IMAGE"
echo
echo "⚠️  IMPORTANT - Before Phase 3:"
echo "You need to set both images to PUBLIC in the Quay.io web UI:"
echo "  1. Visit: https://quay.io/repository/$IMAGE_REPOSITORY/$IMAGE_NAME"
echo "  2. Visit: https://quay.io/repository/$IMAGE_REPOSITORY/${IMAGE_NAME}-pko"
echo "  3. Click Settings → Make Public for each repository"
echo
echo "Once images are public, continue with:"
echo "  ./phase3-prepare-cluster.sh"
