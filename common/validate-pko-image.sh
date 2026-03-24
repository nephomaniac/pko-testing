#!/bin/bash

# Validate PKO Image
# This script validates that a given image is a valid PKO package

validate_pko_image() {
    local image_uri="$1"
    local image_type="${2:-pko}"  # 'operator' or 'pko'

    echo "Validating $image_type image: $image_uri"

    # Check if image exists
    if ! podman pull "$image_uri" &>/dev/null && ! docker pull "$image_uri" &>/dev/null; then
        echo "❌ ERROR: Cannot pull image: $image_uri"
        echo "   Image may not exist or you may lack permissions"
        return 1
    fi

    # For PKO images, check if it's a valid PKO package
    if [ "$image_type" = "pko" ]; then
        echo "Checking if image is a valid PKO package..."

        # PKO packages should contain /package/manifest.yaml
        local container_engine
        if command -v podman &>/dev/null; then
            container_engine=podman
        elif command -v docker &>/dev/null; then
            container_engine=docker
        else
            echo "❌ ERROR: Neither podman nor docker found"
            return 1
        fi

        # Create temporary container and check for PKO package structure
        local temp_container
        temp_container=$($container_engine create "$image_uri" 2>/dev/null)

        if [ -z "$temp_container" ]; then
            echo "❌ ERROR: Failed to create container from image"
            return 1
        fi

        # Check for manifest.yaml
        if ! $container_engine export "$temp_container" | tar -t 2>/dev/null | grep -q "^package/manifest.yaml"; then
            echo "❌ ERROR: Not a valid PKO package (missing package/manifest.yaml)"
            $container_engine rm "$temp_container" &>/dev/null
            return 1
        fi

        # Extract and validate manifest.yaml
        local manifest
        manifest=$($container_engine export "$temp_container" | tar -xO package/manifest.yaml 2>/dev/null)

        if [ -z "$manifest" ]; then
            echo "❌ ERROR: Cannot extract package/manifest.yaml"
            $container_engine rm "$temp_container" &>/dev/null
            return 1
        fi

        # Check if it's a PackageManifest
        if ! echo "$manifest" | grep -q "kind: PackageManifest"; then
            echo "❌ ERROR: manifest.yaml is not a PackageManifest"
            $container_engine rm "$temp_container" &>/dev/null
            return 1
        fi

        # Cleanup
        $container_engine rm "$temp_container" &>/dev/null

        echo "✓ Valid PKO package image"
        echo "  - Contains package/manifest.yaml"
        echo "  - Manifest is valid PackageManifest"
    else
        # For operator images, just verify it exists (already pulled above)
        echo "✓ Valid operator image (exists and is pullable)"
    fi

    return 0
}

# If script is executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <image-uri> [image-type]"
        echo
        echo "Arguments:"
        echo "  image-uri    Full image URI (e.g., quay.io/org/image:tag)"
        echo "  image-type   'operator' or 'pko' (default: pko)"
        echo
        echo "Examples:"
        echo "  $0 quay.io/openshift/configure-alertmanager-operator-pko:v0.1.123"
        echo "  $0 quay.io/openshift/configure-alertmanager-operator:v0.1.123 operator"
        exit 1
    fi

    validate_pko_image "$1" "${2:-pko}"
    exit $?
fi
