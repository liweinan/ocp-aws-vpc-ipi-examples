#!/bin/bash

# Bootstrap Configuration Verification Script
# This script verifies that all bootstrap configurations are correctly set up

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Default values
DEFAULT_CLUSTER_NAME="disconnected-cluster"
DEFAULT_REGISTRY_PORT="5000"
DEFAULT_REGISTRY_USER="admin"
DEFAULT_REGISTRY_PASSWORD="admin123"
DEFAULT_INSTALL_DIR="./openshift-install-dir"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --cluster-name        Cluster name (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --registry-port       Registry port (default: $DEFAULT_REGISTRY_PORT)"
    echo "  --registry-user       Registry username (default: $DEFAULT_REGISTRY_USER)"
    echo "  --registry-password   Registry password (default: $DEFAULT_REGISTRY_PASSWORD)"
    echo "  --install-dir         Installation directory (default: $DEFAULT_INSTALL_DIR)"
    echo "  --help                Display this help message"
    echo ""
    echo "This script verifies that bootstrap configurations are correctly set up"
    echo "for disconnected OpenShift cluster installation."
    exit 1
}

# Function to verify install-config.yaml
verify_install_config() {
    local install_dir="$1"
    local registry_port="$2"
    
    print_info "Verifying install-config.yaml..."
    
    if [[ ! -f "$install_dir/install-config.yaml" ]]; then
        print_error "install-config.yaml not found in $install_dir"
        return 1
    fi
    
    # Check for imageContentSources
    if grep -q "imageContentSources:" "$install_dir/install-config.yaml"; then
        print_success "imageContentSources found in install-config.yaml"
        
        # Check for local registry mirrors
        if grep -q "localhost:$registry_port" "$install_dir/install-config.yaml"; then
            print_success "Local registry mirrors configured correctly"
        else
            print_warning "Local registry mirrors not found in imageContentSources"
        fi
    else
        print_error "imageContentSources not found in install-config.yaml"
        return 1
    fi
    
    # Check for additionalTrustBundle
    if grep -q "additionalTrustBundle:" "$install_dir/install-config.yaml"; then
        print_success "additionalTrustBundle found in install-config.yaml"
    else
        print_warning "additionalTrustBundle not found in install-config.yaml"
    fi
    
    # Check for pullSecret
    if grep -q "pullSecret:" "$install_dir/install-config.yaml"; then
        print_success "pullSecret found in install-config.yaml"
        
        # Check if pull secret contains local registry auth
        if grep -A 10 "pullSecret:" "$install_dir/install-config.yaml" | grep -q "localhost:$registry_port"; then
            print_success "Pull secret contains local registry authentication"
        else
            print_warning "Pull secret may not contain local registry authentication"
        fi
    else
        print_error "pullSecret not found in install-config.yaml"
        return 1
    fi
    
    return 0
}

# Function to verify manifests
verify_manifests() {
    local install_dir="$1"
    local registry_port="$2"
    
    print_info "Verifying manifests..."
    
    if [[ ! -d "$install_dir/manifests" ]]; then
        print_error "Manifests directory not found in $install_dir"
        return 1
    fi
    
    # Check for image content source policy
    if [[ -f "$install_dir/manifests/image-content-source-policy.yaml" ]]; then
        print_success "Image content source policy found"
        
        if grep -q "localhost:$registry_port" "$install_dir/manifests/image-content-source-policy.yaml"; then
            print_success "Image content source policy contains local registry"
        else
            print_warning "Image content source policy missing local registry"
        fi
    else
        print_error "Image content source policy not found"
        return 1
    fi
    
    # Check for pull secret manifest
    if [[ -f "$install_dir/manifests/openshift-config-secret-pull-secret.yaml" ]]; then
        print_success "Pull secret manifest found"
        
        # Decode and check pull secret content
        local dockerconfig=$(grep "\.dockerconfigjson:" "$install_dir/manifests/openshift-config-secret-pull-secret.yaml" | awk '{print $2}')
        if echo "$dockerconfig" | base64 -d | grep -q "localhost:$registry_port"; then
            print_success "Pull secret manifest contains local registry authentication"
        else
            print_warning "Pull secret manifest may not contain local registry authentication"
        fi
    else
        print_error "Pull secret manifest not found"
        return 1
    fi
    
    # Check for bootstrap configuration files
    local bootstrap_files=(
        "99-hosts-config.yaml"
        "99-registry-config.yaml"
        "99-auth-config.yaml"
        "99-release-image-config.yaml"
        "99-bootstrap-config.yaml"
    )
    
    for file in "${bootstrap_files[@]}"; do
        if [[ -f "$install_dir/manifests/$file" ]]; then
            print_success "Bootstrap configuration file found: $file"
        else
            print_warning "Bootstrap configuration file missing: $file"
        fi
    done
    
    return 0
}

