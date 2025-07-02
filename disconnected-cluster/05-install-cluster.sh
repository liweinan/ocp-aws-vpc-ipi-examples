#!/bin/bash

# Cluster Installation Script for Disconnected OpenShift Cluster
# Installs OpenShift cluster using private mirror registry

set -euo pipefail

# Default values
DEFAULT_CLUSTER_NAME="disconnected-cluster"
DEFAULT_INSTALL_DIR="./openshift-install"
DEFAULT_INFRA_OUTPUT_DIR="./infra-output"
DEFAULT_OPENSHIFT_VERSION="4.18.15"
DEFAULT_LOG_LEVEL="info"
DEFAULT_WAIT_TIMEOUT="60"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --cluster-name        Cluster name (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --install-dir         Installation directory (default: $DEFAULT_INSTALL_DIR)"
    echo "  --infra-output-dir    Infrastructure output directory (default: $DEFAULT_INFRA_OUTPUT_DIR)"
    echo "  --openshift-version   OpenShift version (default: $DEFAULT_OPENSHIFT_VERSION)"
    echo "  --log-level           Log level: info, debug, warn (default: $DEFAULT_LOG_LEVEL)"
    echo "  --wait-timeout        Timeout for waiting operations in minutes (default: $DEFAULT_WAIT_TIMEOUT)"
    echo "  --dry-run             Show what would be done without actually doing it"
    echo "  --help                Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --cluster-name my-cluster"
    echo "  $0 --log-level debug --wait-timeout 90"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    local missing_tools=()
    
    for tool in aws jq yq; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo "❌ Missing required tools: ${missing_tools[*]}"
        echo "Please install the missing tools and try again"
        exit 1
    fi
    
    echo "✅ All required tools are available"
}

# Function to check installation directory
check_install_directory() {
    local install_dir="$1"
    
    if [[ ! -d "$install_dir" ]]; then
        echo "❌ Installation directory not found: $install_dir"
        echo "Please run 04-prepare-install-config.sh first"
        exit 1
    fi
    
    # Check if install-config.yaml exists or if it was already consumed (manifests exist)
    if [[ ! -f "$install_dir/install-config.yaml" ]] && [[ ! -d "$install_dir/manifests" ]]; then
        echo "❌ install-config.yaml not found in $install_dir and no manifests directory"
        echo "Please run 04-prepare-install-config.sh first"
        exit 1
    fi
    
    if [[ -f "$install_dir/install-config.yaml" ]]; then
        echo "✅ Installation directory and config found"
    elif [[ -d "$install_dir/manifests" ]]; then
        echo "✅ Installation directory found with existing manifests (install-config.yaml was consumed)"
    fi
}

# Function to check OpenShift installer
check_openshift_installer() {
    local install_dir="$1"
    local openshift_version="$2"
    
    if [[ ! -f "$install_dir/openshift-install" ]]; then
        echo "📥 OpenShift installer not found, downloading version $openshift_version..."
        
        cd "$install_dir"
        
        # Download installer
        wget -q "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$openshift_version/openshift-install-linux.tar.gz"
        tar xzf openshift-install-linux.tar.gz
        chmod +x openshift-install
        rm openshift-install-linux.tar.gz
        
        # Download oc client
        wget -q "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$openshift_version/openshift-client-linux.tar.gz"
        tar xzf openshift-client-linux.tar.gz
        chmod +x oc kubectl
        rm openshift-client-linux.tar.gz
        
        cd - > /dev/null
        
        echo "✅ OpenShift installer downloaded"
    else
        echo "✅ OpenShift installer found"
    fi
}

