#!/bin/bash

# Bastion Host Connection Script
# Automates the process of connecting to the bastion host

set -euo pipefail

# Default values
DEFAULT_BASTION_OUTPUT_DIR="./bastion-output"
DEFAULT_CLUSTER_NAME="my-cluster"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --bastion-output-dir  Directory containing bastion output files (default: $DEFAULT_BASTION_OUTPUT_DIR)"
    echo "  --cluster-name        Cluster name (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --copy-kubeconfig     Copy kubeconfig to bastion after connection"
    echo "  --setup-environment   Load OpenShift environment after connection"
    echo "  --help                Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Connect to bastion with default settings"
    echo "  $0 --cluster-name my-cluster          # Connect to specific cluster's bastion"
    echo "  $0 --copy-kubeconfig                  # Copy kubeconfig and connect"
    echo "  $0 --setup-environment                # Connect and setup environment"
    exit 1
}

# Function to check if required files exist
check_bastion_files() {
    local bastion_dir="$1"
    local cluster_name="$2"
    
    local ssh_key_file="$bastion_dir/${cluster_name}-bastion-key.pem"
    local instance_id_file="$bastion_dir/bastion-instance-id"
    local public_ip_file="$bastion_dir/bastion-public-ip"
    
    local missing_files=()
    
    if [[ ! -f "$ssh_key_file" ]]; then
        missing_files+=("SSH key: $ssh_key_file")
    fi
    
    if [[ ! -f "$instance_id_file" ]]; then
        missing_files+=("Instance ID: $instance_id_file")
    fi
    
    if [[ ! -f "$public_ip_file" ]]; then
        missing_files+=("Public IP: $public_ip_file")
    fi
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        echo "❌ Error: Missing required bastion files:"
        for file in "${missing_files[@]}"; do
            echo "   $file"
        done
        echo ""
        echo "Please ensure you have run create-bastion.sh first:"
        echo "   ./create-bastion.sh --cluster-name $cluster_name"
        exit 1
    fi
    
    echo "$ssh_key_file"
}

# Function to get bastion information
get_bastion_info() {
    local bastion_dir="$1"
    local cluster_name="$2"
    
    local ssh_key_file="$bastion_dir/${cluster_name}-bastion-key.pem"
    local instance_id_file="$bastion_dir/bastion-instance-id"
    local public_ip_file="$bastion_dir/bastion-public-ip"
    
    local instance_id
    local public_ip
    
    instance_id=$(cat "$instance_id_file" | tr -d '\n')
    public_ip=$(cat "$public_ip_file" | tr -d '\n')
    
    echo "SSH_KEY_FILE:$ssh_key_file"
    echo "INSTANCE_ID:$instance_id"
    echo "PUBLIC_IP:$public_ip"
}

# Function to copy kubeconfig to bastion
copy_kubeconfig() {
    local ssh_key_file="$1"
    local public_ip="$2"
    local cluster_name="$3"
    
    local kubeconfig_source="./openshift-install/auth/kubeconfig"
    
    if [[ ! -f "$kubeconfig_source" ]]; then
        echo "⚠️  Warning: kubeconfig not found at $kubeconfig_source"
        echo "   You can copy it manually later using:"
        echo "   scp -i $ssh_key_file $kubeconfig_source ec2-user@$public_ip:~/openshift/"
        return 1
    fi
    
    echo "📋 Copying kubeconfig to bastion host..."
    if scp -i "$ssh_key_file" "$kubeconfig_source" "ec2-user@$public_ip:~/openshift/"; then
        echo "✅ kubeconfig copied successfully"
        return 0
    else
        echo "❌ Failed to copy kubeconfig"
        return 1
    fi
}

