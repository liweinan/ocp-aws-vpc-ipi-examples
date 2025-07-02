#!/bin/bash

# Mirror Registry Setup Script for Disconnected OpenShift Cluster
# This script must be run directly on the bastion host

set -euo pipefail

# Default values
DEFAULT_CLUSTER_NAME="disconnected-cluster"
DEFAULT_REGISTRY_PORT="5000"
DEFAULT_REGISTRY_USER="admin"
DEFAULT_REGISTRY_PASSWORD="admin123"
DEFAULT_REGISTRY_STORAGE="/opt/registry"

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
    echo ""
    echo "Note: This script must be run directly on the bastion host"
    exit 1
}

# Function to check if running on bastion host
is_bastion_host() {
    # Check if we're running on a bastion host by looking for AWS metadata
    if curl -s http://169.254.169.254/latest/meta-data/instance-id >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Function to check prerequisites
check_prerequisites() {
    echo -e "${BLUE}🔍 Checking prerequisites...${NC}"
    
    # Check if running on bastion host
    if ! is_bastion_host; then
        echo -e "${RED}❌ This script must be run on the bastion host${NC}"
        echo "Please copy this script to the bastion host and run it there"
        exit 1
    fi
    
    # Check if running as ubuntu user
    if [[ "$(whoami)" != "ubuntu" ]]; then
        echo -e "${YELLOW}⚠️  This script is designed to run as ubuntu user${NC}"
        echo "Current user: $(whoami)"
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
}

# Function to setup registry
setup_registry() {
    local cluster_name="$1"
    local registry_port="$2"
    local registry_user="$3"
    local registry_password="$4"
    local registry_storage="$5"
    
    echo -e "${BLUE}🔧 Setting up mirror registry...${NC}"
    
    # Check if podman is available
    if ! command -v podman >/dev/null 2>&1; then
        echo -e "${BLUE}📦 Installing podman...${NC}"
        sudo apt-get update -y
        sudo apt-get install -y podman
    fi
    
    # Create registry directories
    echo -e "${BLUE}📁 Creating registry directories...${NC}"
    sudo mkdir -p "$registry_storage"
    sudo mkdir -p "$registry_storage/auth"
    sudo mkdir -p "$registry_storage/certs"
    sudo chown -R "$(whoami):$(whoami)" "$registry_storage"
    
    # Install required packages
    echo -e "${BLUE}📦 Installing required packages...${NC}"
    sudo apt-get update -y
    sudo apt-get install -y apache2-utils
    
    # Create authentication
    echo -e "${BLUE}🔐 Creating registry authentication...${NC}"
    htpasswd -bBc "$registry_storage/auth/htpasswd" "$registry_user" "$registry_password"
    
    # Get instance metadata
    echo -e "${BLUE}📋 Getting instance metadata...${NC}"
    local instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    local public_ip=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
    local private_ip=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
    
    # Create self-signed certificate with multiple SANs
    echo -e "${BLUE}🔒 Creating self-signed certificate with multiple SANs...${NC}"
    cat > "$registry_storage/certs/openssl.conf" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = Organization
CN = registry.local

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = registry.local
DNS.2 = *.local
DNS.3 = localhost
DNS.4 = registry
DNS.5 = registry.${instance_id}.local
DNS.6 = registry.${cluster_name}.local
IP.1 = 127.0.0.1
IP.2 = ${public_ip}
IP.3 = ${private_ip}
EOF
    
    openssl req -newkey rsa:4096 -nodes -sha256 \
        -keyout "$registry_storage/certs/domain.key" \
        -out "$registry_storage/certs/domain.csr" \
        -config "$registry_storage/certs/openssl.conf"
    
    openssl x509 -req -in "$registry_storage/certs/domain.csr" \
        -signkey "$registry_storage/certs/domain.key" \
        -out "$registry_storage/certs/domain.crt" \
        -days 365 \
        -extensions v3_req \
        -extfile "$registry_storage/certs/openssl.conf"
    
    # Clean up CSR file
    rm -f "$registry_storage/certs/domain.csr"
    
    # Stop existing registry if running
    echo -e "${BLUE}🛑 Stopping existing registry if running...${NC}"
    podman stop mirror-registry 2>/dev/null || true
    podman rm mirror-registry 2>/dev/null || true
    
    # Start registry with authentication and TLS
    echo -e "${BLUE}🚀 Starting mirror registry...${NC}"
    podman run -d \
        --name mirror-registry \
        --restart=always \
        -p "$registry_port:5000" \
        -v "$registry_storage/data:/var/lib/registry:z" \
        -v "$registry_storage/auth:/auth:z" \
        -v "$registry_storage/certs:/certs:z" \
        -e REGISTRY_AUTH=htpasswd \
        -e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" \
        -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
        -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
        -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
        registry:2
    
    # Wait for registry to start
    echo -e "${BLUE}⏳ Waiting for registry to start...${NC}"
    sleep 10
    
    # Test registry
    echo -e "${BLUE}🧪 Testing registry...${NC}"
    if curl -k -u "$registry_user:$registry_password" "https://localhost:$registry_port/v2/_catalog" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Registry is working correctly${NC}"
    else
        echo -e "${RED}❌ Registry test failed${NC}"
        echo "Checking registry logs..."
        podman logs mirror-registry
        exit 1
    fi
    
    # Create registry configuration for OpenShift
    echo -e "${BLUE}📝 Creating registry configuration...${NC}"
    cat > "/home/ubuntu/registry-config.yaml" <<EOF
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
EOF
    
    # Create helpful scripts
    cat > "/home/ubuntu/registry-utils.sh" <<EOF
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
EOF
    
    chmod +x "/home/ubuntu/registry-utils.sh"
    
    # Create environment file
    cat > "/home/ubuntu/registry.env" <<EOF
# Registry environment variables
REGISTRY_URL=registry.$cluster_name.local:$registry_port
REGISTRY_USER=$registry_user
REGISTRY_PASSWORD=$registry_password
REGISTRY_STORAGE=$registry_storage
CLUSTER_NAME=$cluster_name
EOF
    
    echo -e "${GREEN}✅ Registry setup completed!${NC}"
}

# Function to test registry access
test_registry_access() {
    local cluster_name="$1"
    local registry_port="$2"
    local registry_user="$3"
    local registry_password="$4"
    
    echo -e "${BLUE}🧪 Testing registry access...${NC}"
    
    # Test local access
    if curl -k -u "$registry_user:$registry_password" "https://localhost:$registry_port/v2/_catalog" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Local registry access working${NC}"
    else
        echo -e "${RED}❌ Local registry access failed${NC}"
        return 1
    fi
    
    # Test with domain name
    if curl -k -u "$registry_user:$registry_password" "https://registry.$cluster_name.local:$registry_port/v2/_catalog" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Domain registry access working${NC}"
    else
        echo -e "${YELLOW}⚠️  Domain registry access failed (this is normal if DNS is not configured)${NC}"
    fi
    
    # Test Docker/Podman access
    if command -v podman &> /dev/null; then
        if podman login --username "$registry_user" --password "$registry_password" --tls-verify=false "localhost:$registry_port" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Registry Docker/Podman access working${NC}"
        else
            echo -e "${YELLOW}⚠️  Registry Docker/Podman access failed (this is normal if you haven't synced images yet)${NC}"
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
    REGISTRY_PORT=${REGISTRY_PORT:-$DEFAULT_REGISTRY_PORT}
    REGISTRY_USER=${REGISTRY_USER:-$DEFAULT_REGISTRY_USER}
    REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-$DEFAULT_REGISTRY_PASSWORD}
    REGISTRY_STORAGE=${REGISTRY_STORAGE:-$DEFAULT_REGISTRY_STORAGE}
    DRY_RUN=${DRY_RUN:-no}
    
    # Display script header
    echo -e "${BLUE}🔧 Mirror Registry Setup for Disconnected OpenShift Cluster${NC}"
    echo "=========================================================="
    echo ""
    echo -e "${BLUE}📋 Configuration:${NC}"
    echo "   Cluster Name: $CLUSTER_NAME"
    echo "   Registry Port: $REGISTRY_PORT"
    echo "   Registry User: $REGISTRY_USER"
    echo "   Registry Storage: $REGISTRY_STORAGE"
    echo "   Dry Run: $DRY_RUN"
    echo ""
    
    if [[ "$DRY_RUN" == "yes" ]]; then
        echo -e "${BLUE}🔍 DRY RUN MODE - No changes will be made${NC}"
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
    
    # Check prerequisites
    check_prerequisites
    
    # Setup registry
    setup_registry "$CLUSTER_NAME" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD" "$REGISTRY_STORAGE"
    
    # Test registry access
    test_registry_access "$CLUSTER_NAME" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"
    
    echo ""
    echo -e "${GREEN}✅ Mirror registry setup completed!${NC}"
    echo ""
    echo -e "${BLUE}📁 Files created:${NC}"
    echo "   /home/ubuntu/registry-config.yaml: Registry configuration for OpenShift"
    echo "   /home/ubuntu/registry-utils.sh: Registry utility functions"
    echo "   /home/ubuntu/registry.env: Registry environment variables"
    echo ""
    echo -e "${BLUE}🔗 Registry access:${NC}"
    echo "   HTTPS: https://registry.$CLUSTER_NAME.local:$REGISTRY_PORT"
    echo "   Docker: registry.$CLUSTER_NAME.local:$REGISTRY_PORT"
    echo "   Local: https://localhost:$REGISTRY_PORT"
    echo ""
    echo -e "${BLUE}📝 Next steps:${NC}"
    echo "1. Run: ./03-sync-images.sh to sync OpenShift images"
    echo "2. Use: ~/registry-utils.sh to manage registry"
    echo ""
    echo -e "${BLUE}📊 Registry information:${NC}"
    echo "   URL: registry.$CLUSTER_NAME.local:$REGISTRY_PORT"
    echo "   User: $REGISTRY_USER"
    echo "   Password: $REGISTRY_PASSWORD"
    echo "   Storage: $REGISTRY_STORAGE"
}

# Run main function with all arguments
main "$@" 