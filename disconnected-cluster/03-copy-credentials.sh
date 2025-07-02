#!/bin/bash

# Copy Credentials to Bastion Host
# This script runs after infrastructure creation and before registry setup

set -euo pipefail

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
    echo "  --help                Display this help message"
    echo ""
    echo "This script copies necessary credentials to the bastion host:"
    echo "  - AWS credentials for infrastructure access"
    echo "  - SSH public key for cluster node access"
    echo "  - Pull secret for image registry access"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    echo -e "${BLUE}🔍 Checking prerequisites...${NC}"
    
    # Check if infrastructure output exists
    if [[ ! -f "./infra-output/bastion-public-ip" ]]; then
        echo -e "${RED}❌ Infrastructure output not found. Please run 01-create-infrastructure.sh first.${NC}"
        exit 1
    fi
    
    # Check if bastion key exists
    if [[ ! -f "./infra-output/bastion-key.pem" ]]; then
        echo -e "${RED}❌ Bastion key not found. Please run 01-create-infrastructure.sh first.${NC}"
        exit 1
    fi
    
    # Check if local AWS credentials exist
    if [[ ! -f "$HOME/.aws/credentials" ]]; then
        echo -e "${RED}❌ AWS credentials not found at $HOME/.aws/credentials${NC}"
        exit 1
    fi
    
    # Check if local SSH public key exists
    if [[ ! -f "$HOME/.ssh/id_rsa.pub" ]]; then
        echo -e "${RED}❌ SSH public key not found at $HOME/.ssh/id_rsa.pub${NC}"
        exit 1
    fi
    
    # Check if local pull secret exists
    if [[ ! -f "$HOME/.ssh/pull-secret.json" ]]; then
        echo -e "${YELLOW}⚠️  Pull secret not found at $HOME/.ssh/pull-secret.json${NC}"
        echo -e "${YELLOW}   Will use auto-generated pull secret for local registry${NC}"
    fi
    
    echo -e "${GREEN}✅ All prerequisites met${NC}"
}

# Function to copy credentials
copy_credentials() {
    local bastion_ip=$(cat ./infra-output/bastion-public-ip)
    local ssh_key="./infra-output/bastion-key.pem"
    
    echo -e "${BLUE}🔐 Copying credentials to bastion host ($bastion_ip)...${NC}"
    
    # Create .aws directory on bastion
    echo -e "${BLUE}📁 Creating .aws directory on bastion...${NC}"
    ssh -i "$ssh_key" ubuntu@"$bastion_ip" -o StrictHostKeyChecking=no "mkdir -p ~/.aws"
    
    # Copy AWS credentials
    echo -e "${BLUE}📋 Copying AWS credentials...${NC}"
    scp -i "$ssh_key" -o StrictHostKeyChecking=no "$HOME/.aws/credentials" ubuntu@"$bastion_ip":/home/ubuntu/.aws/
    
    # Copy AWS config if exists
    if [[ -f "$HOME/.aws/config" ]]; then
        echo -e "${BLUE}📋 Copying AWS config...${NC}"
        scp -i "$ssh_key" -o StrictHostKeyChecking=no "$HOME/.aws/config" ubuntu@"$bastion_ip":/home/ubuntu/.aws/
    fi
    
    # Copy SSH public key
    echo -e "${BLUE}🔑 Copying SSH public key...${NC}"
    scp -i "$ssh_key" -o StrictHostKeyChecking=no "$HOME/.ssh/id_rsa.pub" ubuntu@"$bastion_ip":/home/ubuntu/.ssh/
    
    # Copy pull secret if exists
    if [[ -f "$HOME/.ssh/pull-secret.json" ]]; then
        echo -e "${BLUE}🔐 Copying pull secret...${NC}"
        scp -i "$ssh_key" -o StrictHostKeyChecking=no "$HOME/.ssh/pull-secret.json" ubuntu@"$bastion_ip":/home/ubuntu/
    fi
    
    # Set proper permissions on bastion
    echo -e "${BLUE}🔒 Setting proper permissions...${NC}"
    ssh -i "$ssh_key" ubuntu@"$bastion_ip" -o StrictHostKeyChecking=no "chmod 600 ~/.aws/* && chmod 644 ~/.ssh/id_rsa.pub"
    
    echo -e "${GREEN}✅ Credentials copied successfully!${NC}"
}

