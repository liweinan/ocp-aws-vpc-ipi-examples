#!/bin/bash

# Fix Private Cluster DNS Issue Script
# Provides solutions for OpenShift private cluster DNS resolution problems

set -euo pipefail

# Default values
DEFAULT_INSTALL_DIR="./openshift-install"
DEFAULT_CLUSTER_NAME="my-cluster"
DEFAULT_BASE_DOMAIN="qe.devcluster.openshift.com"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --install-dir         Installation directory (default: $DEFAULT_INSTALL_DIR)"
    echo "  --cluster-name        Cluster name (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --base-domain         Base domain (default: $DEFAULT_BASE_DOMAIN)"
    echo "  --action              Action to take:"
    echo "                         - destroy: Destroy the cluster and recreate with External publish"
    echo "                         - access: Show how to access the private cluster"
    echo "                         - dns: Show DNS troubleshooting steps"
    echo "                         - bastion: Create bastion host for private cluster access"
    echo "  --help                Display this help message"
    exit 1
}

# Function to check if cluster exists
check_cluster_exists() {
    local install_dir="$1"
    
    if [[ ! -f "$install_dir/metadata.json" ]]; then
        echo "❌ No cluster metadata found in $install_dir"
        echo "   Please ensure you're in the correct installation directory"
        return 1
    fi
    
    echo "✅ Cluster metadata found"
    return 0
}

# Function to get cluster info
get_cluster_info() {
    local install_dir="$1"
    
    if [[ -f "$install_dir/metadata.json" ]]; then
        CLUSTER_NAME=$(jq -r '.clusterName' "$install_dir/metadata.json")
        INFRA_ID=$(jq -r '.infraID' "$install_dir/metadata.json")
        REGION=$(jq -r '.aws.region' "$install_dir/metadata.json")
        CLUSTER_DOMAIN=$(jq -r '.aws.clusterDomain' "$install_dir/metadata.json")
        
        echo "📋 Cluster Information:"
        echo "   Cluster Name: $CLUSTER_NAME"
        echo "   Infrastructure ID: $INFRA_ID"
        echo "   Region: $REGION"
        echo "   Cluster Domain: $CLUSTER_DOMAIN"
        echo ""
    fi
}

# Function to show DNS troubleshooting
show_dns_troubleshooting() {
    local cluster_name="$1"
    local base_domain="$2"
    
    echo "🔍 DNS Troubleshooting Steps"
    echo "============================"
    echo ""
    echo "1. Check if DNS records exist in Route53:"
    echo "   aws route53 list-hosted-zones"
    echo "   aws route53 list-resource-record-sets --hosted-zone-id <zone-id>"
    echo ""
    echo "2. Check if the API endpoint is accessible:"
    echo "   nslookup api.$cluster_name.$base_domain"
    echo "   dig api.$cluster_name.$base_domain"
    echo ""
    echo "3. Check if the cluster is actually running:"
    echo "   aws ec2 describe-instances --filters \"Name=tag:kubernetes.io/cluster/*,Values=owned\""
    echo ""
    echo "4. Check load balancer health:"
    echo "   aws elbv2 describe-load-balancers --names $INFRA_ID-int"
    echo ""
    echo "5. Check if the issue is with private cluster configuration:"
    echo "   - Private clusters (publish: Internal) can only be accessed from within the VPC"
    echo "   - You need a bastion host or VPN to access the cluster"
    echo ""
}

# Function to show private cluster access methods
show_private_cluster_access() {
    local cluster_name="$1"
    local base_domain="$2"
    local install_dir="$3"
    
    echo "🔐 Private Cluster Access Methods"
    echo "================================="
    echo ""
    echo "Since your cluster is configured as private (publish: Internal),"
    echo "you can only access it from within the VPC. Here are your options:"
    echo ""
    
    echo "Option 1: Create a Bastion Host"
    echo "--------------------------------"
    echo "1. Create a bastion host in the VPC:"
    echo "   ./create-bastion.sh --cluster-name $cluster_name"
    echo ""
    echo "2. SSH to the bastion host:"
    echo "   ssh -i bastion-output/bastion-key.pem core@<bastion-ip>"
    echo ""
    echo "3. Copy kubeconfig to bastion:"
    echo "   scp -i bastion-output/bastion-key.pem $install_dir/auth/kubeconfig core@<bastion-ip>:~/"
    echo ""
    echo "4. Access cluster from bastion:"
    echo "   export KUBECONFIG=~/kubeconfig"
    echo "   oc get nodes"
    echo ""
    
    echo "Option 2: Use AWS Systems Manager Session Manager"
    echo "------------------------------------------------"
    echo "1. Find a cluster instance:"
    echo "   aws ec2 describe-instances --filters \"Name=tag:kubernetes.io/cluster/*,Values=owned\" --query 'Reservations[].Instances[0].InstanceId' --output text"
    echo ""
    echo "2. Connect via Session Manager:"
    echo "   aws ssm start-session --target <instance-id>"
    echo ""
    echo "3. Access cluster from the instance:"
    echo "   sudo -i"
    echo "   export KUBECONFIG=/etc/kubernetes/kubeconfig"
    echo "   oc get nodes"
    echo ""
    
    echo "Option 3: Set up VPN or Direct Connect"
    echo "-------------------------------------"
    echo "Configure a VPN connection to your VPC to access the private cluster"
    echo "from your local machine."
    echo ""
    
    echo "Option 4: Recreate with External Publish Strategy"
    echo "------------------------------------------------"
    echo "If you want external access, destroy and recreate the cluster:"
    echo "   ./fix-private-cluster.sh --action destroy"
    echo ""
}

