#!/bin/bash

set -e

echo "=== Debugging oc mirror mapping ==="

# Create test registry config
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
      "source": "registry.ci.openshift.org/ocp/4.19.2/installer"
    }
  ]
}
EOF

echo "=== Test 1: oc with debug logging ==="
echo "Requesting: registry.ci.openshift.org/ocp/4.19.2/installer:latest"
echo "Expected mirror: localhost:5000/openshift/installer:latest"

# Run oc with debug logging
sudo oc adm release info registry.ci.openshift.org/ocp/4.19.2/installer:latest \
  --registry-config=/tmp/debug-mirror-config.json \
  --insecure \
  --loglevel=6 \
  --output=json 2>&1 | grep -E "(mirror|registry|pull|image)" | head -20

echo ""
echo "=== Test 2: oc with trace logging ==="
# Run with trace level
sudo oc adm release info registry.ci.openshift.org/ocp/4.19.2/installer:latest \
  --registry-config=/tmp/debug-mirror-config.json \
  --insecure \
  --loglevel=8 \
  --output=json 2>&1 | grep -E "(mirror|registry|pull|image|source)" | head -30

echo ""
echo "=== Test 3: Check oc version and capabilities ==="
oc version --client
oc adm release info --help | grep -E "(mirror|registry)" || echo "No mirror options found in help"

echo ""
echo "=== Test 4: Test with different image format ==="
echo "Trying: registry.ci.openshift.org/openshift/installer:latest"
sudo oc adm release info registry.ci.openshift.org/openshift/installer:latest \
  --registry-config=/tmp/debug-mirror-config.json \
  --insecure \
  --loglevel=6 \
  --output=json 2>&1 | grep -E "(mirror|registry|pull|image)" | head -10

echo ""
echo "=== Test 5: Verify local image exists ==="
curl -k -s -u admin:admin123 https://localhost:5000/v2/openshift/installer/tags/list | jq '.' 