# Function to copy installation scripts
copy_installation_scripts() {
    local bastion_ip=$(cat ./infra-output/bastion-public-ip)
    local ssh_key="./infra-output/bastion-key.pem"
    
    echo -e "${BLUE}📦 Copying installation scripts to bastion host...${NC}"
    
    # Copy all installation scripts
    local scripts=(
        "04-setup-mirror-registry.sh"
        "05-sync-images.sh"
        "07-prepare-install-config.sh"
        "08-install-cluster.sh"
        "09-verify-cluster.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            echo -e "${BLUE}   Copying $script...${NC}"
            scp -i "$ssh_key" -o StrictHostKeyChecking=no "$script" ubuntu@"$bastion_ip":/home/ubuntu/
            ssh -i "$ssh_key" ubuntu@"$bastion_ip" -o StrictHostKeyChecking=no "chmod +x /home/ubuntu/$script"
        else
            echo -e "${YELLOW}   ⚠️  $script not found, skipping...${NC}"
        fi
    done
    
    echo -e "${GREEN}✅ Installation scripts copied successfully!${NC}"
}

# Function to verify files
verify_files() {
    local bastion_ip=$(cat ./infra-output/bastion-public-ip)
    local ssh_key="./infra-output/bastion-key.pem"
    
    echo -e "${BLUE}🔍 Verifying files on bastion host...${NC}"
    
    ssh -i "$ssh_key" ubuntu@"$bastion_ip" -o StrictHostKeyChecking=no "echo 'AWS credentials:' && ls -la ~/.aws/ && echo 'SSH public key:' && ls -la ~/.ssh/id_rsa.pub && echo 'Pull secret:' && ls -la ~/pull-secret.json 2>/dev/null || echo 'No pull secret found'"
    
    echo -e "${GREEN}✅ Verification completed${NC}"
}

# Function to test AWS access
test_aws_access() {
    local bastion_ip=$(cat ./infra-output/bastion-public-ip)
    local ssh_key="./infra-output/bastion-key.pem"
    
    echo -e "${BLUE}🧪 Testing AWS access on bastion host...${NC}"
    
    # Test AWS CLI access with static profile
    local aws_test=$(ssh -i "$ssh_key" ubuntu@"$bastion_ip" -o StrictHostKeyChecking=no "AWS_PROFILE=static aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo 'FAILED'")
    
    if [[ "$aws_test" != "FAILED" ]]; then
        echo -e "${GREEN}✅ AWS access working: $aws_test${NC}"
    else
        echo -e "${YELLOW}⚠️  AWS access test failed. You may need to set AWS_PROFILE or configure credentials.${NC}"
    fi
}

# Main execution
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done
    
    # Display script header
    echo -e "${BLUE}🔐 Copy Credentials to Bastion Host${NC}"
    echo "======================================"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Copy credentials
    copy_credentials
    
    # Copy installation scripts
    copy_installation_scripts
    
    # Verify files
    verify_files
    
    # Test AWS access
    test_aws_access
    
    echo ""
    echo -e "${GREEN}🎉 Credential copy completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}📋 Next steps:${NC}"
    echo "   1. SSH to bastion host: ssh -i ./infra-output/bastion-key.pem ubuntu@$(cat ./infra-output/bastion-public-ip)"
    echo "   2. Run 04-setup-mirror-registry.sh to set up the local registry"
    echo "   3. Run 05-sync-images.sh to sync OpenShift images"
    echo "   4. Run 07-prepare-install-config.sh to prepare installation"
    echo ""
    echo -e "${YELLOW}⚠️  Security note:${NC}"
    echo "   - Credentials are copied to bastion host for installation use"
    echo "   - Consider cleaning up credentials after cluster installation"
    echo "   - Use AWS_PROFILE=static if needed for AWS access"
}

# Run main function with all arguments
main "$@" 