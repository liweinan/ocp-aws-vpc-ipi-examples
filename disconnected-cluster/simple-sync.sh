#!/bin/bash

set -e

# Configuration
OPENSHIFT_VERSION=${1:-"4.15.0"}
CLUSTER_NAME=${2:-"fedora-disconnected-cluster"}
REGISTRY_PORT=${3:-"5000"}
REGISTRY_USER=${4:-"admin"}
REGISTRY_PASSWORD=${5:-"admin123"}

# Log file
LOG_FILE="/home/ubuntu/sync.log"

echo "🚀 Starting simplified OpenShift ${OPENSHIFT_VERSION} image sync..." | tee -a "$LOG_FILE"
echo "   Cluster: ${CLUSTER_NAME}" | tee -a "$LOG_FILE"
echo "   Registry: localhost:${REGISTRY_PORT}" | tee -a "$LOG_FILE"
echo "   User: ${REGISTRY_USER}" | tee -a "$LOG_FILE"
echo "   Log file: ${LOG_FILE}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Create sync directory
SYNC_DIR="/home/ubuntu/openshift-sync"
mkdir -p "${SYNC_DIR}"
cd "${SYNC_DIR}"

# Test registry access
echo "🧪 Testing registry access..." | tee -a "$LOG_FILE"
if ! curl -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" "http://localhost:${REGISTRY_PORT}/v2/_catalog" >/dev/null 2>&1; then
    echo "❌ Cannot access registry" | tee -a "$LOG_FILE"
    echo "   Please ensure registry is running and accessible" | tee -a "$LOG_FILE"
    exit 1
fi
echo "✅ Registry access test passed" | tee -a "$LOG_FILE"

# Login to registry
echo "🔐 Logging into registry..." | tee -a "$LOG_FILE"
if ! podman login --username "${REGISTRY_USER}" --password "${REGISTRY_PASSWORD}" --tls-verify=false "localhost:${REGISTRY_PORT}" >/dev/null 2>&1; then
    echo "❌ Failed to login to registry" | tee -a "$LOG_FILE"
    exit 1
fi
echo "✅ Registry login successful" | tee -a "$LOG_FILE"

# Get image references
echo "🔍 Getting image references..." | tee -a "$LOG_FILE"

# Sync release image only
echo "🔄 Syncing release image..." | tee -a "$LOG_FILE"
RELEASE_IMAGE="quay.io/openshift-release-dev/ocp-release:${OPENSHIFT_VERSION}-x86_64"
echo "   Pulling release image: $RELEASE_IMAGE" | tee -a "$LOG_FILE"
if ! podman pull "$RELEASE_IMAGE" >> "$LOG_FILE" 2>&1; then
    echo "❌ Failed to pull release image" | tee -a "$LOG_FILE"
    exit 1
fi
echo "✅ Release image pulled successfully" | tee -a "$LOG_FILE"

echo "   Tagging release image..." | tee -a "$LOG_FILE"
podman tag "$RELEASE_IMAGE" localhost:${REGISTRY_PORT}/openshift/release:${OPENSHIFT_VERSION}

echo "   Pushing release image..." | tee -a "$LOG_FILE"
if ! podman push --tls-verify=false localhost:${REGISTRY_PORT}/openshift/release:${OPENSHIFT_VERSION} >> "$LOG_FILE" 2>&1; then
    echo "❌ Failed to push release image" | tee -a "$LOG_FILE"
    exit 1
fi
echo "✅ Release image pushed successfully" | tee -a "$LOG_FILE"

# Also sync with digest
echo "🔄 Syncing release image with digest..." | tee -a "$LOG_FILE"
RELEASE_DIGEST=$(oc adm release info "$RELEASE_IMAGE" --output=jsonpath='{.digest}' 2>/dev/null || echo "")
if [[ -n "$RELEASE_DIGEST" ]]; then
    echo "   Release digest: $RELEASE_DIGEST" | tee -a "$LOG_FILE"
    podman tag "$RELEASE_IMAGE" localhost:${REGISTRY_PORT}/openshift/release@${RELEASE_DIGEST}
    if podman push --tls-verify=false localhost:${REGISTRY_PORT}/openshift/release@${RELEASE_DIGEST} >> "$LOG_FILE" 2>&1; then
        echo "✅ Release image with digest pushed successfully" | tee -a "$LOG_FILE"
    else
        echo "⚠️  Warning: Digest push failed (this is normal for some registries)" | tee -a "$LOG_FILE"
    fi
else
    echo "⚠️  Warning: Could not get release digest" | tee -a "$LOG_FILE"
fi

# Create imageContentSources configuration
echo "📝 Creating imageContentSources configuration..." | tee -a "$LOG_FILE"
cat > imageContentSources.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: image-content-sources
  namespace: openshift-config
data:
  registries.conf: |
    unqualified-search-registries = ["registry.${CLUSTER_NAME}.local:${REGISTRY_PORT}"]
    
    [[registry]]
      prefix = ""
      location = "quay.io/openshift-release-dev/ocp-release"
      mirror-by-digest-only = true
      mirrors = ["registry.${CLUSTER_NAME}.local:${REGISTRY_PORT}/openshift/release"]
EOF

# Create install-config template
echo "📝 Creating install-config template..." | tee -a "$LOG_FILE"
cat > install-config-template.yaml <<EOF
apiVersion: v1
baseDomain: example.com
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform:
    aws:
      type: m5.xlarge
  replicas: 3
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      type: m5.xlarge
  replicas: 3
metadata:
  name: ${CLUSTER_NAME}
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: us-east-1
    subnets:
    # Add your subnet IDs here
    vpc: # Add your VPC ID here
publish: Internal
pullSecret: '{"auths":{"registry.${CLUSTER_NAME}.local:${REGISTRY_PORT}":{"auth":"$(echo -n "${REGISTRY_USER}:${REGISTRY_PASSWORD}" | base64)"}}}'
sshKey: |
  # Add your SSH public key here
additionalTrustBundle: |
  # Add your registry certificate here
imageContentSources:
- mirrors:
  - registry.${CLUSTER_NAME}.local:${REGISTRY_PORT}/openshift/release
  source: quay.io/openshift-release-dev/ocp-release
EOF

echo "" | tee -a "$LOG_FILE"
echo "✅ Simplified image synchronization completed successfully!" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "📁 Files created in: ${SYNC_DIR}" | tee -a "$LOG_FILE"
echo "   imageContentSources.yaml: Image content sources configuration" | tee -a "$LOG_FILE"
echo "   install-config-template.yaml: Install configuration template" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "🔗 Registry URL: registry.${CLUSTER_NAME}.local:${REGISTRY_PORT}" | tee -a "$LOG_FILE"
echo "📦 Synced repositories:" | tee -a "$LOG_FILE"
echo "   - OpenShift ${OPENSHIFT_VERSION} release images" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "📝 Next steps:" | tee -a "$LOG_FILE"
echo "1. Copy install-config-template.yaml and customize it" | tee -a "$LOG_FILE"
echo "2. Use the generated configuration for cluster installation" | tee -a "$LOG_FILE"
echo "3. Ensure registry certificate is added to additionalTrustBundle" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "📊 Verification:" | tee -a "$LOG_FILE"
echo "   curl -u ${REGISTRY_USER}:${REGISTRY_PASSWORD} http://localhost:${REGISTRY_PORT}/v2/_catalog" | tee -a "$LOG_FILE"
echo "   curl -u ${REGISTRY_USER}:${REGISTRY_PASSWORD} http://localhost:${REGISTRY_PORT}/v2/openshift/release/tags/list" | tee -a "$LOG_FILE" 