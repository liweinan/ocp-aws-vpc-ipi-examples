#!/bin/bash

# Image Synchronization Script for Disconnected OpenShift Cluster
# This script must be run directly on the bastion host

set -euo pipefail

# Default values
DEFAULT_CLUSTER_NAME="disconnected-cluster"
DEFAULT_OPENSHIFT_VERSION="4.18.15"
DEFAULT_REGISTRY_PORT="5000"
DEFAULT_REGISTRY_USER="admin"
DEFAULT_REGISTRY_PASSWORD="admin123"
DEFAULT_DRY_RUN="no"

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
    echo "  --openshift-version   OpenShift version to sync (default: $DEFAULT_OPENSHIFT_VERSION)"
    echo "  --registry-port       Registry port (default: $DEFAULT_REGISTRY_PORT)"
    echo "  --registry-user       Registry username (default: $DEFAULT_REGISTRY_USER)"
    echo "  --registry-password   Registry password (default: $DEFAULT_REGISTRY_PASSWORD)"
    echo "  --dry-run             Show what would be synced without actually syncing"
    echo "  --help                Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --cluster-name my-disconnected-cluster --openshift-version 4.18.15"
    echo "  $0 --dry-run --openshift-version 4.19.0"
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
    
    # Check required tools
    local missing_tools=()
    
    for tool in jq curl; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Installing missing tools: ${missing_tools[*]}${NC}"
        sudo apt-get update
        sudo apt-get install -y "${missing_tools[@]}"
    fi
    
    echo -e "${GREEN}✅ All required tools are available${NC}"
}

# Function to check registry status
check_registry_status() {
    local registry_port="$1"
    local registry_user="$2"
    local registry_password="$3"
    
    echo -e "${BLUE}🔍 Checking registry status...${NC}"
    
    # Check if registry container is running
    local registry_status=$(podman ps --format 'table {{.Names}}\t{{.Status}}' | grep mirror-registry || echo 'NOT_FOUND')
    
    if [[ "$registry_status" == "NOT_FOUND" ]] || [[ "$registry_status" == *"Exited"* ]]; then
        echo -e "${RED}❌ Registry container is not running${NC}"
        echo "Please run 02-setup-mirror-registry.sh first"
        exit 1
    fi
    
    # Test registry access
    echo -e "${BLUE}🧪 Testing registry access...${NC}"
    if ! curl -k -u "${registry_user}:${registry_password}" "https://localhost:${registry_port}/v2/_catalog" >/dev/null 2>&1; then
        echo -e "${RED}❌ Registry is not accessible${NC}"
        echo "Please check registry logs: podman logs mirror-registry"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Registry is running and accessible${NC}"
}

# Function to install OpenShift CLI
install_openshift_cli() {
    local openshift_version="$1"
    
    echo -e "${BLUE}📦 Installing OpenShift CLI...${NC}"
    
    if ! command -v oc &> /dev/null; then
        echo "   Downloading OpenShift CLI version ${openshift_version}..."
        curl -L "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${openshift_version}/openshift-client-linux.tar.gz" | tar xz
        sudo mv oc kubectl /usr/local/bin/
        echo -e "${GREEN}✅ OpenShift CLI installed${NC}"
    else
        echo -e "${GREEN}✅ OpenShift CLI already installed${NC}"
    fi
}

# Function to sync OpenShift release images
sync_release_images() {
    local openshift_version="$1"
    local cluster_name="$2"
    local registry_port="$3"
    local registry_user="$4"
    local registry_password="$5"
    
    echo -e "${BLUE}🔄 Syncing OpenShift release images...${NC}"
    
    local registry_url="registry.${cluster_name}.local:${registry_port}"
    local sync_dir="/home/ubuntu/openshift-sync"
    
    # Create sync directory
    mkdir -p "${sync_dir}"
    cd "${sync_dir}"
    
    # Login to registry
    echo "   Logging into registry..."
    podman login --username "${registry_user}" --password "${registry_password}" --tls-verify=false "localhost:${registry_port}"
    
    # Download release info
    echo "   Downloading release info..."
    oc adm release mirror \
        --from=quay.io/openshift-release-dev/ocp-release:${openshift_version}-x86_64 \
        --to-dir=./mirror \
        --to=localhost:${registry_port}/openshift/release
    
    # Mirror images to registry
    echo "   Mirroring images to registry..."
    oc image mirror \
        --from-dir=./mirror \
        "file://openshift/release:${openshift_version}-x86_64*" \
        "localhost:${registry_port}/openshift/release:${openshift_version}-x86_64"
    
    echo -e "${GREEN}✅ Release images synced${NC}"
}

# Function to sync additional operators
sync_additional_operators() {
    local cluster_name="$1"
    local registry_port="$2"
    local registry_user="$3"
    local registry_password="$4"
    
    echo -e "${BLUE}🔄 Syncing additional operators...${NC}"
    
    local registry_url="registry.${cluster_name}.local:${registry_port}"
    
    # Sync essential operators
    local operators=(
        "openshift/ose-cli:latest"
        "openshift/ose-cli:4.18"
        "openshift/ose-installer:4.18"
        "openshift/ose-installer:latest"
    )
    
    for operator in "${operators[@]}"; do
        echo "   Syncing ${operator}..."
        podman pull "quay.io/${operator}"
        podman tag "quay.io/${operator}" "localhost:${registry_port}/${operator}"
        podman push "localhost:${registry_port}/${operator}"
    done
    
    echo -e "${GREEN}✅ Additional operators synced${NC}"
}

