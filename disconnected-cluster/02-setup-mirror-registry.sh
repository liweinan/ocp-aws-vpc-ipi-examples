#!/bin/bash

# Mirror Registry Setup Script for Disconnected OpenShift Cluster
# Sets up a private registry on the bastion host for mirroring OpenShift images

set -euo pipefail

# Default values
DEFAULT_CLUSTER_NAME="disconnected-cluster"
DEFAULT_INFRA_OUTPUT_DIR="./infra-output"
DEFAULT_REGISTRY_PORT="5000"
DEFAULT_REGISTRY_USER="admin"
DEFAULT_REGISTRY_PASSWORD="admin123"
DEFAULT_REGISTRY_STORAGE="/opt/registry"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --cluster-name        Cluster name (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --infra-output-dir    Infrastructure output directory (default: $DEFAULT_INFRA_OUTPUT_DIR)"
    echo "  --registry-port       Registry port (default: $DEFAULT_REGISTRY_PORT)"
    echo "  --registry-user       Registry username (default: $DEFAULT_REGISTRY_USER)"
    echo "  --registry-password   Registry password (default: $DEFAULT_REGISTRY_PASSWORD)"
    echo "  --registry-storage    Registry storage path (default: $DEFAULT_REGISTRY_STORAGE)"
    echo "  --dry-run             Show what would be done without actually doing it"
    echo "  --help                Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --cluster-name my-disconnected-cluster"
    echo "  $0 --registry-user mirror --registry-password secure123"
    exit 1
}

