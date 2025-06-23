#!/bin/bash

# OpenShift Cluster Deployment Script
# Uses VPC output from create-vpc.sh to deploy OpenShift IPI cluster

set -euo pipefail

# Default values
DEFAULT_VPC_OUTPUT_DIR="./vpc-output"
DEFAULT_CLUSTER_NAME="my-cluster"
DEFAULT_BASE_DOMAIN="example.com"
DEFAULT_OPENSHIFT_VERSION="4.18.15"
DEFAULT_INSTALL_DIR="./openshift-install"
DEFAULT_PULL_SECRET_FILE=""
DEFAULT_SSH_KEY_FILE=""

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --vpc-output-dir      Directory containing VPC output files (default: $DEFAULT_VPC_OUTPUT_DIR)"
    echo "  --cluster-name        OpenShift cluster name (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --base-domain         Base domain for the cluster (default: $DEFAULT_BASE_DOMAIN)"
    echo "  --openshift-version   OpenShift version to install (default: $DEFAULT_OPENSHIFT_VERSION)"
    echo "  --install-dir         Installation directory (default: $DEFAULT_INSTALL_DIR)"
    echo "  --pull-secret         Red Hat pull secret (as string)"
    echo "  --pull-secret-file    Path to file containing Red Hat pull secret"
    echo "  --ssh-key             SSH public key (as string)"
    echo "  --ssh-key-file        Path to SSH public key file"
    echo "  --compute-nodes       Number of compute nodes (default: 3)"
    echo "  --control-plane-nodes Number of control plane nodes (default: 3)"
    echo "  --compute-instance-type Compute node instance type (default: m5.xlarge)"
    echo "  --control-plane-instance-type Control plane instance type (default: m5.xlarge)"
    echo "  --publish-strategy    Publish strategy: External or Internal (default: Internal)"
    echo "  --network-type        Network type: OpenShiftSDN or OVNKubernetes (default: OVNKubernetes)"
    echo "  --dry-run             Generate install-config.yaml only, don't install"
    echo "  --help                Display this help message"
    exit 1
}

# Function to check if OpenShift installer is available
check_openshift_installer() {
    if command -v openshift-install &> /dev/null; then
        echo "✅ OpenShift installer found in PATH: $(which openshift-install)"
        return 0
    fi
    return 1
}

# Function to read file contents
read_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "Error: File not found: $file"
        exit 1
    fi
    cat "$file"
}

# Function to validate VPC output
validate_vpc_output() {
    local vpc_dir="$1"
    
    required_files=("vpc-id" "private-subnet-ids" "availability-zones" "vpc-summary.txt")
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$vpc_dir/$file" ]]; then
            echo "Error: Required VPC output file not found: $vpc_dir/$file"
            echo "Please run create-vpc.sh first to generate VPC output"
            exit 1
        fi
    done
}

# Function to get AWS region from VPC output
get_region_from_vpc() {
    local vpc_dir="$1"
    local summary_file="$vpc_dir/vpc-summary.txt"
    
    if [[ -f "$summary_file" ]]; then
        grep "^Region:" "$summary_file" | awk '{print $2}'
    else
        echo "us-east-1"  # fallback
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --vpc-output-dir)
            VPC_OUTPUT_DIR="$2"
            shift 2
            ;;
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --base-domain)
            BASE_DOMAIN="$2"
            shift 2
            ;;
        --openshift-version)
            OPENSHIFT_VERSION="$2"
            shift 2
            ;;
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --pull-secret)
            PULL_SECRET="$2"
            shift 2
            ;;
        --pull-secret-file)
            PULL_SECRET=$(read_file "$2")
            shift 2
            ;;
        --ssh-key)
            SSH_KEY="$2"
            shift 2
            ;;
        --ssh-key-file)
            SSH_KEY=$(read_file "$2")
            shift 2
            ;;
        --compute-nodes)
            COMPUTE_NODES="$2"
            shift 2
            ;;
        --control-plane-nodes)
            CONTROL_PLANE_NODES="$2"
            shift 2
            ;;
        --compute-instance-type)
            COMPUTE_INSTANCE_TYPE="$2"
            shift 2
            ;;
        --control-plane-instance-type)
            CONTROL_PLANE_INSTANCE_TYPE="$2"
            shift 2
            ;;
        --publish-strategy)
            PUBLISH_STRATEGY="$2"
            shift 2
            ;;
        --network-type)
            NETWORK_TYPE="$2"
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

