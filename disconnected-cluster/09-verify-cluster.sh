#!/bin/bash

# Cluster Verification Script for Disconnected OpenShift Cluster
# Verifies cluster functionality and mirror registry configuration

set -euo pipefail

# Default values
DEFAULT_CLUSTER_NAME="disconnected-cluster"
DEFAULT_INSTALL_DIR="./openshift-install"
DEFAULT_INFRA_OUTPUT_DIR="./infra-output"
DEFAULT_REGISTRY_PORT="5000"
DEFAULT_REGISTRY_USER="admin"
DEFAULT_REGISTRY_PASSWORD="admin123"
DEFAULT_TIMEOUT="300"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --cluster-name        Cluster name (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --install-dir         Installation directory (default: $DEFAULT_INSTALL_DIR)"
    echo "  --infra-output-dir    Infrastructure output directory (default: $DEFAULT_INFRA_OUTPUT_DIR)"
    echo "  --registry-port       Registry port (default: $DEFAULT_REGISTRY_PORT)"
    echo "  --registry-user       Registry username (default: $DEFAULT_REGISTRY_USER)"
    echo "  --registry-password   Registry password (default: $DEFAULT_REGISTRY_PASSWORD)"
    echo "  --timeout             Timeout for verification checks in seconds (default: $DEFAULT_TIMEOUT)"
    echo "  --skip-registry       Skip registry verification"
    echo "  --skip-operators      Skip operator verification"
    echo "  --help                Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --cluster-name my-cluster"
    echo "  $0 --timeout 600 --skip-registry"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    local missing_tools=()
    
    for tool in oc jq yq; do
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

# Function to check installation directory
check_install_directory() {
    local install_dir="$1"
    
    if [[ ! -d "$install_dir" ]]; then
        echo "❌ Installation directory not found: $install_dir"
        echo "Please ensure cluster installation is complete"
        exit 1
    fi
    
    if [[ ! -f "$install_dir/auth/kubeconfig" ]]; then
        echo "❌ kubeconfig not found in $install_dir/auth/"
        echo "Please ensure cluster installation is complete"
        exit 1
    fi
    
    echo "✅ Installation directory and kubeconfig found"
}

# Function to set up cluster access
setup_cluster_access() {
    local install_dir="$1"
    
    echo "🔧 Setting up cluster access..."
    
    # Set kubeconfig
    export KUBECONFIG="$install_dir/auth/kubeconfig"
    
    # Test cluster access
    if ! oc whoami >/dev/null 2>&1; then
        echo "❌ Cannot access cluster"
        echo "Please ensure cluster is running and kubeconfig is valid"
        exit 1
    fi
    
    echo "✅ Cluster access established"
}

# Function to verify cluster version
verify_cluster_version() {
    echo "📊 Verifying cluster version..."
    
    local cluster_version=$(oc get clusterversion version -o jsonpath='{.status.desired.version}')
    local cluster_status=$(oc get clusterversion version -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
    
    echo "   Version: $cluster_version"
    echo "   Status: $cluster_status"
    
    if [[ "$cluster_status" == "True" ]]; then
        echo "✅ Cluster version is available"
    else
        echo "⚠️  Cluster version is not available"
        echo "   This might be normal during initial installation"
    fi
}

# Function to verify cluster operators
verify_cluster_operators() {
    echo "🔧 Verifying cluster operators..."
    
    local total_operators=$(oc get clusteroperators --no-headers | wc -l)
    local available_operators=$(oc get clusteroperators --no-headers | grep -c "True.*True.*True" || echo "0")
    local degraded_operators=$(oc get clusteroperators --no-headers | grep -c "False" || echo "0")
    
    echo "   Total operators: $total_operators"
    echo "   Available operators: $available_operators"
    echo "   Degraded operators: $degraded_operators"
    
    if [[ "$degraded_operators" -eq 0 ]]; then
        echo "✅ All cluster operators are healthy"
    else
        echo "⚠️  Some cluster operators are degraded"
        echo "   Degraded operators:"
        oc get clusteroperators --no-headers | grep "False" || true
    fi
}

# Function to verify nodes
verify_nodes() {
    echo "🖥️  Verifying cluster nodes..."
    
    local total_nodes=$(oc get nodes --no-headers | wc -l)
    local ready_nodes=$(oc get nodes --no-headers | grep -c "Ready" || echo "0")
    local not_ready_nodes=$(oc get nodes --no-headers | grep -c "NotReady" || echo "0")
    
    echo "   Total nodes: $total_nodes"
    echo "   Ready nodes: $ready_nodes"
    echo "   Not ready nodes: $not_ready_nodes"
    
    if [[ "$not_ready_nodes" -eq 0 ]]; then
        echo "✅ All nodes are ready"
    else
        echo "⚠️  Some nodes are not ready"
        echo "   Not ready nodes:"
        oc get nodes --no-headers | grep "NotReady" || true
    fi
    
    # Show node details
    echo ""
    echo "📋 Node details:"
    oc get nodes -o wide
}

# Function to verify critical pods
verify_critical_pods() {
    echo "📦 Verifying critical pods..."
    
    local critical_namespaces=(
        "openshift-apiserver"
        "openshift-controller-manager"
        "openshift-scheduler"
        "openshift-authentication"
        "openshift-console"
        "openshift-image-registry"
    )
    
    for namespace in "${critical_namespaces[@]}"; do
        echo "   Checking namespace: $namespace"
        
        local total_pods=$(oc get pods -n "$namespace" --no-headers 2>/dev/null | wc -l || echo "0")
        local running_pods=$(oc get pods -n "$namespace" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        local failed_pods=$(oc get pods -n "$namespace" --no-headers 2>/dev/null | grep -c "Failed\|Error\|CrashLoopBackOff" || echo "0")
        
        echo "     Total pods: $total_pods"
        echo "     Running pods: $running_pods"
        echo "     Failed pods: $failed_pods"
        
        if [[ "$failed_pods" -gt 0 ]]; then
            echo "     Failed pods:"
            oc get pods -n "$namespace" --no-headers 2>/dev/null | grep "Failed\|Error\|CrashLoopBackOff" || true
        fi
    done
}

# Function to verify registry access
verify_registry_access() {
    local cluster_name="$1"
    local registry_port="$2"
    local registry_user="$3"
    local registry_password="$4"
    local infra_dir="$5"
    
    echo "🔗 Verifying registry access..."
    
    # Test registry access from cluster
    echo "   Testing registry access from cluster..."
    
    # Create a test pod to verify registry access
    local test_pod_name="registry-test-$(date +%s)"
    
    cat > /tmp/registry-test-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $test_pod_name
  namespace: default
spec:
  containers:
  - name: test
    image: registry.$cluster_name.local:$registry_port/openshift/ose-cli:latest
    command: ["/bin/sh", "-c", "echo 'Registry access test successful' && sleep 10"]
  restartPolicy: Never
EOF
    
    # Apply the test pod
    if oc apply -f /tmp/registry-test-pod.yaml >/dev/null 2>&1; then
        echo "   Test pod created successfully"
        
        # Wait for pod to be ready
        local timeout_counter=0
        while [[ $timeout_counter -lt 60 ]]; do
            local pod_status=$(oc get pod "$test_pod_name" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            if [[ "$pod_status" == "Running" ]]; then
                echo "   Registry access test successful"
                break
            elif [[ "$pod_status" == "Failed" ]]; then
                echo "   Registry access test failed"
                oc describe pod "$test_pod_name"
                break
            fi
            sleep 5
            ((timeout_counter += 5))
        done
        
        # Clean up test pod
        oc delete pod "$test_pod_name" >/dev/null 2>&1 || true
    else
        echo "   Failed to create test pod"
    fi
    
    # Test registry access from bastion
    if [[ -f "$infra_dir/bastion-public-ip" ]]; then
        local bastion_ip=$(cat "$infra_dir/bastion-public-ip")
        echo "   Testing registry access from bastion..."
        
        if curl -k -u "$registry_user:$registry_password" "https://registry.$cluster_name.local:$registry_port/v2/_catalog" >/dev/null 2>&1; then
            echo "   Registry access from bastion successful"
        else
            echo "   Registry access from bastion failed"
        fi
    fi
    
    # Clean up
    rm -f /tmp/registry-test-pod.yaml
}

# Function to verify image content sources
verify_image_content_sources() {
    echo "🖼️  Verifying image content sources..."
    
    local ics_count=$(oc get imagecontentsourcepolicy --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [[ "$ics_count" -gt 0 ]]; then
        echo "   Found $ics_count image content source policies:"
        oc get imagecontentsourcepolicy
        echo ""
        echo "   Image content source policy details:"
        oc get imagecontentsourcepolicy -o yaml
    else
        echo "   No image content source policies found"
        echo "   This might indicate the cluster is not properly configured for disconnected mode"
    fi
}

# Function to verify additional trust bundle
verify_additional_trust_bundle() {
    echo "🔒 Verifying additional trust bundle..."
    
    local trust_bundle=$(oc get configmap -n openshift-config additional-trust-bundle -o jsonpath='{.data.ca-bundle\.crt}' 2>/dev/null || echo "")
    
    if [[ -n "$trust_bundle" ]]; then
        echo "   Additional trust bundle is configured"
        echo "   Certificate count: $(echo "$trust_bundle" | grep -c "BEGIN CERTIFICATE" || echo "0")"
    else
        echo "   No additional trust bundle found"
        echo "   This might cause issues with registry access"
    fi
}

# Function to verify network connectivity
verify_network_connectivity() {
    echo "🌐 Verifying network connectivity..."
    
    # Test internal connectivity
    echo "   Testing internal connectivity..."
    
    # Create a test pod for network testing
    local test_pod_name="network-test-$(date +%s)"
    
    cat > /tmp/network-test-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $test_pod_name
  namespace: default
spec:
  containers:
  - name: test
    image: registry.$cluster_name.local:5000/openshift/ose-cli:latest
    command: ["/bin/sh", "-c", "ping -c 3 8.8.8.8 && echo 'External connectivity test'"]
  restartPolicy: Never
EOF
    
    # Apply the test pod
    if oc apply -f /tmp/network-test-pod.yaml >/dev/null 2>&1; then
        echo "   Network test pod created"
        
        # Wait for pod to complete
        local timeout_counter=0
        while [[ $timeout_counter -lt 60 ]]; do
            local pod_status=$(oc get pod "$test_pod_name" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            if [[ "$pod_status" == "Succeeded" ]]; then
                echo "   Network connectivity test successful"
                oc logs "$test_pod_name"
                break
            elif [[ "$pod_status" == "Failed" ]]; then
                echo "   Network connectivity test failed"
                oc logs "$test_pod_name"
                break
            fi
            sleep 5
            ((timeout_counter += 5))
        done
        
        # Clean up test pod
        oc delete pod "$test_pod_name" >/dev/null 2>&1 || true
    fi
    
    # Clean up
    rm -f /tmp/network-test-pod.yaml
}

# Function to verify storage
verify_storage() {
    echo "💾 Verifying storage..."
    
    # Check storage classes
    local storage_classes=$(oc get storageclass --no-headers | wc -l || echo "0")
    echo "   Storage classes: $storage_classes"
    
    if [[ "$storage_classes" -gt 0 ]]; then
        echo "   Available storage classes:"
        oc get storageclass
    fi
    
    # Check persistent volumes
    local pv_count=$(oc get pv --no-headers 2>/dev/null | wc -l || echo "0")
    echo "   Persistent volumes: $pv_count"
    
    # Check persistent volume claims
    local pvc_count=$(oc get pvc --all-namespaces --no-headers 2>/dev/null | wc -l || echo "0")
    echo "   Persistent volume claims: $pvc_count"
}

# Function to generate verification report
generate_verification_report() {
    local cluster_name="$1"
    local install_dir="$2"
    
    echo "📝 Generating verification report..."
    
    local report_file="cluster-verification-$cluster_name-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "OpenShift Cluster Verification Report"
        echo "====================================="
        echo "Cluster: $cluster_name"
        echo "Date: $(date)"
        echo "Kubeconfig: $install_dir/auth/kubeconfig"
        echo ""
        
        echo "Cluster Version:"
        oc get clusterversion version -o yaml
        echo ""
        
        echo "Cluster Operators:"
        oc get clusteroperators
        echo ""
        
        echo "Nodes:"
        oc get nodes -o wide
        echo ""
        
        echo "Critical Pods:"
        for ns in openshift-apiserver openshift-controller-manager openshift-scheduler openshift-authentication openshift-console openshift-image-registry; do
            echo "Namespace: $ns"
            oc get pods -n "$ns" 2>/dev/null || echo "Namespace not found or no access"
            echo ""
        done
        
        echo "Image Content Source Policies:"
        oc get imagecontentsourcepolicy -o yaml 2>/dev/null || echo "No policies found"
        echo ""
        
        echo "Storage Classes:"
        oc get storageclass
        echo ""
        
        echo "Network Policies:"
        oc get networkpolicy --all-namespaces 2>/dev/null || echo "No network policies found"
        echo ""
        
    } > "$report_file"
    
    echo "✅ Verification report saved to: $report_file"
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
            --install-dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            --infra-output-dir)
                INFRA_OUTPUT_DIR="$2"
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
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --skip-registry)
                SKIP_REGISTRY="yes"
                shift
                ;;
            --skip-operators)
                SKIP_OPERATORS="yes"
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
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}
    INFRA_OUTPUT_DIR=${INFRA_OUTPUT_DIR:-$DEFAULT_INFRA_OUTPUT_DIR}
    REGISTRY_PORT=${REGISTRY_PORT:-$DEFAULT_REGISTRY_PORT}
    REGISTRY_USER=${REGISTRY_USER:-$DEFAULT_REGISTRY_USER}
    REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-$DEFAULT_REGISTRY_PASSWORD}
    TIMEOUT=${TIMEOUT:-$DEFAULT_TIMEOUT}
    SKIP_REGISTRY=${SKIP_REGISTRY:-no}
    SKIP_OPERATORS=${SKIP_OPERATORS:-no}
    
    # Display script header
    echo "🔍 OpenShift Cluster Verification for Disconnected Environment"
    echo "============================================================="
    echo ""
    echo "📋 Configuration:"
    echo "   Cluster Name: $CLUSTER_NAME"
    echo "   Installation Directory: $INSTALL_DIR"
    echo "   Registry URL: registry.$CLUSTER_NAME.local:$REGISTRY_PORT"
    echo "   Timeout: $TIMEOUT seconds"
    echo "   Skip Registry: $SKIP_REGISTRY"
    echo "   Skip Operators: $SKIP_OPERATORS"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Check installation directory
    check_install_directory "$INSTALL_DIR"
    
    # Set up cluster access
    setup_cluster_access "$INSTALL_DIR"
    
    # Perform verification checks
    echo "🚀 Starting cluster verification..."
    echo ""
    
    # Verify cluster version
    verify_cluster_version
    echo ""
    
    # Verify cluster operators
    if [[ "$SKIP_OPERATORS" != "yes" ]]; then
        verify_cluster_operators
        echo ""
    fi
    
    # Verify nodes
    verify_nodes
    echo ""
    
    # Verify critical pods
    verify_critical_pods
    echo ""
    
    # Verify registry access
    if [[ "$SKIP_REGISTRY" != "yes" ]]; then
        verify_registry_access "$CLUSTER_NAME" "$REGISTRY_PORT" "$REGISTRY_USER" "$REGISTRY_PASSWORD" "$INFRA_OUTPUT_DIR"
        echo ""
    fi
    
    # Verify image content sources
    verify_image_content_sources
    echo ""
    
    # Verify additional trust bundle
    verify_additional_trust_bundle
    echo ""
    
    # Verify network connectivity
    verify_network_connectivity
    echo ""
    
    # Verify storage
    verify_storage
    echo ""
    
    # Generate verification report
    generate_verification_report "$CLUSTER_NAME" "$INSTALL_DIR"
    
    echo ""
    echo "✅ Cluster verification completed!"
    echo ""
    echo "📁 Verification report saved to: cluster-verification-$CLUSTER_NAME-*.txt"
    echo ""
    echo "🔧 Next steps:"
    echo "1. Review the verification report for any issues"
    echo "2. Address any failed or degraded components"
    echo "3. Test application deployment on the cluster"
    echo "4. Configure monitoring and logging if needed"
    echo ""
    echo "📝 Important notes:"
    echo "   - Some components may take time to become fully available"
    echo "   - Registry access tests require proper DNS configuration"
    echo "   - Network connectivity tests may fail in fully disconnected environments"
    echo "   - Storage verification depends on your AWS configuration"
}

# Run main function with all arguments
main "$@" 