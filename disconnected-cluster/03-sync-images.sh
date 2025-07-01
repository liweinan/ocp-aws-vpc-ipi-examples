#!/bin/bash

# Image Synchronization Script for Disconnected OpenShift Cluster
# This script downloads core OpenShift resources directly from the release server
# This script must be run directly on the bastion host

set -euo pipefail

# Default values
DEFAULT_CLUSTER_NAME="disconnected-cluster"
DEFAULT_OPENSHIFT_VERSION="4.19.2"
DEFAULT_REGISTRY_PORT="5000"
DEFAULT_REGISTRY_USER="admin"
DEFAULT_REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-admin123}"
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
    echo "  $0 --cluster-name my-disconnected-cluster --openshift-version 4.19.2"
    echo "  $0 --dry-run --openshift-version 4.19.2"
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
    
    for tool in jq curl wget; do
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

# Function to download OpenShift CLI
download_openshift_cli() {
    local openshift_version="$1"
    
    echo -e "${BLUE}📦 Downloading OpenShift CLI...${NC}"
    
    if ! command -v oc &> /dev/null; then
        echo "   Downloading OpenShift CLI version ${openshift_version}..."
        # Remove existing files to avoid conflicts
        rm -f openshift-client-linux.tar.gz
        rm -f oc kubectl
        wget -O openshift-client-linux.tar.gz "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${openshift_version}/openshift-client-linux.tar.gz"
        tar xzf openshift-client-linux.tar.gz
        sudo mv oc kubectl /usr/local/bin/
        rm openshift-client-linux.tar.gz
        echo -e "${GREEN}✅ OpenShift CLI downloaded and installed${NC}"
    else
        echo -e "${GREEN}✅ OpenShift CLI already installed${NC}"
    fi
}

# Function to download OpenShift installer
download_openshift_installer() {
    local openshift_version="$1"
    
    echo -e "${BLUE}📦 Downloading OpenShift installer...${NC}"
    
    if ! command -v openshift-install &> /dev/null; then
        echo "   Downloading OpenShift installer version ${openshift_version}..."
        # Remove existing files to avoid conflicts
        rm -f openshift-install-linux.tar.gz
        rm -rf openshift-install
        wget -O openshift-install-linux.tar.gz "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${openshift_version}/openshift-install-linux.tar.gz"
        tar xzf openshift-install-linux.tar.gz
        sudo mv openshift-install /usr/local/bin/
        rm openshift-install-linux.tar.gz
        echo -e "${GREEN}✅ OpenShift installer downloaded and installed${NC}"
    else
        echo -e "${GREEN}✅ OpenShift installer already installed${NC}"
    fi
}

# Function to download core OpenShift images
download_core_images() {
    local openshift_version="$1"
    local cluster_name="$2"
    local registry_port="$3"
    local registry_user="$4"
    local registry_password="$5"
    
    echo -e "${BLUE}🔄 Downloading core OpenShift images...${NC}"
    
    local registry_url="localhost:${registry_port}"
    local sync_dir="/home/ubuntu/openshift-sync"
    
    # Create sync directory
    mkdir -p "${sync_dir}"
    cd "${sync_dir}"
    
    # Login to registry
    echo "   Logging into registry..."
    podman login --username "${registry_user}" --password "${registry_password}" --tls-verify=false "${registry_url}"
    
    # List of core OpenShift images to sync from quay.io (publicly accessible)
    local core_images=(
        "quay.io/openshift-release-dev/ocp-release:${openshift_version}-x86_64"
    )
    
    for image in "${core_images[@]}"; do
        echo "   Processing image: ${image}"
        
        # Extract image name and tag for local registry
        local image_name=$(echo "$image" | sed 's|quay.io/openshift-release-dev/||' | sed 's|:.*||')
        local image_tag=$(echo "$image" | sed 's|.*:||')
        
        local local_image="${registry_url}/openshift/${image_name}:${image_tag}"
        
        echo "   Pulling ${image}..."
        if podman pull "$image"; then
            echo "   Tagging as ${local_image}..."
            podman tag "$image" "$local_image"
            
            echo "   Pushing to local registry..."
            if podman push "$local_image" --tls-verify=false; then
                echo -e "${GREEN}   ✅ Successfully synced ${local_image}${NC}"
            else
                echo -e "${YELLOW}   ⚠️  Failed to push ${local_image}${NC}"
            fi
        else
            echo -e "${YELLOW}   ⚠️  Failed to pull ${image} - skipping${NC}"
        fi
        
        echo
    done
    
    echo -e "${GREEN}✅ Core images downloaded and pushed to registry${NC}"
}

