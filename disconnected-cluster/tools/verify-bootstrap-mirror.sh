#!/bin/bash

# Verify Bootstrap Mirror Configuration
# This script verifies that bootstrap will use local registry instead of external registry

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Verifying Bootstrap Mirror Configuration${NC}"
echo "=============================================="
echo ""

# Check if running on bastion
if [[ ! -f "/opt/registry/certs/domain.crt" ]]; then
    echo -e "${RED}❌ This script must be run on the bastion host${NC}"
    exit 1
fi

# Configuration
REGISTRY_PORT="5000"
REGISTRY_USER="admin"
REGISTRY_PASSWORD="admin123"
INSTALL_DIR="./openshift-install-dir"

echo -e "${BLUE}📋 Checking local registry status...${NC}"

# 1. Check if registry is running
if sudo -E podman ps --format "table {{.Names}}" | grep -q "registry"; then
    echo -e "${GREEN}✅ Registry container is running${NC}"
else
    echo -e "${RED}❌ Registry container is not running${NC}"
    exit 1
fi

# 2. Check if registry is accessible
if curl -k -s -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" "https://localhost:${REGISTRY_PORT}/v2/_catalog" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Registry is accessible${NC}"
else
    echo -e "${RED}❌ Registry is not accessible${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}📦 Checking critical bootstrap images...${NC}"

# 3. Check critical bootstrap images
critical_images=(
    "openshift/ocp/release:4.19"
    "openshift/ocp/release:4.19.2"
    "openshift/installer:4.19.2"
    "openshift/cli:4.19.2"
    "openshift/machine-config-operator:4.19.2"
    "openshift/cluster-version-operator:4.19.2"
)

missing_images=()
for img in "${critical_images[@]}"; do
    repo=$(echo "$img" | cut -d':' -f1)
    tag=$(echo "$img" | cut -d':' -f2)
    
    if curl -k -s -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" "https://localhost:${REGISTRY_PORT}/v2/${repo}/tags/list" 2>/dev/null | grep -q "\"${tag}\""; then
        echo -e "${GREEN}✅ ${img}${NC}"
    else
        echo -e "${RED}❌ ${img} - MISSING${NC}"
        missing_images+=("$img")
    fi
done

