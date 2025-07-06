#!/bin/bash

# Install Config Preparation Script for Disconnected OpenShift Cluster
# This script can run locally to copy itself to bastion, or directly on bastion host
# Updated to use CI registry images (registry.ci.openshift.org/ocp/4.19.2)

set -euo pipefail

# Set AWS_PROFILE to static if not already set
export AWS_PROFILE=${AWS_PROFILE:-static}

# Default values
DEFAULT_CLUSTER_NAME="disconnected-cluster"
DEFAULT_INFRA_OUTPUT_DIR="./infra-output"
DEFAULT_SYNC_OUTPUT_DIR="./sync-output"
DEFAULT_BASE_DOMAIN="qe.devcluster.openshift.com"
DEFAULT_REGION="us-east-1"
DEFAULT_REGISTRY_PORT="5000"
DEFAULT_REGISTRY_USER="admin"
DEFAULT_REGISTRY_PASSWORD="admin123"
DEFAULT_INSTALL_DIR="./openshift-install-dir"
DEFAULT_SSH_KEY="~/.ssh/id_rsa.pub"
DEFAULT_BASTION_KEY="./infra-output/bastion-key.pem"
DEFAULT_OPENSHIFT_VERSION="4.19.2"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --cluster-name        Cluster name (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --base-domain         Base domain (default: $DEFAULT_BASE_DOMAIN)"
    echo "  --region              AWS region (default: $DEFAULT_REGION)"
    echo "  --registry-port       Registry port (default: $DEFAULT_REGISTRY_PORT)"
    echo "  --registry-user       Registry username (default: $DEFAULT_REGISTRY_USER)"
    echo "  --registry-password   Registry password (default: $DEFAULT_REGISTRY_PASSWORD)"
    echo "  --install-dir         Installation directory (default: $DEFAULT_INSTALL_DIR)"
    echo "  --ssh-key             SSH public key file (default: $DEFAULT_SSH_KEY)"
    echo "  --pull-secret         Pull secret file or content (optional - will auto-generate)"
    echo "  --infra-output-dir    Infrastructure output directory (default: $DEFAULT_INFRA_OUTPUT_DIR)"
    echo "  --dry-run             Show what would be created without actually creating"
    echo "  --help                Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --cluster-name my-cluster --base-domain mydomain.com"
    echo "  $0 --ssh-key ~/.ssh/id_ed25519.pub"
    echo ""
    echo "Note: This script must be run on the bastion host"
    echo "      Cluster will be configured as SNO (Single Node OpenShift) mode"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    local missing_tools=()
    
    for tool in jq yq; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo -e "${RED}❌ Missing required tools: ${missing_tools[*]}${NC}"
        echo "Please install the missing tools and try again"
        exit 1
    fi
    
    echo -e "${GREEN}✅ All required tools are available${NC}"
}

# Function to check if running on bastion host
is_bastion_host() {
    [[ -f "/opt/registry/certs/domain.crt" ]] && [[ -d "/home/ubuntu" ]]
}

# Function to get SSH public key
get_ssh_key() {
    local ssh_key_file="$1"
    
    # Expand tilde if present
    ssh_key_file="${ssh_key_file/#\~/$HOME}"
    
    if [[ ! -f "$ssh_key_file" ]]; then
        echo -e "${RED}❌ SSH public key file not found: $ssh_key_file${NC}"
        echo "Please provide a valid SSH public key file"
        exit 1
    fi
    
    local ssh_key_content=$(cat "$ssh_key_file")
    echo "$ssh_key_content"
}

# Function to get pull secret
get_pull_secret() {
    local pull_secret_input="$1"
    local cluster_name="$2"
    local registry_port="$3"
    local registry_user="$4"
    local registry_password="$5"
    
    # Generate localhost:5000 auth
    local auth_string=$(echo -n "${registry_user}:${registry_password}" | base64)
    local local_auth="{\"auths\":{\"localhost:${registry_port}\":{\"auth\":\"${auth_string}\"}}}"
    
    # If pull secret input is provided, merge it with local auth
    if [[ -n "$pull_secret_input" ]]; then
        if [[ -f "$pull_secret_input" ]]; then
            # File path provided
            local original_secret=$(cat "$pull_secret_input")
        else
            # Direct content provided
            local original_secret="$pull_secret_input"
        fi
        
        # Merge the secrets
        echo "$original_secret" | jq -r --argjson local "$local_auth" '.auths += $local.auths'
    else
        # Use only local auth
        echo "$local_auth"
    fi
}