# Set default values if not provided
VPC_OUTPUT_DIR=${VPC_OUTPUT_DIR:-$DEFAULT_VPC_OUTPUT_DIR}
CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
BASE_DOMAIN=${BASE_DOMAIN:-$DEFAULT_BASE_DOMAIN}
OPENSHIFT_VERSION=${OPENSHIFT_VERSION:-$DEFAULT_OPENSHIFT_VERSION}
INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}
COMPUTE_NODES=${COMPUTE_NODES:-3}
CONTROL_PLANE_NODES=${CONTROL_PLANE_NODES:-3}
COMPUTE_INSTANCE_TYPE=${COMPUTE_INSTANCE_TYPE:-m5.xlarge}
CONTROL_PLANE_INSTANCE_TYPE=${CONTROL_PLANE_INSTANCE_TYPE:-m5.xlarge}
PUBLISH_STRATEGY=${PUBLISH_STRATEGY:-Internal}
NETWORK_TYPE=${NETWORK_TYPE:-OVNKubernetes}
DRY_RUN=${DRY_RUN:-no}

# Validate required parameters
if [[ -z "${PULL_SECRET:-}" ]]; then
    echo "Error: Pull secret is required. Use --pull-secret or --pull-secret-file"
    exit 1
fi

if [[ -z "${SSH_KEY:-}" ]]; then
    echo "Error: SSH key is required. Use --ssh-key or --ssh-key-file"
    exit 1
fi

# Validate VPC output
echo "🔍 Validating VPC output..."
validate_vpc_output "$VPC_OUTPUT_DIR"

# Read VPC information
VPC_ID=$(cat "$VPC_OUTPUT_DIR/vpc-id" | tr -d '\n')
PRIVATE_SUBNET_IDS=$(cat "$VPC_OUTPUT_DIR/private-subnet-ids" | tr -d '\n')
AVAILABILITY_ZONES=$(cat "$VPC_OUTPUT_DIR/availability-zones" | tr -d '\n')
REGION=$(get_region_from_vpc "$VPC_OUTPUT_DIR")

echo "📋 VPC Configuration:"
echo "   VPC ID: $VPC_ID"
echo "   Region: $REGION"
echo "   Private Subnets: $PRIVATE_SUBNET_IDS"
echo "   Availability Zones: $AVAILABILITY_ZONES"
echo ""

# Validate AWS CLI and credentials
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed"
    exit 1
fi

# Build AWS CLI command with profile if set
AWS_CMD="aws"
if [[ -n "${AWS_PROFILE:-}" ]]; then
    AWS_CMD="aws --profile ${AWS_PROFILE}"
fi

if ! $AWS_CMD sts get-caller-identity &> /dev/null; then
    echo "Error: AWS credentials not configured"
    exit 1
fi

# Create installation directory
mkdir -p "$INSTALL_DIR"

# Check if OpenShift installer is already available
if check_openshift_installer; then
    echo "✅ Using existing OpenShift installer from PATH"
    INSTALLER_PATH="openshift-install"
else
    # Download OpenShift installer if not present
    INSTALLER_PATH="$INSTALL_DIR/openshift-install"
    if [[ ! -f "$INSTALLER_PATH" ]]; then
        echo "📥 Downloading OpenShift installer version $OPENSHIFT_VERSION..."
        cd "$INSTALL_DIR"
        
        # Download installer
        wget -q "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OPENSHIFT_VERSION/openshift-install-linux.tar.gz"
        tar xzf openshift-install-linux.tar.gz
        chmod +x openshift-install
        rm openshift-install-linux.tar.gz
        
        # Download oc client
        wget -q "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OPENSHIFT_VERSION/openshift-client-linux.tar.gz"
        tar xzf openshift-client-linux.tar.gz
        chmod +x oc kubectl
        rm openshift-client-linux.tar.gz
        
        cd - > /dev/null
    else
        echo "✅ OpenShift installer already exists at: $INSTALLER_PATH"
    fi
fi

# Generate install-config.yaml manually with proper OpenShift compatibility
echo "📝 Generating install-config.yaml..."

# Read VPC information before changing directories
VPC_ID=$(cat "$VPC_OUTPUT_DIR/vpc-id" | tr -d '\n')
PRIVATE_SUBNET_IDS=$(cat "$VPC_OUTPUT_DIR/private-subnet-ids" | tr -d '\n')
AVAILABILITY_ZONES=$(cat "$VPC_OUTPUT_DIR/availability-zones" | tr -d '\n')

# Convert comma-separated subnets to array format
IFS=',' read -ra SUBNET_ARRAY <<< "$PRIVATE_SUBNET_IDS"
SUBNET_YAML=""
for subnet in "${SUBNET_ARRAY[@]}"; do
    SUBNET_YAML="${SUBNET_YAML}    - ${subnet}"$'\n'
done

