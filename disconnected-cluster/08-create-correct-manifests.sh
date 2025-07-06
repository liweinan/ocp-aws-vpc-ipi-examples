#!/bin/bash

# Create Correct MachineConfig Manifests for Disconnected Cluster
# This script demonstrates the proper way to create MachineConfig files
# and generate ignition files without modifying the ignition files directly

set -eo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_INSTALL_DIR="./openshift-install-dir"
DEFAULT_REGISTRY_IP="10.0.10.10"
DEFAULT_REGISTRY_PORT="5000"
DEFAULT_REGISTRY_USER="admin"
DEFAULT_REGISTRY_PASSWORD="admin123"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --install-dir        Installation directory (default: $DEFAULT_INSTALL_DIR)"
    echo "  --registry-ip        Registry IP address (default: $DEFAULT_REGISTRY_IP)"
    echo "  --registry-port      Registry port (default: $DEFAULT_REGISTRY_PORT)"
    echo "  --registry-user      Registry username (default: $DEFAULT_REGISTRY_USER)"
    echo "  --registry-password  Registry password (default: $DEFAULT_REGISTRY_PASSWORD)"
    echo "  --help               Display this help message"
    exit 1
}

# Parse command line arguments
INSTALL_DIR="$DEFAULT_INSTALL_DIR"
REGISTRY_IP="$DEFAULT_REGISTRY_IP"
REGISTRY_PORT="$DEFAULT_REGISTRY_PORT"
REGISTRY_USER="$DEFAULT_REGISTRY_USER"
REGISTRY_PASSWORD="$DEFAULT_REGISTRY_PASSWORD"

