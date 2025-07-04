#!/bin/bash

# Robust Image Synchronization Script for Disconnected OpenShift Cluster
# This script syncs images from OpenShift CI cluster to local mirror registry
# Uses simplified single-image script for better reliability

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="${1:-weli-test}"
OPENSHIFT_VERSION="${2:-4.19.2}"
REGISTRY_PORT="5000"
REGISTRY_USER="admin"
REGISTRY_PASSWORD="admin123"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SINGLE_SYNC_SCRIPT="${SCRIPT_DIR}/sync-single-image.sh"

# Check if single sync script exists
if [[ ! -f "$SINGLE_SYNC_SCRIPT" ]]; then
    echo -e "${RED}❌ Single sync script not found: $SINGLE_SYNC_SCRIPT${NC}"
    exit 1
fi

# Make sure single sync script is executable
chmod +x "$SINGLE_SYNC_SCRIPT"

echo -e "${BLUE}🔄 Robust CI Registry Image Synchronization${NC}"
echo "=================================================="
echo ""
echo -e "${BLUE}📋 Configuration:${NC}"
echo "   Cluster Name: $CLUSTER_NAME"
echo "   OpenShift Version: $OPENSHIFT_VERSION"
echo "   Registry Port: $REGISTRY_PORT"
echo "   Registry User: $REGISTRY_USER"
echo "   Using script: $SINGLE_SYNC_SCRIPT"
echo ""

# Define core images (critical for cluster installation)
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

# Define additional important images
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

total_images=$((${#core_images[@]} + ${#additional_images[@]}))
synced_count=0
failed_count=0
current_count=0

echo -e "${BLUE}📦 Syncing core images (${#core_images[@]} images)...${NC}"

for img in "${core_images[@]}"; do
    current_count=$((current_count + 1))
    echo ""
    echo -e "${BLUE}[${current_count}/${total_images}] Processing core image: ${img}${NC}"
    
    # Call single sync script (script handles sudo internally)
    if sudo -E "$SINGLE_SYNC_SCRIPT" "$img" "$OPENSHIFT_VERSION" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"; then
        synced_count=$((synced_count + 1))
    else
        echo -e "${RED}   ❌ Failed to sync ${img}${NC}"
        failed_count=$((failed_count + 1))
    fi
    
    # Brief pause between images
    sleep 2
done

echo ""
echo -e "${BLUE}📦 Syncing additional images (${#additional_images[@]} images)...${NC}"

for img in "${additional_images[@]}"; do
    current_count=$((current_count + 1))
    echo ""
    echo -e "${BLUE}[${current_count}/${total_images}] Processing additional image: ${img}${NC}"
    
    # Call single sync script (script handles sudo internally)
    if sudo -E "$SINGLE_SYNC_SCRIPT" "$img" "$OPENSHIFT_VERSION" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"; then
        synced_count=$((synced_count + 1))
    else
        echo -e "${RED}   ❌ Failed to sync ${img}${NC}"
        failed_count=$((failed_count + 1))
    fi
    
    # Brief pause between images
    sleep 2
done

echo ""
echo -e "${GREEN}✅ Image synchronization completed${NC}"
echo "   Successfully synced: ${synced_count} images"
echo "   Failed: ${failed_count} images"
echo "   Total processed: ${current_count}/${total_images} images"

# Generate summary
sync_dir="/home/ubuntu/openshift-sync"
mkdir -p "${sync_dir}"

cat > "${sync_dir}/sync-summary.txt" <<EOF
OpenShift Image Synchronization Summary
=======================================
Date: $(date)
Cluster Name: ${CLUSTER_NAME}
OpenShift Version: ${OPENSHIFT_VERSION}
Registry: localhost:${REGISTRY_PORT}

Results:
- Successfully synced: ${synced_count} images
- Failed: ${failed_count} images
- Total processed: ${current_count}/${total_images} images

Core Images (${#core_images[@]}):
$(printf "  - %s\n" "${core_images[@]}")

Additional Images (${#additional_images[@]}):
$(printf "  - %s\n" "${additional_images[@]}")

Final registry contents:
$(curl -k -s -u admin:admin123 'https://localhost:5000/v2/_catalog' 2>/dev/null | jq '.' || echo "Unable to fetch registry catalog")
EOF

# Generate imageContentSources configuration
cat > "${sync_dir}/imageContentSources.yaml" <<EOF
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: ${CLUSTER_NAME}-icsp
spec:
  repositoryDigestMirrors:
  - mirrors:
    - localhost:${REGISTRY_PORT}/openshift
    source: registry.ci.openshift.org/ocp/${OPENSHIFT_VERSION}
  - mirrors:
    - localhost:${REGISTRY_PORT}/openshift
    source: registry.ci.openshift.org/openshift
  - mirrors:
    - localhost:${REGISTRY_PORT}/openshift
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - localhost:${REGISTRY_PORT}/openshift
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
EOF

echo ""
echo -e "${BLUE}📄 Summary saved to: ${sync_dir}/sync-summary.txt${NC}"
echo -e "${BLUE}📄 ImageContentSources saved to: ${sync_dir}/imageContentSources.yaml${NC}"

# Return success if most images synced
if [[ $synced_count -ge $((total_images * 80 / 100)) ]]; then
    echo ""
    echo -e "${GREEN}🎉 Robust image synchronization completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}📋 Next steps:${NC}"
    echo "   1. Verify images: curl -k -u admin:admin123 'https://localhost:5000/v2/_catalog'"
    echo "   2. Run ./07-prepare-install-config.sh to prepare installation"
    echo "   3. Run ./08-install-cluster.sh to install the cluster"
    exit 0
else
    echo ""
    echo -e "${YELLOW}⚠️  Warning: Only ${synced_count}/${total_images} images synced successfully${NC}"
    echo "You may want to retry failed images or check connectivity"
    exit 1
fi 