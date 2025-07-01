#!/bin/bash

# Image Synchronization Script for Disconnected OpenShift Cluster
# Syncs essential OpenShift images from external registry to private mirror registry on bastion host

set -euo pipefail

# Default values
DEFAULT_CLUSTER_NAME="disconnected-cluster"
DEFAULT_INFRA_OUTPUT_DIR="./infra-output"
DEFAULT_OPENSHIFT_VERSION="4.18.15"
DEFAULT_REGISTRY_PORT="5000"
DEFAULT_REGISTRY_USER="admin"
DEFAULT_REGISTRY_PASSWORD="admin123"
DEFAULT_DRY_RUN="no"
DEFAULT_BASTION_KEY="./infra-output/bastion-key.pem"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --cluster-name        Cluster name (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --infra-output-dir    Infrastructure output directory (default: $DEFAULT_INFRA_OUTPUT_DIR)"
    echo "  --openshift-version   OpenShift version to sync (default: $DEFAULT_OPENSHIFT_VERSION)"
    echo "  --registry-port       Registry port (default: $DEFAULT_REGISTRY_PORT)"
    echo "  --registry-user       Registry username (default: $DEFAULT_REGISTRY_USER)"
    echo "  --registry-password   Registry password (default: $DEFAULT_REGISTRY_PASSWORD)"
    echo "  --dry-run             Show what would be synced without actually syncing"
    echo "  --bastion-key         SSH private key for bastion host (default: $DEFAULT_BASTION_KEY)"
    echo "  --help                Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --cluster-name my-disconnected-cluster --openshift-version 4.18.15"
    echo "  $0 --dry-run --openshift-version 4.19.0"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    local missing_tools=()
    
    for tool in ssh scp jq; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo "❌ Missing required tools: ${missing_tools[*]}"
        echo "Please install the missing tools and try again"
        exit 1
    fi
    
    echo "✅ All required tools are available"
}

# Function to check infrastructure
check_infrastructure() {
    local infra_dir="$1"
    
    if [[ ! -f "$infra_dir/bastion-public-ip" ]]; then
        echo "❌ Infrastructure files not found"
        echo "Please run 01-create-infrastructure.sh first"
        exit 1
    fi
    
    if [[ ! -f "$infra_dir/bastion-instance-id" ]]; then
        echo "❌ Bastion instance ID not found"
        echo "Please run 01-create-infrastructure.sh first"
        exit 1
    fi
    
    echo "✅ Infrastructure files found"
}

# Function to get bastion connection info
get_bastion_info() {
    local infra_dir="$1"
    
    BASTION_IP=$(cat "$infra_dir/bastion-public-ip")
    BASTION_INSTANCE_ID=$(cat "$infra_dir/bastion-instance-id")
    
    echo "📡 Bastion Host: $BASTION_IP"
    echo "🆔 Instance ID: $BASTION_INSTANCE_ID"
}

# Function to test bastion connectivity
test_bastion_connectivity() {
    local bastion_ip="$1"
    local bastion_key="$2"
    
    echo "🧪 Testing bastion host connectivity..."
    
    if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$bastion_key" ubuntu@"$bastion_ip" "echo 'Connection successful'" >/dev/null 2>&1; then
        echo "❌ Cannot connect to bastion host"
        echo "   Please ensure:"
        echo "   1. Bastion host is running"
        echo "   2. SSH key is properly configured"
        echo "   3. Security groups allow SSH access"
        echo "   4. You can connect manually: ssh -i $bastion_key ubuntu@$bastion_ip"
        return 1
    fi
    
    echo "✅ Bastion host connectivity confirmed"
}

