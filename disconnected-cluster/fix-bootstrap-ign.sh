#!/bin/bash

# Fix Bootstrap Ignition Configuration for Disconnected Cluster
# This script modifies the bootstrap.ign file to include proper disconnected cluster configurations

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

echo -e "${BLUE}🔧 Fixing Bootstrap Ignition Configuration for Disconnected Cluster${NC}"
echo "==============================================================="
echo ""
echo -e "${BLUE}📋 Configuration:${NC}"
echo "   Install Directory: $INSTALL_DIR"
echo "   Registry URL: $REGISTRY_IP:$REGISTRY_PORT"
echo "   Registry User: $REGISTRY_USER"
echo ""

# Check if bootstrap.ign exists
if [[ ! -f "$INSTALL_DIR/bootstrap.ign" ]]; then
    echo -e "${RED}❌ bootstrap.ign not found in $INSTALL_DIR${NC}"
    exit 1
fi

echo -e "${BLUE}📝 Creating corrected registries.conf...${NC}"

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

echo -e "${BLUE}🔧 Modifying bootstrap.ign...${NC}"

# Create a temporary directory for processing
TEMP_DIR=$(mktemp -d)
cp "$INSTALL_DIR/bootstrap.ign" "$TEMP_DIR/bootstrap.ign"

# Extract the current bootstrap.ign
cd "$TEMP_DIR"
jq -r '.storage.files[] | select(.path == "/etc/containers/registries.conf") | .contents.source' bootstrap.ign | sed 's/^data:text\/plain;charset=utf-8;base64,//' | base64 -d > current_registries.conf

echo -e "${YELLOW}⚠️  Current registries.conf:${NC}"
cat current_registries.conf

echo -e "${GREEN}✅ New registries.conf:${NC}"
cat /tmp/registries.conf

# Create the new bootstrap.ign with corrected configurations
jq --arg registries "$(cat /tmp/registries.conf | base64 -w 0)" \
   --arg hosts "$(cat /tmp/hosts | base64 -w 0)" \
   --arg auth "$(cat /tmp/auth.json | base64 -w 0)" \
   '.storage.files += [
     {
       "contents": {
         "source": ("data:text/plain;charset=utf-8;base64," + $registries)
       },
       "mode": 420,
       "path": "/etc/containers/registries.conf"
     },
     {
       "contents": {
         "source": ("data:text/plain;charset=utf-8;base64," + $hosts)
       },
       "mode": 420,
       "path": "/etc/hosts"
     },
     {
       "contents": {
         "source": ("data:text/plain;charset=utf-8;base64," + $auth)
       },
       "mode": 384,
       "path": "/root/.docker/config.json"
     }
   ]' bootstrap.ign > bootstrap_fixed.ign

# Replace the original bootstrap.ign
cp bootstrap_fixed.ign "$INSTALL_DIR/bootstrap.ign"

# Clean up
cd - > /dev/null
rm -rf "$TEMP_DIR"
rm -f /tmp/registries.conf /tmp/hosts /tmp/auth.json

echo -e "${GREEN}✅ Bootstrap ignition configuration fixed successfully${NC}"
echo ""
echo -e "${BLUE}📋 Summary of changes:${NC}"
echo "   ✅ Added unqualified-search-registries configuration"
echo "   ✅ Set insecure = true for local registry"
echo "   ✅ Added /etc/hosts entries for registry redirection"
echo "   ✅ Added authentication configuration"
echo ""
echo -e "${GREEN}🎉 Bootstrap node is now configured for disconnected cluster installation${NC}" 