# Convert availability zones to array format
IFS=',' read -ra AZ_ARRAY <<< "$AVAILABILITY_ZONES"
AZ_YAML=""
for az in "${AZ_ARRAY[@]}"; do
    AZ_YAML="${AZ_YAML}      - ${az}"$'\n'
done

# Change to installation directory
cd "$INSTALL_DIR"

# Create install-config.yaml with proper OpenShift 4.x format
echo "🔧 Creating install-config.yaml..."
cat > install-config.yaml <<EOF
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform:
    aws:
      type: ${COMPUTE_INSTANCE_TYPE}
      zones:
${AZ_YAML}  replicas: ${COMPUTE_NODES}
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      type: ${CONTROL_PLANE_INSTANCE_TYPE}
      zones:
${AZ_YAML}  replicas: ${CONTROL_PLANE_NODES}
metadata:
  name: ${CLUSTER_NAME}
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: ${NETWORK_TYPE}
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: ${REGION}
    subnets:
${SUBNET_YAML}    vpc:
      id: ${VPC_ID}
publish: ${PUBLISH_STRATEGY}
pullSecret: '${PULL_SECRET}'
sshKey: |
  ${SSH_KEY}
EOF

echo "✅ install-config.yaml created successfully!"

# Create backup of install-config.yaml (always backup to prevent loss during installation)
BACKUP_FILE="install-config.yaml.backup.$(date +%Y%m%d-%H%M%S)"
cp "install-config.yaml" "$BACKUP_FILE"
echo "✅ Backup created: $BACKUP_FILE"
echo ""

# Display configuration summary
echo "📊 OpenShift Configuration Summary:"
echo "   Cluster Name: $CLUSTER_NAME"
echo "   Base Domain: $BASE_DOMAIN"
echo "   OpenShift Version: $OPENSHIFT_VERSION"
echo "   Region: $REGION"
echo "   VPC ID: $VPC_ID"
echo "   Control Plane: $CONTROL_PLANE_NODES nodes ($CONTROL_PLANE_INSTANCE_TYPE)"
echo "   Compute: $COMPUTE_NODES nodes ($COMPUTE_INSTANCE_TYPE)"
echo "   Network Type: $NETWORK_TYPE"
echo "   Publish Strategy: $PUBLISH_STRATEGY"
echo "   Installation Directory: $INSTALL_DIR"
echo ""

if [[ "$DRY_RUN" == "yes" ]]; then
    echo "🔍 DRY RUN MODE - Only generating install-config.yaml, no installation will be performed"
    echo "📁 Files created:"
    echo "   $INSTALL_DIR/install-config.yaml"
    echo "   $BACKUP_FILE"
    echo ""
    echo "To proceed with installation, run:"
    echo "cd $INSTALL_DIR && ./openshift-install create cluster"
    echo ""
    echo "💡 Tip: You can also run this script without --dry-run to proceed with installation"
    exit 0
fi

# Confirm installation
echo "⚠️  This will create an OpenShift cluster with the following resources:"
echo "   - $CONTROL_PLANE_NODES control plane nodes"
echo "   - $COMPUTE_NODES compute nodes"
echo "   - Associated AWS resources (load balancers, security groups, etc.)"
echo ""
read -p "Do you want to proceed with the installation? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled"
    exit 0
fi

# Start installation
echo "🚀 Starting OpenShift installation..."
echo "⏳ This process will take approximately 30-45 minutes..."
echo ""

# Create cluster
$INSTALLER_PATH create cluster --log-level=info

# Installation completed
echo ""
echo "✅ OpenShift installation completed successfully!"
echo ""
echo "📋 Cluster Information:"
echo "   Console URL: https://console-openshift-console.apps.$CLUSTER_NAME.$BASE_DOMAIN"
echo "   API URL: https://api.$CLUSTER_NAME.$BASE_DOMAIN:6443"
echo "   Username: kubeadmin"
echo "   Password: $(cat auth/kubeadmin-password)"
echo ""
echo "🔧 Next Steps:"
echo "1. Access the OpenShift console using the URL above"
echo "2. Login with kubeadmin and the password shown above"
echo "3. Download the kubeconfig file: $INSTALL_DIR/auth/kubeconfig"
echo "4. Use 'oc login' to access the cluster from command line"
echo ""
echo "📁 Important files:"
echo "   kubeconfig: $INSTALL_DIR/auth/kubeconfig"
echo "   kubeadmin password: $INSTALL_DIR/auth/kubeadmin-password"
echo "   install-config.yaml: $INSTALL_DIR/install-config.yaml"
echo ""
echo "To destroy the cluster:"
echo "cd $INSTALL_DIR && $INSTALLER_PATH destroy cluster" 