# Function to check and fix registry status
check_and_fix_registry() {
    local bastion_ip="$1"
    local bastion_key="$2"
    local registry_port="$3"
    local registry_user="$4"
    local registry_password="$5"
    
    echo "🔍 Checking registry status..."
    
    # Check if registry container is running
    local registry_status=$(ssh -o StrictHostKeyChecking=no -i "$bastion_key" ubuntu@"$bastion_ip" "sudo podman ps --format 'table {{.Names}}\t{{.Status}}' | grep mirror-registry || echo 'NOT_FOUND'")
    
    if [[ "$registry_status" == "NOT_FOUND" ]] || [[ "$registry_status" == *"Exited"* ]]; then
        echo "⚠️  Registry container is not running, attempting to fix..."
        
        # Check if certificates exist
        local cert_status=$(ssh -o StrictHostKeyChecking=no -i "$bastion_key" ubuntu@"$bastion_ip" "sudo ls -la /opt/registry/certs/domain.crt 2>/dev/null || echo 'MISSING'")
        
        if [[ "$cert_status" == "MISSING" ]]; then
            echo "   Generating missing certificates..."
            ssh -o StrictHostKeyChecking=no -i "$bastion_key" ubuntu@"$bastion_ip" "cd /opt/registry/certs && sudo openssl x509 -req -in domain.csr -signkey domain.key -out domain.crt -days 365 -extensions v3_req -extfile openssl.conf"
        fi
        
        # Start registry container
        echo "   Starting registry container..."
        ssh -o StrictHostKeyChecking=no -i "$bastion_key" ubuntu@"$bastion_ip" "sudo podman rm -f mirror-registry 2>/dev/null || true && sudo podman run -d --name mirror-registry -p ${registry_port}:5000 -v /opt/registry/data:/var/lib/registry:z -v /opt/registry/auth:/auth:z -v /opt/registry/certs:/certs:z -e REGISTRY_AUTH=htpasswd -e REGISTRY_AUTH_HTPASSWD_REALM=Registry -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key --restart=always registry:2"
        
        # Wait for registry to start
        echo "   Waiting for registry to start..."
        sleep 10
    fi
    
    # Test registry access
    echo "🧪 Testing registry access..."
    if ! ssh -o StrictHostKeyChecking=no -i "$bastion_key" ubuntu@"$bastion_ip" "curl -k -u ${registry_user}:${registry_password} https://localhost:${registry_port}/v2/_catalog" >/dev/null 2>&1; then
        echo "❌ Registry is not accessible"
        echo "   Please check registry logs: ssh -i $bastion_key ubuntu@$bastion_ip 'sudo podman logs mirror-registry'"
        return 1
    fi
    
    echo "✅ Registry is running and accessible"
}