# Function to verify registry accessibility
verify_registry_access() {
    local registry_port="$1"
    local registry_user="$2"
    local registry_password="$3"
    
    print_info "Verifying registry accessibility..."
    
    # Test registry connectivity
    if curl -k -s -u "$registry_user:$registry_password" "https://localhost:$registry_port/v2/_catalog" >/dev/null 2>&1; then
        print_success "Registry is accessible"
        
        # Check for required images
        local required_images=(
            "openshift/ocp/release"
            "openshift/cli"
            "openshift/installer"
            "openshift/machine-config-operator"
        )
        
        local catalog=$(curl -k -s -u "$registry_user:$registry_password" "https://localhost:$registry_port/v2/_catalog")
        
        for image in "${required_images[@]}"; do
            if echo "$catalog" | jq -r '.repositories[]' | grep -q "^$image$"; then
                print_success "Required image found: $image"
            else
                print_warning "Required image missing: $image"
            fi
        done
        
        # Check for release image tags
        if curl -k -s -u "$registry_user:$registry_password" "https://localhost:$registry_port/v2/openshift/ocp/release/tags/list" | grep -q '"4.19"'; then
            print_success "Release image tag 4.19 found"
        else
            print_warning "Release image tag 4.19 missing"
        fi
        
    else
        print_error "Registry is not accessible"
        return 1
    fi
    
    return 0
}

# Function to verify network connectivity
verify_network_connectivity() {
    print_info "Verifying network connectivity..."
    
    # Check if we can reach the registry IP
    if ping -c 1 10.0.10.10 >/dev/null 2>&1; then
        print_success "Registry IP (10.0.10.10) is reachable"
    else
        print_warning "Registry IP (10.0.10.10) is not reachable via ping (this may be normal)"
    fi
    
    # Check if we can connect to registry port
    if nc -z 10.0.10.10 5000 2>/dev/null; then
        print_success "Registry port 5000 is accessible"
    else
        print_warning "Registry port 5000 is not accessible"
    fi
    
    # Check /etc/hosts configuration
    if grep -q "10.0.10.10.*registry.ci.openshift.org" /etc/hosts; then
        print_success "/etc/hosts contains registry.ci.openshift.org mapping"
    else
        print_warning "/etc/hosts missing registry.ci.openshift.org mapping"
    fi
    
    if grep -q "10.0.10.10.*quay.io" /etc/hosts; then
        print_success "/etc/hosts contains quay.io mapping"
    else
        print_warning "/etc/hosts missing quay.io mapping"
    fi
}

# Function to verify container runtime configuration
verify_container_runtime_config() {
    print_info "Verifying container runtime configuration..."
    
    # Check registries.conf
    if [[ -f "/etc/containers/registries.conf" ]]; then
        print_success "registries.conf exists"
        
        if grep -q "insecure = true" /etc/containers/registries.conf; then
            print_success "registries.conf contains insecure configuration"
        else
            print_warning "registries.conf missing insecure configuration"
        fi
        
        if grep -q "10.0.10.10:5000" /etc/containers/registries.conf; then
            print_success "registries.conf contains local registry configuration"
        else
            print_warning "registries.conf missing local registry configuration"
        fi
    else
        print_warning "registries.conf not found"
    fi
    
    # Check authentication configuration
    if [[ -f "/root/.docker/config.json" ]]; then
        print_success "Docker authentication config exists"
        
        if grep -q "10.0.10.10:5000" /root/.docker/config.json; then
            print_success "Docker authentication config contains local registry"
        else
            print_warning "Docker authentication config missing local registry"
        fi
    else
        print_warning "Docker authentication config not found"
    fi
}