# Function to destroy and recreate cluster
destroy_and_recreate() {
    local install_dir="$1"
    local cluster_name="$2"
    local base_domain="$3"
    
    echo "🗑️  Destroying current cluster..."
    echo "⚠️  This will permanently delete the current cluster and all its data!"
    echo ""
    read -p "Are you sure you want to destroy the cluster? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cluster destruction cancelled"
        exit 0
    fi
    
    cd "$install_dir"
    
    # Check if openshift-install exists
    if [[ ! -f "./openshift-install" ]]; then
        echo "❌ openshift-install not found in $install_dir"
        echo "   Please ensure you have the OpenShift installer available"
        exit 1
    fi
    
    # Destroy cluster
    echo "🔄 Destroying cluster..."
    ./openshift-install destroy cluster --log-level=info
    
    echo ""
    echo "✅ Cluster destroyed successfully!"
    echo ""
    echo "🔄 To recreate with external access, run:"
    echo "   ./deploy-openshift.sh \\"
    echo "     --cluster-name $cluster_name \\"
    echo "     --base-domain $base_domain \\"
    echo "     --publish-strategy External \\"
    echo "     --pull-secret \"<your-pull-secret>\" \\"
    echo "     --ssh-key \"<your-ssh-key>\""
    echo ""
    echo "📝 Note: External publish strategy will make the cluster accessible from the internet"
    echo "   This is less secure but easier to access for development/testing"
}

# Function to create bastion for private cluster
create_bastion_for_private() {
    local cluster_name="$1"
    local install_dir="$2"
    
    echo "🏗️  Creating bastion host for private cluster access..."
    
    # Check if VPC output exists
    if [[ ! -d "../vpc-output" ]]; then
        echo "❌ VPC output directory not found"
        echo "   Please ensure you have run create-vpc.sh first"
        exit 1
    fi
    
    # Create bastion host
    cd ..
    ./create-bastion.sh \
        --cluster-name "$cluster_name" \
        --use-rhcos yes \
        --create-iam-role yes \
        --enhanced-security yes
    
    echo ""
    echo "✅ Bastion host created successfully!"
    echo ""
    echo "🔗 Next steps:"
    echo "1. SSH to the bastion host using the provided command"
    echo "2. Copy your kubeconfig to the bastion:"
    echo "   scp -i bastion-output/bastion-key.pem $install_dir/auth/kubeconfig core@<bastion-ip>:~/"
    echo "3. Access your cluster from the bastion:"
    echo "   export KUBECONFIG=~/kubeconfig"
    echo "   oc get nodes"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --install-dir)
            INSTALL_DIR="$2"
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
        --action)
            ACTION="$2"
            shift 2
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
INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}
CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
BASE_DOMAIN=${BASE_DOMAIN:-$DEFAULT_BASE_DOMAIN}
ACTION=${ACTION:-access}

# Validate action
case "$ACTION" in
    destroy|access|dns|bastion)
        ;;
    *)
        echo "❌ Invalid action: $ACTION"
        echo "   Valid actions: destroy, access, dns, bastion"
        exit 1
        ;;
esac

echo "🔧 OpenShift Private Cluster Fix Tool"
echo "====================================="
echo ""

# Check if cluster exists
if ! check_cluster_exists "$INSTALL_DIR"; then
    exit 1
fi

# Get cluster info
get_cluster_info "$INSTALL_DIR"

# Execute requested action
case "$ACTION" in
    destroy)
        destroy_and_recreate "$INSTALL_DIR" "$CLUSTER_NAME" "$BASE_DOMAIN"
        ;;
    access)
        show_private_cluster_access "$CLUSTER_NAME" "$BASE_DOMAIN" "$INSTALL_DIR"
        ;;
    dns)
        show_dns_troubleshooting "$CLUSTER_NAME" "$BASE_DOMAIN"
        ;;
    bastion)
        create_bastion_for_private "$CLUSTER_NAME" "$INSTALL_DIR"
        ;;
esac 