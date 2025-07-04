#!/bin/bash

# Single Image Sync Script for OpenShift Disconnected Cluster
# This script syncs a single image from CI registry to local mirror registry

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parameters
IMAGE_NAME="$1"
IMAGE_TAG="$2"
REGISTRY_PORT="$3"
REGISTRY_USER="$4"
REGISTRY_PASSWORD="$5"

# Configuration
CI_REGISTRY="registry.ci.openshift.org"
LOCAL_REGISTRY="localhost:${REGISTRY_PORT}"
OPENSHIFT_VERSION="4.19.2"


# Function to sync image using podman
sync_image_with_podman() {
    local src_image="$1"
    local dst_image="$2"
    
    echo -e "${BLUE}   📥 Syncing with podman: ${src_image} -> ${dst_image}${NC}"
    
    # Pull image from source
    if sudo -E podman pull "${src_image}"; then
        # Tag image for local registry
        if sudo -E podman tag "${src_image}" "${dst_image}"; then
            # Push to local registry
            if sudo -E podman push "${dst_image}" --tls-verify=false; then
                # Clean up local image
                sudo -E podman rmi "${src_image}" "${dst_image}" &> /dev/null || true
                return 0
            fi
        fi
    fi
    
    # Clean up on failure
    sudo -E podman rmi "${src_image}" "${dst_image}" &> /dev/null || true
    return 1
}

# Main sync function
sync_image() {
    local image_name="$1"
    local image_tag="$2"
    
    # Determine source image path
    local src_image
    if [[ "$image_name" == */* ]]; then
        # Image name contains path (e.g., origin/release, ocp/release)
        src_image="${CI_REGISTRY}/${image_name}:${image_tag}"
    else
        # Standard OpenShift image
        src_image="${CI_REGISTRY}/openshift/${image_name}:${image_tag}"
    fi
    
    # Determine destination image path - always store under openshift/ namespace
    local dst_image="${LOCAL_REGISTRY}/openshift/${image_name}:${image_tag}"
    
    echo -e "${BLUE}🔄 Syncing image: ${image_name}:${image_tag}${NC}"
    echo "   Source: ${src_image}"
    echo "   Destination: ${dst_image}"
    
    # Use podman for image sync
    if sync_image_with_podman "$src_image" "$dst_image"; then
        echo -e "${GREEN}   ✅ Successfully synced with podman${NC}"
        return 0
    else
        echo -e "${RED}   ❌ Failed to sync with podman${NC}"
        return 1
    fi
}

# Validate parameters
if [[ $# -ne 5 ]]; then
    echo -e "${RED}❌ Usage: $0 <image_name> <image_tag> <registry_port> <registry_user> <registry_password>${NC}"
    exit 1
fi

# Check if required tools are available
if ! command -v podman &> /dev/null; then
    echo -e "${RED}❌ Podman is not available${NC}"
    exit 1
fi

# Perform the sync
sync_image "$IMAGE_NAME" "$IMAGE_TAG" 