# Function to verify sync results
verify_sync_results() {
    local cluster_name="$1"
    local registry_port="$2"
    local registry_user="$3"
    local registry_password="$4"
    
    echo -e "${BLUE}🔍 Verifying sync results...${NC}"
    
    # List images in registry
    echo "   Images in registry:"
    curl -k -s -u "${registry_user}:${registry_password}" "https://localhost:${registry_port}/v2/_catalog" | jq .
    
    # Check specific images
    local required_images=(
        "openshift/release"
    )
    
    for image in "${required_images[@]}"; do
        echo "   Checking ${image}..."
        if curl -k -s -u "${registry_user}:${registry_password}" "https://localhost:${registry_port}/v2/${image}/tags/list" >/dev/null 2>&1; then
            echo -e "${GREEN}   ✅ ${image} found${NC}"
        else
            echo -e "${RED}   ❌ ${image} not found${NC}"
        fi
    done
    
    echo -e "${GREEN}✅ Sync verification completed${NC}"
}

# Function to create sync summary
create_sync_summary() {
    local cluster_name="$1"
    local registry_port="$2"
    local openshift_version="$3"
    local sync_dir="$4"
    
    echo -e "${BLUE}📝 Creating sync summary...${NC}"
    
    cat > "/home/ubuntu/sync-summary.txt" <<EOF
# OpenShift Image Sync Summary
# Generated on $(date)

Cluster Name: ${cluster_name}
OpenShift Version: ${openshift_version}
Registry URL: registry.${cluster_name}.local:${registry_port}
Sync Directory: ${sync_dir}

## Synced Images:
$(curl -k -s -u admin:admin123 "https://localhost:${registry_port}/v2/_catalog" | jq -r '.repositories[]' | sort)

## Registry Access:
- HTTPS: https://registry.${cluster_name}.local:${registry_port}
- Docker: registry.${cluster_name}.local:${registry_port}
- Local: https://localhost:${registry_port}

## Next Steps:
1. Run: ./04-prepare-install-config.sh to prepare installation
2. Run: ./05-install-cluster.sh to install the cluster

## Verification Commands:
- List images: curl -k -u admin:admin123 https://localhost:${registry_port}/v2/_catalog
- Login: podman login --username admin --password admin123 --tls-verify=false localhost:${registry_port}
EOF
    
    echo -e "${GREEN}✅ Sync summary created: /home/ubuntu/sync-summary.txt${NC}"
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
            --openshift-version)
                OPENSHIFT_VERSION="$2"
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
    OPENSHIFT_VERSION=${OPENSHIFT_VERSION:-$DEFAULT_OPENSHIFT_VERSION}
    REGISTRY_PORT=${REGISTRY_PORT:-$DEFAULT_REGISTRY_PORT}
    REGISTRY_USER=${REGISTRY_USER:-$DEFAULT_REGISTRY_USER}
    REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-$DEFAULT_REGISTRY_PASSWORD}
    DRY_RUN=${DRY_RUN:-no}
    
    # Display script header
    echo -e "${BLUE}🔄 Image Synchronization for Disconnected OpenShift Cluster${NC}"
    echo "============================================================="
    echo ""
    echo -e "${BLUE}📋 Configuration:${NC}"
    echo "   Cluster Name: $CLUSTER_NAME"
    echo "   OpenShift Version: $OPENSHIFT_VERSION"
    echo "   Registry Port: $REGISTRY_PORT"
    echo "   Registry User: $REGISTRY_USER"
    echo "   Dry Run: $DRY_RUN"
    echo ""
    
    if [[ "$DRY_RUN" == "yes" ]]; then
        echo -e "${BLUE}🔍 DRY RUN MODE - No images will be synced${NC}"
        echo ""
        echo "Would sync:"
        echo "  - OpenShift release images (version $OPENSHIFT_VERSION)"
        echo "  - Essential operators and tools"
        echo "  - Images to registry: registry.$CLUSTER_NAME.local:$REGISTRY_PORT"
        echo ""
        echo "To actually sync images, run without --dry-run"
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Check registry status
    check_registry_status "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"
    
    # Install OpenShift CLI
    install_openshift_cli "$OPENSHIFT_VERSION"
    
    # Sync OpenShift release images
    sync_release_images "$OPENSHIFT_VERSION" "$CLUSTER_NAME" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"
    
    # Sync additional operators
    sync_additional_operators "$CLUSTER_NAME" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"
    
    # Verify sync results
    verify_sync_results "$CLUSTER_NAME" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"
    
    # Create sync summary
    create_sync_summary "$CLUSTER_NAME" "$REGISTRY_PORT" "$OPENSHIFT_VERSION" "/home/ubuntu/openshift-sync"
    
    echo ""
    echo -e "${GREEN}✅ Image synchronization completed!${NC}"
    echo ""
    echo -e "${BLUE}📁 Files created:${NC}"
    echo "   /home/ubuntu/openshift-sync/: Synced images directory"
    echo "   /home/ubuntu/sync-summary.txt: Sync summary"
    echo ""
    echo -e "${BLUE}🔗 Registry access:${NC}"
    echo "   HTTPS: https://registry.$CLUSTER_NAME.local:$REGISTRY_PORT"
    echo "   Docker: registry.$CLUSTER_NAME.local:$REGISTRY_PORT"
    echo "   Local: https://localhost:$REGISTRY_PORT"
    echo ""
    echo -e "${BLUE}📝 Next steps:${NC}"
    echo "1. Run: ./04-prepare-install-config.sh to prepare installation"
    echo "2. Run: ./05-install-cluster.sh to install the cluster"
    echo ""
    echo -e "${BLUE}📊 Sync information:${NC}"
    echo "   OpenShift Version: $OPENSHIFT_VERSION"
    echo "   Registry URL: registry.$CLUSTER_NAME.local:$REGISTRY_PORT"
    echo "   Registry User: $REGISTRY_USER"
    echo "   Sync Directory: /home/ubuntu/openshift-sync"
}

# Run main function with all arguments
main "$@" 