# Function to check if infrastructure files exist
check_infrastructure() {
    local infra_dir="$1"
    
    local required_files=(
        "vpc-id"
        "bastion-public-ip"
        "bastion-key.pem"
        "bastion-security-group-id"
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

# Function to connect to bastion and setup registry
setup_registry_on_bastion() {
    local cluster_name="$1"
    local bastion_ip="$2"
    local ssh_key="$3"
    local registry_port="$4"
    local registry_user="$5"
    local registry_password="$6"
    local registry_storage="$7"
    
    echo "🔧 Setting up mirror registry on bastion host..."
    
    # Create setup script
    local setup_script=$(mktemp)
    cat > "$setup_script" <<EOF
#!/bin/bash
set -euo pipefail

echo "🚀 Setting up mirror registry for disconnected OpenShift cluster"
echo "================================================================"
echo ""

# Check if Docker is running
if ! systemctl is-active --quiet docker; then
    echo "❌ Docker is not running. Starting Docker..."
    sudo systemctl start docker
    sudo systemctl enable docker
fi

# Check if user is in docker group
if ! groups | grep -q docker; then
    echo "⚠️  User not in docker group. Adding to docker group..."
    sudo usermod -aG docker \$USER
    echo "Please log out and log back in, or run: newgrp docker"
fi

# Create registry directories
echo "📁 Creating registry directories..."
sudo mkdir -p $registry_storage
sudo mkdir -p $registry_storage/auth
sudo mkdir -p $registry_storage/certs
sudo chown -R \$USER:\$USER $registry_storage

# Install required packages
echo "📦 Installing required packages..."
sudo dnf install -y httpd-tools

# Create authentication
echo "🔐 Creating registry authentication..."
htpasswd -bBc $registry_storage/auth/htpasswd $registry_user "$registry_password"

# Create self-signed certificate
echo "🔒 Creating self-signed certificate..."
openssl req -newkey rsa:4096 -nodes -sha256 -keyout $registry_storage/certs/domain.key \
    -x509 -days 365 -out $registry_storage/certs/domain.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=registry.$cluster_name.local"

# Stop existing registry if running
echo "🛑 Stopping existing registry if running..."
docker stop mirror-registry 2>/dev/null || true
docker rm mirror-registry 2>/dev/null || true

# Start registry with authentication and TLS
echo "🚀 Starting mirror registry..."
docker run -d \\
    --name mirror-registry \\
    --restart=always \\
    -p $registry_port:5000 \\
    -v $registry_storage:/var/lib/registry:z \\
    -v $registry_storage/auth:/auth:z \\
    -v $registry_storage/certs:/certs:z \\
    -e REGISTRY_AUTH=htpasswd \\
    -e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" \\
    -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \\
    -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \\
    -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \\
    registry:2

# Wait for registry to start
echo "⏳ Waiting for registry to start..."
sleep 10

# Test registry
echo "🧪 Testing registry..."
if curl -k -u $registry_user:$registry_password https://localhost:$registry_port/v2/_catalog; then
    echo "✅ Registry is working correctly"
else
    echo "❌ Registry test failed"
    exit 1
fi

# Create registry configuration for OpenShift
echo "📝 Creating registry configuration..."
cat > /home/ec2-user/registry-config.yaml <<'CONFIG_EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: registry-config
  namespace: openshift-config
data:
  registry.conf: |
    unqualified-search-registries = ["registry.$cluster_name.local:$registry_port"]
    [[registry]]
      location = "registry.$cluster_name.local:$registry_port"
      insecure = true
      prefix = ""
CONFIG_EOF

# Create helpful scripts
cat > /home/ec2-user/registry-utils.sh <<'UTILS_EOF'
#!/bin/bash
# Registry utility functions

REGISTRY_URL="registry.$cluster_name.local:$registry_port"
REGISTRY_USER="$registry_user"
REGISTRY_PASSWORD="$registry_password"

# Function to login to registry
registry_login() {
    echo "🔐 Logging into registry..."
    podman login --username \$REGISTRY_USER --password \$REGISTRY_PASSWORD --tls-verify=false \$REGISTRY_URL
}

# Function to list images in registry
list_images() {
    echo "📋 Listing images in registry..."
    curl -k -u \$REGISTRY_USER:\$REGISTRY_PASSWORD https://\$REGISTRY_URL/v2/_catalog | jq .
}

# Function to check registry health
check_health() {
    echo "🏥 Checking registry health..."
    if curl -k -u \$REGISTRY_USER:\$REGISTRY_PASSWORD https://\$REGISTRY_URL/v2/_catalog >/dev/null 2>&1; then
        echo "✅ Registry is healthy"
    else
        echo "❌ Registry is not responding"
    fi
}

# Function to show registry info
show_info() {
    echo "📊 Registry Information:"
    echo "   URL: \$REGISTRY_URL"
    echo "   User: \$REGISTRY_USER"
    echo "   Storage: $registry_storage"
    echo "   Certificate: $registry_storage/certs/domain.crt"
    echo ""
    echo "🔗 Access URLs:"
    echo "   HTTPS: https://\$REGISTRY_URL"
    echo "   Docker: \$REGISTRY_URL"
    echo ""
    echo "📝 Usage examples:"
    echo "   podman login --username \$REGISTRY_USER --password \$REGISTRY_PASSWORD --tls-verify=false \$REGISTRY_URL"
    echo "   podman pull \$REGISTRY_URL/openshift/ose-cli:latest"
    echo "   curl -k -u \$REGISTRY_USER:\$REGISTRY_PASSWORD https://\$REGISTRY_URL/v2/_catalog"
}

case "\$1" in
    login)
        registry_login
        ;;
    list)
        list_images
        ;;
    health)
        check_health
        ;;
    info)
        show_info
        ;;
    *)
        echo "Usage: \$0 {login|list|health|info}"
        exit 1
        ;;
esac
UTILS_EOF

chmod +x /home/ec2-user/registry-utils.sh

# Create environment file
cat > /home/ec2-user/registry.env <<'ENV_EOF'
export REGISTRY_URL="registry.$cluster_name.local:$registry_port"
export REGISTRY_USER="$registry_user"
export REGISTRY_PASSWORD="$registry_password"
export REGISTRY_STORAGE="$registry_storage"
export CLUSTER_NAME="$cluster_name"
ENV_EOF

