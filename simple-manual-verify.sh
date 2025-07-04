#!/bin/bash

# Simple manual verification for pull+push process
# Run this on bastion host after oc login

set -e

echo "=== Simple Manual Pull+Push Verification ==="
echo

# Configuration
CI_REGISTRY="registry.ci.openshift.org"
LOCAL_REGISTRY="localhost:5000"
OCP_VERSION="4.19.2"
TEST_IMAGE="cli"

echo "Configuration:"
echo "  CI Registry: $CI_REGISTRY"
echo "  Local Registry: $LOCAL_REGISTRY" 
echo "  Test Image: $TEST_IMAGE"
echo

echo "Step 1: Check current oc login status"
echo "----------------------------------------"
oc whoami && echo "✓ Logged into CI cluster" || echo "✗ Not logged into CI cluster"

echo
echo "Step 2: Get CI registry token from oc"
echo "----------------------------------------"
CI_TOKEN=$(oc whoami -t)
if [ -n "$CI_TOKEN" ]; then
    echo "✓ Got CI token from oc login"
else
    echo "✗ Failed to get CI token"
    exit 1
fi

echo
echo "Step 3: Login to registries with podman"
echo "----------------------------------------"
echo "Logging into CI registry..."
echo "$CI_TOKEN" | podman login --username="weli" --password-stdin "$CI_REGISTRY"

echo "Logging into local registry..."
echo "admin123" | podman login --username="admin" --password-stdin "$LOCAL_REGISTRY" --tls-verify=false

echo
echo "Step 4: Test pull from CI registry"
echo "----------------------------------------"
SOURCE_IMAGE="$CI_REGISTRY/ocp/$OCP_VERSION:$TEST_IMAGE"
echo "Pulling: $SOURCE_IMAGE"

# Clean existing image
podman rmi "$SOURCE_IMAGE" 2>/dev/null || true

if podman pull "$SOURCE_IMAGE"; then
    echo "✓ Successfully pulled $SOURCE_IMAGE"
    podman images | grep "$TEST_IMAGE"
else
    echo "✗ Failed to pull $SOURCE_IMAGE"
    exit 1
fi

echo
echo "Step 5: Test push to local registry"
echo "----------------------------------------"
TARGET_IMAGE="$LOCAL_REGISTRY/openshift/$TEST_IMAGE:latest"
echo "Tagging as: $TARGET_IMAGE"

podman tag "$SOURCE_IMAGE" "$TARGET_IMAGE"
echo "✓ Tagged image"

echo "Pushing to local registry..."
if podman push "$TARGET_IMAGE" --tls-verify=false; then
    echo "✓ Successfully pushed $TARGET_IMAGE"
else
    echo "✗ Failed to push $TARGET_IMAGE"
    exit 1
fi

echo
echo "Step 6: Verify in local registry"
echo "----------------------------------------"
echo "Registry catalog:"
curl -s -k "https://$LOCAL_REGISTRY/v2/_catalog" | jq '.' 2>/dev/null || curl -s -k "https://$LOCAL_REGISTRY/v2/_catalog"

echo
echo "Repository tags:"
curl -s -k "https://$LOCAL_REGISTRY/v2/openshift/$TEST_IMAGE/tags/list" | jq '.' 2>/dev/null || curl -s -k "https://$LOCAL_REGISTRY/v2/openshift/$TEST_IMAGE/tags/list"

echo
echo "=== Manual Verification Complete ==="
echo "✓ Pull+Push process is working!"
echo
echo "To test more images, you can run:"
echo "  podman pull registry.ci.openshift.org/ocp/4.19.2:installer"
echo "  podman tag registry.ci.openshift.org/ocp/4.19.2:installer localhost:5000/openshift/installer:latest"
echo "  podman push localhost:5000/openshift/installer:latest --tls-verify=false"
echo 