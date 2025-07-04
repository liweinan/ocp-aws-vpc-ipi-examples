#!/bin/bash

# Copy Infrastructure and Tools Script for Disconnected OpenShift Cluster
# This script copies infrastructure output files and installs necessary tools on bastion host
# Step 4 in the disconnected cluster installation process

set -euo pipefail

# Set AWS_PROFILE to static if not already set
export AWS_PROFILE=${AWS_PROFILE:-static}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
CLUSTER_NAME="${1:-weli-test}"
BASTION_USER="ubuntu"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_OUTPUT_DIR="${SCRIPT_DIR}/infra-output"
BASTION_KEY="${INFRA_OUTPUT_DIR}/bastion-key.pem"

# Function to print colored messages
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

# Function to show usage
usage() {
    echo "Usage: $0 [cluster-name]"
    echo ""
    echo "This script copies infrastructure files and installs tools on bastion host"
    echo ""
    echo "Parameters:"
    echo "  cluster-name    Name of the cluster (default: weli-test)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Use default cluster name 'weli-test'"
    echo "  $0 my-cluster         # Use custom cluster name"
    echo ""
    echo "Prerequisites:"
    echo "  - Infrastructure must be created (01-create-infrastructure.sh)"
    echo "  - Bastion host must be running (02-create-bastion.sh)"
    echo "  - Credentials must be copied (03-copy-credentials.sh)"
    exit 1
}

# Function to validate prerequisites
validate_prerequisites() {
    print_info "Validating prerequisites..."
    
    # Check if infra-output directory exists
    if [[ ! -d "$INFRA_OUTPUT_DIR" ]]; then
        print_error "Infrastructure output directory not found: $INFRA_OUTPUT_DIR"
        print_error "Please run 01-create-infrastructure.sh first"
        exit 1
    fi
    
    # Check if bastion key exists
    if [[ ! -f "$BASTION_KEY" ]]; then
        print_error "Bastion key not found: $BASTION_KEY"
        print_error "Please run 02-create-bastion.sh first"
        exit 1
    fi
    
    # Check if bastion host is accessible
    local bastion_ip
    if [[ -f "$INFRA_OUTPUT_DIR/bastion-public-ip" ]]; then
        bastion_ip=$(cat "$INFRA_OUTPUT_DIR/bastion-public-ip")
        print_info "Testing connection to bastion host: $bastion_ip"
        
        if ! ssh -i "$BASTION_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$BASTION_USER@$bastion_ip" "echo 'Connection test successful'" > /dev/null 2>&1; then
            print_error "Cannot connect to bastion host: $bastion_ip"
            print_error "Please check if bastion host is running and accessible"
            exit 1
        fi
        
        print_success "Bastion host is accessible"
    else
        print_error "Bastion public IP not found"
        exit 1
    fi
    
    print_success "All prerequisites validated"
}

