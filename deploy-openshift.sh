#!/bin/bash

# OpenShift Cluster Deployment Script
# Uses VPC output from create-vpc.sh to deploy OpenShift IPI cluster

set -euo pipefail

# Default values
DEFAULT_VPC_OUTPUT_DIR="./vpc-output"
DEFAULT_OPENSHIFT_VERSION="4.18.15"
DEFAULT_INSTALL_DIR="./openshift-install"
DEFAULT_PUBLISH_STRATEGY="Internal"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --vpc-output-dir      Directory containing VPC output files (default: $DEFAULT_VPC_OUTPUT_DIR)"
    echo "  --openshift-version   OpenShift version to install (default: $DEFAULT_OPENSHIFT_VERSION)"
    echo "  --install-dir         Installation directory (default: $DEFAULT_INSTALL_DIR)"
    echo "  --publish-strategy    Publish strategy: External or Internal (default: $DEFAULT_PUBLISH_STRATEGY)"
    echo "  --dry-run             Generate install-config.yaml only, don't install"
    echo "  --help                Display this help message"
    echo ""
    echo "Note: Cluster name, base domain, SSH key, and pull secret will be entered"
    echo "      manually during the openshift-install create install-config process."
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
        --openshift-version)
            OPENSHIFT_VERSION="$2"
            shift 2
            ;;
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --publish-strategy)
            PUBLISH_STRATEGY="$2"
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
OPENSHIFT_VERSION=${OPENSHIFT_VERSION:-$DEFAULT_OPENSHIFT_VERSION}
INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}
PUBLISH_STRATEGY=${PUBLISH_STRATEGY:-$DEFAULT_PUBLISH_STRATEGY}
DRY_RUN=${DRY_RUN:-no}

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

# Generate install-config.yaml using openshift-install (manual interaction)
echo "📝 Generating install-config.yaml using openshift-install..."

# Change to installation directory
cd "$INSTALL_DIR"

# Remove any existing install-config.yaml to avoid prompt
rm -f install-config.yaml

echo "🔧 Please manually complete the openshift-install create install-config process..."
echo "   The installer will prompt you for:"
echo "   - SSH Public Key"
echo "   - Platform (select: aws)"
echo "   - Region (use: $REGION)"
echo "   - Base Domain"
echo "   - Cluster Name"
echo "   - Pull Secret"
echo ""

# Set AWS_PROFILE for the installer
export AWS_PROFILE="${AWS_PROFILE:-}"

# Run openshift-install create install-config interactively
echo "🚀 Starting openshift-install create install-config..."
if ! openshift-install create install-config --dir=.; then
    echo "❌ Failed to create install-config.yaml"
    exit 1
fi

# Check if install-config.yaml was created
if [[ ! -f "install-config.yaml" ]]; then
    echo "❌ install-config.yaml was not created"
    exit 1
fi

echo "✅ install-config.yaml generated by openshift-install!"

# Patch VPC, subnets, and publish fields in install-config.yaml
echo "🔧 Patching install-config.yaml with VPC configuration..."

# Use yq to patch the YAML
yq -i ".platform.aws.vpc.id = \"$VPC_ID\"" install-config.yaml
yq -i ".platform.aws.subnets = [$(echo $PRIVATE_SUBNET_IDS | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')]" install-config.yaml
yq -i ".platform.aws.region = \"$REGION\"" install-config.yaml
yq -i ".publish = \"$PUBLISH_STRATEGY\"" install-config.yaml

echo "✅ install-config.yaml patched with VPC configuration!"

# Create backup of install-config.yaml (always backup to prevent loss during installation)
BACKUP_FILE="install-config.yaml.backup.$(date +%Y%m%d-%H%M%S)"
cp "install-config.yaml" "$BACKUP_FILE"
echo "✅ Backup created: $BACKUP_FILE"
echo ""

# Display configuration summary
echo "📊 OpenShift Configuration Summary:"
echo "   OpenShift Version: $OPENSHIFT_VERSION"
echo "   Region: $REGION"
echo "   VPC ID: $VPC_ID"
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
echo "   - Control plane and compute nodes (as configured in install-config.yaml)"
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
echo "   Console URL: Check the install-config.yaml for cluster details"
echo "   API URL: Check the install-config.yaml for cluster details"
echo "   Username: kubeadmin"
echo "   Password: $(cat auth/kubeadmin-password)"
echo ""
echo "🔧 Next Steps:"
echo "1. Access the OpenShift console using the URL from install-config.yaml"
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