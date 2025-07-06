#!/bin/bash

set -e

echo "=== Fixing imageContentSources configuration ==="

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

# Origin release mappings with version tags
- mirrors:
  - localhost:5000/openshift/ocp/release
  source: registry.ci.openshift.org/origin/release:4.19
- mirrors:
  - localhost:5000/openshift/ocp/release
  source: registry.ci.openshift.org/origin/release:4.19.2
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

echo "=== Generated fixed imageContentSources configuration ==="
cat /tmp/fixed-image-content-sources.yaml

echo ""
echo "=== Checking if all required images exist in local registry ==="

# Check if all required images exist
required_images=(
  "openshift/ocp/release"
  "openshift/installer"
  "openshift/cli"
  "openshift/machine-config-operator"
  "openshift/cluster-version-operator"
  "openshift/cluster-dns-operator"
  "openshift/cluster-ingress-operator"
  "openshift/cluster-network-operator"
  "openshift/cluster-storage-operator"
  "openshift/console"
  "openshift/etcd"
  "openshift/haproxy-router"
  "openshift/hyperkube"
  "openshift/oauth-proxy"
  "openshift/oauth-server"
  "openshift/prometheus-node-exporter"
  "openshift/prometheus-operator"
  "openshift/kube-state-metrics"
  "openshift/coredns"
  "openshift/aws-ebs-csi-driver"
  "openshift/aws-ebs-csi-driver-operator"
)

for image in "${required_images[@]}"; do
  echo "Checking $image..."
  if curl -k -s -u admin:admin123 "https://localhost:5000/v2/$image/tags/list" > /dev/null 2>&1; then
    echo "  ✅ $image exists"
  else
    echo "  ❌ $image missing"
  fi
done

echo ""
echo "=== Instructions to apply the fix ==="
echo "1. Copy the fixed configuration:"
echo "   cp /tmp/fixed-image-content-sources.yaml ~/disconnected-cluster/"
echo ""
echo "2. Update your install-config.yaml:"
echo "   yq eval '.imageContentSources = load(\"/tmp/fixed-image-content-sources.yaml\").imageContentSources' ~/disconnected-cluster/openshift-install-dir/install-config.yaml.backup > ~/disconnected-cluster/install-config.yaml"
echo ""
echo "3. Regenerate manifests:"
echo "   cd ~/disconnected-cluster/openshift-install-dir && openshift-install create manifests" 