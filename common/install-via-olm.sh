#!/bin/bash

# Install operator via simulated OLM deployment
# This creates OLM artifacts (Subscription, CSV, CatalogSource) + operator deployment
# Used for testing Mode 1 (PKO cleanup phases)

set -e

OPERATOR_DIR="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load configuration
source "$SCRIPT_DIR/load-config.sh"
load_config "$OPERATOR_DIR"

echo "===================================="
echo "Install Operator via Simulated OLM"
echo "===================================="
echo

# Determine operator repository path
OPERATOR_REPO_PATH=""
OPERATOR_NAME=""
if [ -n "$CAMO_REPO" ]; then
    OPERATOR_REPO_PATH="$CAMO_REPO"
    OPERATOR_NAME="configure-alertmanager-operator"
elif [ -n "$RMO_REPO" ]; then
    OPERATOR_REPO_PATH="$RMO_REPO"
    OPERATOR_NAME="route-monitor-operator"
elif [ -n "$OME_REPO" ]; then
    OPERATOR_REPO_PATH="$OME_REPO"
    OPERATOR_NAME="osd-metrics-exporter"
else
    echo "ERROR: No operator repository configured"
    echo "Set CAMO_REPO, RMO_REPO, or OME_REPO in user-config"
    exit 1
fi

if [ ! -d "$OPERATOR_REPO_PATH/deploy" ]; then
    echo "ERROR: Operator deploy directory not found: $OPERATOR_REPO_PATH/deploy"
    exit 1
fi

echo "Operator: $OPERATOR_NAME"
echo "Repository: $OPERATOR_REPO_PATH"
echo "Namespace: $OPERATOR_NAMESPACE"
echo "Image: $OPERATOR_IMAGE"
echo

echo "This will create:"
echo "  1. Mock OLM artifacts (Subscription, CSV, CatalogSource)"
echo "  2. Deploy operator from $OPERATOR_REPO_PATH/deploy/"
echo "  3. Patch operator image to use: $OPERATOR_IMAGE"
echo
read -p "Proceed with OLM installation? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "Aborted."
    exit 0
fi

echo
echo "===================================="
echo "Step 1: Create Mock CatalogSource"
echo "===================================="
echo

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ${OPERATOR_NAME}-registry
  namespace: $OPERATOR_NAMESPACE
spec:
  sourceType: grpc
  image: quay.io/openshift/origin-operator-registry:latest
  displayName: ${OPERATOR_NAME} Registry
  publisher: Test
  updateStrategy:
    registryPoll:
      interval: 10m
EOF

echo "✓ CatalogSource created"
echo

echo "===================================="
echo "Step 2: Create Mock Subscription"
echo "===================================="
echo

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: $OPERATOR_NAME
  namespace: $OPERATOR_NAMESPACE
spec:
  channel: stable
  name: $OPERATOR_NAME
  source: ${OPERATOR_NAME}-registry
  sourceNamespace: $OPERATOR_NAMESPACE
  installPlanApproval: Automatic
EOF

echo "✓ Subscription created"
echo

echo "===================================="
echo "Step 3: Deploy Operator Resources"
echo "===================================="
echo

# Deploy RBAC resources from operator repo
echo "Deploying RBAC resources..."
for manifest in "$OPERATOR_REPO_PATH/deploy"/*.yaml; do
    filename=$(basename "$manifest")

    # Skip operator deployment for now (will patch and deploy separately)
    if [[ "$filename" == *"operator.yaml" ]]; then
        continue
    fi

    echo "  Applying: $filename"
    oc apply -f "$manifest"
done

echo "✓ RBAC resources deployed"
echo

echo "===================================="
echo "Step 4: Deploy Operator with Custom Image"
echo "===================================="
echo

# Find operator deployment manifest
OPERATOR_MANIFEST=$(find "$OPERATOR_REPO_PATH/deploy" -name "*operator.yaml" -o -name "*deployment.yaml" | head -1)

if [ -z "$OPERATOR_MANIFEST" ]; then
    echo "ERROR: Operator deployment manifest not found in $OPERATOR_REPO_PATH/deploy/"
    exit 1
fi

echo "Patching operator image to: $OPERATOR_IMAGE"

# Extract deployment, patch image, and apply
oc apply -f "$OPERATOR_MANIFEST"
oc set image deployment/$OPERATOR_NAME \
    -n $OPERATOR_NAMESPACE \
    $OPERATOR_NAME=$OPERATOR_IMAGE

echo "✓ Operator deployment created with custom image"
echo

echo "Waiting for operator pod to start..."
sleep 5

echo
echo "===================================="
echo "Step 5: Create Mock CSV"
echo "===================================="
echo

# Get current deployment details for CSV
REPLICAS=$(oc get deployment $OPERATOR_NAME -n $OPERATOR_NAMESPACE -o jsonpath='{.spec.replicas}')
VERSION="v0.0.1-test"

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: ClusterServiceVersion
metadata:
  name: ${OPERATOR_NAME}.${VERSION}
  namespace: $OPERATOR_NAMESPACE
  annotations:
    olm.skipRange: ">=0.0.0 <999.0.0"
spec:
  displayName: ${OPERATOR_NAME}
  description: Test installation for PKO migration
  version: ${VERSION}
  replaces: ""
  provider:
    name: Test
  installModes:
  - type: OwnNamespace
    supported: true
  - type: SingleNamespace
    supported: true
  - type: MultiNamespace
    supported: false
  - type: AllNamespaces
    supported: false
  install:
    strategy: deployment
    spec:
      deployments:
      - name: $OPERATOR_NAME
        spec:
          replicas: $REPLICAS
          selector:
            matchLabels:
              name: $OPERATOR_NAME
EOF

echo "✓ CSV created"
echo

echo "===================================="
echo "OLM Installation Complete!"
echo "===================================="
echo

echo "Created resources:"
echo "  ✓ CatalogSource: ${OPERATOR_NAME}-registry"
echo "  ✓ Subscription: $OPERATOR_NAME"
echo "  ✓ CSV: ${OPERATOR_NAME}.${VERSION}"
echo "  ✓ Deployment: $OPERATOR_NAME (image: $OPERATOR_IMAGE)"
echo "  ✓ RBAC resources from operator repo"
echo

echo "Checking deployment status..."
oc get deployment $OPERATOR_NAME -n $OPERATOR_NAMESPACE

echo
echo "Next step: Run phase4-prepare-migration.sh and select Mode 1 (PKO cleanup)"
