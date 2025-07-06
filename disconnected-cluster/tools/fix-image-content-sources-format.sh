#!/bin/bash

set -e

echo "=== Fixing imageContentSources format ==="
echo "Removing tags from source fields (source must be repository, not reference)"

# Create the corrected imageContentSources configuration
cat > /tmp/fixed-image-content-sources.yaml << 'EOF'
imageContentSources:
# Primary release image mappings
- mirrors:
  - localhost:5000/openshift/ocp/release
  source: registry.ci.openshift.org/ocp/4.19.2
- mirrors:
  - localhost:5000/openshift/ocp/release
  source: registry.ci.openshift.org/ocp/4.19.2/release

# Origin release mappings (without tags in source)
- mirrors:
  - localhost:5000/openshift/ocp/release
  source: registry.ci.openshift.org/origin/release
- mirrors:
  - localhost:5000/openshift/ocp/release
  source: registry.ci.openshift.org/origin/release

# Installer and CLI mappings with correct format
- mirrors:
  - localhost:5000/openshift/installer
  source: registry.ci.openshift.org/openshift/installer
- mirrors:
  - localhost:5000/openshift/cli
  source: registry.ci.openshift.org/openshift/cli

# General openshift mappings
- mirrors:
  - localhost:5000/openshift
  source: registry.ci.openshift.org/openshift
- mirrors:
  - localhost:5000/openshift
  source: registry.ci.openshift.org/origin

# Quay.io mappings (critical for disconnected environments)
- mirrors:
  - localhost:5000/openshift/ocp/release
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - localhost:5000/openshift/ocp/release
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
- mirrors:
  - localhost:5000/openshift/ocp/release
  source: quay.io/openshift-release-dev/ocp-release-nightly

# Additional component mappings
- mirrors:
  - localhost:5000/openshift/machine-config-operator
  source: registry.ci.openshift.org/openshift/machine-config-operator
- mirrors:
  - localhost:5000/openshift/cluster-version-operator
  source: registry.ci.openshift.org/openshift/cluster-version-operator
- mirrors:
  - localhost:5000/openshift/cluster-dns-operator
  source: registry.ci.openshift.org/openshift/cluster-dns-operator
- mirrors:
  - localhost:5000/openshift/cluster-ingress-operator
  source: registry.ci.openshift.org/openshift/cluster-ingress-operator
- mirrors:
  - localhost:5000/openshift/cluster-network-operator
  source: registry.ci.openshift.org/openshift/cluster-network-operator
- mirrors:
  - localhost:5000/openshift/cluster-storage-operator
  source: registry.ci.openshift.org/openshift/cluster-storage-operator
- mirrors:
  - localhost:5000/openshift/console
  source: registry.ci.openshift.org/openshift/console
- mirrors:
  - localhost:5000/openshift/etcd
  source: registry.ci.openshift.org/openshift/etcd
- mirrors:
  - localhost:5000/openshift/haproxy-router
  source: registry.ci.openshift.org/openshift/haproxy-router
- mirrors:
  - localhost:5000/openshift/hyperkube
  source: registry.ci.openshift.org/openshift/hyperkube
- mirrors:
  - localhost:5000/openshift/oauth-proxy
  source: registry.ci.openshift.org/openshift/oauth-proxy
- mirrors:
  - localhost:5000/openshift/oauth-server
  source: registry.ci.openshift.org/openshift/oauth-server
- mirrors:
  - localhost:5000/openshift/prometheus-node-exporter
  source: registry.ci.openshift.org/openshift/prometheus-node-exporter
- mirrors:
  - localhost:5000/openshift/prometheus-operator
  source: registry.ci.openshift.org/openshift/prometheus-operator
- mirrors:
  - localhost:5000/openshift/kube-state-metrics
  source: registry.ci.openshift.org/openshift/kube-state-metrics
- mirrors:
  - localhost:5000/openshift/coredns
  source: registry.ci.openshift.org/openshift/coredns
- mirrors:
  - localhost:5000/openshift/aws-ebs-csi-driver
  source: registry.ci.openshift.org/openshift/aws-ebs-csi-driver
- mirrors:
  - localhost:5000/openshift/aws-ebs-csi-driver-operator
  source: registry.ci.openshift.org/openshift/aws-ebs-csi-driver-operator
EOF

echo "=== Generated corrected imageContentSources configuration ==="
echo "Key changes:"
echo "- Removed tags from source fields (e.g., :4.19, :4.19.2)"
echo "- Source fields now contain only repository paths"
echo ""

echo "=== Applying the fix ==="
# Update install-config.yaml with corrected imageContentSources
yq eval '.imageContentSources = load("/tmp/fixed-image-content-sources.yaml").imageContentSources' install-config.yaml.backup > install-config.yaml

echo "✅ Fixed install-config.yaml"
echo ""
echo "=== Verifying the fix ==="
echo "Checking for any remaining tags in source fields..."

# Check if any source fields still contain tags
if yq eval '.imageContentSources[].source' install-config.yaml | grep -q ":"; then
    echo "❌ Found tags in source fields:"
    yq eval '.imageContentSources[].source' install-config.yaml | grep ":"
else
    echo "✅ All source fields are correctly formatted (no tags)"
fi

echo ""
echo "=== Testing manifest generation ==="
echo "Testing if the fix resolves the validation error..."

if AWS_PROFILE=static openshift-install create manifests --dir=/tmp/test-manifests > /dev/null 2>&1; then
    echo "✅ Manifest generation successful"
else
    echo "❌ Manifest generation still failed"
    echo "Running with verbose output to see the error:"
    AWS_PROFILE=static openshift-install create manifests --dir=/tmp/test-manifests 2>&1 | head -10
fi

echo ""
echo "=== Summary ==="
echo "The fix removes tags from imageContentSources source fields."
echo "This is required because source must be a repository path, not a reference."
echo "The mirror mappings will still work correctly for all image tags." 