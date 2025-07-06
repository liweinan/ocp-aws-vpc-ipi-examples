#!/bin/bash

set -e

echo "=== Deep Debug: Testing if mirror mapping actually works ==="

# Create registry config with correct source path
cat > /tmp/debug-mirror-config.json << 'EOF'
{
  "auths": {
    "localhost:5000": {
      "auth": "YWRtaW46YWRtaW4xMjM="
    }
  },
  "imageContentSources": [
    {
      "mirrors": ["localhost:5000/openshift/installer"],
      "source": "registry.ci.openshift.org/openshift/installer"
    }
  ]
}
EOF

echo "=== Test 1: Check if oc respects imageContentSources ==="
echo "Source: registry.ci.openshift.org/openshift/installer"
echo "Mirror: localhost:5000/openshift/installer"
echo ""

# Test with network isolation simulation
echo "=== Test 2: Simulate network isolation ==="
echo "Blocking external registry access temporarily..."

# Create a temporary hosts file to block external registry
sudo cp /etc/hosts /tmp/hosts.backup
echo "127.0.0.1 registry.ci.openshift.org" | sudo tee -a /etc/hosts > /dev/null

echo "Now testing with blocked external registry..."
sudo oc adm release info registry.ci.openshift.org/openshift/installer:latest \
  --registry-config=/tmp/debug-mirror-config.json \
  --insecure \
  --loglevel=6 \
  --output=json 2>&1 | grep -E "(mirror|localhost|registry)" | head -10

# Restore hosts file
sudo cp /tmp/hosts.backup /etc/hosts

echo ""
echo "=== Test 3: Check oc source code for mirror handling ==="
echo "Looking for mirror-related code in oc binary..."
strings $(which oc) | grep -i mirror | head -5 || echo "No mirror strings found"

echo ""
echo "=== Test 4: Test with different oc command ==="
echo "Testing oc adm release mirror command..."
sudo oc adm release mirror --from=registry.ci.openshift.org/openshift/installer:latest \
  --to-dir=/tmp/mirror-test \
  --registry-config=/tmp/debug-mirror-config.json \
  --insecure \
  --dry-run 2>&1 | grep -E "(mirror|localhost|registry)" | head -10

echo ""
echo "=== Test 5: Check if imageContentSources is a valid config ==="
echo "Testing with oc adm release info help..."
oc adm release info --help | grep -A 5 -B 5 "registry-config" || echo "No registry-config help found" 