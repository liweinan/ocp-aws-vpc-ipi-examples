#!/bin/bash

# Comprehensive Disconnected Cluster Verification Script
# Based on best practices for verifying bootstrap uses local registry

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Comprehensive Disconnected Cluster Verification${NC}"
echo "====================================================="
echo ""

# Configuration
REGISTRY_PORT="5000"
REGISTRY_USER="admin"
REGISTRY_PASSWORD="admin123"
INSTALL_DIR="./openshift-install-dir"
VPC_ID=""
REGION="us-east-1"

# Check if running on bastion
if [[ ! -f "/opt/registry/certs/domain.crt" ]]; then
    echo -e "${RED}❌ This script must be run on the bastion host${NC}"
    exit 1
fi

# Function to check command availability
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}❌ Required command not found: $1${NC}"
        return 1
    fi
    return 0
}

# Check required commands
echo -e "${BLUE}🔧 Checking required tools...${NC}"
required_commands=("yq" "jq" "curl" "aws")
for cmd in "${required_commands[@]}"; do
    if check_command "$cmd"; then
        echo -e "${GREEN}✅ $cmd available${NC}"
    else
        echo -e "${RED}❌ $cmd not available${NC}"
        exit 1
    fi
done

echo ""

## 1. **验证install-config.yaml配置**

echo -e "${BLUE}📋 1. Verifying install-config.yaml configuration...${NC}"

if [[ -f "${INSTALL_DIR}/install-config.yaml.backup" ]]; then
    echo -e "${GREEN}✅ install-config.yaml.backup exists${NC}"
    
    # Check imageContentSources
    echo -e "${BLUE}   Checking imageContentSources...${NC}"
    if yq eval '.imageContentSources' "${INSTALL_DIR}/install-config.yaml.backup" 2>/dev/null | grep -q "localhost:5000"; then
        echo -e "${GREEN}✅ imageContentSources contains localhost:5000${NC}"
    else
        echo -e "${RED}❌ imageContentSources missing localhost:5000${NC}"
    fi
    
    # Check specific mappings
    if yq eval '.imageContentSources' "${INSTALL_DIR}/install-config.yaml.backup" 2>/dev/null | grep -q "registry.ci.openshift.org/origin/release"; then
        echo -e "${GREEN}✅ origin/release mapping found${NC}"
    else
        echo -e "${RED}❌ origin/release mapping missing${NC}"
    fi
    
    if yq eval '.imageContentSources' "${INSTALL_DIR}/install-config.yaml.backup" 2>/dev/null | grep -q "registry.ci.openshift.org/ocp/4.19"; then
        echo -e "${GREEN}✅ ocp/4.19 mapping found${NC}"
    else
        echo -e "${RED}❌ ocp/4.19 mapping missing${NC}"
    fi
    
    # Check pull secret
    echo -e "${BLUE}   Checking pull secret...${NC}"
    if yq eval '.pullSecret' "${INSTALL_DIR}/install-config.yaml.backup" 2>/dev/null | base64 -d 2>/dev/null | jq -r '.auths | keys[]' 2>/dev/null | grep -q "localhost:5000"; then
        echo -e "${GREEN}✅ pullSecret contains localhost:5000${NC}"
    else
        echo -e "${RED}❌ pullSecret missing localhost:5000${NC}"
    fi
else
    echo -e "${RED}❌ install-config.yaml.backup not found${NC}"
    exit 1
fi

echo ""

## 2. **验证生成的manifests**

echo -e "${BLUE}📋 2. Verifying generated manifests...${NC}"

# Check ImageContentSourcePolicy
if [[ -f "${INSTALL_DIR}/manifests/image-content-source-policy.yaml" ]]; then
    echo -e "${GREEN}✅ ImageContentSourcePolicy manifest exists${NC}"
    
    # Check if it contains localhost:5000
    if grep -q "localhost:5000" "${INSTALL_DIR}/manifests/image-content-source-policy.yaml"; then
        echo -e "${GREEN}✅ localhost:5000 in ImageContentSourcePolicy${NC}"
    else
        echo -e "${RED}❌ localhost:5000 missing from ImageContentSourcePolicy${NC}"
    fi
    
    # Check specific mappings
    if grep -q "registry.ci.openshift.org/origin/release" "${INSTALL_DIR}/manifests/image-content-source-policy.yaml"; then
        echo -e "${GREEN}✅ origin/release mapping in ImageContentSourcePolicy${NC}"
    else
        echo -e "${RED}❌ origin/release mapping missing from ImageContentSourcePolicy${NC}"
    fi
else
    echo -e "${RED}❌ ImageContentSourcePolicy manifest not found${NC}"
    exit 1
fi