# Function to validate install-config.yaml
validate_install_config() {
    local install_dir="$1"
    
    echo "🔍 Validating install-config.yaml..."
    
    cd "$install_dir"
    
    # If install-config.yaml was consumed, manifests should already exist
    if [[ ! -f "install-config.yaml" ]] && [[ -d "manifests" ]]; then
        echo "✅ install-config.yaml was already consumed, manifests exist"
        cd - > /dev/null
        return 0
    fi
    
    # Check if openshift-install can parse the config
    if ! ./openshift-install create manifests --dir=. >/dev/null 2>&1; then
        echo "❌ install-config.yaml validation failed"
        echo "Please check the configuration and try again"
        exit 1
    fi
    
    cd - > /dev/null
    
    echo "✅ install-config.yaml validation passed"
}

# Function to check AWS credentials
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "❌ AWS credentials not configured or invalid"
        echo "Please run 'aws configure' or set appropriate environment variables"
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query 'Account' --output text)
    local user_arn=$(aws sts get-caller-identity --query 'Arn' --output text)
    
    echo "✅ AWS credentials validated"
    echo "   Account ID: $account_id"
    echo "   User ARN: $user_arn"
}

# Function to check infrastructure status
check_infrastructure_status() {
    local infra_dir="$1"
    local cluster_name="$2"
    
    echo "🔍 Checking infrastructure status..."
    
    if [[ ! -f "$infra_dir/vpc-id" ]]; then
        echo "❌ Infrastructure files not found"
        echo "Please run 01-create-infrastructure.sh first"
        exit 1
    fi
    
    local vpc_id=$(cat "$infra_dir/vpc-id")
    local region=$(cat "$infra_dir/region")
    
    # Check if VPC exists
    if ! aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$region" >/dev/null 2>&1; then
        echo "❌ VPC not found: $vpc_id"
        echo "Please ensure infrastructure is still available"
        exit 1
    fi
    
    # Check if bastion host is running
    if [[ -f "$infra_dir/bastion-instance-id" ]]; then
        local bastion_id=$(cat "$infra_dir/bastion-instance-id")
        local bastion_status=$(aws ec2 describe-instances --instance-ids "$bastion_id" --region "$region" --query 'Reservations[0].Instances[0].State.Name' --output text)
        
        if [[ "$bastion_status" != "running" ]]; then
            echo "⚠️  Bastion host is not running (status: $bastion_status)"
            echo "Please ensure bastion host is started before proceeding"
        else
            echo "✅ Bastion host is running"
        fi
    fi
    
    echo "✅ Infrastructure status check completed"
}

# Function to check registry access
check_registry_access() {
    local cluster_name="$1"
    local infra_dir="$2"
    
    echo "🔍 Checking registry access..."
    
    # Check if we're running on bastion host (registry should be local)
    if [[ -f "/opt/registry/certs/domain.crt" ]]; then
        # We're on bastion host, check local registry
        if curl -k -s "https://registry.$cluster_name.local:5000/v2/_catalog" >/dev/null 2>&1; then
            echo "✅ Local registry access working"
        else
            echo "⚠️  Local registry access test failed"
            echo "   Checking if registry container is running..."
            if podman ps | grep -q registry; then
                echo "   Registry container is running, but access failed"
                echo "   This might be a certificate or network issue"
            else
                echo "   Registry container is not running"
                echo "   Please ensure registry is started: sudo systemctl start registry"
            fi
        fi
    else
        # We're not on bastion host, check through bastion
        local bastion_ip=$(cat "$infra_dir/bastion-public-ip")
        if curl -k -s "https://$bastion_ip:5000/v2/_catalog" >/dev/null 2>&1; then
            echo "✅ Registry access through bastion working"
        else
            echo "⚠️  Registry access test failed"
            echo "   This might be normal if you haven't added the hosts entry yet"
            echo "   Make sure to add: $bastion_ip registry.$cluster_name.local to /etc/hosts"
        fi
    fi
}

# Function to create installation log
create_installation_log() {
    local install_dir="$1"
    local cluster_name="$2"
    
    local log_file="$install_dir/install-$(date +%Y%m%d-%H%M%S).log"
    
    echo "📝 Installation log will be saved to: $log_file"
    echo "$log_file"
}

