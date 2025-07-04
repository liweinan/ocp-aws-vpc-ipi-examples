#!/bin/bash

# Single Image Synchronization Script
# This script handles pull+push of a single image from CI registry to local registry

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

# Ensure registry login (critical fix from successful experience)
echo "   🔐 Ensuring registry login..."
CI_TOKEN=$(oc whoami -t)
podman login -u="weli" -p="${CI_TOKEN}" "${CI_REGISTRY}"
podman login --username "${REGISTRY_USER}" --password "${REGISTRY_PASSWORD}" --tls-verify=false "localhost:${REGISTRY_PORT}"

# Clean up any existing local copy
podman rmi "$SOURCE_IMAGE" 2>/dev/null || true

# Pull image with retry
PULL_ATTEMPTS=0
MAX_PULL_ATTEMPTS=3
while [[ $PULL_ATTEMPTS -lt $MAX_PULL_ATTEMPTS ]]; do
    ((PULL_ATTEMPTS++))
    echo "   🔄 Pull attempt ${PULL_ATTEMPTS}/${MAX_PULL_ATTEMPTS}..."
    
    if timeout 600 podman pull "$SOURCE_IMAGE" --platform linux/amd64; then
        echo -e "${GREEN}   ✅ Pulled ${SOURCE_IMAGE}${NC}"
        break
    else
        echo "   ⚠️  Pull attempt ${PULL_ATTEMPTS} failed"
        if [[ $PULL_ATTEMPTS -eq $MAX_PULL_ATTEMPTS ]]; then
            echo -e "${RED}   ❌ Failed to pull after ${MAX_PULL_ATTEMPTS} attempts${NC}"
            exit 1
        fi
        sleep 5
    fi
done

# Tag for local registry (both versioned and latest)
echo "   🏷️  Tagging images..."
podman tag "$SOURCE_IMAGE" "$LOCAL_IMAGE"
podman tag "$SOURCE_IMAGE" "$LOCAL_IMAGE_LATEST"

# Push to local registry with retry
PUSH_ATTEMPTS=0
MAX_PUSH_ATTEMPTS=3
while [[ $PUSH_ATTEMPTS -lt $MAX_PUSH_ATTEMPTS ]]; do
    ((PUSH_ATTEMPTS++))
    echo "   🔄 Push attempt ${PUSH_ATTEMPTS}/${MAX_PUSH_ATTEMPTS}..."
    
    if timeout 600 podman push "$LOCAL_IMAGE" --tls-verify=false && \
       timeout 600 podman push "$LOCAL_IMAGE_LATEST" --tls-verify=false; then
        echo -e "${GREEN}   ✅ Synced ${LOCAL_IMAGE} and :latest${NC}"
        
        # Clean up local copy to save space
        podman rmi "$SOURCE_IMAGE" "$LOCAL_IMAGE" "$LOCAL_IMAGE_LATEST" 2>/dev/null || true
        
        # Check disk space and cleanup if needed
        AVAILABLE_SPACE=$(df /home | tail -1 | awk '{print $4}')
        AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
        if [[ $AVAILABLE_GB -lt 5 ]]; then
            echo -e "${YELLOW}   ⚠️  Low disk space (${AVAILABLE_GB}GB), cleaning up...${NC}"
            podman system prune -f
        fi
        
        echo -e "${GREEN}   ✅ Successfully synced ${IMAGE_NAME}${NC}"
        exit 0
    else
        echo "   ⚠️  Push attempt ${PUSH_ATTEMPTS} failed"
        if [[ $PUSH_ATTEMPTS -eq $MAX_PUSH_ATTEMPTS ]]; then
            echo -e "${RED}   ❌ Failed to push after ${MAX_PUSH_ATTEMPTS} attempts${NC}"
            exit 1
        fi
        sleep 5
    fi
done

echo -e "${RED}❌ Failed to sync ${IMAGE_NAME}${NC}"
exit 1 