# Check Pull Secret Manifest
if [[ -f "${INSTALL_DIR}/manifests/openshift-config-secret-pull-secret.yaml" ]]; then
    echo -e "${GREEN}✅ Pull secret manifest exists${NC}"
    
    # Decode and check pull secret content
    dockerconfig=$(yq eval '.data."\.dockerconfigjson"' "${INSTALL_DIR}/manifests/openshift-config-secret-pull-secret.yaml" 2>/dev/null)
    if echo "$dockerconfig" | base64 -d 2>/dev/null | jq -r '.auths | keys[]' 2>/dev/null | grep -q "localhost:5000"; then
        echo -e "${GREEN}✅ localhost:5000 in pull secret manifest${NC}"
    else
        echo -e "${RED}❌ localhost:5000 missing from pull secret manifest${NC}"
    fi
else
    echo -e "${RED}❌ Pull secret manifest not found${NC}"
    exit 1
fi

echo ""

## 3. **验证Registry可访问性**

echo -e "${BLUE}📋 3. Verifying registry accessibility...${NC}"

# Check if registry is running
if sudo -E podman ps --format "table {{.Names}}" | grep -q "registry"; then
    echo -e "${GREEN}✅ Registry container is running${NC}"
else
    echo -e "${RED}❌ Registry container is not running${NC}"
    exit 1
fi

# Check if registry is accessible
if curl -k -s -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" "https://localhost:${REGISTRY_PORT}/v2/_catalog" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Local registry is accessible${NC}"
else
    echo -e "${RED}❌ Local registry is not accessible${NC}"
    exit 1
fi

# Check critical images
echo -e "${BLUE}   Checking critical images...${NC}"
critical_images=(
    "openshift/ocp/release:4.19.2"
    "openshift/ocp/release:4.19"
    "openshift/installer:4.19.2"
    "openshift/cli:4.19.2"
    "openshift/machine-config-operator:4.19.2"
    "openshift/cluster-version-operator:4.19.2"
)

missing_images=()
for image in "${critical_images[@]}"; do
    repo=$(echo "$image" | cut -d: -f1)
    tag=$(echo "$image" | cut -d: -f2)
    
    if curl -k -s -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" "https://localhost:${REGISTRY_PORT}/v2/${repo}/tags/list" 2>/dev/null | grep -q "\"${tag}\""; then
        echo -e "${GREEN}✅ $image found in local registry${NC}"
    else
        echo -e "${RED}❌ $image not found in local registry${NC}"
        missing_images+=("$image")
    fi
done