# Function to copy infrastructure files
copy_infrastructure_files() {
    local bastion_ip=$(cat "$INFRA_OUTPUT_DIR/bastion-public-ip")
    
    print_info "Copying infrastructure files to bastion host..."
    
    # Create disconnected-cluster directory on bastion
    ssh -i "$BASTION_KEY" -o StrictHostKeyChecking=no "$BASTION_USER@$bastion_ip" \
        "mkdir -p /home/ubuntu/disconnected-cluster/infra-output"
    
    # Copy all infrastructure output files
    if scp -i "$BASTION_KEY" -o StrictHostKeyChecking=no -r "$INFRA_OUTPUT_DIR"/* \
       "$BASTION_USER@$bastion_ip:/home/ubuntu/disconnected-cluster/infra-output/"; then
        print_success "Infrastructure files copied successfully"
    else
        print_error "Failed to copy infrastructure files"
        exit 1
    fi
    
    # Verify critical files are copied
    print_info "Verifying copied files..."
    local critical_files=("vpc-id" "private-subnet-ids" "region" "bastion-instance-id")
    local missing_files=()
    
    for file in "${critical_files[@]}"; do
        if ! ssh -i "$BASTION_KEY" -o StrictHostKeyChecking=no "$BASTION_USER@$bastion_ip" \
             "test -f /home/ubuntu/disconnected-cluster/infra-output/$file"; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        print_warning "Some critical files are missing:"
        printf '  - %s\n' "${missing_files[@]}"
    else
        print_success "All critical infrastructure files verified"
    fi
}

# Function to install OpenShift CLI
install_oc_client() {
    local bastion_ip=$(cat "$INFRA_OUTPUT_DIR/bastion-public-ip")
    
    print_info "Installing OpenShift CLI (oc) on bastion host..."
    
    ssh -i "$BASTION_KEY" -o StrictHostKeyChecking=no "$BASTION_USER@$bastion_ip" << 'EOF'
        set -euo pipefail
        
        # Check if oc is already installed
        if command -v oc &> /dev/null; then
            echo "oc client already installed: $(oc version --client)"
        else
            # Download and install oc client
            echo "Downloading OpenShift CLI..."
            cd /tmp
            
            # Use stable OpenShift 4.19 release
            OC_VERSION="4.19.2"
            curl -sL "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-4.19/openshift-client-linux-${OC_VERSION}.tar.gz" -o openshift-client-linux.tar.gz
            
            # Extract and install
            tar -xzf openshift-client-linux.tar.gz
            sudo mv oc kubectl /usr/local/bin/
            
            # Clean up
            rm -f openshift-client-linux.tar.gz README.md
            
            echo "oc client installed successfully: $(oc version --client)"
        fi
        
        # Final verification
        echo "Final verification: $(oc version --client)"
EOF
    
    if [[ $? -eq 0 ]]; then
        print_success "OpenShift CLI installed successfully"
    else
        print_error "Failed to install OpenShift CLI"
        exit 1
    fi
}

# Function to install additional tools
install_additional_tools() {
    local bastion_ip=$(cat "$INFRA_OUTPUT_DIR/bastion-public-ip")
    
    print_info "Installing additional tools on bastion host..."
    
    ssh -i "$BASTION_KEY" -o StrictHostKeyChecking=no "$BASTION_USER@$bastion_ip" << 'EOF'
        set -euo pipefail
        
        # Update package lists
        echo "Updating package lists..."
        sudo apt update -qq
        
        # Install required packages
        echo "Installing required packages..."
        sudo apt install -y \
            jq \
            unzip \
            wget \
            curl \
            htop \
            tree
        
        # Install yq separately (not available in Ubuntu repos)
        if ! command -v yq &> /dev/null; then
            echo "Installing yq..."
            wget -qO /tmp/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
            sudo install /tmp/yq /usr/local/bin/yq
            rm -f /tmp/yq
        else
            echo "yq already installed: $(yq --version)"
        fi
        
        # Install aws-cli v2 if not present
        if ! command -v aws &> /dev/null; then
            echo "Installing AWS CLI v2..."
            cd /tmp
            curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
            unzip -q awscliv2.zip
            sudo ./aws/install
            rm -rf aws awscliv2.zip
        else
            echo "AWS CLI already installed: $(aws --version)"
        fi
        
        # Verify installations
        echo "Tool versions:"
        echo "  jq: $(jq --version)"
        echo "  yq: $(yq --version)"
        echo "  aws: $(aws --version)"
        echo "  podman: $(podman --version)"
EOF
    
    if [[ $? -eq 0 ]]; then
        print_success "Additional tools installed successfully"
    else
        print_error "Failed to install additional tools"
        exit 1
    fi
}

# Function to copy installation scripts
copy_installation_scripts() {
    local bastion_ip=$(cat "$INFRA_OUTPUT_DIR/bastion-public-ip")
    
    print_info "Copying installation scripts to bastion host..."
    
    # Copy remaining scripts (05-09)
    local scripts_to_copy=(
        "05-setup-mirror-registry.sh"
        "06-sync-images-robust.sh"
        "sync-single-image.sh"
        "07-prepare-install-config.sh"
        "08-install-cluster.sh"
        "09-verify-cluster.sh"
    )
    
    for script in "${scripts_to_copy[@]}"; do
        if [[ -f "$SCRIPT_DIR/$script" ]]; then
            if scp -i "$BASTION_KEY" -o StrictHostKeyChecking=no \
               "$SCRIPT_DIR/$script" "$BASTION_USER@$bastion_ip:/home/ubuntu/disconnected-cluster/"; then
                print_success "Copied $script"
                
                # Make script executable
                ssh -i "$BASTION_KEY" -o StrictHostKeyChecking=no "$BASTION_USER@$bastion_ip" \
                    "chmod +x /home/ubuntu/disconnected-cluster/$script"
            else
                print_warning "Failed to copy $script"
            fi
        else
            print_warning "Script not found: $script"
        fi
    done
    
    print_success "Installation scripts copied and made executable"
}

# Function to verify tool installation
verify_tool_installation() {
    local bastion_ip=$(cat "$INFRA_OUTPUT_DIR/bastion-public-ip")
    
    print_info "Verifying tool installation on bastion host..."
    
    # Capture the output to check for error markers
    local verification_output
    verification_output=$(ssh -i "$BASTION_KEY" -o StrictHostKeyChecking=no "$BASTION_USER@$bastion_ip" << 'EOF'
        echo "=== Tool Verification ==="
        
        # Check critical tools
        tools=("oc" "aws" "jq" "yq" "podman")
        missing_tools=()
        
        for tool in "${tools[@]}"; do
            if command -v "$tool" &> /dev/null; then
                echo "✅ $tool: $(command -v $tool)"
            else
                echo "❌ $tool: NOT FOUND"
                missing_tools+=("$tool")
            fi
        done
        
        if [[ ${#missing_tools[@]} -gt 0 ]]; then
            echo ""
            echo "⚠️  Missing tools: ${missing_tools[*]}"
            echo "TOOL_CHECK_FAILED"
        else
            echo ""
            echo "✅ All required tools are installed and available"
        fi
        
        # Verify AWS credentials
        echo ""
        echo "=== AWS Credentials ==="
        if aws sts get-caller-identity > /dev/null 2>&1; then
            echo "✅ AWS credentials are valid"
            aws sts get-caller-identity --query 'Arn' --output text
        else
            echo "❌ AWS credentials are not configured properly"
            echo "AWS_CHECK_FAILED"
        fi
EOF
    )
    
    echo "$verification_output"
    
    if echo "$verification_output" | grep -q "TOOL_CHECK_FAILED"; then
        print_error "Some tools are missing"
        exit 1
    elif echo "$verification_output" | grep -q "AWS_CHECK_FAILED"; then
        print_error "AWS credentials verification failed"
        exit 1
    else
        print_success "All tools verified successfully"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}🔧 Copy Infrastructure and Tools Setup${NC}"
    echo "========================================="
    echo ""
    echo "Cluster Name: $CLUSTER_NAME"
    echo "Infrastructure Directory: $INFRA_OUTPUT_DIR"
    echo ""
    
    # Validate prerequisites
    validate_prerequisites
    
    # Copy infrastructure files
    copy_infrastructure_files
    
    # Install OpenShift CLI
    install_oc_client
    
    # Install additional tools
    install_additional_tools
    
    # Copy installation scripts
    copy_installation_scripts
    
    # Verify installation
    verify_tool_installation
    
    echo ""
    print_success "========================================="
    print_success "Infrastructure and tools setup completed!"
    print_success "========================================="
    echo ""
    print_info "Next steps:"
    echo "  1. ssh -i $BASTION_KEY $BASTION_USER@$(cat $INFRA_OUTPUT_DIR/bastion-public-ip)"
    echo "  2. cd disconnected-cluster"
    echo "  3. ./05-setup-mirror-registry.sh"
    echo "  4. ./06-sync-images-robust.sh"
    echo "  5. ./07-prepare-install-config.sh"
    echo "  6. ./08-install-cluster.sh"
    echo ""
    print_info "All tools and scripts are now available on the bastion host"
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        usage
        ;;
    *)
        main
        ;;
esac