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

# Define release images (critical for bootstrap)
release_images=(
    "ocp/release:4.19.2"
    "ocp/release:4.19.0"
    "ocp/release:4.19"
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
    "prometheus-node-exporter"
    "kube-state-metrics"
)

total_images=$((${#core_images[@]} + ${#release_images[@]} + ${#additional_images[@]}))
synced_count=0
failed_count=0
skipped_count=0
current_count=0

echo -e "${BLUE}📦 Syncing release images (${#release_images[@]} images)...${NC}"

# Sync release images first (most critical)
for img in "${release_images[@]}"; do
    current_count=$((current_count + 1))
    echo ""
    echo -e "${BLUE}[${current_count}/${total_images}] Processing release image: ${img}${NC}"
    
    # Parse image name and tag
    img_name=$(echo "$img" | cut -d':' -f1)
    img_tag=$(echo "$img" | cut -d':' -f2)
    
    # Check if image already exists
    repo_path=""
    if [[ "$img_name" == */* ]]; then
        repo_path="openshift/${img_name}"
    else
        repo_path="openshift/${img_name}"
    fi
    
    if curl -k -s -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" "https://localhost:${REGISTRY_PORT}/v2/${repo_path}/tags/list" 2>/dev/null | grep -q "${img_tag}"; then
        echo -e "${YELLOW}   ⏭️  Already exists in registry, skipping${NC}"
        skipped_count=$((skipped_count + 1))
    else
        # Call single sync script for all images
        if sudo -E "$SINGLE_SYNC_SCRIPT" "$img_name" "$img_tag" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"; then
            synced_count=$((synced_count + 1))
        else
            echo -e "${RED}   ❌ Failed to sync ${img}${NC}"
            failed_count=$((failed_count + 1))
        fi
    fi
    
    # Brief pause between images
    sleep 2
done

echo ""
echo -e "${BLUE}📦 Syncing core images (${#core_images[@]} images)...${NC}"

for img in "${core_images[@]}"; do
    current_count=$((current_count + 1))
    echo ""
    echo -e "${BLUE}[${current_count}/${total_images}] Processing core image: ${img}${NC}"
    
    # Check if image already exists before attempting sync
    if curl -k -s -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" "https://localhost:${REGISTRY_PORT}/v2/openshift/${img}/tags/list" 2>/dev/null | grep -q "${OPENSHIFT_VERSION}"; then
        echo -e "${YELLOW}   ⏭️  Already exists in registry, skipping${NC}"
        skipped_count=$((skipped_count + 1))
    else
        # Call single sync script (script handles sudo internally)
        if sudo -E "$SINGLE_SYNC_SCRIPT" "$img" "$OPENSHIFT_VERSION" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"; then
            synced_count=$((synced_count + 1))
        else
            echo -e "${RED}   ❌ Failed to sync ${img}${NC}"
            failed_count=$((failed_count + 1))
        fi
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
    
    # Check if image already exists before attempting sync
    if curl -k -s -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" "https://localhost:${REGISTRY_PORT}/v2/openshift/${img}/tags/list" 2>/dev/null | grep -q "${OPENSHIFT_VERSION}"; then
        echo -e "${YELLOW}   ⏭️  Already exists in registry, skipping${NC}"
        skipped_count=$((skipped_count + 1))
    else
        # Call single sync script (script handles sudo internally)
        if sudo -E "$SINGLE_SYNC_SCRIPT" "$img" "$OPENSHIFT_VERSION" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"; then
            synced_count=$((synced_count + 1))
        else
            echo -e "${RED}   ❌ Failed to sync ${img}${NC}"
            failed_count=$((failed_count + 1))
        fi
    fi
    
    # Brief pause between images
    sleep 2
done

echo ""
echo -e "${GREEN}✅ Image synchronization completed${NC}"
echo "   Successfully synced: ${synced_count} images"
echo "   Already existed (skipped): ${skipped_count} images"
echo "   Failed: ${failed_count} images"
echo "   Total processed: ${current_count}/${total_images} images"

# Verify all expected images are in registry
echo ""
echo -e "${BLUE}🔍 Verifying registry contents...${NC}"
all_expected_images=("${core_images[@]}" "${additional_images[@]}")
registry_catalog=$(curl -k -s -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" "https://localhost:${REGISTRY_PORT}/v2/_catalog" 2>/dev/null || echo '{"repositories":[]}')
missing_images=()
verified_count=0

# Verify regular images
for img in "${all_expected_images[@]}"; do
    expected_repo="openshift/${img}"
    if echo "$registry_catalog" | jq -r '.repositories[]' | grep -q "^${expected_repo}$"; then
        # Double check the specific version tag exists
        if curl -k -s -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" "https://localhost:${REGISTRY_PORT}/v2/openshift/${img}/tags/list" 2>/dev/null | grep -q "${OPENSHIFT_VERSION}"; then
            verified_count=$((verified_count + 1))
        else
            missing_images+=("${img} (version ${OPENSHIFT_VERSION} missing)")
        fi
    else
        missing_images+=("${img} (repository missing)")
    fi
done

# Verify release images
for img in "${release_images[@]}"; do
    expected_repo="openshift/${img%%:*}"
    expected_tag="${img##*:}"
    if echo "$registry_catalog" | jq -r '.repositories[]' | grep -q "^${expected_repo}$"; then
        # Double check the specific version tag exists
        if curl -k -s -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" "https://localhost:${REGISTRY_PORT}/v2/${expected_repo}/tags/list" 2>/dev/null | grep -q "${expected_tag}"; then
            verified_count=$((verified_count + 1))
        else
            missing_images+=("${img} (version ${expected_tag} missing)")
        fi
    else
        missing_images+=("${img} (repository missing)")
    fi
done

echo "   Verified in registry: ${verified_count}/${total_images} images"

if [[ ${#missing_images[@]} -gt 0 ]]; then
    echo -e "${YELLOW}   ⚠️  Missing images:${NC}"
    for missing in "${missing_images[@]}"; do
        echo "     - ${missing}"
    done
else
    echo -e "${GREEN}   ✅ All expected images verified in registry${NC}"
fi

# Generate summary
sync_dir="/home/ubuntu/openshift-sync"
# Ensure directory exists with correct permissions
mkdir -p "${sync_dir}"
# Fix ownership if directory was created with wrong permissions
if [[ ! -w "${sync_dir}" ]]; then
    echo "Fixing directory permissions for ${sync_dir}..."
    sudo chown -R ubuntu:ubuntu "${sync_dir}" 2>/dev/null || true
fi

cat > "${sync_dir}/sync-summary.txt" <<EOF
OpenShift Image Synchronization Summary
=======================================
Date: $(date)
Cluster Name: ${CLUSTER_NAME}
OpenShift Version: ${OPENSHIFT_VERSION}
Registry: localhost:${REGISTRY_PORT}

Results:
- Successfully synced: ${synced_count} images
- Already existed (skipped): ${skipped_count} images  
- Failed: ${failed_count} images
- Verified in registry: ${verified_count} images
- Total processed: ${current_count}/${total_images} images

Release Images (${#release_images[@]}):
$(printf "  - %s\n" "${release_images[@]}")

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
    source: registry.ci.openshift.org/origin
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

# Return success if most images are available in registry (either synced or already existed)
available_images=$((synced_count + skipped_count))
if [[ $verified_count -ge $((total_images * 90 / 100)) && $available_images -ge $((total_images * 90 / 100)) ]]; then
    echo ""
    echo -e "${GREEN}🎉 Robust image synchronization completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}📊 Final Status:${NC}"
    echo "   ✅ Available in registry: ${available_images}/${total_images} images (${verified_count} verified)"
    echo "   📦 Newly synced: ${synced_count} images"
    echo "   ⏭️  Already existed: ${skipped_count} images"
    echo "   ❌ Failed: ${failed_count} images"
    echo ""
    echo -e "${BLUE}📋 Next steps:${NC}"
    echo "   1. Run ./07-prepare-install-config.sh to prepare installation"
    echo "   2. Run ./08-install-cluster.sh to install the cluster"
    echo "   3. Verify with: curl -k -u admin:admin123 'https://localhost:5000/v2/_catalog'"
    exit 0
else
    echo ""
    echo -e "${YELLOW}⚠️  Warning: Only ${verified_count}/${total_images} images verified in registry${NC}"
    echo "   Available: ${available_images} (synced: ${synced_count}, existed: ${skipped_count})"
    echo "   Failed: ${failed_count}"
    echo ""
    echo "You may want to retry failed images or check connectivity"
    exit 1
fi 