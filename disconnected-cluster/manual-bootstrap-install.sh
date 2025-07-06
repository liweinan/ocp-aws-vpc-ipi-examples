#!/bin/bash

# Manual Bootstrap Installation Script
# This script should be executed on the bootstrap node to complete the cluster installation
# It uses the ignition-generated scripts that are already present on the bootstrap node

set -eo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 Manual Bootstrap Installation Script${NC}"
echo "=============================================="
echo ""
echo -e "${YELLOW}⚠️  This script should be run on the bootstrap node${NC}"
echo -e "${YELLOW}⚠️  It will use the ignition-generated scripts${NC}"
echo ""

# Function to check if running on bootstrap node
check_bootstrap_node() {
    # Check if it's CoreOS (RHEL CoreOS)
    if [[ ! -f /etc/os-release ]] || ! grep -q "CoreOS" /etc/os-release; then
        echo -e "${RED}❌ This script must be run on a CoreOS bootstrap node${NC}"
        exit 1
    fi
    
    if [[ ! -f /etc/motd ]] || ! grep -q "bootstrap" /etc/motd; then
        echo -e "${RED}❌ This script must be run on the bootstrap node${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Running on bootstrap node${NC}"
}

# Function to check ignition-generated scripts
check_ignition_scripts() {
    echo -e "${BLUE}🔍 Checking ignition-generated scripts...${NC}"
    
    # Check for key scripts
    local scripts=(
        "/usr/local/bin/bootkube.sh"
        "/usr/local/bin/release-image-download.sh"
        "/usr/local/bin/kubelet.sh"
        "/usr/local/bin/crio-configure.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            echo -e "${GREEN}✅ Found: $script${NC}"
        else
            echo -e "${YELLOW}⚠️  Missing: $script${NC}"
        fi
    done
    
    # Check for systemd services
    local services=(
        "release-image.service"
        "bootkube.service"
        "kubelet.service"
    )
    
    echo ""
    echo -e "${BLUE}🔍 Checking systemd services...${NC}"
    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "$service"; then
            echo -e "${GREEN}✅ Found service: $service${NC}"
        else
            echo -e "${YELLOW}⚠️  Missing service: $service${NC}"
        fi
    done
}

# Function to verify registry connectivity
verify_registry() {
    echo -e "${BLUE}🔍 Verifying registry connectivity...${NC}"
    
    # Check if we can reach the bastion registry
    if curl -k -s -u admin:admin123 "https://10.0.10.10:5000/v2/" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Registry is accessible${NC}"
    else
        echo -e "${YELLOW}⚠️  Registry may not be accessible, continuing anyway${NC}"
    fi
    
    # Check registries.conf
    if [[ -f /etc/containers/registries.conf ]]; then
        echo -e "${GREEN}✅ registries.conf exists${NC}"
        echo "Content:"
        cat /etc/containers/registries.conf | head -10
    else
        echo -e "${YELLOW}⚠️  registries.conf not found${NC}"
    fi
    
    # Check hosts file
    if grep -q "10.0.10.10" /etc/hosts; then
        echo -e "${GREEN}✅ hosts file contains registry entries${NC}"
        grep "10.0.10.10" /etc/hosts
    else
        echo -e "${YELLOW}⚠️  hosts file missing registry entries${NC}"
    fi
}

# Function to start release-image service
start_release_image_service() {
    echo -e "${BLUE}📥 Starting release-image service...${NC}"
    
    # Check if service exists
    if systemctl list-unit-files | grep -q "release-image.service"; then
        echo -e "${GREEN}✅ release-image.service found${NC}"
        
        # Check if service is already running
        if systemctl is-active --quiet release-image.service; then
            echo -e "${GREEN}✅ release-image.service is already running${NC}"
        else
            echo -e "${BLUE}🚀 Starting release-image.service...${NC}"
            systemctl start release-image.service
            echo -e "${GREEN}✅ release-image.service started${NC}"
        fi
        
        # Monitor the service
        echo -e "${BLUE}📊 Monitoring release-image.service...${NC}"
        echo "Press Ctrl+C to stop monitoring"
        journalctl -f -u release-image.service
    else
        echo -e "${RED}❌ release-image.service not found${NC}"
        echo "You may need to run the script manually:"
        echo "   /usr/local/bin/release-image-download.sh"
    fi
}

# Function to start bootkube service
start_bootkube_service() {
    echo -e "${BLUE}🚀 Starting bootkube service...${NC}"
    
    # Check if service exists
    if systemctl list-unit-files | grep -q "bootkube.service"; then
        echo -e "${GREEN}✅ bootkube.service found${NC}"
        
        # Check if service is already running
        if systemctl is-active --quiet bootkube.service; then
            echo -e "${GREEN}✅ bootkube.service is already running${NC}"
        else
            echo -e "${BLUE}🚀 Starting bootkube.service...${NC}"
            systemctl start bootkube.service
            echo -e "${GREEN}✅ bootkube.service started${NC}"
        fi
        
        # Monitor the service
        echo -e "${BLUE}📊 Monitoring bootkube.service...${NC}"
        echo "Press Ctrl+C to stop monitoring"
        journalctl -f -u bootkube.service
    else
        echo -e "${RED}❌ bootkube.service not found${NC}"
        echo "You may need to run the script manually:"
        echo "   /usr/local/bin/bootkube.sh"
    fi
}

# Function to run scripts manually
run_scripts_manually() {
    echo -e "${BLUE}🔧 Running ignition scripts manually...${NC}"
    
    # Change to the correct directory
    cd /opt/openshift
    
    # Run release-image-download script
    echo -e "${BLUE}📥 Running release-image-download.sh...${NC}"
    if [[ -f /usr/local/bin/release-image-download.sh ]]; then
        /usr/local/bin/release-image-download.sh
        echo -e "${GREEN}✅ release-image-download.sh completed${NC}"
    else
        echo -e "${RED}❌ release-image-download.sh not found${NC}"
    fi
    
    # Run bootkube script
    echo -e "${BLUE}🚀 Running bootkube.sh...${NC}"
    if [[ -f /usr/local/bin/bootkube.sh ]]; then
        /usr/local/bin/bootkube.sh
        echo -e "${GREEN}✅ bootkube.sh completed${NC}"
    else
        echo -e "${RED}❌ bootkube.sh not found${NC}"
    fi
}

# Function to monitor installation
monitor_installation() {
    echo -e "${BLUE}📊 Installation monitoring commands:${NC}"
    echo ""
    echo "1. Check service status:"
    echo "   systemctl status release-image.service"
    echo "   systemctl status bootkube.service"
    echo "   systemctl status kubelet.service"
    echo ""
    echo "2. Monitor service logs:"
    echo "   journalctl -f -u release-image.service"
    echo "   journalctl -f -u bootkube.service"
    echo "   journalctl -f -u kubelet.service"
    echo ""
    echo "3. Check API server:"
    echo "   curl -k https://localhost:6443/healthz"
    echo ""
    echo "4. Check if installation is complete:"
    echo "   ls -la /opt/openshift/auth/"
    echo ""
    echo "5. Check cluster status:"
    echo "   export KUBECONFIG=/opt/openshift/auth/kubeconfig"
    echo "   oc get nodes"
    echo "   oc get clusteroperators"
    echo ""
    echo "6. Check bootstrap progress:"
    echo "   journalctl -b -f -u release-image.service -u bootkube.service"
}

# Function to show troubleshooting commands
show_troubleshooting() {
    echo -e "${BLUE}🔧 Troubleshooting commands:${NC}"
    echo ""
    echo "1. Check system resources:"
    echo "   free -h"
    echo "   df -h"
    echo "   top"
    echo ""
    echo "2. Check network connectivity:"
    echo "   ping -c 3 10.0.10.10"
    echo "   curl -k https://10.0.10.10:5000/v2/"
    echo ""
    echo "3. Check container runtime:"
    echo "   podman ps"
    echo "   podman images"
    echo ""
    echo "4. Check ignition scripts:"
    echo "   ls -la /usr/local/bin/"
    echo "   ls -la /opt/openshift/"
    echo ""
    echo "5. Check systemd services:"
    echo "   systemctl list-unit-files | grep -E '(release|bootkube|kubelet)'"
    echo ""
    echo "6. Check logs:"
    echo "   journalctl -b -u release-image.service"
    echo "   journalctl -b -u bootkube.service"
    echo "   journalctl -b -u kubelet.service"
    echo ""
    echo "7. Check bootstrap scripts:"
    echo "   ls -la /opt/openshift/bootstrap-scripts/"
    echo "   cat /opt/openshift/bootstrap-scripts/README.md"
}

# Function to check installation status
check_installation_status() {
    echo -e "${BLUE}🔍 Checking installation status...${NC}"
    
    # Check if auth directory exists
    if [[ -d /opt/openshift/auth ]]; then
        echo -e "${GREEN}✅ Auth directory exists${NC}"
        ls -la /opt/openshift/auth/
    else
        echo -e "${YELLOW}⚠️  Auth directory not found${NC}"
    fi
    
    # Check if kubeconfig exists
    if [[ -f /opt/openshift/auth/kubeconfig ]]; then
        echo -e "${GREEN}✅ kubeconfig exists${NC}"
        
        # Try to use kubeconfig
        export KUBECONFIG=/opt/openshift/auth/kubeconfig
        if oc get nodes 2>/dev/null; then
            echo -e "${GREEN}✅ Cluster is accessible${NC}"
            echo "Nodes:"
            oc get nodes
        else
            echo -e "${YELLOW}⚠️  Cluster not yet accessible${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  kubeconfig not found${NC}"
    fi
    
    # Check service status
    echo ""
    echo -e "${BLUE}📊 Service Status:${NC}"
    systemctl status release-image.service --no-pager -l || true
    echo ""
    systemctl status bootkube.service --no-pager -l || true
    echo ""
    systemctl status kubelet.service --no-pager -l || true
}

# Main execution
main() {
    echo -e "${BLUE}🔧 Manual Bootstrap Installation${NC}"
    echo "====================================="
    echo ""
    
    # Check if running on bootstrap node
    check_bootstrap_node
    
    # Check ignition-generated scripts
    check_ignition_scripts
    
    # Verify registry connectivity
    verify_registry
    
    echo ""
    echo -e "${BLUE}📋 Installation Options:${NC}"
    echo "1. Start release-image service"
    echo "2. Start bootkube service"
    echo "3. Run scripts manually"
    echo "4. Monitor installation"
    echo "5. Check installation status"
    echo "6. Show troubleshooting commands"
    echo "7. Exit"
    echo ""
    
    read -p "Choose an option (1-7): " choice
    
    case $choice in
        1)
            start_release_image_service
            ;;
        2)
            start_bootkube_service
            ;;
        3)
            run_scripts_manually
            ;;
        4)
            monitor_installation
            ;;
        5)
            check_installation_status
            ;;
        6)
            show_troubleshooting
            ;;
        7)
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            exit 1
            ;;
    esac
}

# Run main function
main "$@" 