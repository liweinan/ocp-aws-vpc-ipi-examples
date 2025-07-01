#!/bin/bash

# Install Config Preparation Script for Disconnected OpenShift Cluster
# This script can run locally to copy itself to bastion, or directly on bastion host

set -euo pipefail

# Set AWS_PROFILE to static if not already set
export AWS_PROFILE=${AWS_PROFILE:-static}

# Default values
DEFAULT_CLUSTER_NAME="disconnected-cluster"
DEFAULT_INFRA_OUTPUT_DIR="./infra-output"
DEFAULT_SYNC_OUTPUT_DIR="./sync-output"
DEFAULT_BASE_DOMAIN="example.com"
DEFAULT_REGION="us-east-1"
DEFAULT_REGISTRY_PORT="5000"
DEFAULT_REGISTRY_USER="admin"
DEFAULT_REGISTRY_PASSWORD="admin123"
DEFAULT_INSTALL_DIR="./openshift-install"
DEFAULT_SSH_KEY="~/.ssh/id_rsa.pub"
DEFAULT_BASTION_KEY="./infra-output/bastion-key.pem"

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
    
    # 只输出 JSON，不输出提示
    if [[ -f "/home/ubuntu/pull-secret.json" ]]; then
        cat "/home/ubuntu/pull-secret.json"
    elif [[ -n "$pull_secret_input" ]]; then
        if [[ -f "$pull_secret_input" ]]; then
            cat "$pull_secret_input"
        else
            echo "$pull_secret_input"
        fi
    else
        local auth_string=$(echo -n "${registry_user}:${registry_password}" | base64)
        echo "{\"auths\":{\"registry.${cluster_name}.local:${registry_port}\":{\"auth\":\"${auth_string}\"}}}"
    fi
}

# Function to get infrastructure information
get_infrastructure_info() {
    if [[ -f "$INFRA_OUTPUT_DIR/vpc-id" ]]; then
        local region=$(cat "$INFRA_OUTPUT_DIR/region")
        local vpc_id=$(cat "$INFRA_OUTPUT_DIR/vpc-id")
        local private_subnet_ids=$(cat "$INFRA_OUTPUT_DIR/private-subnet-ids")
        echo -e "$region\n$vpc_id\n$private_subnet_ids"
    else
        local region=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
        local instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
        local vpc_id=$(aws ec2 describe-instances --instance-ids "$instance_id" --region "$region" --query 'Reservations[0].Instances[0].VpcId' --output text)
        local private_subnet_ids=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:kubernetes.io/role/internal-elb,Values=1" --region "$region" --query 'Subnets[].SubnetId' --output text | tr '\t' ',')
        echo -e "$region\n$vpc_id\n$private_subnet_ids"
    fi
}

# Function to create install-config.yaml
create_install_config() {
    local cluster_name="$1"
    local base_domain="$2"
    local region="$3"
    local vpc_id="$4"
    local private_subnet_ids="$5"
    local registry_port="$6"
    local registry_user="$7"
    local registry_password="$8"
    local ssh_key_content="$9"
    local pull_secret_content="${10}"
    local registry_cert="${11}"
    local install_dir="${12}"
    
    echo -e "${BLUE}📝 Creating install-config.yaml...${NC}"
    
    # Create installation directory
    mkdir -p "$install_dir"
    
    # Create install-config.yaml
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
  replicas: 0
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      type: m5.xlarge
  replicas: 1
metadata:
  name: $cluster_name
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: $region
    subnets:
EOF
    
    # Add private subnet IDs
    for subnet_id in $(echo "$private_subnet_ids" | tr ',' ' '); do
        echo "    - $subnet_id" >> "$install_dir/install-config.yaml"
    done
    
    # Continue with the rest of the config
    cat >> "$install_dir/install-config.yaml" <<EOF
    vpc: $vpc_id
publish: Internal
pullSecret: '$pull_secret_content'
sshKey: |
$(echo "$ssh_key_content" | sed 's/^/  /')
additionalTrustBundle: |
$(echo "$registry_cert" | sed 's/^/  /')
imageContentSources:
- mirrors:
  - registry.$cluster_name.local:$registry_port/openshift/release
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - registry.$cluster_name.local:$registry_port/openshift/release
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
EOF
    
    echo -e "${GREEN}✅ install-config.yaml created${NC}"
}

# Function to download OpenShift installer from local registry
download_installer() {
    local install_dir="$1"
    local cluster_name="$2"
    local registry_port="$3"
    
    if [[ ! -f "$install_dir/openshift-install" ]]; then
        echo -e "${BLUE}📥 Downloading OpenShift installer from local registry...${NC}"
        cd "$install_dir"
        
        # Pull installer image from local registry
        podman pull registry.${cluster_name}.local:${registry_port}/openshift/release:4.18.15-x86_64-installer
        
        # Extract installer binary from image
        podman run --rm -v .:/output registry.${cluster_name}.local:${registry_port}/openshift/release:4.18.15-x86_64-installer cp /usr/bin/openshift-install /output/
        
        chmod +x openshift-install
        echo -e "${GREEN}✅ OpenShift installer downloaded from local registry${NC}"
    else
        echo -e "${GREEN}✅ OpenShift installer already exists${NC}"
    fi
}

# Function to validate install-config.yaml
validate_install_config() {
    local install_dir="$1"
    
    echo -e "${BLUE}🔍 Validating install-config.yaml...${NC}"
    cd "$install_dir"
    
    # Check if install-config.yaml exists and is valid YAML
    if [[ -f "install-config.yaml" ]]; then
        yq eval '.' install-config.yaml > /dev/null
        echo -e "${GREEN}✅ install-config.yaml validation passed${NC}"
    else
        echo -e "${RED}❌ install-config.yaml not found${NC}"
        exit 1
    fi
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
    echo "   Registry URL: registry.$CLUSTER_NAME.local:$REGISTRY_PORT"
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
        read -r region vpc_id private_subnet_ids < <(get_infrastructure_info)
        
        # Get SSH key
        local ssh_key_content=$(get_ssh_key "$SSH_KEY")
        
        # Get pull secret
        local pull_secret_content=$(get_pull_secret "$PULL_SECRET" "$CLUSTER_NAME" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD")
        
        # Get registry certificate
        echo -e "${BLUE}📥 Getting registry certificate...${NC}"
        local registry_cert=$(sudo cat /opt/registry/certs/domain.crt)
        
        # Create install-config.yaml
        create_install_config "$CLUSTER_NAME" "$BASE_DOMAIN" "$region" "$vpc_id" "$private_subnet_ids" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD" "$ssh_key_content" "$pull_secret_content" "$registry_cert" "$INSTALL_DIR"
        
        # Download OpenShift installer
        download_installer "$INSTALL_DIR" "$CLUSTER_NAME" "$REGISTRY_PORT"
        
        # Validate install-config.yaml
        validate_install_config "$INSTALL_DIR"
        
        echo ""
        echo -e "${GREEN}✅ Install config preparation completed on bastion host!${NC}"
        echo ""
        echo -e "${BLUE}🚀 To start cluster installation:${NC}"
        echo "   cd $INSTALL_DIR"
        echo "   ./openshift-install create cluster --log-level=info"
        echo ""
        echo -e "${YELLOW}📝 Important notes:${NC}"
        echo "   - Cluster will be installed in SNO (Single Node OpenShift) mode"
        echo "   - 1 master node, 0 worker nodes for simplified deployment"
        echo "   - All images will be pulled from local registry"
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