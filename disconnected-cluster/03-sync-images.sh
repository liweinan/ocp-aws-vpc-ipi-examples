#!/bin/bash

# Image Synchronization Script for Disconnected OpenShift Cluster
# Syncs OpenShift images from external registry to private mirror registry

set -euo pipefail

# Default values
DEFAULT_CLUSTER_NAME="disconnected-cluster"
DEFAULT_INFRA_OUTPUT_DIR="./infra-output"
DEFAULT_OPENSHIFT_VERSION="4.18.15"
DEFAULT_REGISTRY_PORT="5000"
DEFAULT_REGISTRY_USER="admin"
DEFAULT_REGISTRY_PASSWORD="admin123"
DEFAULT_SYNC_DIR="./sync-output"
DEFAULT_DRY_RUN="no"

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
    echo "  --sync-dir            Sync output directory (default: $DEFAULT_SYNC_DIR)"
    echo "  --dry-run             Show what would be synced without actually syncing"
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
    
    for tool in oc podman jq yq; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo "❌ Missing required tools: ${missing_tools[*]}"
        echo "Please install the missing tools and try again"
        echo ""
        echo "Installation commands:"
        echo "  # Install OpenShift CLI"
        echo "  curl -L https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz | tar xz"
        echo "  sudo mv oc kubectl /usr/local/bin/"
        echo ""
        echo "  # Install Podman"
        echo "  sudo dnf install -y podman"
        echo ""
        echo "  # Install jq and yq"
        echo "  sudo dnf install -y jq yq"
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
    
    echo "✅ Infrastructure files found"
}

# Function to test registry access
test_registry_access() {
    local cluster_name="$1"
    local registry_port="$2"
    local registry_user="$3"
    local registry_password="$4"
    
    echo "🧪 Testing registry access..."
    
    # Test HTTPS access
    if curl -k -u "$registry_user:$registry_password" "https://registry.$cluster_name.local:$registry_port/v2/_catalog" >/dev/null 2>&1; then
        echo "✅ Registry HTTPS access working"
    else
        echo "❌ Registry HTTPS access failed"
        echo "   Please ensure:"
        echo "   1. Registry is running on bastion host"
        echo "   2. Hosts entry is added: $(cat $DEFAULT_INFRA_OUTPUT_DIR/bastion-public-ip) registry.$cluster_name.local"
        echo "   3. Registry credentials are correct"
        return 1
    fi
    
    # Test Docker/Podman login
    if podman login --username "$registry_user" --password "$registry_password" --tls-verify=false "registry.$cluster_name.local:$registry_port" >/dev/null 2>&1; then
        echo "✅ Registry Docker/Podman access working"
    else
        echo "❌ Registry Docker/Podman access failed"
        return 1
    fi
}

# Function to download OpenShift installer
download_openshift_installer() {
    local openshift_version="$1"
    local sync_dir="$2"
    
    echo "📥 Downloading OpenShift installer version $openshift_version..."
    
    mkdir -p "$sync_dir"
    cd "$sync_dir"
    
    # Download installer
    if [[ ! -f "openshift-install" ]]; then
        echo "   Downloading openshift-install..."
        wget -q "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$openshift_version/openshift-install-linux.tar.gz"
        tar xzf openshift-install-linux.tar.gz
        chmod +x openshift-install
        rm openshift-install-linux.tar.gz
    else
        echo "   OpenShift installer already exists"
    fi
    
    # Download oc client
    if [[ ! -f "oc" ]]; then
        echo "   Downloading oc client..."
        wget -q "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$openshift_version/openshift-client-linux.tar.gz"
        tar xzf openshift-client-linux.tar.gz
        chmod +x oc kubectl
        rm openshift-client-linux.tar.gz
    else
        echo "   OpenShift client already exists"
    fi
    
    cd - > /dev/null
    
    echo "✅ OpenShift tools downloaded"
}

