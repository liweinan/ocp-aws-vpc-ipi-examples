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

# Function to sync image using skopeo
sync_image_with_skopeo() {
    local src_image="$1"
    local dst_image="$2"
    
    echo -e "${BLUE}   📥 Syncing with skopeo: ${src_image} -> ${dst_image}${NC}"
    
    # Create auth file for local registry
    local auth_file="/tmp/auth-${RANDOM}.json"
    echo "{\"auths\":{\"${LOCAL_REGISTRY}\":{\"auth\":\"$(echo -n ${REGISTRY_USER}:${REGISTRY_PASSWORD} | base64)\"}}}" > "$auth_file"
    
    # Use skopeo to copy the image
    if sudo -E skopeo copy \
        --tls-verify=false \
        --dest-tls-verify=false \
        --dest-authfile "$auth_file" \
        "docker://${src_image}" \
        "docker://${dst_image}"; then
        rm -f "$auth_file"
        return 0
    else
        rm -f "$auth_file"
        return 1
    fi
}

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
        # Image name contains path (e.g., origin/release)
        src_image="${CI_REGISTRY}/${image_name}:${image_tag}"
    else
        # Standard OpenShift image
        src_image="${CI_REGISTRY}/openshift/${image_name}:${image_tag}"
    fi
    
    # Determine destination image path
    local dst_image="${LOCAL_REGISTRY}/openshift/${image_name}:${image_tag}"
    
    echo -e "${BLUE}🔄 Syncing image: ${image_name}:${image_tag}${NC}"
    echo "   Source: ${src_image}"
    echo "   Destination: ${dst_image}"
    
    # Try skopeo first, then podman as fallback
    if command -v skopeo &> /dev/null; then
        if sync_image_with_skopeo "$src_image" "$dst_image"; then
            echo -e "${GREEN}   ✅ Successfully synced with skopeo${NC}"
            return 0
        else
            echo -e "${YELLOW}   ⚠️  Skopeo sync failed, trying podman...${NC}"
        fi
    fi
    
    if sync_image_with_podman "$src_image" "$dst_image"; then
        echo -e "${GREEN}   ✅ Successfully synced with podman${NC}"
        return 0
    else
        echo -e "${RED}   ❌ Failed to sync with both skopeo and podman${NC}"
        return 1
    fi
}

# Validate parameters
if [[ $# -ne 5 ]]; then
    echo -e "${RED}❌ Usage: $0 <image_name> <image_tag> <registry_port> <registry_user> <registry_password>${NC}"
    exit 1
fi

# Check if required tools are available
if ! command -v skopeo &> /dev/null && ! command -v podman &> /dev/null; then
    echo -e "${RED}❌ Neither skopeo nor podman is available${NC}"
    exit 1
fi

# Perform the sync
sync_image "$IMAGE_NAME" "$IMAGE_TAG" 