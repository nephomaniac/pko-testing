#!/bin/bash

# Deploy operator via OLM using production images from quay.io
# This extracts resources from OLM templates and deploys with real registry images
# Used for testing actual OLM→PKO migrations with production-like deployments

set -e

OPERATOR_DIR="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load configuration
source "$SCRIPT_DIR/load-config.sh"
load_config "$OPERATOR_DIR"

echo "===================================="
echo "Deploy OLM from Quay.io Images"
echo "===================================="
echo

# Determine operator repository path and template
OPERATOR_REPO_PATH=""
OLM_TEMPLATE_PATH=""
OPERATOR_NAME_VAR=""

if [ -n "$CAMO_REPO" ]; then
    OPERATOR_REPO_PATH="$CAMO_REPO"
    OPERATOR_NAME_VAR="configure-alertmanager-operator"
    OLM_TEMPLATE_PATH="$CAMO_REPO/build/templates/olm-artifacts-template.yaml.tmpl"
elif [ -n "$RMO_REPO" ]; then
    OPERATOR_REPO_PATH="$RMO_REPO"
    OPERATOR_NAME_VAR="route-monitor-operator"
    OLM_TEMPLATE_PATH="$RMO_REPO/hack/olm-registry/olm-artifacts-template.yaml"
elif [ -n "$OME_REPO" ]; then
    OPERATOR_REPO_PATH="$OME_REPO"
    OPERATOR_NAME_VAR="osd-metrics-exporter"
    OLM_TEMPLATE_PATH="$OME_REPO/hack/olm-registry/olm-artifacts-template.yaml"
else
    echo "ERROR: No operator repository configured"
    echo "Set CAMO_REPO, RMO_REPO, or OME_REPO in user-config"
    exit 1
fi

if [ ! -f "$OLM_TEMPLATE_PATH" ]; then
    echo "ERROR: OLM template not found: $OLM_TEMPLATE_PATH"
    echo "Check OLM_TEMPLATE_PATH in operator-config"
    exit 1
fi

echo "Operator: $OPERATOR_NAME_VAR"
echo "Repository: $OPERATOR_REPO_PATH"
echo "Template: $OLM_TEMPLATE_PATH"
echo "Namespace: $OPERATOR_NAMESPACE"
echo

# Prompt for quay.io images if not configured
if [ -z "$OLM_REGISTRY_IMAGE" ]; then
    echo "Enter CatalogSource registry image (e.g., quay.io/app-sre/osd-metrics-exporter-registry@sha256:...):"
    read OLM_REGISTRY_IMAGE
fi

if [ -z "$OLM_OPERATOR_IMAGE" ]; then
    echo "Enter operator image (e.g., quay.io/app-sre/osd-metrics-exporter:v0.1.483-gf3edcbc):"
    read OLM_OPERATOR_IMAGE
fi

if [ -z "$OLM_CHANNEL" ]; then
    OLM_CHANNEL="staging"
    echo "Using default channel: $OLM_CHANNEL"
fi

echo
echo "Configuration:"
echo "  Registry Image: $OLM_REGISTRY_IMAGE"
echo "  Operator Image: $OLM_OPERATOR_IMAGE"
echo "  Channel: $OLM_CHANNEL"
echo "  Namespace: $OPERATOR_NAMESPACE"
echo

read -p "Proceed with OLM deployment? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "Aborted."
    exit 0
fi

echo
echo "===================================="
echo "Step 1: Extract OLM Resources"
echo "===================================="
echo

# Create temporary file for processed resources
TEMP_RESOURCES="/tmp/olm-resources-${OPERATOR_NAME_VAR}-$$.yaml"

echo "Extracting resources from template..."

# Read template and extract just the resources section (skip SelectorSyncSet wrapper)
# We need to find where the resources array starts and extract those items

python3 -c "
import yaml
import sys

# Read the template
with open('$OLM_TEMPLATE_PATH', 'r') as f:
    template = yaml.safe_load(f)

# Extract resources from SelectorSyncSet or directly from template
resources = []
if template.get('kind') == 'Template' and 'objects' in template:
    # Template with SelectorSyncSet wrapper
    for obj in template['objects']:
        if obj.get('kind') == 'SelectorSyncSet' and 'resources' in obj.get('spec', {}):
            resources = obj['spec']['resources']
            break
elif isinstance(template, list):
    # Already a list of resources
    resources = template
else:
    print('ERROR: Unexpected template format', file=sys.stderr)
    sys.exit(1)

if not resources:
    print('ERROR: No resources found in template', file=sys.stderr)
    sys.exit(1)

