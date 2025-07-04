#!/bin/bash

# Single Image Synchronization Script
# This script handles pull+push of a single image from CI registry to local registry
# Simplified to match manual operation logic

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 <image-name> <openshift-version> <registry-port> <registry-user> <registry-password>"
    echo "Example: $0 cli 4.19.2 5000 admin admin123"
    exit 1
}

# Check arguments
if [[ $# -ne 5 ]]; then
    usage
fi

IMAGE_NAME="$1"
OPENSHIFT_VERSION="$2"
REGISTRY_PORT="$3"
REGISTRY_USER="$4"
REGISTRY_PASSWORD="$5"

# Configuration
CI_REGISTRY="registry.ci.openshift.org"
REGISTRY_URL="localhost:${REGISTRY_PORT}"
SOURCE_IMAGE="${CI_REGISTRY}/ocp/${OPENSHIFT_VERSION}:${IMAGE_NAME}"
LOCAL_IMAGE="${REGISTRY_URL}/openshift/${IMAGE_NAME}:${OPENSHIFT_VERSION}"
LOCAL_IMAGE_LATEST="${REGISTRY_URL}/openshift/${IMAGE_NAME}:latest"

echo -e "${BLUE}🔄 Syncing image: ${IMAGE_NAME}${NC}"
echo "   Source: ${SOURCE_IMAGE}"
echo "   Target: ${LOCAL_IMAGE}"

# Check if image already exists in local registry
if curl -k -s -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" "https://localhost:${REGISTRY_PORT}/v2/openshift/${IMAGE_NAME}/tags/list" 2>/dev/null | grep -q "${OPENSHIFT_VERSION}"; then
    echo -e "${YELLOW}   ⏭️  Already exists, skipping${NC}"
    exit 0
fi

# Simple registry login (like manual operation)
echo "   🔐 Logging into registries..."
CI_TOKEN=$(oc whoami -t)
sudo -E podman login -u="weli" -p="${CI_TOKEN}" "${CI_REGISTRY}"
sudo -E podman login --username "${REGISTRY_USER}" --password "${REGISTRY_PASSWORD}" --tls-verify=false "localhost:${REGISTRY_PORT}"

# Pull image (exactly like manual operation)
echo "   📥 Pulling image..."
sudo -E podman pull "$SOURCE_IMAGE" --platform linux/amd64

# Tag for local registry
echo "   🏷️  Tagging images..."
sudo -E podman tag "$SOURCE_IMAGE" "$LOCAL_IMAGE"
sudo -E podman tag "$SOURCE_IMAGE" "$LOCAL_IMAGE_LATEST"

# Push to local registry (exactly like manual operation)
echo "   📤 Pushing images..."
sudo -E podman push "$LOCAL_IMAGE" --tls-verify=false
sudo -E podman push "$LOCAL_IMAGE_LATEST" --tls-verify=false

# Clean up local copy to save space
echo "   🧹 Cleaning up local images..."
sudo -E podman rmi "$SOURCE_IMAGE" "$LOCAL_IMAGE" "$LOCAL_IMAGE_LATEST" 2>/dev/null || true

echo -e "${GREEN}   ✅ Successfully synced ${IMAGE_NAME}${NC}" 