# Function to setup environment on bastion
setup_environment() {
    local ssh_key_file="$1"
    local public_ip="$2"
    
    echo "🔧 Setting up OpenShift environment on bastion..."
    
    # Create a temporary script to run on the bastion
    local temp_script="/tmp/setup_bastion_env.sh"
    
    cat > "$temp_script" <<'EOF'
#!/bin/bash
# Load OpenShift environment
source /home/ec2-user/openshift/env.sh

# Set up kubeconfig if it exists
if [[ -f "/home/ec2-user/openshift/kubeconfig" ]]; then
    export KUBECONFIG=/home/ec2-user/openshift/kubeconfig
    echo "✅ KUBECONFIG set to /home/ec2-user/openshift/kubeconfig"
    
    # Test cluster connection
    if oc get nodes &>/dev/null; then
        echo "✅ Successfully connected to OpenShift cluster"
        echo ""
        echo "📊 Cluster Information:"
        oc get nodes
        echo ""
        echo "🔧 Cluster Operators:"
        oc get clusteroperators
        echo ""
        echo "🌐 Console URL:"
        oc whoami --show-console
    else
        echo "⚠️  Could not connect to OpenShift cluster"
        echo "   Please check your kubeconfig and cluster status"
    fi
else
    echo "⚠️  kubeconfig not found at /home/ec2-user/openshift/kubeconfig"
    echo "   Please copy it from your local machine:"
    echo "   scp -i <ssh-key> ./openshift-install/auth/kubeconfig ec2-user@$public_ip:~/openshift/"
fi

echo ""
echo "🔧 Available commands:"
echo "   oc get nodes                    # Check cluster nodes"
echo "   oc get clusteroperators         # Check cluster operators"
echo "   oc get clusterversion           # Check cluster version"
echo "   oc whoami --show-console        # Get console URL"
echo "   aws ec2 describe-instances      # Check AWS resources"
echo ""
echo "📁 Workspace: /home/ec2-user/openshift/"
echo "🔑 Environment loaded: source /home/ec2-user/openshift/env.sh"
EOF
    
    # Copy the script to bastion and execute it
    if scp -i "$ssh_key_file" "$temp_script" "ec2-user@$public_ip:/tmp/"; then
        ssh -i "$ssh_key_file" "ec2-user@$public_ip" "chmod +x /tmp/setup_bastion_env.sh && /tmp/setup_bastion_env.sh"
        ssh -i "$ssh_key_file" "ec2-user@$public_ip" "rm -f /tmp/setup_bastion_env.sh"
    else
        echo "❌ Failed to setup environment on bastion"
        return 1
    fi
    
    # Clean up local temp script
    rm -f "$temp_script"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --bastion-output-dir)
            BASTION_OUTPUT_DIR="$2"
            shift 2
            ;;
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --copy-kubeconfig)
            COPY_KUBECONFIG="yes"
            shift
            ;;
        --setup-environment)
            SETUP_ENVIRONMENT="yes"
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
BASTION_OUTPUT_DIR=${BASTION_OUTPUT_DIR:-$DEFAULT_BASTION_OUTPUT_DIR}
CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
COPY_KUBECONFIG=${COPY_KUBECONFIG:-no}
SETUP_ENVIRONMENT=${SETUP_ENVIRONMENT:-no}

# Display script header
echo "🔗 Bastion Host Connection Script"
echo "================================="
echo ""

# Check if bastion output directory exists
if [[ ! -d "$BASTION_OUTPUT_DIR" ]]; then
    echo "❌ Error: Bastion output directory not found: $BASTION_OUTPUT_DIR"
    echo ""
    echo "Please run create-bastion.sh first:"
    echo "   ./create-bastion.sh --cluster-name $CLUSTER_NAME"
    exit 1
fi

# Check for required files
echo "🔍 Checking bastion files..."
ssh_key_file=$(check_bastion_files "$BASTION_OUTPUT_DIR" "$CLUSTER_NAME")

# Get bastion information
echo "📋 Getting bastion information..."
bastion_info=$(get_bastion_info "$BASTION_OUTPUT_DIR" "$CLUSTER_NAME")

ssh_key_file=$(echo "$bastion_info" | grep "^SSH_KEY_FILE:" | cut -d':' -f2-)
instance_id=$(echo "$bastion_info" | grep "^INSTANCE_ID:" | cut -d':' -f2-)
public_ip=$(echo "$bastion_info" | grep "^PUBLIC_IP:" | cut -d':' -f2-)

echo "✅ Bastion information retrieved:"
echo "   Instance ID: $instance_id"
echo "   Public IP: $public_ip"
echo "   SSH Key: $ssh_key_file"
echo ""

# Set proper permissions on SSH key
echo "🔐 Setting SSH key permissions..."
if chmod 600 "$ssh_key_file"; then
    echo "✅ SSH key permissions set"
else
    echo "❌ Failed to set SSH key permissions"
    exit 1
fi

# Copy kubeconfig if requested
if [[ "$COPY_KUBECONFIG" == "yes" ]]; then
    copy_kubeconfig "$ssh_key_file" "$public_ip" "$CLUSTER_NAME"
fi

# Setup environment if requested
if [[ "$SETUP_ENVIRONMENT" == "yes" ]]; then
    setup_environment "$ssh_key_file" "$public_ip"
fi

# Connect to bastion host
echo "🚀 Connecting to bastion host..."
echo "   SSH Command: ssh -i $ssh_key_file ec2-user@$public_ip"
echo ""

# If setup environment was requested, don't start an interactive session
if [[ "$SETUP_ENVIRONMENT" == "yes" ]]; then
    echo "✅ Environment setup completed"
    echo ""
    echo "To connect interactively, run:"
    echo "   ssh -i $ssh_key_file ec2-user@$public_ip"
else
    # Start interactive SSH session
    ssh -i "$ssh_key_file" "ec2-user@$public_ip"
fi 