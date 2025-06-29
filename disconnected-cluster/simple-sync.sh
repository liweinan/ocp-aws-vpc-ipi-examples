#!/bin/bash

set -e

# Configuration
OPENSHIFT_VERSION=${1:-"4.15.0"}
CLUSTER_NAME=${2:-"fedora-disconnected-cluster"}
REGISTRY_PORT=${3:-"5000"}
REGISTRY_USER=${4:-"admin"}
REGISTRY_PASSWORD=${5:-"admin123"}

echo "🚀 Starting simplified OpenShift ${OPENSHIFT_VERSION} image sync..."
echo "   Cluster: ${CLUSTER_NAME}"
echo "   Registry: localhost:${REGISTRY_PORT}"
echo "   User: ${REGISTRY_USER}"
echo ""

# Create sync directory
SYNC_DIR="/home/ubuntu/openshift-sync"
mkdir -p "${SYNC_DIR}"
cd "${SYNC_DIR}"

# Test registry access
echo "🧪 Testing registry access..."
if ! curl -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" "http://localhost:${REGISTRY_PORT}/v2/_catalog" >/dev/null 2>&1; then
    echo "❌ Cannot access registry"
    echo "   Please ensure registry is running and accessible"
    exit 1
fi

# Login to registry
echo "🔐 Logging into registry..."
podman login --username "${REGISTRY_USER}" --password "${REGISTRY_PASSWORD}" --tls-verify=false "localhost:${REGISTRY_PORT}"

# Extract release images
echo "📦 Extracting release images..."
oc adm release extract --from=quay.io/openshift-release-dev/ocp-release:${OPENSHIFT_VERSION}-x86_64 --to=/tmp/release-images

# Get image references
echo "🔍 Getting image references..."

# Sync release image only
echo "🔄 Syncing release image..."
RELEASE_IMAGE="quay.io/openshift-release-dev/ocp-release:${OPENSHIFT_VERSION}-x86_64"
echo "   Pulling release image: $RELEASE_IMAGE"
podman pull "$RELEASE_IMAGE"
echo "   Tagging release image..."
podman tag "$RELEASE_IMAGE" localhost:${REGISTRY_PORT}/openshift/release:${OPENSHIFT_VERSION}
echo "   Pushing release image..."
podman push --tls-verify=false localhost:${REGISTRY_PORT}/openshift/release:${OPENSHIFT_VERSION}

# Also sync with digest
echo "🔄 Syncing release image with digest..."
RELEASE_DIGEST=$(oc adm release info "$RELEASE_IMAGE" --output=jsonpath='{.digest}')
echo "   Release digest: $RELEASE_DIGEST"
podman tag "$RELEASE_IMAGE" localhost:${REGISTRY_PORT}/openshift/release@${RELEASE_DIGEST}
podman push --tls-verify=false localhost:${REGISTRY_PORT}/openshift/release@${RELEASE_DIGEST}

echo "✅ Simplified sync completed!"
echo ""
echo "📊 Synced images:"
echo "   - openshift/release:${OPENSHIFT_VERSION}"
echo ""
echo "🔍 Registry catalog:"
curl -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" "http://localhost:${REGISTRY_PORT}/v2/_catalog" | jq . 