# Function to verify release image scripts
verify_release_image_scripts() {
    print_info "Verifying release image scripts..."
    
    # Check release-image.sh
    if [[ -f "/usr/local/bin/release-image.sh" ]]; then
        print_success "release-image.sh exists"
        
        if grep -q "10.0.10.10:5000" /usr/local/bin/release-image.sh; then
            print_success "release-image.sh contains local registry configuration"
        else
            print_warning "release-image.sh missing local registry configuration"
        fi
    else
        print_warning "release-image.sh not found"
    fi
    
    # Check release-image-download.sh
    if [[ -f "/usr/local/bin/release-image-download.sh" ]]; then
        print_success "release-image-download.sh exists"
        
        if grep -q "REGISTRY_USER" /usr/local/bin/release-image-download.sh; then
            print_success "release-image-download.sh contains authentication configuration"
        else
            print_warning "release-image-download.sh missing authentication configuration"
        fi
    else
        print_warning "release-image-download.sh not found"
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
            --install-dir)
                INSTALL_DIR="$2"
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
    CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
    REGISTRY_PORT=${REGISTRY_PORT:-$DEFAULT_REGISTRY_PORT}
    REGISTRY_USER=${REGISTRY_USER:-$DEFAULT_REGISTRY_USER}
    REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-$DEFAULT_REGISTRY_PASSWORD}
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}
    
    echo -e "${BLUE}🔍 Bootstrap Configuration Verification${NC}"
    echo "============================================="
    echo ""
    echo -e "${BLUE}📋 Configuration:${NC}"
    echo "   Cluster Name: $CLUSTER_NAME"
    echo "   Registry Port: $REGISTRY_PORT"
    echo "   Registry User: $REGISTRY_USER"
    echo "   Install Directory: $INSTALL_DIR"
    echo ""
    
    local overall_status=0
    
    # Verify install-config.yaml
    if verify_install_config "$INSTALL_DIR" "$REGISTRY_PORT"; then
        print_success "Install config verification passed"
    else
        print_error "Install config verification failed"
        overall_status=1
    fi
    
    echo ""
    
    # Verify manifests
    if verify_manifests "$INSTALL_DIR" "$REGISTRY_PORT"; then
        print_success "Manifests verification passed"
    else
        print_error "Manifests verification failed"
        overall_status=1
    fi
    
    echo ""
    
    # Verify registry accessibility
    if verify_registry_access "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"; then
        print_success "Registry accessibility verification passed"
    else
        print_error "Registry accessibility verification failed"
        overall_status=1
    fi
    
    echo ""
    
    # Verify network connectivity
    verify_network_connectivity
    
    echo ""
    
    # Verify container runtime configuration
    verify_container_runtime_config
    
    echo ""
    
    # Verify release image scripts
    verify_release_image_scripts
    
    echo ""
    echo -e "${BLUE}📊 Verification Summary${NC}"
    echo "========================"
    
    if [[ $overall_status -eq 0 ]]; then
        print_success "All critical verifications passed!"
        echo ""
        print_info "Bootstrap node should be able to pull images successfully"
        print_info "You can proceed with cluster installation"
    else
        print_error "Some verifications failed"
        echo ""
        print_warning "Please fix the issues before proceeding with cluster installation"
        print_warning "Check the warnings and errors above for details"
    fi
    
    echo ""
    print_info "Next steps:"
    echo "  1. If all verifications passed, run: ./08-install-cluster.sh"
    echo "  2. If verifications failed, check the configuration and retry"
    echo "  3. Monitor installation logs for any issues"
    
    exit $overall_status
}

# Run main function with all arguments
main "$@" 