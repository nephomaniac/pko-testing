#!/bin/bash
set -e

# Phase 1: Build CAMO PKO Images Locally
# This script builds both the operator image and PKO package image

# Parse command-line arguments
QUAY_USERNAME=""
AUTO_CONFIRM=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --quay-username)
            QUAY_USERNAME="$2"
            shift 2
            ;;
        --auto-confirm)
            AUTO_CONFIRM=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--quay-username <username>] [--auto-confirm]"
            exit 1
            ;;
    esac
done

echo "===================================="
echo "Phase 1: Build CAMO PKO Images"
echo "===================================="
echo

# Script runs from operator directory (camo/, rmo/, etc.)
OPERATOR_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load configuration (if it exists)
if [ -f "$OPERATOR_DIR/config/user-config" ]; then
    source "$SCRIPT_DIR/load-config.sh"
    load_config "$OPERATOR_DIR"
fi

# Check if CAMO_REPO is set and valid
if [ -z "$CAMO_REPO" ] || [ ! -d "$CAMO_REPO" ]; then
    echo "CAMO repository path not found or invalid."
    echo
    read -p "Enter path to CAMO repository: " CAMO_REPO_INPUT

    if [ -z "$CAMO_REPO_INPUT" ]; then
        echo "ERROR: CAMO repository path is required"
        exit 1
    fi

    # Expand ~ to home directory
    CAMO_REPO_INPUT="${CAMO_REPO_INPUT/#\~/$HOME}"

    if [ ! -d "$CAMO_REPO_INPUT" ]; then
        echo "ERROR: Directory does not exist: $CAMO_REPO_INPUT"
        exit 1
    fi

    CAMO_REPO="$CAMO_REPO_INPUT"

    # Save to user-config
    USER_CONFIG="$OPERATOR_DIR/config/user-config"
    if [ -f "$USER_CONFIG" ]; then
        # Update existing config
        if grep -q "^CAMO_REPO=" "$USER_CONFIG"; then
            # Update existing line (macOS compatible)
            sed -i '' "s|^CAMO_REPO=.*|CAMO_REPO=$CAMO_REPO|" "$USER_CONFIG"
        else
            # Add new line
            echo "CAMO_REPO=$CAMO_REPO" >> "$USER_CONFIG"
        fi
        echo "✓ Saved CAMO_REPO to config: $USER_CONFIG"
    fi
fi

cd "$CAMO_REPO"
echo "Working directory: $(pwd)"
echo

# Prompt for Quay username if not provided
if [ -z "$QUAY_USERNAME" ]; then
    read -p "Enter your Quay.io username: " QUAY_USERNAME
    if [ -z "$QUAY_USERNAME" ]; then
        echo "ERROR: Quay username is required"
        exit 1
    fi
fi

# Set image variables
export IMAGE_REGISTRY="quay.io"
export IMAGE_REPOSITORY="$QUAY_USERNAME"
export IMAGE_NAME="configure-alertmanager-operator"

# Get git commit info for versioning
CURRENT_COMMIT=$(git rev-parse --short=7 HEAD)
IMAGE_TAG="test-${CURRENT_COMMIT}"

echo "Image Configuration:"
echo "  Registry: $IMAGE_REGISTRY"
echo "  Repository: $IMAGE_REPOSITORY"
echo "  Operator Image: $IMAGE_REGISTRY/$IMAGE_REPOSITORY/$IMAGE_NAME:$IMAGE_TAG"
echo "  PKO Package Image: $IMAGE_REGISTRY/$IMAGE_REPOSITORY/${IMAGE_NAME}-pko:$IMAGE_TAG"
echo

if [ "$AUTO_CONFIRM" = false ]; then
    read -p "Continue with these settings? (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ]; then
        echo "Aborted."
        exit 0
    fi
fi

echo
echo "===================================="
echo "Step 1.1: Building Operator Image"
echo "===================================="
echo "Command: GOOS=linux GOARCH=amd64 ALLOW_DIRTY_CHECKOUT=true IMAGE_REPOSITORY=$IMAGE_REPOSITORY CONTAINER_ENGINE=podman make docker-build"
echo

GOOS=linux GOARCH=amd64 ALLOW_DIRTY_CHECKOUT=true \
  IMAGE_REPOSITORY="$IMAGE_REPOSITORY" \
  CONTAINER_ENGINE=podman \
  make docker-build

if [ $? -ne 0 ]; then
    echo "ERROR: Operator image build failed"
    exit 1
fi

# Get the actual image name that was built (it includes version)
BUILT_IMAGE=$(podman images --format "{{.Repository}}:{{.Tag}}" | grep "$IMAGE_REPOSITORY/$IMAGE_NAME" | grep -v "pko" | head -1)
echo
echo "Built operator image: $BUILT_IMAGE"