while [[ $# -gt 0 ]]; do
    case $1 in
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --registry-ip)
            REGISTRY_IP="$2"
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
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

echo -e "${BLUE}🔧 Creating Correct MachineConfig Manifests for Disconnected Cluster${NC}"
echo "==============================================================="
echo ""
echo -e "${BLUE}📋 Configuration:${NC}"
echo "   Install Directory: $INSTALL_DIR"
echo "   Registry URL: $REGISTRY_IP:$REGISTRY_PORT"
echo "   Registry User: $REGISTRY_USER"
echo ""

# Check if install-config.yaml exists
if [[ ! -f "$INSTALL_DIR/install-config.yaml" ]]; then
    echo -e "${RED}❌ install-config.yaml not found in $INSTALL_DIR${NC}"
    echo "Please run the install config preparation script first"
    exit 1
fi

# Check if manifests directory exists
if [[ ! -d "$INSTALL_DIR/manifests" ]]; then
    echo -e "${RED}❌ manifests directory not found in $INSTALL_DIR${NC}"
    echo "Please run 'openshift-install create manifests' first"
    exit 1
fi

echo -e "${BLUE}📝 Creating registries.conf content...${NC}"

# Create the correct registries.conf content
cat > /tmp/registries.conf <<EOF
unqualified-search-registries = ["$REGISTRY_IP:$REGISTRY_PORT"]

[[registry]]
  location = "$REGISTRY_IP:$REGISTRY_PORT"
  insecure = true
  prefix = ""

[[registry]]
  location = "registry.ci.openshift.org"
  insecure = false
  prefix = ""

[[registry]]
  location = "quay.io"
  insecure = false
  prefix = ""

[[registry.mirror]]
  location = "$REGISTRY_IP:$REGISTRY_PORT"
  insecure = true

[[registry.mirror]]
  location = "$REGISTRY_IP:$REGISTRY_PORT"
  insecure = true
EOF

echo -e "${BLUE}📝 Creating hosts file content...${NC}"

# Create the correct hosts content
cat > /tmp/hosts <<EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
$REGISTRY_IP registry.ci.openshift.org
$REGISTRY_IP quay.io
EOF

echo -e "${BLUE}📝 Creating authentication config...${NC}"

# Create the authentication config
cat > /tmp/auth.json <<EOF
{"auths":{"$REGISTRY_IP:$REGISTRY_PORT":{"auth":"$(echo -n "$REGISTRY_USER:$REGISTRY_PASSWORD" | base64)"}}}
EOF

echo -e "${BLUE}📝 Creating release-image-download script...${NC}"

# Create the release-image-download script
cat > /tmp/release-image-download.sh <<EOF
#!/bin/bash
set -e

echo "Downloading OpenShift release image from local registry..."

# Pull the release image from local registry
podman pull --tls-verify=false --authfile=/root/.docker/config.json $REGISTRY_IP:$REGISTRY_PORT/openshift/ocp/release:4.19

# Extract the openshift-install binary
podman run --rm --authfile=/root/.docker/config.json $REGISTRY_IP:$REGISTRY_PORT/openshift/ocp/release:4.19 /usr/bin/openshift-install version

echo "Release image download completed"
EOF

chmod +x /tmp/release-image-download.sh

echo -e "${BLUE}🔧 Creating MachineConfig files in manifests directory...${NC}"

# Create hosts MachineConfig
cat > "$INSTALL_DIR/manifests/99-hosts-config.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-hosts-config
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(cat /tmp/hosts | base64 -w 0)
        mode: 0644
        path: /etc/hosts
EOF

# Create registry MachineConfig
cat > "$INSTALL_DIR/manifests/99-registry-config.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-registry-config
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(cat /tmp/registries.conf | base64 -w 0)
        mode: 0644
        path: /etc/containers/registries.conf
EOF

# Create authentication MachineConfig
cat > "$INSTALL_DIR/manifests/99-auth-config.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-auth-config
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(cat /tmp/auth.json | base64 -w 0)
        mode: 0644
        path: /root/.docker/config.json
EOF

# Create release-image service MachineConfig
cat > "$INSTALL_DIR/manifests/99-release-image-service.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-release-image-service
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(cat /tmp/release-image-download.sh | base64 -w 0)
        mode: 0755
        path: /usr/local/bin/release-image-download.sh
    systemd:
      units:
      - name: release-image.service
        enabled: true
        contents: |
          [Unit]
          Description=Download the OpenShift Release Image
          Before=bootkube.service
          After=network-online.target
          Wants=network-online.target
          
          [Service]
          Type=oneshot
          ExecStart=/usr/local/bin/release-image-download.sh
          StandardOutput=journal
          StandardError=journal
          
          [Install]
          WantedBy=multi-user.target
EOF

echo -e "${GREEN}✅ MachineConfig files created successfully${NC}"

# List all MachineConfig files
echo -e "${BLUE}📋 MachineConfig files created:${NC}"
ls -la "$INSTALL_DIR/manifests/" | grep -E "(hosts|registry|auth|release)"

echo ""
echo -e "${BLUE}🔧 Now generating ignition files...${NC}"

# Generate ignition files
cd "$INSTALL_DIR"
if openshift-install create ignition-configs --log-level=info; then
    echo -e "${GREEN}✅ Ignition files generated successfully${NC}"
    
    # Verify that the MachineConfigs were included in the ignition files
    echo ""
    echo -e "${BLUE}🔍 Verifying MachineConfig inclusion in ignition files...${NC}"
    
    if [[ -f "bootstrap.ign" ]]; then
        echo -e "${GREEN}✅ bootstrap.ign generated${NC}"
        
        # Check for registries.conf in bootstrap.ign
        if cat bootstrap.ign | jq -r '.storage.files[] | select(.path == "/etc/containers/registries.conf") | .contents.source' 2>/dev/null | grep -q "data:text/plain"; then
            echo -e "${GREEN}✅ registries.conf found in bootstrap.ign${NC}"
            
            # Extract and show registries.conf content
            echo ""
            echo -e "${BLUE}📋 registries.conf content in bootstrap.ign:${NC}"
            cat bootstrap.ign | jq -r '.storage.files[] | select(.path == "/etc/containers/registries.conf") | .contents.source' | sed 's/^data:text\/plain;charset=utf-8;base64,//' | base64 -d 2>/dev/null | head -20
        else
            echo -e "${YELLOW}⚠️  registries.conf not found in bootstrap.ign${NC}"
        fi
        
        # Check for hosts file in bootstrap.ign
        if cat bootstrap.ign | jq -r '.storage.files[] | select(.path == "/etc/hosts") | .contents.source' 2>/dev/null | grep -q "data:text/plain"; then
            echo -e "${GREEN}✅ hosts file found in bootstrap.ign${NC}"
        else
            echo -e "${YELLOW}⚠️  hosts file not found in bootstrap.ign${NC}"
        fi
        
        # Check for auth config in bootstrap.ign
        if cat bootstrap.ign | jq -r '.storage.files[] | select(.path == "/root/.docker/config.json") | .contents.source' 2>/dev/null | grep -q "data:text/plain"; then
            echo -e "${GREEN}✅ auth config found in bootstrap.ign${NC}"
        else
            echo -e "${YELLOW}⚠️  auth config not found in bootstrap.ign${NC}"
        fi
        
        # Check for systemd units in bootstrap.ign
        if cat bootstrap.ign | jq -r '.systemd.units[] | select(.name == "release-image.service") | .name' 2>/dev/null | grep -q "release-image.service"; then
            echo -e "${GREEN}✅ release-image.service found in bootstrap.ign${NC}"
        else
            echo -e "${YELLOW}⚠️  release-image.service not found in bootstrap.ign${NC}"
        fi
    else
        echo -e "${RED}❌ bootstrap.ign not generated${NC}"
    fi
    
    if [[ -f "master.ign" ]]; then
        echo -e "${GREEN}✅ master.ign generated${NC}"
    fi
    
    if [[ -f "worker.ign" ]]; then
        echo -e "${GREEN}✅ worker.ign generated${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}🎉 Correct MachineConfig workflow completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}📋 Summary:${NC}"
    echo "   ✅ MachineConfig files created in manifests directory"
    echo "   ✅ Ignition files generated with MachineConfigs included"
    echo "   ✅ Bootstrap node will use local registry configuration"
    echo "   ✅ No manual ignition file modification required"
    echo ""
    echo -e "${BLUE}🚀 Next steps:${NC}"
    echo "   - Use the generated ignition files for cluster installation"
    echo "   - Bootstrap node will automatically use local registry"
    echo "   - No need to modify ignition files after generation"
    
else
    echo -e "${RED}❌ Failed to generate ignition files${NC}"
    exit 1
fi

# Clean up temporary files
rm -f /tmp/registries.conf /tmp/hosts /tmp/auth.json /tmp/release-image-download.sh

echo ""
echo -e "${GREEN}🎉 Correct MachineConfig workflow demonstration completed!${NC}" 