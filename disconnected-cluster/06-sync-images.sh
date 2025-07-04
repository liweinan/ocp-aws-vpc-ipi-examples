#!/bin/bash

# Image Synchronization Script for Disconnected OpenShift Cluster from CI Registry
# This script syncs images from OpenShift CI cluster to local mirror registry
# Based on successful manual sync experience with registry.ci.openshift.org/ocp/4.19.2
# All images verified available via quick-check-images.sh

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
    echo "Prerequisites:"
    echo "  - Must be run on bastion host"
    echo "  - oc must be logged into CI cluster (oc whoami should work)"
    echo "  - Local mirror registry must be running"
    echo ""
    echo "Examples:"
    echo "  $0 --cluster-name my-disconnected-cluster"
    echo "  $0 --dry-run --openshift-version 4.19.2"
    echo ""
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    echo -e "${BLUE}🔍 Checking prerequisites...${NC}"
    
    # Check if running on bastion host
    if ! curl -s http://169.254.169.254/latest/meta-data/instance-id >/dev/null 2>&1; then
        echo -e "${RED}❌ This script must be run on the bastion host${NC}"
        echo "Please copy this script to the bastion host and run it there"
        exit 1
    fi
    
    # Check required tools
    local missing_tools=()
    for tool in jq curl podman oc; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo -e "${RED}❌ Missing required tools: ${missing_tools[*]}${NC}"
        echo "Please install missing tools and try again"
        exit 1
    fi
    
    # Check oc login status
    echo "   Checking oc login status..."
    if ! oc whoami >/dev/null 2>&1; then
        echo -e "${RED}❌ Not logged into OpenShift cluster${NC}"
        echo ""
        echo "Please login to CI cluster first:"
        echo "  oc login --token=<YOUR_TOKEN> --server=https://api.ci.l2s4.p1.openshiftapps.com:6443 --insecure-skip-tls-verify=true"
        echo ""
        exit 1
    fi
    
    local current_user=$(oc whoami 2>/dev/null || echo "unknown")
    echo -e "${GREEN}   ✅ Logged into OpenShift as: ${current_user}${NC}"
    
    echo -e "${GREEN}✅ All prerequisites met${NC}"
}

# Function to check registry status
check_registry_status() {
    local registry_port="$1"
    local registry_user="$2"
    local registry_password="$3"
    
    echo -e "${BLUE}🔍 Checking local registry status...${NC}"
    
    # Check if registry container is running
    local registry_status=$(podman ps --format 'table {{.Names}}\t{{.Status}}' | grep -E "(mirror-registry|registry)" || echo 'NOT_FOUND')
    
    if [[ "$registry_status" == "NOT_FOUND" ]] || [[ "$registry_status" == *"Exited"* ]]; then
        echo -e "${RED}❌ Registry container is not running${NC}"
        echo "Please run 04-setup-mirror-registry.sh first"
        exit 1
    fi
    
    # Test registry access
    echo -e "${BLUE}🧪 Testing local registry access...${NC}"
    if ! curl -k -u "${registry_user}:${registry_password}" "https://localhost:${registry_port}/v2/_catalog" >/dev/null 2>&1; then
        echo -e "${RED}❌ Local registry is not accessible${NC}"
        echo "Please check registry logs: podman logs mirror-registry"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Local registry is running and accessible${NC}"
}

# Function to check disk space
check_disk_space() {
    echo -e "${BLUE}🔍 Checking disk space...${NC}"
    
    local available_space=$(df /home | tail -1 | awk '{print $4}')
    local available_gb=$((available_space / 1024 / 1024))
    
    echo "   Available space: ${available_gb}GB"
    
    if [[ $available_gb -lt 10 ]]; then
        echo -e "${RED}❌ Insufficient disk space (${available_gb}GB available, need at least 10GB)${NC}"
        echo "Please free up disk space before continuing"
        echo "You can run: podman system prune -a -f"
        exit 1
    elif [[ $available_gb -lt 15 ]]; then
        echo -e "${YELLOW}⚠️  Low disk space (${available_gb}GB available, recommended 15GB+)${NC}"
        echo "Consider running: podman system prune -a -f"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo -e "${GREEN}✅ Sufficient disk space (${available_gb}GB available)${NC}"
    fi
}