# Function to create mirror configuration
create_mirror_config() {
    local openshift_version="$1"
    local cluster_name="$2"
    local registry_port="$3"
    local sync_dir="$4"
    
    echo "📝 Creating mirror configuration..."
    
    cd "$sync_dir"
    
    # Create imageset-config.yaml
    cat > imageset-config.yaml <<EOF
apiVersion: mirror.openshift.io/v1alpha2
kind: ImageSetConfiguration
metadata:
  name: openshift-$openshift_version
mirror:
  platform:
    channels:
    - name: stable-$openshift_version
      type: ocp
  additionalImages:
  - name: registry.redhat.io/ubi8/ubi:latest
  - name: registry.redhat.io/ubi8/ubi-minimal:latest
  - name: registry.redhat.io/ubi9/ubi:latest
  - name: registry.redhat.io/ubi9/ubi-minimal:latest
  operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v$openshift_version
    packages:
    - name: advanced-cluster-management
    - name: multicluster-engine
    - name: local-storage-operator
    - name: openshift-gitops-operator
    - name: openshift-pipelines-operator-rh
    - name: quay-operator
    - name: red-hat-camel-k
    - name: red-hat-openstack
    - name: red-hat-codeready-workspaces
    - name: eclipse-che
    - name: amq-streams
    - name: amq7-interconnect-operator
    - name: apicurio-registry
    - name: 3scale-operator
    - name: apicurito
    - name: fuse
    - name: jboss-datagrid-8-operator
    - name: jboss-datavirt-8-operator
    - name: jboss-eap-8-operator
    - name: jboss-fuse-8-operator
    - name: jboss-webserver-5-operator
    - name: jboss-amq-7-operator
    - name: cluster-logging
    - name: elasticsearch-operator
    - name: jaeger-product
    - name: kiali-ossm
    - name: servicemeshoperator
    - name: grafana-operator
    - name: prometheus
    - name: node-problem-detector
    - name: nfd
    - name: ptp-operator
    - name: sriov-network-operator
    - name: cluster-baremetal-operator
    - name: metallb-operator
    - name: bare-metal-event-relay
    - name: lvms-operator
    - name: ocs-operator
    - name: odf-operator
    - name: odf-lvm-operator
    - name: odf-multicluster-orchestrator
    - name: odf-operator-ibm
    - name: mcg-operator
    - name: noobaa-operator
    - name: openshift-container-storage
    - name: container-security-operator
    - name: compliance-operator
    - name: gatekeeper-operator
    - name: oauth-proxy
    - name: cert-manager
    - name: cluster-autoscaler
    - name: cluster-logging
    - name: elasticsearch-operator
    - name: file-integrity-operator
    - name: insights-operator
    - name: local-storage-operator
    - name: machine-api-operator
    - name: marketplace-operator
    - name: node-tuning-operator
    - name: openshift-apiserver
    - name: openshift-controller-manager
    - name: openshift-samples
    - name: operator-lifecycle-manager
    - name: operator-lifecycle-manager-catalog
    - name: operator-lifecycle-manager-packageserver
    - name: service-ca-operator
    - name: special-resource-operator
    - name: windows-machine-config-operator
  - catalog: registry.redhat.io/redhat/certified-operator-index:v$openshift_version
    packages:
    - name: isv-operator
    - name: mongodb-enterprise
    - name: postgresql
    - name: redis-enterprise
    - name: vault
    - name: etcd
    - name: cockroachdb
    - name: cass-operator
    - name: crunchy-postgresql-operator
    - name: influxdb-operator
    - name: mariadb-enterprise
    - name: mysql-enterprise
    - name: nginx-ingress-operator
    - name: hazelcast-enterprise
    - name: rabbitmq-cluster-operator
    - name: redis-enterprise-operator
    - name: scylladb
    - name: solr-operator
    - name: spark-operator
    - name: strimzi-kafka-operator
    - name: tensorflow-operator
    - name: tensorflow-serving
    - name: kubeflow
    - name: argo
    - name: tektoncd-operator
    - name: gitlab-operator-kubernetes
    - name: gitlab-runner-operator
    - name: jenkins-operator
    - name: jfrog-artifactory-oss-operator
    - name: nexus-operator
    - name: sonarqube-operator
    - name: grafana-operator
    - name: prometheus-operator
    - name: elasticsearch-operator
    - name: fluentd-operator
    - name: jaeger-operator
    - name: kiali-operator
    - name: istio-operator
    - name: linkerd-operator
    - name: contour-operator
    - name: traefik-operator
    - name: nginx-ingress-operator
    - name: haproxy-ingress-operator
    - name: cert-manager
    - name: external-dns-operator
    - name: cluster-autoscaler
    - name: descheduler-operator
    - name: kubevirt-hyperconverged
    - name: node-problem-detector
    - name: nfd-operator
    - name: ptp-operator
    - name: sriov-network-operator
    - name: cluster-baremetal-operator
    - name: metallb-operator
    - name: bare-metal-event-relay
    - name: lvms-operator
    - name: ocs-operator
    - name: odf-operator
    - name: odf-lvm-operator
    - name: odf-multicluster-orchestrator
    - name: odf-operator-ibm
    - name: mcg-operator
    - name: noobaa-operator
    - name: openshift-container-storage
    - name: container-security-operator
    - name: compliance-operator
    - name: gatekeeper-operator
    - name: oauth-proxy
    - name: cert-manager
    - name: cluster-autoscaler
    - name: cluster-logging
    - name: elasticsearch-operator
    - name: file-integrity-operator
    - name: insights-operator
    - name: local-storage-operator
    - name: machine-api-operator
    - name: marketplace-operator
    - name: node-tuning-operator
    - name: openshift-apiserver
    - name: openshift-controller-manager
    - name: openshift-samples
    - name: operator-lifecycle-manager
    - name: operator-lifecycle-manager-catalog
    - name: operator-lifecycle-manager-packageserver
    - name: service-ca-operator
    - name: special-resource-operator
    - name: windows-machine-config-operator
  - catalog: registry.redhat.io/redhat/community-operator-index:v$openshift_version
    packages:
    - name: prometheus-operator
    - name: grafana-operator
    - name: elasticsearch-operator
    - name: fluentd-operator
    - name: jaeger-operator
    - name: kiali-operator
    - name: istio-operator
    - name: linkerd-operator
    - name: contour-operator
    - name: traefik-operator
    - name: nginx-ingress-operator
    - name: haproxy-ingress-operator
    - name: cert-manager
    - name: external-dns-operator
    - name: cluster-autoscaler
    - name: descheduler-operator
    - name: kubevirt-hyperconverged
    - name: node-problem-detector
    - name: nfd-operator
    - name: ptp-operator
    - name: sriov-network-operator
    - name: cluster-baremetal-operator
    - name: metallb-operator
    - name: bare-metal-event-relay
    - name: lvms-operator
    - name: ocs-operator
    - name: odf-operator
    - name: odf-lvm-operator
    - name: odf-multicluster-orchestrator
    - name: odf-operator-ibm
    - name: mcg-operator
    - name: noobaa-operator
    - name: openshift-container-storage
    - name: container-security-operator
    - name: compliance-operator
    - name: gatekeeper-operator
    - name: oauth-proxy
    - name: cert-manager
    - name: cluster-autoscaler
    - name: cluster-logging
    - name: elasticsearch-operator
    - name: file-integrity-operator
    - name: insights-operator
    - name: local-storage-operator
    - name: machine-api-operator
    - name: marketplace-operator
    - name: node-tuning-operator
    - name: openshift-apiserver
    - name: openshift-controller-manager
    - name: openshift-samples
    - name: operator-lifecycle-manager
    - name: operator-lifecycle-manager-catalog
    - name: operator-lifecycle-manager-packageserver
    - name: service-ca-operator
    - name: special-resource-operator
    - name: windows-machine-config-operator
storageConfig:
  local:
    path: ./mirror
EOF
    
    # Create mirror-to-registry.sh script
    cat > mirror-to-registry.sh <<EOF
#!/bin/bash
# Mirror OpenShift images to private registry

set -euo pipefail

REGISTRY_URL="registry.$cluster_name.local:$registry_port"
REGISTRY_USER="$DEFAULT_REGISTRY_USER"
REGISTRY_PASSWORD="$DEFAULT_REGISTRY_PASSWORD"

echo "🚀 Starting image mirroring to $REGISTRY_URL"
echo "============================================="
echo ""

# Login to registry
echo "🔐 Logging into registry..."
podman login --username "\$REGISTRY_USER" --password "\$REGISTRY_PASSWORD" --tls-verify=false "\$REGISTRY_URL"

# Create mirror
echo "📦 Creating mirror..."
./oc adm release mirror \\
    --from=quay.io/openshift-release-dev/ocp-release:$openshift_version-x86_64 \\
    --to-dir=./mirror \\
    --to=\$REGISTRY_URL/openshift/release

echo ""
echo "✅ Mirror creation completed!"
echo ""
echo "📁 Mirror files created in: ./mirror"
echo "🔗 Registry URL: \$REGISTRY_URL"
echo ""
echo "📝 Next steps:"
echo "1. Copy mirror files to disconnected environment"
echo "2. Run: ./oc adm release mirror --from-dir=./mirror --to=\$REGISTRY_URL/openshift/release"
echo "3. Use the generated install-config.yaml for cluster installation"
EOF
    
    chmod +x mirror-to-registry.sh
    
    cd - > /dev/null
    
    echo "✅ Mirror configuration created"
}

