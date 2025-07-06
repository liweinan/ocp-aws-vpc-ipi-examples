#!/bin/bash

set -e

echo "=== Checking Bootstrap Ignition Configuration ==="

echo ""
echo "=== 1. Check if ignition files exist ==="
echo "Looking for ignition files in current directory..."

ignition_files=(
    "bootstrap.ign"
    "master.ign"
    "worker.ign"
    "metadata.json"
)

for file in "${ignition_files[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ Found: $file"
    else
        echo "❌ Missing: $file"
    fi
done

echo ""
echo "=== 2. Check install-config.yaml ==="
echo "Verifying source configuration..."

if [ -f "install-config.yaml" ]; then
    echo "✅ Found install-config.yaml"
    
    # Check imageContentSources
    echo ""
    echo "Current imageContentSources configuration:"
    yq eval '.imageContentSources' install-config.yaml 2>/dev/null || echo "No imageContentSources found"
    
    # Check pullSecret
    echo ""
    echo "Checking pullSecret for local registry..."
    if yq eval '.pullSecret' install-config.yaml | grep -q "localhost:5000" 2>/dev/null; then
        echo "✅ pullSecret contains localhost:5000 authentication"
    else
        echo "❌ pullSecret missing localhost:5000 authentication"
    fi
    
    # Check additionalTrustBundle
    echo ""
    echo "Checking additionalTrustBundle..."
    if yq eval '.additionalTrustBundle' install-config.yaml | grep -q "BEGIN CERTIFICATE" 2>/dev/null; then
        echo "✅ additionalTrustBundle contains certificate"
    else
        echo "❌ additionalTrustBundle missing or invalid"
    fi
else
    echo "❌ install-config.yaml not found"
    exit 1
fi

echo ""
echo "=== 3. Check generated manifests ==="
echo "Verifying manifest generation..."

if [ -d "manifests" ]; then
    echo "✅ Found manifests directory"
    
    # Check image-content-source-policy.yaml
    if [ -f "manifests/image-content-source-policy.yaml" ]; then
        echo "✅ Found image-content-source-policy.yaml"
        echo "Content:"
        cat manifests/image-content-source-policy.yaml | head -20
    else
        echo "❌ Missing image-content-source-policy.yaml"
    fi
    
    # Check other important manifests
    important_manifests=(
        "cluster-config-v1-configmap.yaml"
        "cluster-infrastructure-02-config.yml"
        "cluster-ingress-02-config.yml"
        "cluster-network-02-config.yml"
        "cluster-proxy-01-config.yaml"
        "cluster-scheduler-02-config.yml"
        "cvo-overrides.yaml"
        "kube-cloud-config.yaml"
        "kube-system-configmap-root-ca.yaml"
        "machine-config-server-tls-secret.yaml"
        "openshift-config-secret-pull-secret.yaml"
    )
    
    echo ""
    echo "Checking other important manifests:"
    for manifest in "${important_manifests[@]}"; do
        if [ -f "manifests/$manifest" ]; then
            echo "✅ $manifest"
        else
            echo "❌ $manifest"
        fi
    done
else
    echo "❌ manifests directory not found"
fi

echo ""
echo "=== 4. Analyze bootstrap.ign content ==="
echo "Extracting and analyzing bootstrap ignition configuration..."