# Function to sync images from CI cluster
sync_from_ci_cluster() {
    local cluster_name="$1"
    local registry_port="$2"
    local registry_user="$3"
    local registry_password="$4"
    local openshift_version="$5"
    
    echo -e "${BLUE}🔄 Syncing images from OpenShift CI cluster...${NC}"
    
    local registry_url="localhost:${registry_port}"
    local sync_dir="/home/ubuntu/openshift-sync"
    local ci_registry="registry.ci.openshift.org"
    
    # Create sync directory
    mkdir -p "${sync_dir}"
    cd "${sync_dir}"
    
    # Get CI cluster user info
    echo "   Getting CI cluster user information..."
    local ci_user=$(oc whoami 2>/dev/null || echo "unknown")
    local ci_token=$(oc whoami -t 2>/dev/null || echo "")
    
    echo "   CI cluster user: ${ci_user}"
    
    # Login to local registry
    echo "   Logging into local registry..."
    podman login --username "${registry_user}" --password "${registry_password}" --tls-verify=false "${registry_url}"
    
    # Login to CI registry
    echo "   Logging into CI registry..."
    if [[ -n "$ci_token" ]]; then
        podman login -u="${ci_user}" -p="${ci_token}" "${ci_registry}"
        echo -e "${GREEN}   ✅ Logged into CI registry${NC}"
    else
        echo -e "${RED}   ❌ Could not get CI token${NC}"
        return 1
    fi
    
    echo ""
    echo "   🚀 Syncing from CI cluster imagestream: ocp/${openshift_version}..."
    echo "   📊 All 21 images verified available via quick-check-images.sh"
    echo ""
    
    # Define core images (all verified available)
    local core_images=(
        "cli"
        "installer"
        "machine-config-operator"
        "cluster-version-operator"
        "etcd"
        "hyperkube"
        "oauth-server"
        "oauth-proxy"
        "console"
        "haproxy-router"
        "coredns"
    )
    
    # Define additional important images (all verified available)
    local additional_images=(
        "cluster-network-operator"
        "cluster-dns-operator"
        "cluster-storage-operator"
        "cluster-ingress-operator"
        "aws-ebs-csi-driver"
        "aws-ebs-csi-driver-operator"
        "cluster-monitoring-operator"
        "prometheus-operator"
        "node-exporter"
        "kube-state-metrics"
    )
    
    local synced_count=0
    local failed_count=0
    local skipped_count=0
    
    # Function to sync a single image with better error handling
    sync_single_image() {
        local img="$1"
        local image_type="$2"  # "core" or "additional"
        
        local source_image="${ci_registry}/ocp/${openshift_version}:${img}"
        local local_image="${registry_url}/openshift/${img}:${openshift_version}"
        local local_image_latest="${registry_url}/openshift/${img}:latest"
        
        echo "   Processing: ${img} (${image_type})"
        echo "     Source: ${source_image}"
        echo "     Target: ${local_image}"
        
        # Check if image already exists in local registry
        if curl -k -s -u "${registry_user}:${registry_password}" "https://localhost:${registry_port}/v2/openshift/${img}/tags/list" 2>/dev/null | grep -q "${openshift_version}"; then
            echo -e "${YELLOW}     ⏭️  Already exists, skipping${NC}"
            ((skipped_count++))
            return 0
        fi
        
        # Clean up any existing local copy
        podman rmi "$source_image" 2>/dev/null || true
        
        # Try to pull the image with retry
        local pull_attempts=0
        local max_pull_attempts=3
        while [[ $pull_attempts -lt $max_pull_attempts ]]; do
            ((pull_attempts++))
            echo "     🔄 Pull attempt ${pull_attempts}/${max_pull_attempts}..."
            
            if timeout 600 podman pull "$source_image" --platform linux/amd64; then
                echo -e "${GREEN}     ✅ Pulled ${source_image}${NC}"
                break
            else
                echo "     ⚠️  Pull attempt ${pull_attempts} failed"
                if [[ $pull_attempts -eq $max_pull_attempts ]]; then
                    echo -e "${RED}     ❌ Failed to pull after ${max_pull_attempts} attempts${NC}"
                    ((failed_count++))
                    return 1
                fi
                sleep 5
            fi
        done
        
        # Tag for local registry (both versioned and latest)
        podman tag "$source_image" "$local_image"
        podman tag "$source_image" "$local_image_latest"
        
        # Push to local registry with retry
        local push_attempts=0
        local max_push_attempts=3
        while [[ $push_attempts -lt $max_push_attempts ]]; do
            ((push_attempts++))
            echo "     🔄 Push attempt ${push_attempts}/${max_push_attempts}..."
            
            if timeout 600 podman push "$local_image" --tls-verify=false && \
               timeout 600 podman push "$local_image_latest" --tls-verify=false; then
                echo -e "${GREEN}     ✅ Synced ${local_image} and :latest${NC}"
                ((synced_count++))
                
                # Clean up local copy to save space
                podman rmi "$source_image" "$local_image" "$local_image_latest" 2>/dev/null || true
                return 0
            else
                echo "     ⚠️  Push attempt ${push_attempts} failed"
                if [[ $push_attempts -eq $max_push_attempts ]]; then
                    echo -e "${RED}     ❌ Failed to push after ${max_push_attempts} attempts${NC}"
                    ((failed_count++))
                    return 1
                fi
                sleep 5
            fi
        done
    }
    
    # Sync core images first (these are critical)
    echo "   📦 Syncing core images (11/11 verified available)..."
    for img in "${core_images[@]}"; do
        sync_single_image "$img" "core"
        echo
        
        # Check disk space after each image
        local available_space=$(df /home | tail -1 | awk '{print $4}')
        local available_gb=$((available_space / 1024 / 1024))
        if [[ $available_gb -lt 5 ]]; then
            echo -e "${YELLOW}⚠️  Low disk space (${available_gb}GB), cleaning up...${NC}"
            podman system prune -f
        fi
    done
    
    # Sync additional images
    echo "   📦 Syncing additional images (10/10 verified available)..."
    for img in "${additional_images[@]}"; do
        sync_single_image "$img" "additional"
        echo
        
        # Check disk space after each image
        local available_space=$(df /home | tail -1 | awk '{print $4}')
        local available_gb=$((available_space / 1024 / 1024))
        if [[ $available_gb -lt 5 ]]; then
            echo -e "${YELLOW}⚠️  Low disk space (${available_gb}GB), cleaning up...${NC}"
            podman system prune -f
        fi
    done
    
    echo -e "${GREEN}   CI cluster image sync completed${NC}"
    echo "   Successfully synced: ${synced_count} images"
    echo "   Already existed: ${skipped_count} images"
    echo "   Failed: ${failed_count} images"
    echo "   Total processed: $((synced_count + skipped_count + failed_count))/21 images"
    
    # Generate imageContentSources configuration
    echo ""
    echo "   📝 Generating imageContentSources configuration..."
    cat > "${sync_dir}/imageContentSources.yaml" <<EOF
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: ${cluster_name}-icsp
spec:
  repositoryDigestMirrors:
  - mirrors:
    - ${registry_url}/openshift
    source: ${ci_registry}/ocp/${openshift_version}
  - mirrors:
    - ${registry_url}/openshift
    source: ${ci_registry}/openshift
  - mirrors:
    - ${registry_url}/openshift
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - ${registry_url}/openshift
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
EOF
    
    echo -e "${GREEN}   ✅ ImageContentSources saved to ${sync_dir}/imageContentSources.yaml${NC}"
    
    echo ""
    echo -e "${GREEN}✅ Complete CI cluster image sync finished${NC}"
    echo "   Total operation summary:"
    echo "   ✅ Images synced: ${synced_count}"
    echo "   ⏭️  Already existed: ${skipped_count}"
    echo "   ⚠️  Failed: ${failed_count}"
    echo "   📁 Sync directory: ${sync_dir}"
    echo "   📄 Image content sources: ${sync_dir}/imageContentSources.yaml"
    echo ""
    echo "   📋 Next steps:"
    echo "   1. Use the imageContentSources.yaml in your install-config.yaml"
    echo "   2. Run ./07-prepare-install-config.sh to prepare installation"
    echo "   3. Run ./08-install-cluster.sh to install the cluster"
    
    # Return success if we synced most images
    if [[ $synced_count -ge 15 ]]; then
        return 0
    else
        echo -e "${YELLOW}⚠️  Warning: Only ${synced_count} images synced successfully${NC}"
        return 1
    fi
}

