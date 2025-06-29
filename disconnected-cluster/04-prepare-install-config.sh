#!/bin/bash

# Install Config Preparation Script for Disconnected OpenShift Cluster
# Generates install-config.yaml for disconnected cluster installation

set -euo pipefail

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

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --cluster-name        Cluster name (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --infra-output-dir    Infrastructure output directory (default: $DEFAULT_INFRA_OUTPUT_DIR)"
    echo "  --sync-output-dir     Sync output directory (default: $DEFAULT_SYNC_OUTPUT_DIR)"
    echo "  --base-domain         Base domain (default: $DEFAULT_BASE_DOMAIN)"
    echo "  --region              AWS region (default: $DEFAULT_REGION)"
    echo "  --registry-port       Registry port (default: $DEFAULT_REGISTRY_PORT)"
    echo "  --registry-user       Registry username (default: $DEFAULT_REGISTRY_USER)"
    echo "  --registry-password   Registry password (default: $DEFAULT_REGISTRY_PASSWORD)"
    echo "  --install-dir         Installation directory (default: $DEFAULT_INSTALL_DIR)"
    echo "  --ssh-key             SSH public key file (default: $DEFAULT_SSH_KEY)"
    echo "  --pull-secret         Pull secret file or content"
    echo "  --dry-run             Show what would be created without actually creating"
    echo "  --help                Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --cluster-name my-cluster --base-domain mydomain.com"
    echo "  $0 --pull-secret pull-secret.json --ssh-key ~/.ssh/id_ed25519.pub"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    local missing_tools=()
    
    for tool in yq jq; do
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

# Function to check infrastructure files
check_infrastructure() {
    local infra_dir="$1"
    
    local required_files=(
        "vpc-id"
        "private-subnet-ids"
        "region"
        "bastion-public-ip"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$infra_dir/$file" ]]; then
            echo "❌ Required infrastructure file not found: $infra_dir/$file"
            echo "Please run 01-create-infrastructure.sh first"
            exit 1
        fi
    done
    
    echo "✅ Infrastructure files found"
}

# Function to check sync files
check_sync_files() {
    local sync_dir="$1"
    
    if [[ ! -d "$sync_dir" ]]; then
        echo "❌ Sync directory not found: $sync_dir"
        echo "Please run 03-sync-images.sh first"
        exit 1
    fi
    
    if [[ ! -f "$sync_dir/install-config-template.yaml" ]]; then
        echo "❌ Install config template not found: $sync_dir/install-config-template.yaml"
        echo "Please run 03-sync-images.sh first"
        exit 1
    fi
    
    echo "✅ Sync files found"
}

# Function to get SSH public key
get_ssh_key() {
    local ssh_key_file="$1"
    
    # Expand tilde if present
    ssh_key_file="${ssh_key_file/#\~/$HOME}"
    
    if [[ ! -f "$ssh_key_file" ]]; then
        echo "❌ SSH public key file not found: $ssh_key_file"
        echo "Please provide a valid SSH public key file"
        exit 1
    fi
    
    local ssh_key_content=$(cat "$ssh_key_file")
    echo "$ssh_key_content"
}

# Function to get pull secret
get_pull_secret() {
    local pull_secret_input="$1"
    
    if [[ -z "$pull_secret_input" ]]; then
        echo "❌ Pull secret is required"
        echo "Please provide a pull secret using --pull-secret"
        echo "You can get it from: https://console.redhat.com/openshift/install/pull-secret"
        exit 1
    fi
    
    # Check if it's a file
    if [[ -f "$pull_secret_input" ]]; then
        local pull_secret_content=$(cat "$pull_secret_input")
        echo "$pull_secret_content"
    else
        # Assume it's the content directly
        echo "$pull_secret_input"
    fi
}

# Function to get registry certificate
get_registry_certificate() {
    local cluster_name="$1"
    local registry_port="$2"
    local infra_dir="$3"
    
    local bastion_ip=$(cat "$infra_dir/bastion-public-ip")
    local ssh_key="$infra_dir/bastion-key.pem"
    
    echo "📥 Downloading registry certificate..."
    
    # Create temporary script to get certificate
    local temp_script=$(mktemp)
    cat > "$temp_script" <<EOF
#!/bin/bash
# Get registry certificate from bastion host

set -euo pipefail

REGISTRY_CERT="/opt/registry/certs/domain.crt"

if [[ -f "\$REGISTRY_CERT" ]]; then
    cat "\$REGISTRY_CERT"
else
    echo "❌ Registry certificate not found: \$REGISTRY_CERT"
    exit 1
fi
EOF
    
    # Execute script on bastion host
    local cert_content=$(ssh -i "$ssh_key" -o StrictHostKeyChecking=no "ec2-user@$bastion_ip" "bash -s" < "$temp_script")
    
    # Clean up
    rm -f "$temp_script"
    
    if [[ $? -eq 0 ]]; then
        echo "$cert_content"
    else
        echo "❌ Failed to get registry certificate"
        echo "   You can manually copy it from: /opt/registry/certs/domain.crt on bastion host"
        return 1
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
    
    echo "📝 Creating install-config.yaml..."
    
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
  replicas: 3
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      type: m5.xlarge
  replicas: 3
metadata:
  name: $cluster_name
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OpenShiftSDN
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
    
    echo "✅ install-config.yaml created"
}

# Function to create backup
create_backup() {
    local install_dir="$1"
    local cluster_name="$2"
    
    local backup_file="install-config-$cluster_name-backup-$(date +%Y%m%d-%H%M%S).yaml"
    cp "$install_dir/install-config.yaml" "$backup_file"
    
    echo "✅ Backup created: $backup_file"
}

# Function to validate install-config.yaml
validate_install_config() {
    local install_dir="$1"
    
    echo "🔍 Validating install-config.yaml..."
    
    if ! yq eval '.' "$install_dir/install-config.yaml" >/dev/null 2>&1; then
        echo "❌ install-config.yaml is not valid YAML"
        return 1
    fi
    
    # Check required fields
    local required_fields=(
        "baseDomain"
        "metadata.name"
        "platform.aws.region"
        "platform.aws.vpc"
        "pullSecret"
        "sshKey"
        "additionalTrustBundle"
        "imageContentSources"
    )
    
    for field in "${required_fields[@]}"; do
        if ! yq eval ".$field" "$install_dir/install-config.yaml" >/dev/null 2>&1; then
            echo "❌ Required field missing: $field"
            return 1
        fi
    done
    
    echo "✅ install-config.yaml validation passed"
}

# Function to create helper scripts
create_helper_scripts() {
    local install_dir="$1"
    local cluster_name="$2"
    local registry_port="$3"
    local registry_user="$4"
    local registry_password="$5"
    
    echo "📝 Creating helper scripts..."
    
    # Create installation script
    cat > "$install_dir/install-cluster.sh" <<EOF
#!/bin/bash
# Install OpenShift cluster using disconnected registry

set -euo pipefail

CLUSTER_NAME="$cluster_name"
REGISTRY_URL="registry.$cluster_name.local:$registry_port"
REGISTRY_USER="$registry_user"
REGISTRY_PASSWORD="$registry_password"

echo "🚀 Installing OpenShift cluster: \$CLUSTER_NAME"
echo "=============================================="
echo ""

# Check if openshift-install exists
if [[ ! -f "./openshift-install" ]]; then
    echo "❌ openshift-install not found in current directory"
    echo "Please ensure you have the OpenShift installer available"
    exit 1
fi

# Validate install-config.yaml
echo "🔍 Validating install-config.yaml..."
if ! ./openshift-install create install-config --dir=. --dry-run; then
    echo "❌ install-config.yaml validation failed"
    exit 1
fi

# Start installation
echo "🚀 Starting cluster installation..."
echo "⏳ This process will take approximately 30-45 minutes..."
echo ""

./openshift-install create cluster --log-level=info

echo ""
echo "✅ Cluster installation completed!"
echo ""
echo "📋 Cluster Information:"
echo "   Console URL: Check the installation output above"
echo "   API URL: Check the installation output above"
echo "   Username: kubeadmin"
echo "   Password: \$(cat auth/kubeadmin-password)"
echo ""
echo "🔧 Next Steps:"
echo "1. Access the OpenShift console"
echo "2. Login with kubeadmin and the password shown above"
echo "3. Download the kubeconfig file: \$PWD/auth/kubeconfig"
echo "4. Use 'oc login' to access the cluster from command line"
EOF
    
    chmod +x "$install_dir/install-cluster.sh"
    
    # Create verification script
    cat > "$install_dir/verify-cluster.sh" <<EOF
#!/bin/bash
# Verify OpenShift cluster installation

set -euo pipefail

CLUSTER_NAME="$cluster_name"

echo "🔍 Verifying OpenShift cluster: \$CLUSTER_NAME"
echo "============================================="
echo ""

# Check if kubeconfig exists
if [[ ! -f "./auth/kubeconfig" ]]; then
    echo "❌ kubeconfig not found"
    echo "Please ensure cluster installation is complete"
    exit 1
fi

# Set kubeconfig
export KUBECONFIG="\$PWD/auth/kubeconfig"

# Check cluster operators
echo "📊 Checking cluster operators..."
oc get clusteroperators

# Check nodes
echo ""
echo "🖥️  Checking cluster nodes..."
oc get nodes

# Check pods
echo ""
echo "📦 Checking critical pods..."
oc get pods -n openshift-apiserver
oc get pods -n openshift-controller-manager
oc get pods -n openshift-scheduler

# Check registry access
echo ""
echo "🔗 Checking registry access..."
oc get pods -n openshift-image-registry

echo ""
echo "✅ Cluster verification completed!"
EOF
    
    chmod +x "$install_dir/verify-cluster.sh"
    
    echo "✅ Helper scripts created"
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
            --infra-output-dir)
                INFRA_OUTPUT_DIR="$2"
                shift 2
                ;;
            --sync-output-dir)
                SYNC_OUTPUT_DIR="$2"
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
    INFRA_OUTPUT_DIR=${INFRA_OUTPUT_DIR:-$DEFAULT_INFRA_OUTPUT_DIR}
    SYNC_OUTPUT_DIR=${SYNC_OUTPUT_DIR:-$DEFAULT_SYNC_OUTPUT_DIR}
    BASE_DOMAIN=${BASE_DOMAIN:-$DEFAULT_BASE_DOMAIN}
    REGION=${REGION:-$DEFAULT_REGION}
    REGISTRY_PORT=${REGISTRY_PORT:-$DEFAULT_REGISTRY_PORT}
    REGISTRY_USER=${REGISTRY_USER:-$DEFAULT_REGISTRY_USER}
    REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-$DEFAULT_REGISTRY_PASSWORD}
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}
    SSH_KEY=${SSH_KEY:-$DEFAULT_SSH_KEY}
    PULL_SECRET=${PULL_SECRET:-}
    DRY_RUN=${DRY_RUN:-no}
    
    # Display script header
    echo "📝 Install Config Preparation for Disconnected OpenShift Cluster"
    echo "==============================================================="
    echo ""
    echo "📋 Configuration:"
    echo "   Cluster Name: $CLUSTER_NAME"
    echo "   Base Domain: $BASE_DOMAIN"
    echo "   Region: $REGION"
    echo "   Registry URL: registry.$CLUSTER_NAME.local:$REGISTRY_PORT"
    echo "   Installation Directory: $INSTALL_DIR"
    echo "   SSH Key: $SSH_KEY"
    echo "   Dry Run: $DRY_RUN"
    echo ""
    
    if [[ "$DRY_RUN" == "yes" ]]; then
        echo "🔍 DRY RUN MODE - No files will be created"
        echo ""
        echo "Would create:"
        echo "  - install-config.yaml in $INSTALL_DIR"
        echo "  - Helper scripts for installation and verification"
        echo "  - Backup of install-config.yaml"
        echo ""
        echo "To actually create files, run without --dry-run"
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Check infrastructure
    check_infrastructure "$INFRA_OUTPUT_DIR"
    
    # Check sync files
    check_sync_files "$SYNC_OUTPUT_DIR"
    
    # Get infrastructure information
    local vpc_id=$(cat "$INFRA_OUTPUT_DIR/vpc-id")
    local private_subnet_ids=$(cat "$INFRA_OUTPUT_DIR/private-subnet-ids")
    local region=$(cat "$INFRA_OUTPUT_DIR/region")
    
    # Get SSH key
    local ssh_key_content=$(get_ssh_key "$SSH_KEY")
    
    # Get pull secret
    local pull_secret_content=$(get_pull_secret "$PULL_SECRET")
    
    # Get registry certificate
    local registry_cert=$(get_registry_certificate "$CLUSTER_NAME" "$REGISTRY_PORT" "$INFRA_OUTPUT_DIR")
    
    # Create install-config.yaml
    create_install_config "$CLUSTER_NAME" "$BASE_DOMAIN" "$region" "$vpc_id" "$private_subnet_ids" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD" "$ssh_key_content" "$pull_secret_content" "$registry_cert" "$INSTALL_DIR"
    
    # Create backup
    create_backup "$INSTALL_DIR" "$CLUSTER_NAME"
    
    # Validate install-config.yaml
    validate_install_config "$INSTALL_DIR"
    
    # Create helper scripts
    create_helper_scripts "$INSTALL_DIR" "$CLUSTER_NAME" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"
    
    echo ""
    echo "✅ Install config preparation completed successfully!"
    echo ""
    echo "📁 Files created in: $INSTALL_DIR"
    echo "   install-config.yaml: Main installation configuration"
    echo "   install-cluster.sh: Cluster installation script"
    echo "   verify-cluster.sh: Cluster verification script"
    echo ""
    echo "🔗 Next steps:"
    echo "1. Review install-config.yaml and customize if needed"
    echo "2. Copy OpenShift installer to $INSTALL_DIR"
    echo "3. Run: cd $INSTALL_DIR && ./install-cluster.sh"
    echo ""
    echo "📝 Important notes:"
    echo "   - The cluster will be installed in Internal publish mode"
    echo "   - All images will be pulled from your private registry"
    echo "   - The registry certificate is included in additionalTrustBundle"
    echo "   - Ensure your bastion host is accessible from the cluster nodes"
}

# Run main function with all arguments
main "$@" 