# Tag it with our test tag
echo "Tagging as: $IMAGE_REGISTRY/$IMAGE_REPOSITORY/$IMAGE_NAME:$IMAGE_TAG"
podman tag "$BUILT_IMAGE" "$IMAGE_REGISTRY/$IMAGE_REPOSITORY/$IMAGE_NAME:$IMAGE_TAG"

echo
echo "===================================="
echo "Step 1.2: Building PKO Package Image"
echo "===================================="
echo

# Check that deploy_pko directory exists
if [ ! -d "deploy_pko" ]; then
    echo "ERROR: deploy_pko directory not found. Run 'make pko-migrate' first."
    exit 1
fi

echo "Building PKO package from deploy_pko/ directory..."
echo "Command: podman build -f build/Dockerfile.pko -t $IMAGE_REGISTRY/$IMAGE_REPOSITORY/${IMAGE_NAME}-pko:$IMAGE_TAG ./deploy_pko/"
echo

podman build \
  -f build/Dockerfile.pko \
  -t "$IMAGE_REGISTRY/$IMAGE_REPOSITORY/${IMAGE_NAME}-pko:$IMAGE_TAG" \
  ./deploy_pko/

if [ $? -ne 0 ]; then
    echo "ERROR: PKO package image build failed"
    exit 1
fi

echo
echo "===================================="
echo "Build Complete!"
echo "===================================="
echo
echo "Images built:"
echo "  Operator: $IMAGE_REGISTRY/$IMAGE_REPOSITORY/$IMAGE_NAME:$IMAGE_TAG"
echo "  PKO Package: $IMAGE_REGISTRY/$IMAGE_REPOSITORY/${IMAGE_NAME}-pko:$IMAGE_TAG"
echo
echo "Verify images:"
echo "  podman images | grep $IMAGE_REPOSITORY"
echo
echo "Next step: Run phase2-push-images.sh"
echo

# Return to operator directory
cd "$OPERATOR_DIR"

# Update user-config with built image information
USER_CONFIG="$OPERATOR_DIR/config/user-config"
if [ -f "$USER_CONFIG" ]; then
    # Update or add OPERATOR_IMAGE
    if grep -q "^OPERATOR_IMAGE=" "$USER_CONFIG"; then
        sed -i '' "s|^OPERATOR_IMAGE=.*|OPERATOR_IMAGE=$IMAGE_REGISTRY/$IMAGE_REPOSITORY/$IMAGE_NAME:$IMAGE_TAG|" "$USER_CONFIG"
    else
        echo "OPERATOR_IMAGE=$IMAGE_REGISTRY/$IMAGE_REPOSITORY/$IMAGE_NAME:$IMAGE_TAG" >> "$USER_CONFIG"
    fi

    # Update or add PKO_IMAGE
    if grep -q "^PKO_IMAGE=" "$USER_CONFIG"; then
        sed -i '' "s|^PKO_IMAGE=.*|PKO_IMAGE=$IMAGE_REGISTRY/$IMAGE_REPOSITORY/${IMAGE_NAME}-pko:$IMAGE_TAG|" "$USER_CONFIG"
    else
        echo "PKO_IMAGE=$IMAGE_REGISTRY/$IMAGE_REPOSITORY/${IMAGE_NAME}-pko:$IMAGE_TAG" >> "$USER_CONFIG"
    fi

    echo "✓ Updated image references in $USER_CONFIG"
fi

# Save runtime state
source "$SCRIPT_DIR/load-config.sh"
save_runtime_state "$OPERATOR_DIR" "phase1-build-images" "success" \
    "OPERATOR_IMAGE=$IMAGE_REGISTRY/$IMAGE_REPOSITORY/$IMAGE_NAME:$IMAGE_TAG" \
    "PKO_IMAGE=$IMAGE_REGISTRY/$IMAGE_REPOSITORY/${IMAGE_NAME}-pko:$IMAGE_TAG"

echo
echo "Configuration saved to runtime state"
echo

# Source shared cluster verification functions
source "$SCRIPT_DIR/cluster-verification.sh"

# Check cluster connection (informational only)
echo "===================================="
echo "Cluster Connection Status"
echo "===================================="
echo

if oc whoami &>/dev/null; then
    CURRENT_SERVER=$(oc whoami --show-server)
    CURRENT_USER=$(oc whoami)

    echo "✓ Connected to cluster:"
    echo "  Server: $CURRENT_SERVER"
    echo "  User: $CURRENT_USER"
    echo

    if [ -n "$CLUSTER_ID" ]; then
        echo "Target cluster from config: $CLUSTER_ID"
        if [ -n "$CLUSTER_SERVER" ] && [ "$CURRENT_SERVER" != "$CLUSTER_SERVER" ]; then
            echo "⚠️  Warning: Connected to different server than configured"
            echo "  Configured: $CLUSTER_SERVER"
            echo "  Current: $CURRENT_SERVER"
        fi
    fi
else
    echo "⚠️  Not currently logged into any OpenShift cluster."
    echo
    echo "Images built successfully, but you'll need to login to your"
    echo "test cluster before running deployment phases (phase 3+)."
fi