# Function to verify sync results
verify_sync_results() {
    local cluster_name="$1"
    local registry_port="$2"
    local registry_user="$3"
    local registry_password="$4"
    
    echo -e "${BLUE}🔍 Verifying sync results...${NC}"
    
    # List all repositories in registry
    echo "   Getting registry catalog..."
    local catalog=$(curl -k -s -u "${registry_user}:${registry_password}" "https://localhost:${registry_port}/v2/_catalog")
    local repo_count=$(echo "$catalog" | jq -r '.repositories | length')
    
    echo "   Registry contains ${repo_count} repositories:"
    echo "$catalog" | jq -r '.repositories[]' | sort
    
    # Check for critical OpenShift images
    local critical_found=0
    local critical_images=("openshift/cli" "openshift/installer" "openshift/etcd" "openshift/console" "openshift/cluster-version-operator")
    
    echo ""
    echo "   Checking for critical OpenShift images:"
    for image in "${critical_images[@]}"; do
        if echo "$catalog" | jq -r '.repositories[]' | grep -q "^${image}$"; then
            echo -e "${GREEN}   ✅ ${image} found${NC}"
            ((critical_found++))
        else
            echo -e "${YELLOW}   ⚠️  ${image} not found${NC}"
        fi
    done
    
    # Overall assessment
    echo ""
    if [[ $repo_count -ge 15 && $critical_found -ge 4 ]]; then
        echo -e "${GREEN}✅ Image sync appears successful (${repo_count} repositories, ${critical_found}/${#critical_images[@]} critical images)${NC}"
    else
        echo -e "${YELLOW}⚠️  Image sync partially complete (${repo_count} repositories, ${critical_found}/${#critical_images[@]} critical images)${NC}"
    fi
    
    echo -e "${GREEN}✅ Sync verification completed${NC}"
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
    echo -e "${BLUE}🔄 CI Registry Image Synchronization${NC}"
    echo "=================================================="
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
        echo "Would sync from CI cluster:"
        echo "  - Core OpenShift images from registry.ci.openshift.org/ocp/$OPENSHIFT_VERSION"
        echo "  - Additional OpenShift components"
        echo "  - Push all images to local registry: localhost:$REGISTRY_PORT"
        echo "  - Generate image content source policy"
        echo ""
        echo "⚠️  This operation will download several GB of data and take 15-30 minutes"
        echo "To actually sync images, run without --dry-run"
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Check disk space
    check_disk_space
    
    # Check registry status
    check_registry_status "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"
    
    # Sync images from CI cluster
    sync_from_ci_cluster "$CLUSTER_NAME" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD" "$OPENSHIFT_VERSION"
    
    # Verify sync results
    verify_sync_results "$CLUSTER_NAME" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"
    
    echo ""
    echo -e "${GREEN}✅ OpenShift CI image synchronization completed!${NC}"
    echo ""
    echo -e "${BLUE}📁 Files created:${NC}"
    echo "   /home/ubuntu/openshift-sync/: Sync operation directory"
    echo "   /home/ubuntu/openshift-sync/imageContentSources.yaml: Image content source policy"
    echo ""
    echo -e "${BLUE}🔗 Registry access:${NC}"
    echo "   HTTPS: https://localhost:$REGISTRY_PORT"
    echo "   Docker: localhost:$REGISTRY_PORT"
    echo ""
    echo -e "${BLUE}📝 Next steps:${NC}"
    echo "1. Run: ./07-prepare-install-config.sh to prepare installation configuration"
    echo "2. Run: ./08-install-cluster.sh to install the cluster"
    echo ""
    echo -e "${BLUE}📊 Sync information:${NC}"
    echo "   Source: OpenShift CI cluster ($(oc whoami 2>/dev/null || echo 'unknown'))"
    echo "   OpenShift Version: $OPENSHIFT_VERSION"
    echo "   Local Registry: localhost:$REGISTRY_PORT"
    echo "   Sync Directory: /home/ubuntu/openshift-sync"
}

# Run main function with all arguments
main "$@" 