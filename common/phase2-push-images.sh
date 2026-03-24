#!/bin/bash
set -e

# Phase 2: Push CAMO PKO Images to Quay
# This script pushes both images to your personal Quay repository

echo "===================================="
echo "Phase 2: Push Images to Quay"
echo "===================================="
echo

# Load configuration from phase 1
CONFIG_FILE="$(cd "$(dirname "$0")" && pwd)/.camo-pko-test-config"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    echo "Please run phase1-build-images.sh first"
    exit 1
fi

source "$CONFIG_FILE"

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

read -p "Push images to Quay.io? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "Aborted."
    exit 0
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