# Function to perform image mirroring
perform_mirroring() {
    local openshift_version="$1"
    local cluster_name="$2"
    local registry_port="$3"
    local registry_user="$4"
    local registry_password="$5"
    local sync_dir="$6"
    
    echo "🔄 Starting image mirroring process..."
    echo "   This process may take 30-60 minutes depending on your internet connection"
    echo "   and the number of images being mirrored."
    echo ""
    
    cd "$sync_dir"
    
    # Login to registry
    echo "🔐 Logging into registry..."
    ./oc registry login --registry="registry.$cluster_name.local:$registry_port" --auth-basic="$registry_user:$registry_password" --insecure
    
    # Create mirror
    echo "📦 Creating mirror..."
    echo "   This will download all required OpenShift images..."
    echo ""
    
    ./oc adm release mirror \
        --from=quay.io/openshift-release-dev/ocp-release:$openshift_version-x86_64 \
        --to-dir=./mirror \
        --to=registry.$cluster_name.local:$registry_port/openshift/release \
        --insecure
    
    cd - > /dev/null
    
    echo "✅ Image mirroring completed!"
}

# Function to create install-config template
create_install_config_template() {
    local cluster_name="$1"
    local registry_port="$2"
    local sync_dir="$3"
    
    echo "📝 Creating install-config template..."
    
    cd "$sync_dir"
    
    # Create install-config template
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
  name: $cluster_name
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
pullSecret: '{"auths":{"registry.$cluster_name.local:$registry_port":{"auth":"$(echo -n "$DEFAULT_REGISTRY_USER:$DEFAULT_REGISTRY_PASSWORD" | base64)"}}}'
sshKey: |
  # Add your SSH public key here
additionalTrustBundle: |
  # Add your registry certificate here
imageContentSources:
- mirrors:
  - registry.$cluster_name.local:$registry_port/openshift/release
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - registry.$cluster_name.local:$registry_port/openshift/release
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
EOF
    
    cd - > /dev/null
    
    echo "✅ Install-config template created"
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
            --sync-dir)
                SYNC_DIR="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="yes"
                shift
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
    SYNC_DIR=${SYNC_DIR:-$DEFAULT_SYNC_DIR}
    DRY_RUN=${DRY_RUN:-$DEFAULT_DRY_RUN}
    
    # Display script header
    echo "🔄 Image Synchronization for Disconnected OpenShift Cluster"
    echo "=========================================================="
    echo ""
    echo "📋 Configuration:"
    echo "   Cluster Name: $CLUSTER_NAME"
    echo "   OpenShift Version: $OPENSHIFT_VERSION"
    echo "   Registry URL: registry.$CLUSTER_NAME.local:$REGISTRY_PORT"
    echo "   Registry User: $REGISTRY_USER"
    echo "   Sync Directory: $SYNC_DIR"
    echo "   Dry Run: $DRY_RUN"
    echo ""
    
    if [[ "$DRY_RUN" == "yes" ]]; then
        echo "🔍 DRY RUN MODE - No images will be synced"
        echo ""
        echo "Would sync:"
        echo "  - OpenShift $OPENSHIFT_VERSION release images"
        echo "  - Additional images (UBI, operators, etc.)"
        echo "  - Create mirror configuration"
        echo "  - Generate install-config template"
        echo ""
        echo "Estimated time: 30-60 minutes"
        echo "Estimated storage: 50-100 GB"
        echo ""
        echo "To actually sync images, run without --dry-run"
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Check infrastructure
    check_infrastructure "$INFRA_OUTPUT_DIR"
    
    # Test registry access
    test_registry_access "$CLUSTER_NAME" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD"
    
    # Download OpenShift installer
    download_openshift_installer "$OPENSHIFT_VERSION" "$SYNC_DIR"
    
    # Create mirror configuration
    create_mirror_config "$OPENSHIFT_VERSION" "$CLUSTER_NAME" "$REGISTRY_PORT" "$SYNC_DIR"
    
    # Perform mirroring
    perform_mirroring "$OPENSHIFT_VERSION" "$CLUSTER_NAME" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD" "$SYNC_DIR"
    
    # Create install-config template
    create_install_config_template "$CLUSTER_NAME" "$REGISTRY_PORT" "$SYNC_DIR"
    
    echo ""
    echo "✅ Image synchronization completed successfully!"
    echo ""
    echo "📁 Files created in: $SYNC_DIR"
    echo "   mirror/: Mirrored images"
    echo "   install-config-template.yaml: Install configuration template"
    echo "   mirror-to-registry.sh: Mirror script for disconnected environment"
    echo ""
    echo "🔗 Next steps:"
    echo "1. Copy the $SYNC_DIR directory to your disconnected environment"
    echo "2. Run: ./04-prepare-install-config.sh --cluster-name $CLUSTER_NAME"
    echo "3. Use the generated install-config.yaml for cluster installation"
    echo ""
    echo "📝 Important notes:"
    echo "   - The mirror directory contains all required OpenShift images"
    echo "   - The install-config-template.yaml needs to be customized with your specific values"
    echo "   - Ensure sufficient storage space in your disconnected environment"
    echo "   - The registry certificate needs to be added to the additionalTrustBundle"
}

# Run main function with all arguments
main "$@" 