if [ -f "bootstrap.ign" ]; then
    echo "✅ Found bootstrap.ign"
    
    # Check ignition version
    echo ""
    echo "Ignition version:"
    cat bootstrap.ign | jq -r '.ignition.version' 2>/dev/null || echo "Failed to get ignition version"
    
    # Check for registries.conf
    echo ""
    echo "Checking for registries.conf in ignition:"
    if cat bootstrap.ign | jq -r '.storage.files[] | select(.path == "/etc/containers/registries.conf") | .contents.source' 2>/dev/null | grep -q "data:text/plain"; then
        echo "✅ registries.conf found in ignition"
        
        # Extract and decode registries.conf
        echo ""
        echo "Decoded registries.conf content:"
        cat bootstrap.ign | jq -r '.storage.files[] | select(.path == "/etc/containers/registries.conf") | .contents.source' | sed 's/^data:text\/plain;charset=utf-8;base64,//' | base64 -d 2>/dev/null | head -30 || echo "Failed to decode registries.conf"
    else
        echo "❌ registries.conf not found in ignition"
    fi
    
    # Check for CA certificate
    echo ""
    echo "Checking for CA certificate in ignition:"
    if cat bootstrap.ign | jq -r '.storage.files[] | select(.path | contains("ca")) | .path' 2>/dev/null | grep -q "ca"; then
        echo "✅ CA certificate found in ignition"
        cat bootstrap.ign | jq -r '.storage.files[] | select(.path | contains("ca")) | .path' 2>/dev/null
    else
        echo "❌ CA certificate not found in ignition"
    fi
    
    # Check for pull secret
    echo ""
    echo "Checking for pull secret in ignition:"
    if cat bootstrap.ign | jq -r '.storage.files[] | select(.path | contains("config.json")) | .path' 2>/dev/null | grep -q "config.json"; then
        echo "✅ Pull secret config found in ignition"
        cat bootstrap.ign | jq -r '.storage.files[] | select(.path | contains("config.json")) | .path' 2>/dev/null
    else
        echo "❌ Pull secret config not found in ignition"
    fi
    
    # Check systemd units
    echo ""
    echo "Checking systemd units in ignition:"
    systemd_units=$(cat bootstrap.ign | jq -r '.systemd.units[].name' 2>/dev/null | head -10)
    if [ -n "$systemd_units" ]; then
        echo "✅ Systemd units found:"
        echo "$systemd_units"
    else
        echo "❌ No systemd units found"
    fi
    
else
    echo "❌ bootstrap.ign not found"
fi

echo ""
echo "=== 5. Test ignition configuration generation ==="
echo "Testing ignition generation with current configuration..."

# Create a test directory
mkdir -p /tmp/ignition-test
cp install-config.yaml /tmp/ignition-test/

echo "Generating ignition configs in test directory..."
if openshift-install create ignition-configs --dir=/tmp/ignition-test > /dev/null 2>&1; then
    echo "✅ Ignition generation successful"
    
    # Check if registries.conf contains mirror configuration
    if [ -f "/tmp/ignition-test/bootstrap.ign" ]; then
        echo ""
        echo "Checking registries.conf in generated bootstrap.ign:"
        registries_conf=$(cat /tmp/ignition-test/bootstrap.ign | jq -r '.storage.files[] | select(.path == "/etc/containers/registries.conf") | .contents.source' | sed 's/^data:text\/plain;charset=utf-8;base64,//' | base64 -d 2>/dev/null)
        
        if echo "$registries_conf" | grep -q "localhost:5000"; then
            echo "✅ registries.conf contains localhost:5000 mirror configuration"
            echo "Mirror configuration:"
            echo "$registries_conf" | grep -A 5 -B 5 "localhost:5000" || echo "No localhost:5000 found in registries.conf"
        else
            echo "❌ registries.conf missing localhost:5000 mirror configuration"
            echo "Current registries.conf content:"
            echo "$registries_conf" | head -20
        fi
    fi
else
    echo "❌ Ignition generation failed"
fi

echo ""
echo "=== 6. Verify imageContentSources mapping ==="
echo "Checking if imageContentSources are correctly mapped..."

# Check specific mappings
critical_mappings=(
    "registry.ci.openshift.org/origin/release:4.19"
    "registry.ci.openshift.org/openshift/installer"
    "registry.ci.openshift.org/openshift/cli"
)

echo "Checking critical image mappings:"
for mapping in "${critical_mappings[@]}"; do
    if yq eval '.imageContentSources[] | select(.source == "'$mapping'")' install-config.yaml > /dev/null 2>&1; then
        mirror=$(yq eval '.imageContentSources[] | select(.source == "'$mapping'") | .mirrors[0]' install-config.yaml 2>/dev/null)
        echo "✅ $mapping -> $mirror"
    else
        echo "❌ Missing mapping for: $mapping"
    fi
done

echo ""
echo "=== 7. Test local registry accessibility ==="
echo "Verifying local registry is accessible from bootstrap perspective..."