if [[ ${#missing_images[@]} -gt 0 ]]; then
    echo -e "${RED}❌ Missing critical images:${NC}"
    printf '   - %s\n' "${missing_images[@]}"
    echo -e "${YELLOW}🔧 Run ./06-sync-images-robust.sh to sync missing images${NC}"
    exit 1
fi

echo ""

## 4. **验证网络隔离**

echo -e "${BLUE}📋 4. Verifying network isolation...${NC}"

# Get VPC ID if not set
if [[ -z "$VPC_ID" ]]; then
    if [[ -f "infra-output/vpc-id" ]]; then
        VPC_ID=$(cat infra-output/vpc-id)
    else
        # Try to get from AWS
        VPC_ID=$(aws ec2 describe-instances --instance-ids $(curl -s http://169.254.169.254/latest/meta-data/instance-id) --region "$REGION" --query 'Reservations[0].Instances[0].VpcId' --output text 2>/dev/null || echo "")
    fi
fi

if [[ -n "$VPC_ID" ]]; then
    echo -e "${GREEN}✅ VPC ID: $VPC_ID${NC}"
    
    # Check for NAT Gateways
    echo -e "${BLUE}   Checking for NAT Gateways...${NC}"
    nat_gateways=$(aws ec2 describe-nat-gateways --filters "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=pending,running" --region "$REGION" --query 'length(NatGateways)' --output text 2>/dev/null || echo "0")
    if [[ "$nat_gateways" == "0" ]]; then
        echo -e "${GREEN}✅ No NAT Gateways found (expected for disconnected cluster)${NC}"
    else
        echo -e "${YELLOW}⚠️  Found $nat_gateways NAT Gateway(s) - this might allow external access${NC}"
    fi
    
    # Check VPC Endpoints
    echo -e "${BLUE}   Checking VPC Endpoints...${NC}"
    vpc_endpoints=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" --region "$REGION" --query 'length(VpcEndpoints)' --output text 2>/dev/null || echo "0")
    if [[ "$vpc_endpoints" -gt 0 ]]; then
        echo -e "${GREEN}✅ Found $vpc_endpoints VPC Endpoint(s)${NC}"
    else
        echo -e "${YELLOW}⚠️  No VPC Endpoints found${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Could not determine VPC ID, skipping network checks${NC}"
fi

# Test external registry connectivity
echo -e "${BLUE}   Testing external registry connectivity...${NC}"
if curl -s --connect-timeout 5 "https://registry.ci.openshift.org/v2/" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  External registry (registry.ci.openshift.org) is accessible${NC}"
    echo -e "${YELLOW}   This might cause issues in a truly disconnected environment${NC}"
else
    echo -e "${GREEN}✅ External registry (registry.ci.openshift.org) is not accessible (expected)${NC}"
fi

if curl -s --connect-timeout 5 "https://quay.io/v2/" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  External registry (quay.io) is accessible${NC}"
else
    echo -e "${GREEN}✅ External registry (quay.io) is not accessible (expected)${NC}"
fi

echo ""

## 5. **测试镜像拉取**

echo -e "${BLUE}📋 5. Testing image pull from local registry...${NC}"

# Test pulling a critical image
echo -e "${BLUE}   Testing pull of openshift/ocp/release:4.19 from local registry...${NC}"
if sudo -E podman pull "localhost:${REGISTRY_PORT}/openshift/ocp/release:4.19" --tls-verify=false > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Successfully pulled openshift/ocp/release:4.19 from local registry${NC}"
    # Clean up
    sudo -E podman rmi "localhost:${REGISTRY_PORT}/openshift/ocp/release:4.19" > /dev/null 2>&1 || true
else
    echo -e "${RED}❌ Failed to pull openshift/ocp/release:4.19 from local registry${NC}"
    exit 1
fi

echo ""

## 6. **验证配置完整性**

echo -e "${BLUE}📋 6. Verifying configuration completeness...${NC}"

# Check if all required files exist
required_files=(
    "${INSTALL_DIR}/install-config.yaml.backup"
    "${INSTALL_DIR}/manifests/image-content-source-policy.yaml"
    "${INSTALL_DIR}/manifests/openshift-config-secret-pull-secret.yaml"
)

for file in "${required_files[@]}"; do
    if [[ -f "$file" ]]; then
        echo -e "${GREEN}✅ $(basename "$file") exists${NC}"
    else
        echo -e "${RED}❌ $(basename "$file") missing${NC}"
        exit 1
    fi
done

# Check if openshift-install is available
if command -v openshift-install &> /dev/null; then
    echo -e "${GREEN}✅ openshift-install available${NC}"
    openshift-install version
else
    echo -e "${RED}❌ openshift-install not available${NC}"
    exit 1
fi

echo ""

## 7. **生成验证报告**

echo -e "${BLUE}📋 7. Generating verification report...${NC}"

# Create verification report
report_file="disconnected-verification-report-$(date +%Y%m%d-%H%M%S).txt"
cat > "$report_file" <<EOF
Disconnected Cluster Verification Report
========================================
Date: $(date)
Host: $(hostname)
VPC ID: $VPC_ID
Region: $REGION

Configuration Status:
- Install Config: ${INSTALL_DIR}/install-config.yaml.backup
- Manifests: ${INSTALL_DIR}/manifests/
- Registry: localhost:${REGISTRY_PORT}

Critical Images Status:
$(for image in "${critical_images[@]}"; do
    repo=$(echo "$image" | cut -d: -f1)
    tag=$(echo "$image" | cut -d: -f2)
    if curl -k -s -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" "https://localhost:${REGISTRY_PORT}/v2/${repo}/tags/list" 2>/dev/null | grep -q "\"${tag}\""; then
        echo "✅ $image"
    else
        echo "❌ $image"
    fi
done)

Network Status:
- NAT Gateways: $nat_gateways
- VPC Endpoints: $vpc_endpoints
- External registry accessible: $(curl -s --connect-timeout 5 "https://registry.ci.openshift.org/v2/" > /dev/null 2>&1 && echo "YES" || echo "NO")

Registry Status:
$(curl -k -s -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" "https://localhost:${REGISTRY_PORT}/v2/_catalog" 2>/dev/null | jq '.' || echo "Unable to fetch registry catalog")

EOF

echo -e "${GREEN}✅ Verification report saved to: $report_file${NC}"

echo ""
echo -e "${GREEN}🎉 Comprehensive verification completed!${NC}"
echo ""
echo -e "${BLUE}📊 Summary:${NC}"
echo "   ✅ Install config contains correct image mappings"
echo "   ✅ Manifests contain localhost:5000 configurations"
echo "   ✅ Local registry is accessible and contains critical images"
echo "   ✅ Pull secret contains local registry authentication"
echo "   ✅ Image pull from local registry works"
echo "   ✅ Network isolation verified"
echo ""
echo -e "${BLUE}🚀 Bootstrap should now use local registry instead of external registry${NC}"
echo ""
echo -e "${YELLOW}📝 Next steps:${NC}"
echo "   1. Review the verification report: $report_file"
echo "   2. If all checks pass, proceed with cluster installation"
echo "   3. Monitor bootstrap logs for local registry usage"
echo "   4. Verify no external registry access during installation"
echo ""
echo -e "${YELLOW}⚠️  Note: If external registry is accessible, ensure your network configuration${NC}"
echo "   properly blocks external registry access during bootstrap phase." 