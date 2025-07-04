#!/bin/bash

# Docker-based Image Synchronization Script
# Using docker instead of podman to avoid connection issues

set -euo pipefail

echo "🔄 Docker-based Image Synchronization"
echo "===================================="

# Configuration
CI_REGISTRY="registry.ci.openshift.org"
LOCAL_REGISTRY="localhost:5000"
OCP_VERSION="4.19.2"

# Get CI token
echo "Getting CI token..."
CI_TOKEN=$(oc whoami -t)
CI_USER=$(oc whoami)

echo "CI User: $CI_USER"

# Login to CI registry with docker
echo "Logging into CI registry with docker..."
echo "$CI_TOKEN" | docker login -u "$CI_USER" --password-stdin "$CI_REGISTRY"

# Login to local registry with docker
echo "Logging into local registry with docker..."
echo "admin123" | docker login -u admin --password-stdin "$LOCAL_REGISTRY"

# Core images to sync
core_images=(
    "cli"
    "installer"
    "machine-config-operator"
    "cluster-version-operator"
    "etcd"
    "hyperkube"
    "oauth-server"
    "oauth-proxy"
    "console"
    "haproxy-router"
    "coredns"
)

# Additional images
additional_images=(
    "cluster-network-operator"
    "cluster-dns-operator"
    "cluster-storage-operator"
    "cluster-ingress-operator"
    "aws-ebs-csi-driver"
    "aws-ebs-csi-driver-operator"
    "cluster-monitoring-operator"
    "prometheus-operator"
    "node-exporter"
    "kube-state-metrics"
)

synced=0
failed=0

# Function to sync a single image
sync_image() {
    local img="$1"
    local source_image="${CI_REGISTRY}/ocp/${OCP_VERSION}:${img}"
    local target_image="${LOCAL_REGISTRY}/openshift/${img}:${OCP_VERSION}"
    local target_latest="${LOCAL_REGISTRY}/openshift/${img}:latest"
    
    echo "Syncing: $img"
    echo "  From: $source_image"
    echo "  To: $target_image"
    
    # Pull from CI registry
    if docker pull "$source_image"; then
        echo "  ✅ Pulled successfully"
        
        # Tag for local registry
        docker tag "$source_image" "$target_image"
        docker tag "$source_image" "$target_latest"
        
        # Push to local registry
        if docker push "$target_image" && docker push "$target_latest"; then
            echo "  ✅ Pushed successfully"
            ((synced++))
            
            # Clean up local copy
            docker rmi "$source_image" "$target_image" "$target_latest" 2>/dev/null || true
        else
            echo "  ❌ Push failed"
            ((failed++))
        fi
    else
        echo "  ❌ Pull failed"
        ((failed++))
    fi
    echo
}

# Sync core images
echo "📦 Syncing core images..."
for img in "${core_images[@]}"; do
    sync_image "$img"
done

# Sync additional images
echo "📦 Syncing additional images..."
for img in "${additional_images[@]}"; do
    sync_image "$img"
done

echo "🎉 Synchronization completed!"
echo "   Synced: $synced images"
echo "   Failed: $failed images"
echo "   Total: $((synced + failed)) images"

# Check final registry state
echo ""
echo "📋 Final registry catalog:"
curl -s -u admin:admin123 "http://localhost:5000/v2/_catalog" | jq '.' || curl -s -u admin:admin123 "http://localhost:5000/v2/_catalog" 