# Function to create sync script for bastion
create_bastion_sync_script() {
    local openshift_version="$1"
    local cluster_name="$2"
    local registry_port="$3"
    local registry_user="$4"
    local registry_password="$5"
    
    echo "📝 Creating sync script for bastion host..."
    
    cat > /tmp/sync-images-on-bastion.sh <<'EOF'
#!/bin/bash

# Image sync script to run on bastion host
set -euo pipefail

OPENSHIFT_VERSION="$1"
CLUSTER_NAME="$2"
REGISTRY_PORT="$3"
REGISTRY_USER="$4"
REGISTRY_PASSWORD="$5"
REGISTRY_URL="registry.${CLUSTER_NAME}.local:${REGISTRY_PORT}"

echo "🔄 Starting image synchronization on bastion host..."
echo "=================================================="
echo ""
echo "📋 Configuration:"
echo "   OpenShift Version: ${OPENSHIFT_VERSION}"
echo "   Registry URL: ${REGISTRY_URL}"
echo "   Registry User: ${REGISTRY_USER}"
echo ""

# Create sync directory
SYNC_DIR="/home/ubuntu/openshift-sync"
mkdir -p "${SYNC_DIR}"
cd "${SYNC_DIR}"

# Install required tools if not present
echo "🔧 Installing required tools..."
if ! command -v oc &> /dev/null; then
    echo "   Installing OpenShift CLI..."
    curl -L "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OPENSHIFT_VERSION}/openshift-client-linux.tar.gz" | tar xz
    sudo mv oc kubectl /usr/local/bin/
fi

if ! command -v podman &> /dev/null; then
    echo "   Installing Podman..."
    sudo dnf install -y podman
fi

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

# Create mirror directory
echo "📁 Creating mirror directory..."
mkdir -p mirror

# Sync OpenShift release images (core installation images)
echo "📦 Syncing OpenShift ${OPENSHIFT_VERSION} release images..."
echo "   This may take 20-40 minutes depending on your internet connection..."
echo ""

# Use simplified sync approach - only sync the release image
echo "🔄 Syncing release image..."
RELEASE_IMAGE="quay.io/openshift-release-dev/ocp-release:${OPENSHIFT_VERSION}-x86_64"
echo "   Pulling release image: $RELEASE_IMAGE"
podman pull "$RELEASE_IMAGE"
echo "   Tagging release image..."
podman tag "$RELEASE_IMAGE" localhost:${REGISTRY_PORT}/openshift/release:${OPENSHIFT_VERSION}
echo "   Pushing release image..."
podman push --tls-verify=false localhost:${REGISTRY_PORT}/openshift/release:${OPENSHIFT_VERSION}

# Also sync with digest for better compatibility
echo "🔄 Syncing release image with digest..."
RELEASE_DIGEST=$(oc adm release info "$RELEASE_IMAGE" --output=jsonpath='{.digest}' 2>/dev/null || echo "")
if [[ -n "$RELEASE_DIGEST" ]]; then
    echo "   Release digest: $RELEASE_DIGEST"
    podman tag "$RELEASE_IMAGE" localhost:${REGISTRY_PORT}/openshift/release@${RELEASE_DIGEST}
    podman push --tls-verify=false localhost:${REGISTRY_PORT}/openshift/release@${RELEASE_DIGEST} || echo "   Warning: Digest push failed (this is normal for some registries)"
fi

# Sync essential additional images
echo "📦 Syncing essential additional images..."

# Sync UBI images (commonly used base images)
echo "   Syncing UBI base images..."
oc image mirror \
    registry.redhat.io/ubi8/ubi:latest \
    ${REGISTRY_URL}/ubi8/ubi:latest \
    --insecure

oc image mirror \
    registry.redhat.io/ubi8/ubi-minimal:latest \
    ${REGISTRY_URL}/ubi8/ubi-minimal:latest \
    --insecure

oc image mirror \
    registry.redhat.io/ubi9/ubi:latest \
    ${REGISTRY_URL}/ubi9/ubi:latest \
    --insecure

oc image mirror \
    registry.redhat.io/ubi9/ubi-minimal:latest \
    ${REGISTRY_URL}/ubi9/ubi-minimal:latest \
    --insecure

# Sync essential operators (only the most commonly used ones)
echo "   Syncing essential operators..."

# Red Hat Operators - Core ones only
oc image mirror \
    registry.redhat.io/redhat/redhat-operator-index:v${OPENSHIFT_VERSION} \
    ${REGISTRY_URL}/redhat/redhat-operator-index:v${OPENSHIFT_VERSION} \
    --insecure

# Certified Operators - Core ones only  
oc image mirror \
    registry.redhat.io/redhat/certified-operator-index:v${OPENSHIFT_VERSION} \
    ${REGISTRY_URL}/redhat/certified-operator-index:v${OPENSHIFT_VERSION} \
    --insecure

# Community Operators - Core ones only
oc image mirror \
    registry.redhat.io/redhat/community-operator-index:v${OPENSHIFT_VERSION} \
    ${REGISTRY_URL}/redhat/community-operator-index:v${OPENSHIFT_VERSION} \
    --insecure

# Create imageContentSources configuration
echo "📝 Creating imageContentSources configuration..."
cat > imageContentSources.yaml <<'IMAGECONTENTEOF'
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
    
    [[registry]]
      prefix = ""
      location = "quay.io/openshift-release-dev/ocp-v4.0-art-dev"
      mirror-by-digest-only = true
      mirrors = ["registry.${CLUSTER_NAME}.local:${REGISTRY_PORT}/openshift/release"]
    
    [[registry]]
      prefix = ""
      location = "registry.redhat.io/ubi8"
      mirrors = ["registry.${CLUSTER_NAME}.local:${REGISTRY_PORT}/ubi8"]
    
    [[registry]]
      prefix = ""
      location = "registry.redhat.io/ubi9"
      mirrors = ["registry.${CLUSTER_NAME}.local:${REGISTRY_PORT}/ubi9"]
    
    [[registry]]
      prefix = ""
      location = "registry.redhat.io/redhat"
      mirrors = ["registry.${CLUSTER_NAME}.local:${REGISTRY_PORT}/redhat"]
IMAGECONTENTEOF

# Create install-config template
echo "📝 Creating install-config template..."
cat > install-config-template.yaml <<'INSTALLCONFIGEOF'
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
- mirrors:
  - registry.${CLUSTER_NAME}.local:${REGISTRY_PORT}/openshift/release
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
INSTALLCONFIGEOF

echo ""
echo "✅ Image synchronization completed successfully!"
echo ""
echo "📁 Files created in: ${SYNC_DIR}"
echo "   mirror/: Mirrored OpenShift release images"
echo "   imageContentSources.yaml: Image content sources configuration"
echo "   install-config-template.yaml: Install configuration template"
echo ""
echo "🔗 Registry URL: ${REGISTRY_URL}"
echo "📦 Synced repositories:"
echo "   - OpenShift ${OPENSHIFT_VERSION} release images"
echo "   - UBI base images (ubi8, ubi9)"
echo "   - Essential operator catalogs"
echo ""
echo "📝 Next steps:"
echo "1. Copy install-config-template.yaml and customize it"
echo "2. Use the generated configuration for cluster installation"
echo "3. Ensure registry certificate is added to additionalTrustBundle"
EOF

    chmod +x /tmp/sync-images-on-bastion.sh
    echo "✅ Sync script created"
}