echo ""
echo "✅ Mirror registry setup completed!"
echo ""
echo "📊 Registry Information:"
echo "   URL: registry.$cluster_name.local:$registry_port"
echo "   User: $registry_user"
echo "   Storage: $registry_storage"
echo ""
echo "🔧 Available commands:"
echo "   source ~/registry.env                    # Load registry environment"
echo "   ~/registry-utils.sh info                 # Show registry information"
echo "   ~/registry-utils.sh health               # Check registry health"
echo "   ~/registry-utils.sh login                # Login to registry"
echo "   ~/registry-utils.sh list                 # List images in registry"
echo ""
echo "📝 Next steps:"
echo "1. Add registry.$cluster_name.local to /etc/hosts on your local machine"
echo "2. Run: ./03-sync-images.sh to sync OpenShift images"
echo ""
echo "🔗 Registry access:"
echo "   HTTPS: https://registry.$cluster_name.local:$registry_port"
echo "   Docker: registry.$cluster_name.local:$registry_port"
EOF
    
    # Copy setup script to bastion
    echo "📤 Copying setup script to bastion host..."
    scp -i "$ssh_key" -o StrictHostKeyChecking=no "$setup_script" "ec2-user@$bastion_ip:/tmp/setup-registry.sh"
    
    # Execute setup script on bastion
    echo "🚀 Executing setup script on bastion host..."
    ssh -i "$ssh_key" -o StrictHostKeyChecking=no "ec2-user@$bastion_ip" "chmod +x /tmp/setup-registry.sh && /tmp/setup-registry.sh"
    
    # Clean up local script
    rm -f "$setup_script"
    
    echo "✅ Mirror registry setup completed on bastion host"
}

# Function to create local configuration
create_local_config() {
    local cluster_name="$1"
    local bastion_ip="$2"
    local registry_port="$3"
    local infra_dir="$4"
    
    echo "📝 Creating local configuration files..."
    
    # Create hosts file entry
    local hosts_entry="$bastion_ip registry.$cluster_name.local"
    echo "📋 Add this entry to your /etc/hosts file:"
    echo "   $hosts_entry"
    echo ""
    
    # Create registry configuration file
    cat > "registry-config-$cluster_name.yaml" <<EOF
# Registry configuration for $cluster_name
# Add this entry to your /etc/hosts file:
# $hosts_entry

registry_url: "registry.$cluster_name.local:$registry_port"
registry_user: "$DEFAULT_REGISTRY_USER"
registry_password: "$DEFAULT_REGISTRY_PASSWORD"
bastion_ip: "$bastion_ip"
cluster_name: "$cluster_name"

# Test registry access:
# curl -k -u $DEFAULT_REGISTRY_USER:$DEFAULT_REGISTRY_PASSWORD https://registry.$cluster_name.local:$registry_port/v2/_catalog

# Login to registry:
# podman login --username $DEFAULT_REGISTRY_USER --password $DEFAULT_REGISTRY_PASSWORD --tls-verify=false registry.$cluster_name.local:$registry_port
EOF
    
    echo "✅ Local configuration created: registry-config-$cluster_name.yaml"
}

