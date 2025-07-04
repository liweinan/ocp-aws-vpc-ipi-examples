#!/bin/bash

# Manual verification script for pull+push process
# This script tests the image sync workflow step by step

set -e

echo "=== Manual Pull+Push Verification Script ==="
echo "Testing image sync from CI registry to local registry"
echo

# Configuration
CI_REGISTRY="registry.ci.openshift.org"
LOCAL_REGISTRY="localhost:5000"
OCP_VERSION="4.19.2"
TEST_IMAGE="cli"  # Start with a simple image

echo "Configuration:"
echo "  CI Registry: $CI_REGISTRY"
echo "  Local Registry: $LOCAL_REGISTRY"
echo "  OCP Version: $OCP_VERSION"
echo "  Test Image: $TEST_IMAGE"
echo

# Check if we're on the bastion host
if [ ! -f /home/ubuntu/.ci-token ]; then
    echo "ERROR: This script should run on the bastion host"
    echo "Please copy to bastion host and run there"
    exit 1
fi

# Load CI token
CI_TOKEN=$(cat /home/ubuntu/.ci-token)
if [ -z "$CI_TOKEN" ]; then
    echo "ERROR: CI token not found or empty"
    exit 1
fi

echo "Step 1: Check registry connectivity"
echo "----------------------------------------"
echo "Testing CI registry connectivity..."
curl -s -k "https://$CI_REGISTRY/v2/" > /dev/null && echo "✓ CI registry accessible" || echo "✗ CI registry not accessible"

echo "Testing local registry connectivity..."
curl -s -k "https://$LOCAL_REGISTRY/v2/" > /dev/null && echo "✓ Local registry accessible" || echo "✗ Local registry not accessible"

echo
echo "Step 2: Login to registries"
echo "----------------------------------------"
echo "Logging into CI registry..."
echo "$CI_TOKEN" | podman login --username="weli" --password-stdin "$CI_REGISTRY"

echo "Logging into local registry..."
echo "admin123" | podman login --username="admin" --password-stdin "$LOCAL_REGISTRY" --tls-verify=false

echo
echo "Step 3: Test image pull"
echo "----------------------------------------"
SOURCE_IMAGE="$CI_REGISTRY/ocp/$OCP_VERSION:$TEST_IMAGE"
echo "Pulling test image: $SOURCE_IMAGE"

# Clean up any existing image first
podman rmi "$SOURCE_IMAGE" 2>/dev/null || true

# Pull the image
if podman pull "$SOURCE_IMAGE"; then
    echo "✓ Successfully pulled $SOURCE_IMAGE"
else
    echo "✗ Failed to pull $SOURCE_IMAGE"
    exit 1
fi

echo
echo "Step 4: Test image push"
echo "----------------------------------------"
TARGET_IMAGE="$LOCAL_REGISTRY/openshift/$TEST_IMAGE:latest"
echo "Tagging image for local registry: $TARGET_IMAGE"

if podman tag "$SOURCE_IMAGE" "$TARGET_IMAGE"; then
    echo "✓ Successfully tagged image"
else
    echo "✗ Failed to tag image"
    exit 1
fi

echo "Pushing to local registry..."
if podman push "$TARGET_IMAGE" --tls-verify=false; then
    echo "✓ Successfully pushed $TARGET_IMAGE"
else
    echo "✗ Failed to push $TARGET_IMAGE"
    exit 1
fi

echo
echo "Step 5: Verify push success"
echo "----------------------------------------"
echo "Checking local registry catalog..."
curl -s -k "https://$LOCAL_REGISTRY/v2/_catalog" | jq '.' || curl -s -k "https://$LOCAL_REGISTRY/v2/_catalog"

echo
echo "Checking specific repository tags..."
curl -s -k "https://$LOCAL_REGISTRY/v2/openshift/$TEST_IMAGE/tags/list" | jq '.' || curl -s -k "https://$LOCAL_REGISTRY/v2/openshift/$TEST_IMAGE/tags/list"

echo
echo "Step 6: Clean up test images"
echo "----------------------------------------"
echo "Removing local images to save space..."
podman rmi "$SOURCE_IMAGE" "$TARGET_IMAGE" 2>/dev/null || true

echo
echo "=== Verification Complete ==="
echo "If all steps showed ✓, the pull+push process is working correctly!"
echo 