# Function to get infrastructure information
get_infrastructure_info() {
    if [[ -f "$INFRA_OUTPUT_DIR/vpc-id" ]]; then
        local region=$(cat "$INFRA_OUTPUT_DIR/region")
        local vpc_id=$(cat "$INFRA_OUTPUT_DIR/vpc-id")
        local private_subnet_ids=$(cat "$INFRA_OUTPUT_DIR/private-subnet-ids")
        local public_subnet_ids=$(cat "$INFRA_OUTPUT_DIR/public-subnet-ids")
        echo "$region $vpc_id $private_subnet_ids $public_subnet_ids"
    else
        local region=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
        local instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
        local vpc_id=$(aws ec2 describe-instances --instance-ids "$instance_id" --region "$region" --query 'Reservations[0].Instances[0].VpcId' --output text)
        local private_subnet_ids=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:kubernetes.io/role/internal-elb,Values=1" --region "$region" --query 'Subnets[].SubnetId' --output text | tr '\t' ',')
        local public_subnet_ids=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:kubernetes.io/role/elb,Values=1" --region "$region" --query 'Subnets[].SubnetId' --output text | tr '\t' ',')
        echo "$region $vpc_id $private_subnet_ids $public_subnet_ids"
    fi
}

# Function to create install-config.yaml
create_install_config() {
    local cluster_name="$1"
    local base_domain="$2"
    local region="$3"
    local vpc_id="$4"
    local private_subnet_ids="$5"
    local public_subnet_ids="$6"
    local registry_port="$7"
    local registry_user="$8"
    local registry_password="$9"
    local ssh_key_content="${10}"
    local pull_secret_content="${11}"
    local registry_cert="${12}"
    local install_dir="${13}"
    
    echo -e "${BLUE}📝 Creating install-config.yaml...${NC}"
    
    # Create installation directory
    mkdir -p "$install_dir"
    
    # Get VPC CIDR for machineNetwork
    local vpc_cidr
    if [[ -f "infra-output/vpc-cidr" ]]; then
        vpc_cidr=$(cat infra-output/vpc-cidr)
        echo -e "${GREEN}✅ Using VPC CIDR from infra-output: $vpc_cidr${NC}"
    else
        # Fallback: get VPC CIDR from AWS
        vpc_cidr=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$region" --query 'Vpcs[0].CidrBlock' --output text)
        echo -e "${GREEN}✅ Retrieved VPC CIDR from AWS: $vpc_cidr${NC}"
    fi
    
    # Get bastion host private IP for registry access
    local bastion_private_ip
    if [[ -f "infra-output/bastion-instance-id" ]]; then
        local bastion_instance_id=$(cat infra-output/bastion-instance-id)
        bastion_private_ip=$(aws ec2 describe-instances \
            --instance-ids "$bastion_instance_id" \
            --region "$region" \
            --query 'Reservations[0].Instances[0].PrivateIpAddress' \
            --output text)
        echo -e "${GREEN}✅ Using bastion private IP: $bastion_private_ip${NC}"
    else
        # Fallback: get from current instance if running on bastion
        bastion_private_ip=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo "10.0.10.10")
        echo -e "${YELLOW}⚠️  Using fallback registry URL: $bastion_private_ip${NC}"
    fi
    
    # Create install-config.yaml with proper registry configuration
    cat > "$install_dir/install-config.yaml" <<EOF
apiVersion: v1
baseDomain: $base_domain
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform:
    aws:
      type: m5.xlarge
      rootVolume:
        size: 120
        type: gp3
  replicas: 0
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      type: m5.xlarge
      rootVolume:
        size: 120
        type: gp3
  replicas: 1
metadata:
  name: $cluster_name
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: $vpc_cidr
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: $region
    vpc:
      subnets:
$(for subnet in $(echo $private_subnet_ids | tr ',' ' '); do echo "      - id: $subnet"; done)
$(for subnet in $(echo $public_subnet_ids | tr ',' ' '); do echo "      - id: $subnet"; done)
pullSecret: '$pull_secret_content'
sshKey: |
$(echo "$ssh_key_content" | sed 's/^/  /')
additionalTrustBundle: |
$(echo "$registry_cert" | sed 's/^/  /')
imageContentSources:
- mirrors:
  - $bastion_private_ip:$registry_port/openshift/ocp/release
  source: registry.ci.openshift.org/ocp/4.19.2
- mirrors:
  - $bastion_private_ip:$registry_port/openshift/ocp/release
  source: registry.ci.openshift.org/ocp/4.19
- mirrors:
  - $bastion_private_ip:$registry_port/openshift/ocp/release
  source: registry.ci.openshift.org/origin/release
- mirrors:
  - $bastion_private_ip:$registry_port/openshift
  source: registry.ci.openshift.org/openshift
- mirrors:
  - $bastion_private_ip:$registry_port/openshift
  source: registry.ci.openshift.org/origin
- mirrors:
  - $bastion_private_ip:$registry_port/openshift
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - $bastion_private_ip:$registry_port/openshift
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
EOF

    echo -e "${GREEN}✅ install-config.yaml created successfully${NC}"
    
    # Create additional configuration files for bootstrap compatibility
    create_bootstrap_configs "$install_dir" "$bastion_private_ip" "$registry_port" "$registry_user" "$registry_password"
}