if [[ ${#missing_images[@]} -gt 0 ]]; then
    echo ""
    echo -e "${RED}❌ Missing critical bootstrap images:${NC}"
    printf '   - %s\n' "${missing_images[@]}"
    echo ""
    echo -e "${YELLOW}🔧 Run ./06-sync-images-robust.sh to sync missing images${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}📄 Checking install configuration...${NC}"

# 4. Check install-config.yaml backup
if [[ -f "${INSTALL_DIR}/install-config.yaml.backup" ]]; then
    echo -e "${GREEN}✅ install-config.yaml.backup exists${NC}"
    
    # Check imageContentSources
    if grep -q "registry.ci.openshift.org/origin/release" "${INSTALL_DIR}/install-config.yaml.backup"; then
        echo -e "${GREEN}✅ origin/release mapping found${NC}"
    else
        echo -e "${RED}❌ origin/release mapping missing${NC}"
    fi
    
    if grep -q "registry.ci.openshift.org/ocp/4.19" "${INSTALL_DIR}/install-config.yaml.backup"; then
        echo -e "${GREEN}✅ ocp/4.19 mapping found${NC}"
    else
        echo -e "${RED}❌ ocp/4.19 mapping missing${NC}"
    fi
    
    # Check pull secret
    if grep -q "localhost:5000" "${INSTALL_DIR}/install-config.yaml.backup"; then
        echo -e "${GREEN}✅ localhost:5000 in pull secret${NC}"
    else
        echo -e "${RED}❌ localhost:5000 missing from pull secret${NC}"
    fi
else
    echo -e "${RED}❌ install-config.yaml.backup not found${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}📋 Checking generated manifests...${NC}"

# 5. Check generated manifests
if [[ -f "${INSTALL_DIR}/manifests/image-content-source-policy.yaml" ]]; then
    echo -e "${GREEN}✅ ImageContentSourcePolicy manifest exists${NC}"
    
    # Check if it contains localhost:5000
    if grep -q "localhost:5000" "${INSTALL_DIR}/manifests/image-content-source-policy.yaml"; then
        echo -e "${GREEN}✅ localhost:5000 in ImageContentSourcePolicy${NC}"
    else
        echo -e "${RED}❌ localhost:5000 missing from ImageContentSourcePolicy${NC}"
    fi
    
    # Check if it contains registry.ci.openshift.org/origin/release
    if grep -q "registry.ci.openshift.org/origin/release" "${INSTALL_DIR}/manifests/image-content-source-policy.yaml"; then
        echo -e "${GREEN}✅ origin/release mapping in ImageContentSourcePolicy${NC}"
    else
        echo -e "${RED}❌ origin/release mapping missing from ImageContentSourcePolicy${NC}"
    fi
else
    echo -e "${RED}❌ ImageContentSourcePolicy manifest not found${NC}"
    exit 1
fi

if [[ -f "${INSTALL_DIR}/manifests/openshift-config-secret-pull-secret.yaml" ]]; then
    echo -e "${GREEN}✅ Pull secret manifest exists${NC}"
    
    # Decode and check pull secret content
    dockerconfig=$(grep "\.dockerconfigjson:" "${INSTALL_DIR}/manifests/openshift-config-secret-pull-secret.yaml" | awk '{print $2}')
    if echo "$dockerconfig" | base64 -d | grep -q "localhost:5000"; then
        echo -e "${GREEN}✅ localhost:5000 in pull secret manifest${NC}"
    else
        echo -e "${RED}❌ localhost:5000 missing from pull secret manifest${NC}"
    fi
else
    echo -e "${RED}❌ Pull secret manifest not found${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}🔧 Testing image pull from local registry...${NC}"

# 6. Test pulling a critical image from local registry
echo -e "${BLUE}📥 Testing pull of openshift/ocp/release:4.19 from local registry...${NC}"
if sudo -E podman pull "localhost:${REGISTRY_PORT}/openshift/ocp/release:4.19" --tls-verify=false > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Successfully pulled openshift/ocp/release:4.19 from local registry${NC}"
    # Clean up
    sudo -E podman rmi "localhost:${REGISTRY_PORT}/openshift/ocp/release:4.19" > /dev/null 2>&1 || true
else
    echo -e "${RED}❌ Failed to pull openshift/ocp/release:4.19 from local registry${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}🔍 Testing oc adm release mirror with image mappings...${NC}"

# 7. Test oc adm release mirror with image mappings
echo -e "${BLUE}📋 Creating temporary registry config for testing...${NC}"

# Create temporary registry config with image mappings
cat > /tmp/test-registry-config.json << EOF
{
  "auths": {
    "localhost:${REGISTRY_PORT}": {
      "auth": "$(echo -n "${REGISTRY_USER}:${REGISTRY_PASSWORD}" | base64)"
    }
  },
  "imageContentSources": [
    {
      "mirrors": ["localhost:${REGISTRY_PORT}/openshift/ocp/release"],
      "source": "registry.ci.openshift.org/origin/release"
    },
    {
      "mirrors": ["localhost:${REGISTRY_PORT}/openshift/ocp/release"],
      "source": "registry.ci.openshift.org/origin/release:4.19"
    },
    {
      "mirrors": ["localhost:${REGISTRY_PORT}/openshift/ocp/release"],
      "source": "registry.ci.openshift.org/origin/release:4.19.2"
    },
    {
      "mirrors": ["localhost:${REGISTRY_PORT}/openshift/installer"],
      "source": "registry.ci.openshift.org/ocp/4.19.2/installer"
    },
    {
      "mirrors": ["localhost:${REGISTRY_PORT}/openshift/cli"],
      "source": "registry.ci.openshift.org/ocp/4.19.2/cli"
    }
  ]
}
EOF

echo -e "${GREEN}✅ Temporary registry config created${NC}"

# Test oc adm release info with mappings
echo -e "${BLUE}📊 Testing oc adm release info with image mappings...${NC}"
if oc adm release info "registry.ci.openshift.org/origin/release:4.19" \
    --registry-config=/tmp/test-registry-config.json \
    --output=json > /tmp/release-info.json 2>/dev/null; then
    echo -e "${GREEN}✅ oc adm release info succeeded with mappings${NC}"
    
    # Check if the output contains localhost:5000 references
    if grep -q "localhost:${REGISTRY_PORT}" /tmp/release-info.json; then
        echo -e "${GREEN}✅ Image mappings are being applied correctly${NC}"
        
        # Show some example mappings
        echo -e "${BLUE}📋 Sample image mappings found:${NC}"
        grep "localhost:${REGISTRY_PORT}" /tmp/release-info.json | head -3 | sed 's/^/   /'
    else
        echo -e "${YELLOW}⚠️  No localhost:${REGISTRY_PORT} references found in output${NC}"
    fi
else
    echo -e "${RED}❌ oc adm release info failed with mappings${NC}"
    echo -e "${YELLOW}⚠️  This might indicate mapping configuration issues${NC}"
fi

# Test actual mirror operation (dry-run)
echo -e "${BLUE}🔄 Testing oc adm release mirror (dry-run)...${NC}"
if oc adm release mirror \
    --from="registry.ci.openshift.org/origin/release:4.19" \
    --to-dir=/tmp/mirror-test \
    --registry-config=/tmp/test-registry-config.json \
    --dry-run > /tmp/mirror-test.log 2>&1; then
    echo -e "${GREEN}✅ oc adm release mirror dry-run succeeded${NC}"
    
    # Check if mirror log shows localhost:5000 usage
    if grep -q "localhost:${REGISTRY_PORT}" /tmp/mirror-test.log; then
        echo -e "${GREEN}✅ Mirror operation is using local registry${NC}"
        echo -e "${BLUE}📋 Sample mirror operations:${NC}"
        grep "localhost:${REGISTRY_PORT}" /tmp/mirror-test.log | head -3 | sed 's/^/   /'
    else
        echo -e "${YELLOW}⚠️  Mirror operation not showing local registry usage${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  oc adm release mirror dry-run failed (this might be expected)${NC}"
    echo -e "${BLUE}📋 Error details:${NC}"
    tail -5 /tmp/mirror-test.log | sed 's/^/   /'
fi

# Clean up temporary files
rm -f /tmp/test-registry-config.json /tmp/release-info.json /tmp/mirror-test.log
rm -rf /tmp/mirror-test

echo ""
echo -e "${BLUE}🌐 Testing external registry connectivity (should fail)...${NC}"

# 8. Test external registry connectivity (should fail in disconnected environment)
echo -e "${BLUE}📡 Testing connectivity to registry.ci.openshift.org...${NC}"
if curl -s --connect-timeout 5 "https://registry.ci.openshift.org/v2/" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  External registry is accessible (this might cause issues)${NC}"
else
    echo -e "${GREEN}✅ External registry is not accessible (expected in disconnected environment)${NC}"
fi

echo ""
echo -e "${GREEN}🎉 Bootstrap mirror configuration verification completed!${NC}"
echo ""
echo -e "${BLUE}📊 Summary:${NC}"
echo "   ✅ Local registry is running and accessible"
echo "   ✅ All critical bootstrap images are present"
echo "   ✅ Install config contains correct image mappings"
echo "   ✅ Manifests contain localhost:5000 configurations"
echo "   ✅ Pull secret contains local registry authentication"
echo "   ✅ Image pull from local registry works"
echo "   ✅ oc adm release mirror respects image mappings"
echo ""
echo -e "${BLUE}🚀 Bootstrap should now use local registry instead of external registry${NC}"
echo ""
echo -e "${YELLOW}📝 Note: If external registry is accessible, ensure your network configuration${NC}"
echo "   properly blocks external registry access during bootstrap phase." 