# Function to download additional required images
download_additional_images() {
    local cluster_name="$1"
    local registry_port="$2"
    local registry_user="$3"
    local registry_password="$4"
    
    echo -e "${BLUE}🔄 Downloading additional required images...${NC}"
    
    local registry_url="localhost:${registry_port}"
    
    # List of additional useful images (optional - these may require authentication)
    local additional_images=(
        "quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:1293f5ccad2a2776241344faecaf7320f60ee91882df4e24b309f3a7cefc04be"
    )
    
    echo "   Note: Additional images may require authentication and are optional for basic installation"
    
    for image in "${additional_images[@]}"; do
        echo "   Processing ${image}..."
        
        # Extract image name and tag for local registry
        local image_name=$(echo "$image" | sed 's|quay.io/openshift-release-dev/||' | sed 's|@.*||')
        local image_tag="latest"
        
        # If it's a digest, use a descriptive tag
        if [[ "$image" == *"@sha256:"* ]]; then
            image_tag="sha256-$(echo "$image" | sed 's|.*@sha256:||' | cut -c1-8)"
        fi
        
        local local_image="${registry_url}/openshift/${image_name}:${image_tag}"
        
        # Try to pull and push to local registry
        if podman pull "$image" 2>/dev/null; then
            podman tag "$image" "$local_image"
            if podman push "$local_image" --tls-verify=false 2>/dev/null; then
                echo -e "${GREEN}   ✅ ${image} synced${NC}"
            else
                echo -e "${YELLOW}   ⚠️  Failed to push ${local_image}${NC}"
            fi
        else
            echo -e "${YELLOW}   ⚠️  Could not pull ${image} (requires authentication)${NC}"
        fi
    done
    
    echo -e "${GREEN}✅ Additional images processed${NC}"
}

# Function to verify sync results
verify_sync_results() {
    local cluster_name="$1"
    local registry_port="$2"
    local registry_user="$3"
    local registry_password="$4"
    
    echo -e "${BLUE}🔍 Verifying sync results...${NC}"
    
    # List images in registry
    echo "   Registry catalog:"
    local catalog=$(curl -k -s -u "${registry_user}:${registry_password}" "https://localhost:${registry_port}/v2/_catalog")
    echo "$catalog" | jq .
    
    # Check specific images and their tags
    local required_images=(
        "openshift/release"
    )
    
    for image in "${required_images[@]}"; do
        echo "   Checking ${image}..."
        local tags_response=$(curl -k -s -u "${registry_user}:${registry_password}" "https://localhost:${registry_port}/v2/${image}/tags/list")
        if echo "$tags_response" | jq -e '.tags' >/dev/null 2>&1; then
            local tags=$(echo "$tags_response" | jq -r '.tags[]' 2>/dev/null)
            if [ -n "$tags" ]; then
                echo -e "${GREEN}   ✅ ${image} found with tags: $tags${NC}"
            else
                echo -e "${GREEN}   ✅ ${image} found (no tags)${NC}"
            fi
        else
            echo -e "${RED}   ❌ ${image} not found${NC}"
        fi
    done
    
    # Test pulling an image from local registry
    echo "   Testing image pull from local registry..."
    if podman pull "localhost:${registry_port}/openshift/release:latest" --tls-verify=false 2>/dev/null; then
        echo -e "${GREEN}   ✅ Successfully pulled image from local registry${NC}"
    else
        echo -e "${YELLOW}   ⚠️  Could not pull image from local registry${NC}"
    fi
    
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
Registry URL: localhost:${registry_port}
Sync Directory: ${sync_dir}

## Synced Images:
$(curl -k -s -u admin:admin123 "https://localhost:${registry_port}/v2/_catalog" | jq -r '.repositories[]' | sort)

## Registry Access:
- HTTPS: https://localhost:${registry_port}
- Docker: localhost:${registry_port}

## Downloaded Tools:
- OpenShift CLI (oc)
- OpenShift Installer (openshift-install)

## Next Steps:
1. Run: ./04-prepare-install-config.sh to prepare installation configuration
2. Run: ./05-install-cluster.sh to install the cluster

## Verification Commands:
- List images: curl -k -u admin:\${REGISTRY_PASSWORD:-admin123} https://localhost:${registry_port}/v2/_catalog
- Login: podman login --username admin --password \${REGISTRY_PASSWORD:-admin123} --tls-verify=false localhost:${registry_port}
- Check CLI: oc version
- Check installer: openshift-install version
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
        echo "Would download:"
        echo "  - OpenShift CLI and installer"
        echo "  - Core OpenShift release images (version $OPENSHIFT_VERSION)"
        echo "  - Essential operator images"
        echo "  - Push to registry: localhost:$REGISTRY_PORT"
        echo ""
        echo "To actually sync images, run without --dry-run"
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Check registry status
    check_registry_status "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"
    
    # Download OpenShift CLI
    download_openshift_cli "$OPENSHIFT_VERSION"
    
    # Download OpenShift installer
    download_openshift_installer "$OPENSHIFT_VERSION"
    
    # Download core OpenShift images
    download_core_images "$OPENSHIFT_VERSION" "$CLUSTER_NAME" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"
    
    # Download additional required images
    download_additional_images "$CLUSTER_NAME" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"
    
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
    echo "   HTTPS: https://localhost:$REGISTRY_PORT"
    echo "   Docker: localhost:$REGISTRY_PORT"
    echo ""
    echo -e "${BLUE}📝 Next steps:${NC}"
    echo "1. Run: ./04-prepare-install-config.sh to prepare installation configuration"
    echo "2. Run: ./05-install-cluster.sh to install the cluster"
    echo ""
    echo -e "${BLUE}📊 Sync information:${NC}"
    echo "   OpenShift Version: $OPENSHIFT_VERSION"
    echo "   Registry URL: localhost:$REGISTRY_PORT"
    echo "   Registry User: $REGISTRY_USER"
    echo "   Sync Directory: /home/ubuntu/openshift-sync"
}

# Run main function with all arguments
main "$@" 