# Function to copy script to bastion and execute
execute_sync_on_bastion() {
    local bastion_ip="$1"
    local openshift_version="$2"
    local cluster_name="$3"
    local registry_port="$4"
    local registry_user="$5"
    local registry_password="$6"
    local bastion_key="$7"
    
    echo "🚀 Copying sync script to bastion host..."
    scp -i "$bastion_key" -o StrictHostKeyChecking=no /tmp/sync-images-on-bastion.sh ubuntu@"$bastion_ip":/home/ubuntu/
    
    echo "🔄 Executing sync script on bastion host..."
    echo "   This process may take 30-60 minutes depending on your internet connection"
    echo "   and the number of images being synced."
    echo ""
    echo "📡 You can monitor progress by connecting to bastion:"
    echo "   ssh -i $bastion_key ubuntu@$bastion_ip"
    echo "   tail -f /home/ubuntu/openshift-sync/sync.log"
    echo ""
    
    # Execute the script on bastion host
    ssh -i "$bastion_key" -o StrictHostKeyChecking=no ubuntu@"$bastion_ip" "cd /home/ubuntu && ./sync-images-on-bastion.sh '$openshift_version' '$cluster_name' '$registry_port' '$registry_user' '$registry_password' 2>&1 | tee sync.log"
    
    echo ""
    echo "✅ Image synchronization completed on bastion host!"
}

# Function to create helper scripts
create_helper_scripts() {
    local cluster_name="$1"
    local infra_dir="$2"
    local bastion_ip="$3"
    local bastion_key="$4"
    
    echo "📝 Creating helper scripts..."
    
    # Create script to check sync status
    cat > check-sync-status.sh <<EOF
#!/bin/bash
# Check sync status on bastion host

BASTION_IP="$bastion_ip"
CLUSTER_NAME="$cluster_name"
BASTION_KEY="$bastion_key"

echo "🔍 Checking sync status on bastion host..."
ssh -i "$BASTION_KEY" -o StrictHostKeyChecking=no ubuntu@\$BASTION_IP "ls -la /home/ubuntu/openshift-sync/"

echo ""
echo "📊 Registry catalog:"
ssh -i "$BASTION_KEY" -o StrictHostKeyChecking=no ubuntu@\$BASTION_IP "curl -k -s -u admin:admin123 https://registry.\$CLUSTER_NAME.local:5000/v2/_catalog | jq ."
EOF

    # Create script to copy files from bastion
    cat > copy-from-bastion.sh <<EOF
#!/bin/bash
# Copy sync results from bastion host

BASTION_IP="$bastion_ip"
CLUSTER_NAME="$cluster_name"
BASTION_KEY="$bastion_key"

echo "📋 Copying files from bastion host..."
mkdir -p ./bastion-output

scp -i "$BASTION_KEY" -o StrictHostKeyChecking=no -r ubuntu@\$BASTION_IP:/home/ubuntu/openshift-sync/install-config-template.yaml ./bastion-output/
scp -i "$BASTION_KEY" -o StrictHostKeyChecking=no -r ubuntu@\$BASTION_IP:/home/ubuntu/openshift-sync/imageContentSources.yaml ./bastion-output/

echo "✅ Files copied to ./bastion-output/"
echo "   - install-config-template.yaml"
echo "   - imageContentSources.yaml"
EOF

    chmod +x check-sync-status.sh copy-from-bastion.sh
    
    echo "✅ Helper scripts created:"
    echo "   - check-sync-status.sh: Check sync status on bastion"
    echo "   - copy-from-bastion.sh: Copy files from bastion"
}