# Function to create additional bootstrap configuration files
create_bootstrap_configs() {
    local install_dir="$1"
    local bastion_ip="$2"
    local registry_port="$3"
    local registry_user="$4"
    local registry_password="$5"
    
    echo -e "${BLUE}🔧 Creating additional bootstrap configuration files...${NC}"
    
    # Create registries.conf for bootstrap nodes
    cat > "$install_dir/registries.conf" <<EOF
unqualified-search-registries = ["$bastion_ip:$registry_port"]

[[registry]]
  location = "$bastion_ip:$registry_port"
  insecure = true
  prefix = ""

[[registry]]
  location = "registry.ci.openshift.org"
  insecure = false
  prefix = ""

[[registry]]
  location = "quay.io"
  insecure = false
  prefix = ""

[[registry.mirror]]
  location = "$bastion_ip:$registry_port"
  insecure = true

[[registry.mirror]]
  location = "$bastion_ip:$registry_port"
  insecure = true
EOF

    # Create hosts configuration for bootstrap nodes
    cat > "$install_dir/hosts-config.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-hosts-config
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(echo -e "127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4\n::1         localhost localhost.localdomain localhost6 localhost6.localdomain6\n$bastion_ip registry.ci.openshift.org\n$bastion_ip quay.io" | base64 -w 0)
        mode: 0644
        path: /etc/hosts
EOF

    # Create registry configuration for bootstrap nodes
    cat > "$install_dir/registry-config.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-registry-config
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(cat "$install_dir/registries.conf" | base64 -w 0)
        mode: 0644
        path: /etc/containers/registries.conf
EOF

    # Create authentication configuration for bootstrap nodes
    cat > "$install_dir/auth-config.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-auth-config
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(echo "{\"auths\":{\"$bastion_ip:$registry_port\":{\"auth\":\"$(echo -n "$registry_user:$registry_password" | base64)\"}}}" | base64 -w 0)
        mode: 0644
        path: /root/.docker/config.json
EOF

    # Create release-image configuration for bootstrap nodes
    cat > "$install_dir/release-image-config.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-release-image-config
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(echo -e "#!/usr/bin/env bash\n# This library provides an \`image_for\` helper function which can get the\n# pull spec for a specific image in a release.\n\n# 使用本地 registry mirror 而不是直接访问外部 registry\nRELEASE_IMAGE_DIGEST=\"$bastion_ip:$registry_port/openshift/ocp/release:4.19\"\n\nimage_for() {\n    # 直接使用本地 registry，避免网络访问\n    echo \"$bastion_ip:$registry_port/openshift/\${1}\"\n}" | base64 -w 0)
        mode: 0755
        path: /usr/local/bin/release-image.sh
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(echo -e "#!/usr/bin/env bash\nset -euo pipefail\n# Download the release image. This script is executed as a oneshot\n# service by systemd, because we cannot make use of Requires and a\n# simple service: https://github.com/systemd/systemd/issues/1312.\n#\n# This script continues trying to download the release image until\n# successful because we cannot use Restart=on-failure with a oneshot\n# service: https://github.com/systemd/systemd/issues/2582.\n#\n\n. /usr/local/bin/bootstrap-service-record.sh\n\n# 加载release-image.sh以获取正确的RELEASE_IMAGE_DIGEST\n. /usr/local/bin/release-image.sh\n\n# 使用release-image.sh中定义的RELEASE_IMAGE_DIGEST\nRELEASE_IMAGE=\"\$RELEASE_IMAGE_DIGEST\"\n\n# Registry认证信息\nREGISTRY_USER=\"$registry_user\"\nREGISTRY_PASSWORD=\"$registry_password\"\nREGISTRY_URL=\"$bastion_ip:$registry_port\"\n\nrelease_image_issue=\"/etc/issue.d/50_release-image.issue\"\n\n# 确保已登录到registry\nif ! podman login --username \"\$REGISTRY_USER\" --password \"\$REGISTRY_PASSWORD\" --tls-verify=false \"\$REGISTRY_URL\" >/dev/null 2>&1; then\n    echo \"Registry登录失败，尝试重新登录...\"\n    podman login --username \"\$REGISTRY_USER\" --password \"\$REGISTRY_PASSWORD\" --tls-verify=false \"\$REGISTRY_URL\"\nfi\n\nif podman image exists \"\$RELEASE_IMAGE\"; then\n    echo \"Release image already exists, skipping download\"\n    exit 0\nfi\n\nwhile true; do\n    echo \"Pulling \$RELEASE_IMAGE...\"\n    if podman pull --tls-verify=false \"\$RELEASE_IMAGE\"; then\n        echo \"Release image downloaded successfully\"\n        break\n    else\n        echo \"Pull failed. Retrying \$RELEASE_IMAGE...\"\n        sleep 10\n        # 重新登录registry\n        if ! podman login --username \"\$REGISTRY_USER\" --password \"\$REGISTRY_PASSWORD\" --tls-verify=false \"\$REGISTRY_URL\" >/dev/null 2>&1; then\n            podman login --username \"\$REGISTRY_USER\" --password \"\$REGISTRY_PASSWORD\" --tls-verify=false \"\$REGISTRY_URL\"\n        fi\n    fi\ndone" | base64 -w 0)
        mode: 0755
        path: /usr/local/bin/release-image-download.sh
EOF

    echo -e "${GREEN}✅ Additional bootstrap configuration files created${NC}"
    echo "   - registries.conf: Container registry configuration"
    echo "   - hosts-config.yaml: Hosts file configuration"
    echo "   - registry-config.yaml: Registry configuration for OpenShift"
    echo "   - auth-config.yaml: Authentication configuration"
    echo "   - release-image-config.yaml: Release image configuration"
}