# Function to perform cluster installation
perform_cluster_installation() {
    local install_dir="$1"
    local log_level="$2"
    local log_file="$3"
    
    echo "🚀 Starting OpenShift cluster installation..."
    echo "⏳ This process will take approximately 30-45 minutes..."
    echo "📝 Log file: $log_file"
    echo ""
    
    cd "$install_dir"
    
    # Start installation with logging
    echo "🔄 Running: ./openshift-install create cluster --log-level=$log_level"
    echo ""
    
    if ! ./openshift-install create cluster --log-level="$log_level" 2>&1 | tee "$log_file"; then
        echo ""
        echo "❌ Cluster installation failed"
        echo "Check the log file for details: $log_file"
        cd - > /dev/null
        exit 1
    fi
    
    cd - > /dev/null
    
    echo ""
    echo "✅ Cluster installation completed successfully!"
}

# Function to extract cluster information
extract_cluster_info() {
    local install_dir="$1"
    local cluster_name="$2"
    
    echo "📋 Extracting cluster information..."
    
    cd "$install_dir"
    
    # Get console URL
    local console_url=$(./openshift-install --dir=. wait-for bootstrap-complete --log-level=info 2>&1 | grep "Console URL" | awk '{print $3}' || echo "Not available yet")
    
    # Get API URL
    local api_url=$(./openshift-install --dir=. wait-for bootstrap-complete --log-level=info 2>&1 | grep "API URL" | awk '{print $3}' || echo "Not available yet")
    
    # Get kubeadmin password
    local kubeadmin_password=""
    if [[ -f "auth/kubeadmin-password" ]]; then
        kubeadmin_password=$(cat auth/kubeadmin-password)
    fi
    
    cd - > /dev/null
    
    # Save cluster information
    cat > "cluster-info-$cluster_name.yaml" <<EOF
# Cluster Information for $cluster_name
# Generated on $(date)

cluster_name: $cluster_name
console_url: $console_url
api_url: $api_url
kubeadmin_password: $kubeadmin_password
kubeconfig: $install_dir/auth/kubeconfig
install_log: $install_dir/install-*.log

# Access Information:
# Console: $console_url
# API: $api_url
# Username: kubeadmin
# Password: $kubeadmin_password
# Kubeconfig: $install_dir/auth/kubeconfig
EOF
    
    echo "✅ Cluster information saved to: cluster-info-$cluster_name.yaml"
}

# Function to wait for cluster readiness
wait_for_cluster_readiness() {
    local install_dir="$1"
    local wait_timeout="$2"
    
    echo "⏳ Waiting for cluster to be ready..."
    echo "   Timeout: $wait_timeout minutes"
    echo ""
    
    cd "$install_dir"
    
    # Wait for bootstrap to complete
    echo "🔄 Waiting for bootstrap to complete..."
    if ! timeout "${wait_timeout}m" ./openshift-install --dir=. wait-for bootstrap-complete --log-level=info; then
        echo "❌ Bootstrap completion timeout"
        echo "Check the installation logs for details"
        cd - > /dev/null
        return 1
    fi
    
    # Wait for install to complete
    echo "🔄 Waiting for installation to complete..."
    if ! timeout "${wait_timeout}m" ./openshift-install --dir=. wait-for install-complete --log-level=info; then
        echo "❌ Installation completion timeout"
        echo "Check the installation logs for details"
        cd - > /dev/null
        return 1
    fi
    
    cd - > /dev/null
    
    echo "✅ Cluster is ready!"
}