# Test local registry connectivity
if curl -k -s -u admin:admin123 "https://localhost:5000/v2/openshift/ocp/release/tags/list" > /dev/null 2>&1; then
    echo "✅ Local registry is accessible"
    
    # Check if required images exist
    required_images=(
        "openshift/ocp/release:4.19"
        "openshift/installer:latest"
        "openshift/cli:latest"
    )
    
    echo ""
    echo "Checking required images in local registry:"
    for image in "${required_images[@]}"; do
        repo="${image%:*}"
        tag="${image#*:}"
        if curl -k -s -u admin:admin123 "https://localhost:5000/v2/$repo/tags/list" | grep -q "$tag" 2>/dev/null; then
            echo "✅ $image exists"
        else
            echo "❌ $image missing"
        fi
    done
else
    echo "❌ Local registry is not accessible"
fi

echo ""
echo "=== 8. Final Ignition Configuration Assessment ==="
echo "Based on the analysis above:"

# Count checks
checks_passed=0
total_checks=7

echo "1. install-config.yaml with imageContentSources..."
if [ -f "install-config.yaml" ] && yq eval '.imageContentSources' install-config.yaml > /dev/null 2>&1; then
    echo "   ✅ PASS"
    ((checks_passed++))
else
    echo "   ❌ FAIL"
fi

echo "2. pullSecret with local registry auth..."
if [ -f "install-config.yaml" ] && yq eval '.pullSecret' install-config.yaml | grep -q "localhost:5000" 2>/dev/null; then
    echo "   ✅ PASS"
    ((checks_passed++))
else
    echo "   ❌ FAIL"
fi

echo "3. additionalTrustBundle with certificate..."
if [ -f "install-config.yaml" ] && yq eval '.additionalTrustBundle' install-config.yaml | grep -q "BEGIN CERTIFICATE" 2>/dev/null; then
    echo "   ✅ PASS"
    ((checks_passed++))
else
    echo "   ❌ FAIL"
fi

echo "4. manifest generation..."
if [ -d "manifests" ] && [ -f "manifests/image-content-source-policy.yaml" ]; then
    echo "   ✅ PASS"
    ((checks_passed++))
else
    echo "   ❌ FAIL"
fi

echo "5. bootstrap.ign generation..."
if [ -f "bootstrap.ign" ]; then
    echo "   ✅ PASS"
    ((checks_passed++))
else
    echo "   ❌ FAIL"
fi

echo "6. registries.conf in ignition..."
if [ -f "bootstrap.ign" ] && cat bootstrap.ign | jq -r '.storage.files[] | select(.path == "/etc/containers/registries.conf") | .contents.source' 2>/dev/null | grep -q "data:text/plain"; then
    echo "   ✅ PASS"
    ((checks_passed++))
else
    echo "   ❌ FAIL"
fi

echo "7. local registry accessibility..."
if curl -k -s -u admin:admin123 "https://localhost:5000/v2/openshift/ocp/release/tags/list" > /dev/null 2>&1; then
    echo "   ✅ PASS"
    ((checks_passed++))
else
    echo "   ❌ FAIL"
fi

echo ""
echo "=== Ignition Configuration Results ==="
echo "Passed: $checks_passed/$total_checks checks"

if [ $checks_passed -eq $total_checks ]; then
    echo "🎉 All checks passed! Bootstrap ignition configuration is correct."
    echo ""
    echo "Your bootstrap node should:"
    echo "1. ✅ Load correct registries.conf with mirror mappings"
    echo "2. ✅ Use localhost:5000 for image pulls"
    echo "3. ✅ Have proper CA certificate trust"
    echo "4. ✅ Have correct pull secret authentication"
    echo "5. ✅ Start successfully with local registry"
else
    echo "⚠️  Some checks failed. Review the configuration."
    echo ""
    echo "Failed checks indicate issues with:"
    echo "- install-config.yaml configuration"
    echo "- Manifest generation"
    echo "- Ignition file generation"
    echo "- Local registry setup"
fi

echo ""
echo "=== Next Steps ==="
echo "If all checks pass, proceed with cluster installation."
echo "Monitor bootstrap logs for:"
echo "- registries.conf loading"
echo "- Image pull from localhost:5000"
echo "- Certificate trust establishment"
echo "- Authentication success" 