# Function to check registry status
check_registry_status() {
    local registry_port="$1"
    
    echo -e "${BLUE}🔍 Checking registry status...${NC}"
    
    # Get bastion private IP for registry access
    local bastion_private_ip
    if [[ -f "infra-output/bastion-instance-id" ]]; then
        local bastion_instance_id=$(cat infra-output/bastion-instance-id)
        local region=$(cat infra-output/region 2>/dev/null || echo "us-east-1")
        bastion_private_ip=$(aws ec2 describe-instances \
            --instance-ids "$bastion_instance_id" \
            --region "$region" \
            --query 'Reservations[0].Instances[0].PrivateIpAddress' \
            --output text)
    else
        # Fallback: get from current instance if running on bastion
        bastion_private_ip=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo "localhost")
    fi
    
    local registry_url="${bastion_private_ip}:${registry_port}"
    
    # Check if registry container is running
    if sudo -E podman ps --format "table {{.Names}}" | grep -q "registry"; then
        echo -e "${GREEN}✅ Registry container is running${NC}"
    else
        echo -e "${YELLOW}⚠️  Registry container is not running${NC}"
        echo "   Run: ./05-setup-mirror-registry.sh to start the registry"
        return 1
    fi
    
    # Check if registry is accessible
    if curl -k -s -u admin:admin123 "https://${registry_url}/v2/_catalog" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Registry is accessible on ${registry_url}${NC}"
    else
        echo -e "${YELLOW}⚠️  Registry is not accessible on ${registry_url}${NC}"
        echo "   Check if the registry is properly configured and running"
        return 1
    fi
    
    # Check for critical bootstrap images
    echo -e "${BLUE}🔍 Checking critical bootstrap images...${NC}"
    local missing_critical_images=()
    
    # Check for ocp/release image (critical for bootstrap)
    if ! curl -k -s -u admin:admin123 "https://${registry_url}/v2/openshift/ocp/release/tags/list" 2>/dev/null | grep -q "4.19"; then
        missing_critical_images+=("ocp/release:4.19")
    fi
    
    # Check for installer image
    if ! curl -k -s -u admin:admin123 "https://${registry_url}/v2/openshift/installer/tags/list" 2>/dev/null | grep -q "4.19"; then
        missing_critical_images+=("installer:4.19")
    fi
    
    # Check for CLI image
    if ! curl -k -s -u admin:admin123 "https://${registry_url}/v2/openshift/cli/tags/list" 2>/dev/null | grep -q "4.19"; then
        missing_critical_images+=("cli:4.19")
    fi
    
    if [[ ${#missing_critical_images[@]} -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Missing critical bootstrap images:${NC}"
        printf '   - %s\n' "${missing_critical_images[@]}"
        echo ""
        echo -e "${YELLOW}🔧 Run ./06-sync-images-robust.sh to sync missing images${NC}"
        return 1
    else
        echo -e "${GREEN}✅ All critical bootstrap images are present${NC}"
    fi
}

# Function to install OpenShift installer from local registry
install_openshift_installer() {
    local registry_url="$1"
    local registry_user="$2"
    local registry_password="$3"
    local openshift_version="$4"
    
    echo -e "${BLUE}🔧 Installing OpenShift installer from local registry...${NC}"
    
    # Check if installer image exists in local registry
    if ! curl -k -s -u "${registry_user}:${registry_password}" "https://${registry_url}/v2/openshift/installer/tags/list" | grep -q "${openshift_version}"; then
        echo -e "${RED}❌ OpenShift installer image not found in local registry${NC}"
        echo "   Run ./06-sync-images-robust.sh to sync the installer image first"
        return 1
    fi
    
    # Pull installer image from local registry
    echo -e "${BLUE}📥 Pulling installer image from local registry...${NC}"
    if ! sudo -E podman pull "${registry_url}/openshift/installer:${openshift_version}" --tls-verify=false; then
        echo -e "${RED}❌ Failed to pull installer image${NC}"
        return 1
    fi
    
    # Extract installer binary from container
    echo -e "${BLUE}🔧 Extracting installer binary...${NC}"
    local temp_container="temp-installer-$$"
    
    if ! sudo -E podman create --name "${temp_container}" "${registry_url}/openshift/installer:${openshift_version}"; then
        echo -e "${RED}❌ Failed to create temporary container${NC}"
        return 1
    fi
    
    # Copy installer binary
    if ! sudo -E podman cp "${temp_container}:/usr/bin/openshift-install" ./openshift-install; then
        echo -e "${RED}❌ Failed to copy installer binary${NC}"
        sudo -E podman rm "${temp_container}" &> /dev/null
        return 1
    fi
    
    # Clean up temporary container
    sudo -E podman rm "${temp_container}" &> /dev/null
    
    # Set permissions and move to PATH
    sudo chmod +x ./openshift-install
    sudo mv ./openshift-install /usr/local/bin/
    
    echo -e "${GREEN}✅ OpenShift installer installed successfully${NC}"
    openshift-install version
    
    # Clean up installer image to save space
    sudo -E podman rmi "${registry_url}/openshift/installer:${openshift_version}" &> /dev/null || true
    
    return 0
}

# Function to check OpenShift installer availability
check_installer() {
    local install_dir="$1"
    local registry_url="$2"
    local registry_user="$3"
    local registry_password="$4"
    local openshift_version="$5"
    
    echo -e "${BLUE}🔍 Checking OpenShift installer availability...${NC}"
    
    if command -v openshift-install &> /dev/null; then
        echo -e "${GREEN}✅ OpenShift installer found in PATH${NC}"
        openshift-install version
    elif [[ -f "$install_dir/openshift-install" ]]; then
        echo -e "${GREEN}✅ OpenShift installer found in installation directory${NC}"
        "$install_dir/openshift-install" version
    else
        echo -e "${YELLOW}⚠️  OpenShift installer not found, attempting to install...${NC}"
        
        # Try to install from local registry
        if install_openshift_installer "${registry_url}" "${registry_user}" "${registry_password}" "${openshift_version}"; then
            echo -e "${GREEN}✅ OpenShift installer installed successfully${NC}"
        else
            echo -e "${RED}❌ Failed to install OpenShift installer${NC}"
            echo "   Please ensure the installer image is available in the local registry"
            echo "   Run ./06-sync-images-robust.sh to sync all required images"
            return 1
        fi
    fi
}

# Function to validate and fix install-config.yaml
validate_install_config() {
    local install_dir="$1"
    
    echo -e "${BLUE}🔍 Validating install-config.yaml...${NC}"
    
    # Check if install-config.yaml exists and is valid YAML
    if [[ -f "$install_dir/install-config.yaml" ]]; then
        # Validate YAML syntax
        if yq eval '.' "$install_dir/install-config.yaml" > /dev/null; then
            echo -e "${GREEN}✅ install-config.yaml validation passed${NC}"
        else
            echo -e "${RED}❌ install-config.yaml has invalid YAML syntax${NC}"
            exit 1
        fi
        
        # Check and fix registry URL if needed
        if grep -q "registry\..*\.local:5000" "$install_dir/install-config.yaml"; then
            echo -e "${YELLOW}⚠️  Fixing registry URL to use localhost...${NC}"
            sed -i 's/registry\.[^.]*\.local:5000/localhost:5000/g' "$install_dir/install-config.yaml"
            echo -e "${GREEN}✅ Registry URL fixed to use localhost${NC}"
        fi
        
        # Verify registry connectivity
        echo -e "${BLUE}🔍 Verifying registry connectivity...${NC}"
        if curl -k -s -u admin:admin123 https://localhost:5000/v2/_catalog > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Registry is accessible${NC}"
        else
            echo -e "${YELLOW}⚠️  Registry may not be accessible - check if it's running${NC}"
        fi
        
        # Verify imageContentSources configuration
        echo -e "${BLUE}🔍 Verifying imageContentSources configuration...${NC}"
        if grep -q "registry.ci.openshift.org/origin" "$install_dir/install-config.yaml"; then
            echo -e "${GREEN}✅ origin source mapping found${NC}"
        else
            echo -e "${RED}❌ Missing origin source mapping - this will cause bootstrap failures${NC}"
            echo "   Bootstrap nodes need registry.ci.openshift.org/origin -> localhost:5000/openshift mapping"
            exit 1
        fi
        
        if grep -q "registry.ci.openshift.org/ocp/4.19" "$install_dir/install-config.yaml"; then
            echo -e "${GREEN}✅ ocp/4.19 source mapping found${NC}"
        else
            echo -e "${RED}❌ Missing ocp/4.19 source mapping${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ install-config.yaml not found${NC}"
        exit 1
    fi
}

# Function to backup install-config.yaml
backup_install_config() {
    local install_dir="$1"
    
    echo -e "${BLUE}💾 Backing up install-config.yaml...${NC}"
    
    if [[ -f "$install_dir/install-config.yaml" ]]; then
        cp "$install_dir/install-config.yaml" "$install_dir/install-config.yaml.backup"
        echo -e "${GREEN}✅ install-config.yaml backed up to install-config.yaml.backup${NC}"
    else
        echo -e "${YELLOW}⚠️  install-config.yaml not found, skipping backup${NC}"
    fi
}

# Function to create and validate manifests
create_and_validate_manifests() {
    local install_dir="$1"
    
    echo -e "${BLUE}🔧 Creating manifests...${NC}"
    
    # Create manifests
    if AWS_PROFILE=static openshift-install create manifests --dir="$install_dir"; then
        echo -e "${GREEN}✅ Manifests created successfully${NC}"
    else
        echo -e "${RED}❌ Failed to create manifests${NC}"
        exit 1
    fi
    
    # Validate key manifest files
    echo -e "${BLUE}🔍 Validating key manifest files...${NC}"
    
    # Check if manifests directory exists
    if [[ ! -d "$install_dir/manifests" ]]; then
        echo -e "${RED}❌ Manifests directory not found${NC}"
        exit 1
    fi
    
    # Validate image content source policy
    if [[ -f "$install_dir/manifests/image-content-source-policy.yaml" ]]; then
        echo -e "${GREEN}✅ Image content source policy created${NC}"
        # Verify it contains localhost:5000
        if grep -q "localhost:5000" "$install_dir/manifests/image-content-source-policy.yaml"; then
            echo -e "${GREEN}✅ Image content source policy contains localhost:5000${NC}"
        else
            echo -e "${RED}❌ Image content source policy missing localhost:5000${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ Image content source policy not found${NC}"
        exit 1
    fi
    
    # Validate pull secret
    if [[ -f "$install_dir/manifests/openshift-config-secret-pull-secret.yaml" ]]; then
        echo -e "${GREEN}✅ Pull secret manifest created${NC}"
        # Verify it contains localhost:5000 (check base64 decoded content)
        local dockerconfig=$(grep "\.dockerconfigjson:" "$install_dir/manifests/openshift-config-secret-pull-secret.yaml" | awk '{print $2}')
        if echo "$dockerconfig" | base64 -d | grep -q "localhost:5000"; then
            echo -e "${GREEN}✅ Pull secret contains localhost:5000${NC}"
        else
            echo -e "${RED}❌ Pull secret missing localhost:5000${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ Pull secret manifest not found${NC}"
        exit 1
    fi
    
    # List all manifest files
    echo -e "${BLUE}📋 Generated manifest files:${NC}"
    ls -la "$install_dir/manifests/"
    
    echo -e "${GREEN}✅ Manifest validation completed${NC}"
}

# Function to apply bootstrap configurations
apply_bootstrap_configs() {
    local install_dir="$1"
    
    echo -e "${BLUE}🔧 Applying bootstrap configurations...${NC}"
    
    # Create manifests directory if it doesn't exist
    mkdir -p "$install_dir/manifests"
    
    # Create hosts MachineConfig
    cat > "$install_dir/manifests/99-hosts-config.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-hosts-config
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(echo -e "127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4\n::1         localhost localhost.localdomain localhost6 localhost6.localdomain6\n10.0.10.10 registry.ci.openshift.org\n10.0.10.10 quay.io" | base64 -w 0)
        mode: 0644
        path: /etc/hosts
EOF

    # Create registry MachineConfig
    cat > "$install_dir/manifests/99-registry-config.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-registry-config
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(cat "$install_dir/registries.conf" | base64 -w 0)
        mode: 0644
        path: /etc/containers/registries.conf
EOF

    # Create authentication MachineConfig
    cat > "$install_dir/manifests/99-auth-config.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-auth-config
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(echo "{\"auths\":{\"10.0.10.10:5000\":{\"auth\":\"$(echo -n "admin:admin123" | base64)\"}}}" | base64 -w 0)
        mode: 0644
        path: /root/.docker/config.json
EOF

    # Create release-image-download script
    cat > "$install_dir/release-image-download.sh" <<EOF
#!/bin/bash
set -e

echo "Downloading OpenShift release image from local registry..."

# Pull the release image from local registry
podman pull --tls-verify=false --authfile=/root/.docker/config.json 10.0.10.10:5000/openshift/ocp/release:4.19

# Extract the openshift-install binary
podman run --rm --authfile=/root/.docker/config.json 10.0.10.5000/openshift/ocp/release:4.19 /usr/bin/openshift-install version

echo "Release image download completed"
EOF

    chmod +x "$install_dir/release-image-download.sh"

    # Create release-image service MachineConfig
    cat > "$install_dir/manifests/99-release-image-service.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-release-image-service
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(cat "$install_dir/release-image-download.sh" | base64 -w 0)
        mode: 0755
        path: /usr/local/bin/release-image-download.sh
    systemd:
      units:
      - name: release-image.service
        enabled: true
        contents: |
          [Unit]
          Description=Download the OpenShift Release Image
          Before=bootkube.service
          After=network-online.target
          Wants=network-online.target
          
          [Service]
          Type=oneshot
          ExecStart=/usr/local/bin/release-image-download.sh
          StandardOutput=journal
          StandardError=journal
          
          [Install]
          WantedBy=multi-user.target
EOF

    echo -e "${GREEN}✅ Bootstrap MachineConfig files created in manifests directory${NC}"
    
    # List all bootstrap configuration files
    echo -e "${BLUE}📋 Bootstrap configuration files:${NC}"
    ls -la "$install_dir/manifests/" | grep -E "(hosts|registry|auth|release)"
    
    echo -e "${GREEN}✅ Bootstrap configurations applied successfully${NC}"
}

# Function to create tool installation MachineConfig
create_tool_installation_config() {
    local install_dir="$1"
    local bastion_ip="$2"
    local registry_port="$3"
    local registry_user="$4"
    local registry_password="$5"
    
    echo -e "${BLUE}🔧 Creating tool installation MachineConfig...${NC}"
    
    # Create script to extract and install binaries
    cat > "$install_dir/extract-tools.sh" <<EOF
#!/bin/bash
set -e

echo "Extracting and installing OpenShift tools from local registry..."

REGISTRY_URL="${bastion_ip}:${registry_port}"
REGISTRY_USER="${registry_user}"
REGISTRY_PASSWORD="${registry_password}"

# Login to registry
podman login --username "\$REGISTRY_USER" --password "\$REGISTRY_PASSWORD" --tls-verify=false "\$REGISTRY_URL"

# Extract oc binary from cli image
if podman image exists "\$REGISTRY_URL/openshift/cli:4.19.2"; then
    echo "Extracting oc binary..."
    podman create --name temp-cli "\$REGISTRY_URL/openshift/cli:4.19.2"
    podman cp temp-cli:/usr/bin/oc /tmp/oc
    podman rm temp-cli
    mv /tmp/oc /usr/local/bin/oc
    chmod +x /usr/local/bin/oc
    echo "oc binary installed successfully"
    /usr/local/bin/oc version --client
else
    echo "cli:4.19.2 image not found, trying alternative tags..."
    # Try alternative tags
    for tag in "4.19.0" "latest"; do
        if podman image exists "\$REGISTRY_URL/openshift/cli:\$tag"; then
            echo "Extracting oc binary from cli:\$tag..."
            podman create --name temp-cli "\$REGISTRY_URL/openshift/cli:\$tag"
            podman cp temp-cli:/usr/bin/oc /tmp/oc
            podman rm temp-cli
            mv /tmp/oc /usr/local/bin/oc
            chmod +x /usr/local/bin/oc
            echo "oc binary installed successfully from tag \$tag"
            break
        fi
    done
fi

# Extract installer binary from installer image
if podman image exists "\$REGISTRY_URL/openshift/installer:4.19.2"; then
    echo "Extracting installer binary..."
    podman create --name temp-installer "\$REGISTRY_URL/openshift/installer:4.19.2"
    podman cp temp-installer:/usr/bin/openshift-install /tmp/openshift-install
    podman rm temp-installer
    mv /tmp/openshift-install /usr/local/bin/openshift-install
    chmod +x /usr/local/bin/openshift-install
    echo "openshift-install binary installed successfully"
    /usr/local/bin/openshift-install version
else
    echo "installer:4.19.2 image not found, trying alternative tags..."
    # Try alternative tags
    for tag in "4.19.0" "latest"; do
        if podman image exists "\$REGISTRY_URL/openshift/installer:\$tag"; then
            echo "Extracting installer binary from installer:\$tag..."
            podman create --name temp-installer "\$REGISTRY_URL/openshift/installer:\$tag"
            podman cp temp-installer:/usr/bin/openshift-install /tmp/openshift-install
            podman rm temp-installer
            mv /tmp/openshift-install /usr/local/bin/openshift-install
            chmod +x /usr/local/bin/openshift-install
            echo "openshift-install binary installed successfully from tag \$tag"
            break
        fi
    done
fi

echo "Tool extraction and installation completed"
EOF

    chmod +x "$install_dir/extract-tools.sh"

    # Create MachineConfig for tool installation
    cat > "$install_dir/manifests/99-tool-installation.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-tool-installation
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(cat "$install_dir/extract-tools.sh" | base64 -w 0)
        mode: 0755
        path: /usr/local/bin/extract-tools.sh
    systemd:
      units:
      - name: tool-installation.service
        enabled: true
        contents: |
          [Unit]
          Description=Install OpenShift tools from local registry
          After=network-online.target
          Before=bootkube.service
          Wants=network-online.target
          
          [Service]
          Type=oneshot
          ExecStart=/usr/local/bin/extract-tools.sh
          StandardOutput=journal
          StandardError=journal
          TimeoutStartSec=300
          
          [Install]
          WantedBy=multi-user.target
EOF

    echo -e "${GREEN}✅ Tool installation MachineConfig created${NC}"
    echo "   - extract-tools.sh: Script to extract oc/installer binaries"
    echo "   - 99-tool-installation.yaml: MachineConfig to run tool installation"
}

# Main execution
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --base-domain)
                BASE_DOMAIN="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --registry-port)
                REGISTRY_PORT="$2"
                shift 2
                ;;
            --registry-user)
                REGISTRY_USER="$2"
                shift 2
                ;;
            --registry-password)
                REGISTRY_PASSWORD="$2"
                shift 2
                ;;
            --install-dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            --ssh-key)
                SSH_KEY="$2"
                shift 2
                ;;
            --pull-secret)
                PULL_SECRET="$2"
                shift 2
                ;;
            --infra-output-dir)
                INFRA_OUTPUT_DIR="$2"
                shift 2
                ;;
            --sync-output-dir)
                SYNC_OUTPUT_DIR="$2"
                shift 2
                ;;

            --dry-run)
                DRY_RUN="yes"
                shift
                ;;
            --help)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done
    
    # Set default values
    CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
    BASE_DOMAIN=${BASE_DOMAIN:-$DEFAULT_BASE_DOMAIN}
    REGION=${REGION:-$DEFAULT_REGION}
    REGISTRY_PORT=${REGISTRY_PORT:-$DEFAULT_REGISTRY_PORT}
    REGISTRY_USER=${REGISTRY_USER:-$DEFAULT_REGISTRY_USER}
    REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-$DEFAULT_REGISTRY_PASSWORD}
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}
    SSH_KEY=${SSH_KEY:-$DEFAULT_SSH_KEY}
    PULL_SECRET=${PULL_SECRET:-}
    INFRA_OUTPUT_DIR=${INFRA_OUTPUT_DIR:-$DEFAULT_INFRA_OUTPUT_DIR}
    SYNC_OUTPUT_DIR=${SYNC_OUTPUT_DIR:-$DEFAULT_SYNC_OUTPUT_DIR}
    OPENSHIFT_VERSION=${OPENSHIFT_VERSION:-$DEFAULT_OPENSHIFT_VERSION}

    DRY_RUN=${DRY_RUN:-no}
    BASTION_KEY=${BASTION_KEY:-$DEFAULT_BASTION_KEY}
    
    # Display script header
    echo -e "${BLUE}📝 Install Config Preparation for Disconnected OpenShift Cluster${NC}"
    echo "==============================================================="
    echo ""
    echo -e "${BLUE}📋 Configuration:${NC}"
    echo "   Cluster Name: $CLUSTER_NAME"
    echo "   Base Domain: $BASE_DOMAIN"
    echo "   Region: $REGION"
    echo "   Registry URL: localhost:$REGISTRY_PORT"
    echo "   Installation Directory: $INSTALL_DIR"
    echo "   SSH Key: $SSH_KEY"
    echo "   Dry Run: $DRY_RUN"
    echo ""
    
    # Check if running on bastion host
    if is_bastion_host; then
        echo -e "${BLUE}🔧 Running on bastion host - preparing install config...${NC}"
        
        # Check prerequisites
        check_prerequisites
        
        # Get infrastructure information
        read -r region vpc_id private_subnet_ids public_subnet_ids < <(get_infrastructure_info)
        
        # Get SSH key
        local ssh_key_content=$(get_ssh_key "$SSH_KEY")
        
        # Get pull secret
        local pull_secret_content=$(get_pull_secret "$PULL_SECRET" "$CLUSTER_NAME" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD")
        
        # Get registry certificate
        echo -e "${BLUE}📥 Getting registry certificate...${NC}"
        local registry_cert=$(sudo cat /opt/registry/certs/domain.crt)
        
        # Create install-config.yaml
        create_install_config "$CLUSTER_NAME" "$BASE_DOMAIN" "$region" "$vpc_id" "$private_subnet_ids" "$public_subnet_ids" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD" "$ssh_key_content" "$pull_secret_content" "$registry_cert" "$INSTALL_DIR"
        
        # Check registry status
        check_registry_status "$REGISTRY_PORT"
        
        # Check OpenShift installer availability
        check_installer "$INSTALL_DIR" "localhost:$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD" "$OPENSHIFT_VERSION"
        
        # Backup install-config.yaml before it gets consumed
        backup_install_config "$INSTALL_DIR"
        
        # Validate install-config.yaml
        validate_install_config "$INSTALL_DIR"
        
        # Create and validate manifests
        create_and_validate_manifests "$INSTALL_DIR"
        
        # Apply bootstrap configurations
        apply_bootstrap_configs "$INSTALL_DIR"
        
        # Create tool installation MachineConfig
        create_tool_installation_config "$INSTALL_DIR" "$bastion_private_ip" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"
        
        echo ""
        echo -e "${GREEN}✅ Install config preparation completed on bastion host!${NC}"
        echo ""
        echo -e "${BLUE}🚀 To start cluster installation:${NC}"
        echo "   cd $INSTALL_DIR"
        echo "   ./openshift-install create cluster --log-level=info"
        echo ""
        echo -e "${BLUE}🔍 Registry Status:${NC}"
        echo "   - Registry URL: localhost:$REGISTRY_PORT"
        echo "   - Registry should be accessible and contain OpenShift images"
        echo "   - If registry issues occur, run: ./02-setup-mirror-registry.sh"
        echo ""
        echo -e "${BLUE}📋 Manifest Status:${NC}"
        echo "   - Manifests created and validated in $INSTALL_DIR/manifests/"
        echo "   - install-config.yaml backed up to install-config.yaml.backup"
        echo "   - Image content source policy and pull secret verified"
        echo "   - Tool installation MachineConfig created for automatic oc/installer setup"
        echo ""
        echo -e "${YELLOW}📝 Important notes:${NC}"
        echo "   - Cluster will be installed in SNO (Single Node OpenShift) mode"
        echo "   - 1 master node, 0 worker nodes for simplified deployment"
        echo "   - All images will be pulled from local registry"
        echo "   - oc/installer tools will be automatically extracted and installed"
        echo "   - Installation may take 20-30 minutes (faster than multi-node)"
        echo "   - Check logs for any issues during installation"
    else
        echo -e "${RED}❌ This script must be run on the bastion host${NC}"
        echo "Please copy this script to the bastion host and run it there"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"