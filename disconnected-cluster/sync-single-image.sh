#!/bin/bash

# Single Image Synchronization Script for Disconnected OpenShift Cluster
# This script syncs a single image from OpenShift CI cluster to local mirror registry

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 <image_name> <image_tag> <registry_port> <registry_user> <registry_password>"
    echo ""
    echo "Example:"
    echo "  $0 cli 4.19.2 5000 admin admin123"
    echo ""
    echo "This script will:"
    echo "  1. Pull image from registry.ci.openshift.org/openshift/<image_name>:<image_tag>"
    echo "  2. Tag it for local registry"
    echo "  3. Push to local registry at localhost:<registry_port>"
    exit 1
}

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check arguments
if [[ $# -ne 5 ]]; then
    print_error "Invalid number of arguments"
    usage
fi

IMAGE_NAME="$1"
IMAGE_TAG="$2"
REGISTRY_PORT="$3"
REGISTRY_USER="$4"
REGISTRY_PASSWORD="$5"

# Validate inputs
if [[ -z "$IMAGE_NAME" || -z "$IMAGE_TAG" || -z "$REGISTRY_PORT" || -z "$REGISTRY_USER" || -z "$REGISTRY_PASSWORD" ]]; then
    print_error "All arguments must be non-empty"
    usage
fi

# Check if podman is available
if ! command -v podman &> /dev/null; then
    print_error "podman is not installed or not in PATH"
    exit 1
fi

# Check if we're logged into CI cluster
if ! oc whoami &> /dev/null; then
    print_error "Not logged into OpenShift CI cluster"
    echo "Please login first:"
    echo "  oc login --token=<YOUR_TOKEN> --server=https://api.ci.l2s4.p1.openshiftapps.com:6443 --insecure-skip-tls-verify=true"
    exit 1
fi

print_info "🔄 Syncing image: openshift/${IMAGE_NAME}:${IMAGE_TAG}"
print_info "   Source: registry.ci.openshift.org/openshift/${IMAGE_NAME}:${IMAGE_TAG}"
print_info "   Target: localhost:${REGISTRY_PORT}/openshift/${IMAGE_NAME}:${IMAGE_TAG}"

# Step 1: Pull image from CI registry
print_info "📥 Pulling image from CI registry..."
if ! sudo -E podman pull "registry.ci.openshift.org/openshift/${IMAGE_NAME}:${IMAGE_TAG}" --tls-verify=false; then
    print_error "Failed to pull image from CI registry"
    exit 1
fi
print_success "Image pulled successfully"

# Step 2: Tag image for local registry
print_info "🏷️  Tagging image for local registry..."
if ! sudo -E podman tag "registry.ci.openshift.org/openshift/${IMAGE_NAME}:${IMAGE_TAG}" "localhost:${REGISTRY_PORT}/openshift/${IMAGE_NAME}:${IMAGE_TAG}"; then
    print_error "Failed to tag image"
    exit 1
fi
print_success "Image tagged successfully"

# Step 3: Login to local registry
print_info "🔐 Logging into local registry..."
if ! sudo -E podman login --username "$REGISTRY_USER" --password "$REGISTRY_PASSWORD" --tls-verify=false "localhost:${REGISTRY_PORT}"; then
    print_error "Failed to login to local registry"
    exit 1
fi
print_success "Logged into local registry"

# Step 4: Push image to local registry
print_info "📤 Pushing image to local registry..."
if ! sudo -E podman push "localhost:${REGISTRY_PORT}/openshift/${IMAGE_NAME}:${IMAGE_TAG}" --tls-verify=false; then
    print_error "Failed to push image to local registry"
    exit 1
fi
print_success "Image pushed successfully"

# Step 5: Verify image in local registry
print_info "🔍 Verifying image in local registry..."
if curl -k -s -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" "https://localhost:${REGISTRY_PORT}/v2/openshift/${IMAGE_NAME}/tags/list" 2>/dev/null | grep -q "${IMAGE_TAG}"; then
    print_success "✅ Image verified in local registry"
else
    print_warning "⚠️  Image verification failed - image may not be accessible"
fi

# Step 6: Clean up local images to save space
print_info "🧹 Cleaning up local images..."
sudo -E podman rmi "registry.ci.openshift.org/openshift/${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || true
sudo -E podman rmi "localhost:${REGISTRY_PORT}/openshift/${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || true
print_success "Cleanup completed"

print_success "🎉 Image sync completed successfully!"
print_info "   Image: openshift/${IMAGE_NAME}:${IMAGE_TAG}"
print_info "   Available at: localhost:${REGISTRY_PORT}/openshift/${IMAGE_NAME}:${IMAGE_TAG}" 