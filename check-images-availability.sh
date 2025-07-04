#!/bin/bash

# Check if specific images exist in CI registry
# Run this on bastion host after oc login

set -e

echo "=== Checking Image Availability in CI Registry ==="
echo

CI_REGISTRY="registry.ci.openshift.org"
OCP_VERSION="4.19.2"

# Core images list
core_images=(
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

# Additional important images
additional_images=(
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

echo "Getting CI token from oc login..."
CI_TOKEN=$(oc whoami -t)
if [ -z "$CI_TOKEN" ]; then
    echo "ERROR: Not logged into CI cluster"
    exit 1
fi

echo "Logging into CI registry..."
echo "$CI_TOKEN" | podman login --username="weli" --password-stdin "$CI_REGISTRY"

echo
echo "Checking Core Images:"
echo "====================="
core_found=0
core_total=${#core_images[@]}

for image in "${core_images[@]}"; do
    image_url="$CI_REGISTRY/ocp/$OCP_VERSION:$image"
    printf "%-30s " "$image"
    
    if podman pull --quiet "$image_url" 2>/dev/null; then
        echo "✓ EXISTS"
        ((core_found++))
        # Clean up to save space
        podman rmi "$image_url" >/dev/null 2>&1 || true
    else
        echo "✗ NOT FOUND"
    fi
done

echo
echo "Checking Additional Images:"
echo "=========================="
additional_found=0
additional_total=${#additional_images[@]}

for image in "${additional_images[@]}"; do
    image_url="$CI_REGISTRY/ocp/$OCP_VERSION:$image"
    printf "%-30s " "$image"
    
    if podman pull --quiet "$image_url" 2>/dev/null; then
        echo "✓ EXISTS"
        ((additional_found++))
        # Clean up to save space
        podman rmi "$image_url" >/dev/null 2>&1 || true
    else
        echo "✗ NOT FOUND"
    fi
done

echo
echo "=== Summary ==="
echo "Core Images:       $core_found/$core_total found"
echo "Additional Images: $additional_found/$additional_total found"
echo "Total:             $((core_found + additional_found))/$((core_total + additional_total)) found"

if [ $core_found -eq $core_total ]; then
    echo "✓ All core images are available!"
else
    echo "⚠ Some core images are missing"
fi

echo
echo "=== Alternative Check Using Manifest ==="
echo "Let's also check what's actually available in the imagestream:"
echo

# Get the imagestream to see what's actually available
oc get imagestream 4.19.2 -n ocp -o jsonpath='{.spec.tags[*].name}' | tr ' ' '\n' | sort | head -20
echo
echo "... (showing first 20 tags)"
echo
echo "Total tags available:"
oc get imagestream 4.19.2 -n ocp -o jsonpath='{.spec.tags[*].name}' | wc -w 