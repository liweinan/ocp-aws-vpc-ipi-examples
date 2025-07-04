#!/bin/bash

# Quick check of image availability using imagestream query
# Run this on bastion host after oc login

echo "=== Quick Image Availability Check ==="
echo

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

echo "Getting available tags from imagestream 4.19.2..."
available_tags=$(oc get imagestream 4.19.2 -n ocp -o jsonpath='{.spec.tags[*].name}' 2>/dev/null)

if [ -z "$available_tags" ]; then
    echo "ERROR: Could not get imagestream tags. Make sure you're logged into CI cluster."
    exit 1
fi

echo "Total available tags: $(echo $available_tags | wc -w)"
echo

echo "Checking Core Images:"
echo "====================="
core_found=0
core_total=${#core_images[@]}

for image in "${core_images[@]}"; do
    printf "%-30s " "$image"
    if echo "$available_tags" | grep -q "\b$image\b"; then
        echo "✓ AVAILABLE"
        ((core_found++))
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
    printf "%-30s " "$image"
    if echo "$available_tags" | grep -q "\b$image\b"; then
        echo "✓ AVAILABLE"
        ((additional_found++))
    else
        echo "✗ NOT FOUND"
    fi
done

echo
echo "=== Summary ==="
echo "Core Images:       $core_found/$core_total available"
echo "Additional Images: $additional_found/$additional_total available"
echo "Total:             $((core_found + additional_found))/$((core_total + additional_total)) available"

if [ $core_found -eq $core_total ]; then
    echo "✓ All core images are available!"
else
    echo "⚠ Some core images are missing"
fi

echo
echo "=== Missing Images Analysis ==="
echo "Core images not found:"
for image in "${core_images[@]}"; do
    if ! echo "$available_tags" | grep -q "\b$image\b"; then
        echo "  - $image"
    fi
done

echo
echo "Additional images not found:"
for image in "${additional_images[@]}"; do
    if ! echo "$available_tags" | grep -q "\b$image\b"; then
        echo "  - $image"
    fi
done

echo
echo "=== Alternative Names Check ==="
echo "Looking for similar names in available tags..."
echo

# Check for alternative names
for image in "${core_images[@]}" "${additional_images[@]}"; do
    if ! echo "$available_tags" | grep -q "\b$image\b"; then
        echo "Alternatives for '$image':"
        echo "$available_tags" | tr ' ' '\n' | grep -i "$image" | head -3 | sed 's/^/  - /' || echo "  (no alternatives found)"
    fi
done 