# Function to test registry access
test_registry_access() {
    local cluster_name="$1"
    local registry_port="$2"
    local registry_user="$3"
    local registry_password="$4"
    
    echo "🧪 Testing registry access..."
    
    # Test HTTPS access
    if curl -k -u "$registry_user:$registry_password" "https://registry.$cluster_name.local:$registry_port/v2/_catalog" >/dev/null 2>&1; then
        echo "✅ Registry HTTPS access working"
    else
        echo "❌ Registry HTTPS access failed"
        echo "   Make sure you've added the hosts entry:"
        echo "   $(cat $DEFAULT_INFRA_OUTPUT_DIR/bastion-public-ip) registry.$cluster_name.local"
        return 1
    fi
    
    # Test Docker/Podman access
    if command -v podman &> /dev/null; then
        if podman login --username "$registry_user" --password "$registry_password" --tls-verify=false "registry.$cluster_name.local:$registry_port" >/dev/null 2>&1; then
            echo "✅ Registry Docker/Podman access working"
        else
            echo "⚠️  Registry Docker/Podman access failed (this is normal if you haven't synced images yet)"
        fi
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
            --infra-output-dir)
                INFRA_OUTPUT_DIR="$2"
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
            --registry-storage)
                REGISTRY_STORAGE="$2"
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
    REGISTRY_PORT=${REGISTRY_PORT:-$DEFAULT_REGISTRY_PORT}
    REGISTRY_USER=${REGISTRY_USER:-$DEFAULT_REGISTRY_USER}
    REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-$DEFAULT_REGISTRY_PASSWORD}
    REGISTRY_STORAGE=${REGISTRY_STORAGE:-$DEFAULT_REGISTRY_STORAGE}
    DRY_RUN=${DRY_RUN:-no}
    
    # Display script header
    echo "🔧 Mirror Registry Setup for Disconnected OpenShift Cluster"
    echo "=========================================================="
    echo ""
    echo "📋 Configuration:"
    echo "   Cluster Name: $CLUSTER_NAME"
    echo "   Infrastructure Directory: $INFRA_OUTPUT_DIR"
    echo "   Registry Port: $REGISTRY_PORT"
    echo "   Registry User: $REGISTRY_USER"
    echo "   Registry Storage: $REGISTRY_STORAGE"
    echo "   Dry Run: $DRY_RUN"
    echo ""
    
    if [[ "$DRY_RUN" == "yes" ]]; then
        echo "🔍 DRY RUN MODE - No changes will be made"
        echo ""
        echo "Would setup:"
        echo "  - Docker registry on bastion host"
        echo "  - Authentication (user: $REGISTRY_USER)"
        echo "  - TLS certificate"
        echo "  - Registry storage at $REGISTRY_STORAGE"
        echo "  - Utility scripts for registry management"
        echo ""
        echo "To actually setup the registry, run without --dry-run"
        exit 0
    fi
    
    # Check infrastructure
    check_infrastructure "$INFRA_OUTPUT_DIR"
    
    # Get infrastructure information
    local bastion_ip=$(cat "$INFRA_OUTPUT_DIR/bastion-public-ip")
    local ssh_key="$INFRA_OUTPUT_DIR/bastion-key.pem"
    
    echo "📋 Infrastructure Information:"
    echo "   Bastion IP: $bastion_ip"
    echo "   SSH Key: $ssh_key"
    echo ""
    
    # Setup registry on bastion
    setup_registry_on_bastion "$CLUSTER_NAME" "$bastion_ip" "$ssh_key" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD" "$REGISTRY_STORAGE"
    
    # Create local configuration
    create_local_config "$CLUSTER_NAME" "$bastion_ip" "$REGISTRY_PORT" "$INFRA_OUTPUT_DIR"
    
    # Test registry access
    echo ""
    echo "🧪 Testing registry access..."
    echo "   Please add the following entry to your /etc/hosts file:"
    echo "   $bastion_ip registry.$CLUSTER_NAME.local"
    echo ""
    read -p "Have you added the hosts entry? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        test_registry_access "$CLUSTER_NAME" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"
    else
        echo "⚠️  Skipping registry access test"
        echo "   You can test it later by running:"
        echo "   curl -k -u $REGISTRY_USER:$REGISTRY_PASSWORD https://registry.$CLUSTER_NAME.local:$REGISTRY_PORT/v2/_catalog"
    fi
    
    echo ""
    echo "✅ Mirror registry setup completed!"
    echo ""
    echo "📁 Files created:"
    echo "   registry-config-$CLUSTER_NAME.yaml: Local registry configuration"
    echo ""
    echo "🔗 Next steps:"
    echo "1. Add hosts entry: $bastion_ip registry.$CLUSTER_NAME.local"
    echo "2. Test registry access"
    echo "3. Run: ./03-sync-images.sh --cluster-name $CLUSTER_NAME"
    echo ""
    echo "📝 Registry information:"
    echo "   URL: registry.$CLUSTER_NAME.local:$REGISTRY_PORT"
    echo "   User: $REGISTRY_USER"
    echo "   Password: $REGISTRY_PASSWORD"
    echo "   Bastion IP: $bastion_ip"
}

# Run main function with all arguments
main "$@" 