# Write resources as separate YAML documents
with open('$TEMP_RESOURCES', 'w') as f:
    for resource in resources:
        yaml.dump(resource, f)
        f.write('---\n')

print(f'Extracted {len(resources)} resources')
" || {
    echo "ERROR: Failed to extract resources from template"
    echo "Falling back to manual extraction..."
    
    # Fallback: use sed/awk to extract resources section
    # This is more fragile but doesn't require Python
    awk '/^  resources:/,0' "$OLM_TEMPLATE_PATH" | \
        grep -v "^  resources:" | \
        sed 's/^        //' > "$TEMP_RESOURCES"
}

echo "✓ Resources extracted to $TEMP_RESOURCES"
echo

echo "===================================="
echo "Step 2: Substitute Parameters"
echo "===================================="
echo

# Extract image digest from registry image if it contains @sha256:
if [[ "$OLM_REGISTRY_IMAGE" =~ @(sha256:[a-f0-9]+) ]]; then
    IMAGE_DIGEST="${BASH_REMATCH[1]}"
    REGISTRY_IMG="${OLM_REGISTRY_IMAGE%@*}"
else
    # No digest, use full image as-is
    IMAGE_DIGEST=""
    REGISTRY_IMG="$OLM_REGISTRY_IMAGE"
fi

# Extract image tag from operator image
if [[ "$OLM_OPERATOR_IMAGE" =~ :([^:]+)$ ]]; then
    IMAGE_TAG="${BASH_REMATCH[1]}"
else
    IMAGE_TAG="latest"
fi

echo "Parameters:"
echo "  REGISTRY_IMG: $REGISTRY_IMG"
echo "  IMAGE_DIGEST: $IMAGE_DIGEST"
echo "  IMAGE_TAG: $IMAGE_TAG"
echo "  CHANNEL: $OLM_CHANNEL"
echo "  REPO_NAME: $OPERATOR_NAME_VAR"
echo

# Substitute parameters in the extracted resources
PROCESSED_RESOURCES="/tmp/olm-processed-${OPERATOR_NAME_VAR}-$$.yaml"

# Use sed for parameter substitution
sed \
    -e "s|\${REGISTRY_IMG}@\${IMAGE_DIGEST}|$OLM_REGISTRY_IMAGE|g" \
    -e "s|\${REGISTRY_IMG}|$REGISTRY_IMG|g" \
    -e "s|\${IMAGE_DIGEST}|$IMAGE_DIGEST|g" \
    -e "s|\${IMAGE_TAG}|$IMAGE_TAG|g" \
    -e "s|\${CHANNEL}|$OLM_CHANNEL|g" \
    -e "s|\${REPO_NAME}|$OPERATOR_NAME_VAR|g" \
    "$TEMP_RESOURCES" > "$PROCESSED_RESOURCES"

echo "✓ Parameters substituted"
echo

echo "===================================="
echo "Step 3: Deploy OLM Resources"
echo "===================================="
echo

echo "Deploying resources to cluster..."
oc apply -f "$PROCESSED_RESOURCES"

echo
echo "✓ OLM resources deployed"
echo

echo "===================================="
echo "Step 4: Monitor Installation"
echo "===================================="
echo

echo "Waiting for CatalogSource to become ready..."
sleep 5

oc get catalogsource -n "$OPERATOR_NAMESPACE"
echo

echo "Waiting for Subscription to install operator..."
sleep 10

oc get subscription,csv -n "$OPERATOR_NAMESPACE"
echo

echo "Checking operator deployment..."
oc get deployment,pods -n "$OPERATOR_NAMESPACE" -l name="$OPERATOR_NAME_VAR" || \
    oc get deployment,pods -n "$OPERATOR_NAMESPACE"

echo
echo "===================================="
echo "OLM Deployment Complete!"
echo "===================================="
echo

echo "Resources created from: $OLM_TEMPLATE_PATH"
echo "Registry Image: $OLM_REGISTRY_IMAGE"
echo "Operator Image: $OLM_OPERATOR_IMAGE"
echo

echo "Check status:"
echo "  oc get csv -n $OPERATOR_NAMESPACE"
echo "  oc get subscription -n $OPERATOR_NAMESPACE"
echo "  oc get pods -n $OPERATOR_NAMESPACE"
echo

echo "Next step: Test OLM→PKO migration with phase4-prepare-migration.sh"
echo

# Cleanup temp files
rm -f "$TEMP_RESOURCES" "$PROCESSED_RESOURCES"