# Main execution
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --infra-output-dir)
                INFRA_OUTPUT_DIR="$2"
                shift 2
                ;;
            --openshift-version)
                OPENSHIFT_VERSION="$2"
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
            --dry-run)
                DRY_RUN="yes"
                shift
                ;;
            --bastion-key)
                BASTION_KEY="$2"
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
    
    # Set default values
    CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
    INFRA_OUTPUT_DIR=${INFRA_OUTPUT_DIR:-$DEFAULT_INFRA_OUTPUT_DIR}
    OPENSHIFT_VERSION=${OPENSHIFT_VERSION:-$DEFAULT_OPENSHIFT_VERSION}
    REGISTRY_PORT=${REGISTRY_PORT:-$DEFAULT_REGISTRY_PORT}
    REGISTRY_USER=${REGISTRY_USER:-$DEFAULT_REGISTRY_USER}
    REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-$DEFAULT_REGISTRY_PASSWORD}
    DRY_RUN=${DRY_RUN:-$DEFAULT_DRY_RUN}
    BASTION_KEY=${BASTION_KEY:-$DEFAULT_BASTION_KEY}
    
    # Display script header
    echo "🔄 Image Synchronization for Disconnected OpenShift Cluster"
    echo "=========================================================="
    echo ""
    echo "📋 Configuration:"
    echo "   Cluster Name: $CLUSTER_NAME"
    echo "   OpenShift Version: $OPENSHIFT_VERSION"
    echo "   Registry URL: registry.$CLUSTER_NAME.local:$REGISTRY_PORT"
    echo "   Registry User: $REGISTRY_USER"
    echo "   Dry Run: $DRY_RUN"
    echo ""
    
    if [[ "$DRY_RUN" == "yes" ]]; then
        echo "🔍 DRY RUN MODE - No images will be synced"
        echo ""
        echo "Would sync on bastion host:"
        echo "  - OpenShift $OPENSHIFT_VERSION release images (core installation)"
        echo "  - UBI base images (ubi8, ubi9)"
        echo "  - Essential operator catalogs (Red Hat, Certified, Community)"
        echo "  - Create imageContentSources configuration"
        echo "  - Generate install-config template"
        echo ""
        echo "Estimated time: 30-60 minutes"
        echo "Estimated storage: 20-40 GB"
        echo ""
        echo "To actually sync images, run without --dry-run"
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Check infrastructure
    check_infrastructure "$INFRA_OUTPUT_DIR"
    
    # Get bastion info
    get_bastion_info "$INFRA_OUTPUT_DIR"
    
    # Test bastion connectivity
    test_bastion_connectivity "$BASTION_IP" "$BASTION_KEY"
    
    # Check and fix registry status
    check_and_fix_registry "$BASTION_IP" "$BASTION_KEY" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"
    
    # Create sync script for bastion
    create_bastion_sync_script "$OPENSHIFT_VERSION" "$CLUSTER_NAME" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"
    
    # Execute sync on bastion
    execute_sync_on_bastion "$BASTION_IP" "$OPENSHIFT_VERSION" "$CLUSTER_NAME" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD" "$BASTION_KEY"
    
    # Create helper scripts
    create_helper_scripts "$CLUSTER_NAME" "$INFRA_OUTPUT_DIR" "$BASTION_IP" "$BASTION_KEY"
    
    echo ""
    echo "✅ Image synchronization completed successfully!"
    echo ""
    echo "📁 Files created on bastion host: /home/ubuntu/openshift-sync/"
    echo "   mirror/: Mirrored OpenShift release images"
    echo "   imageContentSources.yaml: Image content sources configuration"
    echo "   install-config-template.yaml: Install configuration template"
    echo ""
    echo "🔗 Registry URL: registry.$CLUSTER_NAME.local:$REGISTRY_PORT"
    echo "📦 Synced repositories:"
    echo "   - OpenShift $OPENSHIFT_VERSION release images (core installation)"
    echo "   - UBI base images (ubi8, ubi9)"
    echo "   - Essential operator catalogs"
    echo ""
    echo "📝 Next steps:"
    echo "1. Run: ./check-sync-status.sh (to verify sync status)"
    echo "2. Run: ./copy-from-bastion.sh (to copy config files)"
    echo "3. Customize install-config-template.yaml with your specific values"
    echo "4. Run: ./04-prepare-install-config.sh --cluster-name $CLUSTER_NAME"
    echo ""
    echo "📝 Important notes:"
    echo "   - All images are now available in the private registry"
    echo "   - The registry certificate needs to be added to additionalTrustBundle"
    echo "   - Cluster nodes will pull images from the private registry"
    echo "   - Bastion host has all required images for disconnected installation"
}

# Run main function with all arguments
main "$@" 