# Function to verify cluster access
verify_cluster_access() {
    local install_dir="$1"
    local cluster_name="$2"
    
    echo "🔍 Verifying cluster access..."
    
    cd "$install_dir"
    
    # Set kubeconfig
    export KUBECONFIG="$PWD/auth/kubeconfig"
    
    # Test cluster access
    if ! ./oc whoami --show-console 2>/dev/null; then
        echo "❌ Cluster access verification failed"
        echo "Please check the installation logs"
        cd - > /dev/null
        return 1
    fi
    
    # Get cluster information
    echo ""
    echo "📊 Cluster Information:"
    ./oc whoami --show-console
    ./oc whoami --show-server
    
    # Check cluster operators
    echo ""
    echo "🔧 Checking cluster operators..."
    ./oc get clusteroperators --no-headers | head -10
    
    # Check nodes
    echo ""
    echo "🖥️  Checking cluster nodes..."
    ./oc get nodes --no-headers
    
    cd - > /dev/null
    
    echo "✅ Cluster access verified"
}

# Function to create post-installation script
create_post_installation_script() {
    local install_dir="$1"
    local cluster_name="$2"
    
    echo "📝 Creating post-installation script..."
    
    cat > "$install_dir/post-install-$cluster_name.sh" <<EOF
#!/bin/bash
# Post-installation tasks for $cluster_name

set -euo pipefail

CLUSTER_NAME="$cluster_name"
INSTALL_DIR="$install_dir"

echo "🔧 Post-installation tasks for \$CLUSTER_NAME"
echo "============================================="
echo ""

# Set kubeconfig
export KUBECONFIG="\$INSTALL_DIR/auth/kubeconfig"

# Check cluster status
echo "📊 Checking cluster status..."
oc get clusterversion
oc get clusteroperators

# Check node status
echo ""
echo "🖥️  Checking node status..."
oc get nodes

# Check critical pods
echo ""
echo "📦 Checking critical pods..."
oc get pods -n openshift-apiserver
oc get pods -n openshift-controller-manager
oc get pods -n openshift-scheduler

# Check registry
echo ""
echo "🔗 Checking image registry..."
oc get pods -n openshift-image-registry

# Show access information
echo ""
echo "🔗 Cluster Access Information:"
echo "   Console URL: \$(oc whoami --show-console)"
echo "   API URL: \$(oc whoami --show-server)"
echo "   Username: kubeadmin"
echo "   Password: \$(cat \$INSTALL_DIR/auth/kubeadmin-password)"
echo "   Kubeconfig: \$KUBECONFIG"

echo ""
echo "✅ Post-installation tasks completed!"
EOF
    
    chmod +x "$install_dir/post-install-$cluster_name.sh"
    
    echo "✅ Post-installation script created: $install_dir/post-install-$cluster_name.sh"
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
            --install-dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            --infra-output-dir)
                INFRA_OUTPUT_DIR="$2"
                shift 2
                ;;
            --openshift-version)
                OPENSHIFT_VERSION="$2"
                shift 2
                ;;
            --log-level)
                LOG_LEVEL="$2"
                shift 2
                ;;
            --wait-timeout)
                WAIT_TIMEOUT="$2"
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
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}
    INFRA_OUTPUT_DIR=${INFRA_OUTPUT_DIR:-$DEFAULT_INFRA_OUTPUT_DIR}
    OPENSHIFT_VERSION=${OPENSHIFT_VERSION:-$DEFAULT_OPENSHIFT_VERSION}
    LOG_LEVEL=${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}
    WAIT_TIMEOUT=${WAIT_TIMEOUT:-$DEFAULT_WAIT_TIMEOUT}
    DRY_RUN=${DRY_RUN:-no}
    
    # Display script header
    echo "🚀 OpenShift Cluster Installation for Disconnected Environment"
    echo "============================================================="
    echo ""
    echo "📋 Configuration:"
    echo "   Cluster Name: $CLUSTER_NAME"
    echo "   Installation Directory: $INSTALL_DIR"
    echo "   OpenShift Version: $OPENSHIFT_VERSION"
    echo "   Log Level: $LOG_LEVEL"
    echo "   Wait Timeout: $WAIT_TIMEOUT minutes"
    echo "   Dry Run: $DRY_RUN"
    echo ""
    
    if [[ "$DRY_RUN" == "yes" ]]; then
        echo "🔍 DRY RUN MODE - No installation will be performed"
        echo ""
        echo "Would perform:"
        echo "  - Validate install-config.yaml"
        echo "  - Check AWS credentials and infrastructure"
        echo "  - Download OpenShift installer (if needed)"
        echo "  - Install OpenShift cluster"
        echo "  - Wait for cluster readiness"
        echo "  - Verify cluster access"
        echo ""
        echo "To actually install the cluster, run without --dry-run"
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Check installation directory
    check_install_directory "$INSTALL_DIR"
    
    # Check AWS credentials
    check_aws_credentials
    
    # Check infrastructure status
    check_infrastructure_status "$INFRA_OUTPUT_DIR" "$CLUSTER_NAME"
    
    # Check registry access
    check_registry_access "$CLUSTER_NAME" "$INFRA_OUTPUT_DIR"
    
    # Check OpenShift installer
    check_openshift_installer "$INSTALL_DIR" "$OPENSHIFT_VERSION"
    
    # Validate install-config.yaml
    validate_install_config "$INSTALL_DIR"
    
    # Create installation log
    local log_file=$(create_installation_log "$INSTALL_DIR" "$CLUSTER_NAME")
    
    # Confirm installation
    echo "⚠️  This will create an OpenShift cluster with the following resources:"
    echo "   - Control plane nodes (3x m5.xlarge)"
    echo "   - Compute nodes (3x m5.xlarge)"
    echo "   - Associated AWS resources (load balancers, security groups, etc.)"
    echo "   - Estimated cost: $50-100 per day"
    echo ""
    read -p "Do you want to proceed with the installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled"
        exit 0
    fi
    
    # Perform cluster installation
    perform_cluster_installation "$INSTALL_DIR" "$LOG_LEVEL" "$log_file"
    
    # Wait for cluster readiness
    wait_for_cluster_readiness "$INSTALL_DIR" "$WAIT_TIMEOUT"
    
    # Extract cluster information
    extract_cluster_info "$INSTALL_DIR" "$CLUSTER_NAME"
    
    # Verify cluster access
    verify_cluster_access "$INSTALL_DIR" "$CLUSTER_NAME"
    
    # Create post-installation script
    create_post_installation_script "$INSTALL_DIR" "$CLUSTER_NAME"
    
    echo ""
    echo "✅ OpenShift cluster installation completed successfully!"
    echo ""
    echo "📁 Files created:"
    echo "   $INSTALL_DIR/auth/kubeconfig: Cluster access configuration"
    echo "   $INSTALL_DIR/auth/kubeadmin-password: Admin password"
    echo "   cluster-info-$CLUSTER_NAME.yaml: Cluster information"
    echo "   $INSTALL_DIR/post-install-$CLUSTER_NAME.sh: Post-installation tasks"
    echo ""
    echo "🔗 Access Information:"
    echo "   Console URL: Check cluster-info-$CLUSTER_NAME.yaml"
    echo "   API URL: Check cluster-info-$CLUSTER_NAME.yaml"
    echo "   Username: kubeadmin"
    echo "   Password: Check cluster-info-$CLUSTER_NAME.yaml"
    echo ""
    echo "🔧 Next steps:"
    echo "1. Access the OpenShift console"
    echo "2. Login with kubeadmin and the password from cluster-info-$CLUSTER_NAME.yaml"
    echo "3. Run: cd $INSTALL_DIR && ./post-install-$CLUSTER_NAME.sh"
    echo "4. Configure additional users and permissions"
    echo ""
    echo "📝 Important notes:"
    echo "   - The cluster is installed in Internal publish mode"
    echo "   - All images are pulled from your private registry"
    echo "   - The cluster is accessible only through the bastion host"
    echo "   - Keep the kubeconfig file secure"
}

# Run main function with all arguments
main "$@" 