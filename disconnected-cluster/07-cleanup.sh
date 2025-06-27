#!/bin/bash

# Cleanup Script for Disconnected OpenShift Cluster
# Cleans up temporary files and resources created during installation

set -euo pipefail

# Default values
DEFAULT_CLUSTER_NAME="disconnected-cluster"
DEFAULT_INSTALL_DIR="./openshift-install"
DEFAULT_INFRA_OUTPUT_DIR="./infra-output"
DEFAULT_SYNC_OUTPUT_DIR="./sync-output"
DEFAULT_CLEANUP_LEVEL="files"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --cluster-name        Cluster name (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --install-dir         Installation directory (default: $DEFAULT_INSTALL_DIR)"
    echo "  --infra-output-dir    Infrastructure output directory (default: $DEFAULT_INFRA_OUTPUT_DIR)"
    echo "  --sync-output-dir     Sync output directory (default: $DEFAULT_SYNC_OUTPUT_DIR)"
    echo "  --cleanup-level       Cleanup level: files, cluster, all (default: $DEFAULT_CLEANUP_LEVEL)"
    echo "  --force               Skip confirmation prompts"
    echo "  --dry-run             Show what would be cleaned without actually cleaning"
    echo "  --help                Display this help message"
    echo ""
    echo "Cleanup levels:"
    echo "  files:    Clean up temporary files and logs only"
    echo "  cluster:  Clean up cluster and temporary files"
    echo "  all:      Clean up everything including infrastructure"
    echo ""
    echo "Examples:"
    echo "  $0 --cluster-name my-cluster --cleanup-level files"
    echo "  $0 --cleanup-level all --force"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    local missing_tools=()
    
    for tool in aws jq yq; do
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

# Function to clean up temporary files
cleanup_temp_files() {
    local cluster_name="$1"
    local install_dir="$2"
    local sync_dir="$3"
    
    echo "🧹 Cleaning up temporary files..."
    
    # Clean up temporary files
    local temp_files=(
        "registry-config-$cluster_name.yaml"
        "cluster-info-$cluster_name.yaml"
        "cluster-verification-$cluster_name-*.txt"
        "install-config-$cluster_name-backup-*.yaml"
        "/tmp/registry-test-pod.yaml"
        "/tmp/network-test-pod.yaml"
    )
    
    for pattern in "${temp_files[@]}"; do
        for file in $pattern; do
            if [[ -f "$file" ]]; then
                echo "   Removing: $file"
                rm -f "$file"
            fi
        done
    done
    
    # Clean up logs
    if [[ -d "$install_dir" ]]; then
        local log_files=(
            "$install_dir/install-*.log"
            "$install_dir/.openshift_install.log"
            "$install_dir/.openshift_install_state.json"
        )
        
        for pattern in "${log_files[@]}"; do
            for file in $pattern; do
                if [[ -f "$file" ]]; then
                    echo "   Removing: $file"
                    rm -f "$file"
                fi
            done
        done
    fi
    
    # Clean up sync directory (keep mirror files)
    if [[ -d "$sync_dir" ]]; then
        local sync_temp_files=(
            "$sync_dir/openshift-install-linux.tar.gz"
            "$sync_dir/openshift-client-linux.tar.gz"
            "$sync_dir/mirror-to-registry.sh"
        )
        
        for file in "${sync_temp_files[@]}"; do
            if [[ -f "$file" ]]; then
                echo "   Removing: $file"
                rm -f "$file"
            fi
        done
    fi
    
    echo "✅ Temporary files cleaned up"
}

# Function to clean up cluster
cleanup_cluster() {
    local cluster_name="$1"
    local install_dir="$2"
    local force="$3"
    
    echo "🗑️  Cleaning up OpenShift cluster..."
    
    if [[ ! -d "$install_dir" ]]; then
        echo "⚠️  Installation directory not found: $install_dir"
        echo "   Skipping cluster cleanup"
        return
    fi
    
    if [[ ! -f "$install_dir/install-config.yaml" ]]; then
        echo "⚠️  install-config.yaml not found in $install_dir"
        echo "   Skipping cluster cleanup"
        return
    fi
    
    if [[ ! -f "$install_dir/openshift-install" ]]; then
        echo "⚠️  openshift-install not found in $install_dir"
        echo "   Skipping cluster cleanup"
        return
    fi
    
    # Confirm cluster deletion
    if [[ "$force" != "yes" ]]; then
        echo "⚠️  This will permanently delete the OpenShift cluster: $cluster_name"
        echo "   All cluster data and applications will be lost!"
        echo ""
        read -p "Are you sure you want to delete the cluster? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Cluster deletion cancelled"
            return
        fi
    fi
    
    echo "🔄 Deleting cluster..."
    cd "$install_dir"
    
    if ./openshift-install destroy cluster --log-level=info; then
        echo "✅ Cluster deleted successfully"
    else
        echo "❌ Cluster deletion failed"
        echo "   You may need to manually clean up AWS resources"
    fi
    
    cd - > /dev/null
}

# Function to clean up infrastructure
cleanup_infrastructure() {
    local cluster_name="$1"
    local infra_dir="$2"
    local force="$3"
    
    echo "🏗️  Cleaning up infrastructure..."
    
    if [[ ! -d "$infra_dir" ]]; then
        echo "⚠️  Infrastructure directory not found: $infra_dir"
        echo "   Skipping infrastructure cleanup"
        return
    fi
    
    # Confirm infrastructure deletion
    if [[ "$force" != "yes" ]]; then
        echo "⚠️  This will permanently delete all infrastructure for cluster: $cluster_name"
        echo "   This includes VPC, subnets, security groups, bastion host, and all associated resources!"
        echo ""
        read -p "Are you sure you want to delete the infrastructure? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Infrastructure deletion cancelled"
            return
        fi
    fi
    
    # Get infrastructure information
    if [[ ! -f "$infra_dir/vpc-id" ]]; then
        echo "❌ VPC ID not found in $infra_dir"
        echo "   Cannot proceed with infrastructure cleanup"
        return
    fi
    
    local vpc_id=$(cat "$infra_dir/vpc-id")
    local region=$(cat "$infra_dir/region")
    
    echo "🔄 Deleting infrastructure in region: $region"
    
    # Delete bastion host
    if [[ -f "$infra_dir/bastion-instance-id" ]]; then
        local bastion_id=$(cat "$infra_dir/bastion-instance-id")
        echo "   Deleting bastion host: $bastion_id"
        aws ec2 terminate-instances --instance-ids "$bastion_id" --region "$region" >/dev/null 2>&1 || true
    fi
    
    # Delete bastion security group
    if [[ -f "$infra_dir/bastion-security-group-id" ]]; then
        local bastion_sg_id=$(cat "$infra_dir/bastion-security-group-id")
        echo "   Deleting bastion security group: $bastion_sg_id"
        aws ec2 delete-security-group --group-id "$bastion_sg_id" --region "$region" >/dev/null 2>&1 || true
    fi
    
    # Delete cluster security group
    if [[ -f "$infra_dir/cluster-security-group-id" ]]; then
        local cluster_sg_id=$(cat "$infra_dir/cluster-security-group-id")
        echo "   Deleting cluster security group: $cluster_sg_id"
        aws ec2 delete-security-group --group-id "$cluster_sg_id" --region "$region" >/dev/null 2>&1 || true
    fi
    
    # Delete SSH key pair
    echo "   Deleting SSH key pair: ${cluster_name}-bastion-key"
    aws ec2 delete-key-pair --key-name "${cluster_name}-bastion-key" --region "$region" >/dev/null 2>&1 || true
    
    # Delete NAT Gateway
    if [[ -f "$infra_dir/nat-gateway-id" ]]; then
        local nat_gateway_id=$(cat "$infra_dir/nat-gateway-id")
        echo "   Deleting NAT Gateway: $nat_gateway_id"
        aws ec2 delete-nat-gateway --nat-gateway-id "$nat_gateway_id" --region "$region" >/dev/null 2>&1 || true
    fi
    
    # Delete Elastic IP
    if [[ -f "$infra_dir/eip-id" ]]; then
        local eip_id=$(cat "$infra_dir/eip-id")
        echo "   Deleting Elastic IP: $eip_id"
        aws ec2 release-address --allocation-id "$eip_id" --region "$region" >/dev/null 2>&1 || true
    fi
    
    # Delete subnets
    if [[ -f "$infra_dir/public-subnet-ids" ]]; then
        local public_subnets=$(cat "$infra_dir/public-subnet-ids")
        for subnet_id in $(echo "$public_subnets" | tr ',' ' '); do
            echo "   Deleting public subnet: $subnet_id"
            aws ec2 delete-subnet --subnet-id "$subnet_id" --region "$region" >/dev/null 2>&1 || true
        done
    fi
    
    if [[ -f "$infra_dir/private-subnet-ids" ]]; then
        local private_subnets=$(cat "$infra_dir/private-subnet-ids")
        for subnet_id in $(echo "$private_subnets" | tr ',' ' '); do
            echo "   Deleting private subnet: $subnet_id"
            aws ec2 delete-subnet --subnet-id "$subnet_id" --region "$region" >/dev/null 2>&1 || true
        done
    fi
    
    # Delete route tables
    echo "   Deleting route tables..."
    local route_tables=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" --region "$region" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text 2>/dev/null || echo "")
    for rt_id in $route_tables; do
        aws ec2 delete-route-table --route-table-id "$rt_id" --region "$region" >/dev/null 2>&1 || true
    done
    
    # Delete internet gateway
    local igw_id=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" --region "$region" --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || echo "")
    if [[ -n "$igw_id" && "$igw_id" != "None" ]]; then
        echo "   Deleting internet gateway: $igw_id"
        aws ec2 detach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$vpc_id" --region "$region" >/dev/null 2>&1 || true
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" --region "$region" >/dev/null 2>&1 || true
    fi
    
    # Delete VPC
    echo "   Deleting VPC: $vpc_id"
    aws ec2 delete-vpc --vpc-id "$vpc_id" --region "$region" >/dev/null 2>&1 || true
    
    echo "✅ Infrastructure cleanup completed"
}

# Function to clean up directories
cleanup_directories() {
    local install_dir="$1"
    local infra_dir="$2"
    local sync_dir="$3"
    local force="$4"
    
    echo "📁 Cleaning up directories..."
    
    # Confirm directory deletion
    if [[ "$force" != "yes" ]]; then
        echo "⚠️  This will delete the following directories:"
        [[ -d "$install_dir" ]] && echo "   - $install_dir"
        [[ -d "$infra_dir" ]] && echo "   - $infra_dir"
        [[ -d "$sync_dir" ]] && echo "   - $sync_dir"
        echo ""
        read -p "Are you sure you want to delete these directories? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Directory deletion cancelled"
            return
        fi
    fi
    
    # Delete directories
    if [[ -d "$install_dir" ]]; then
        echo "   Removing: $install_dir"
        rm -rf "$install_dir"
    fi
    
    if [[ -d "$infra_dir" ]]; then
        echo "   Removing: $infra_dir"
        rm -rf "$infra_dir"
    fi
    
    if [[ -d "$sync_dir" ]]; then
        echo "   Removing: $sync_dir"
        rm -rf "$sync_dir"
    fi
    
    echo "✅ Directories cleaned up"
}

# Function to create cleanup report
create_cleanup_report() {
    local cluster_name="$1"
    local cleanup_level="$2"
    
    echo "📝 Creating cleanup report..."
    
    local report_file="cleanup-report-$cluster_name-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$report_file" <<EOF
OpenShift Disconnected Cluster Cleanup Report
============================================
Cluster: $cluster_name
Cleanup Level: $cleanup_level
Date: $(date)

Cleanup Summary:
- Temporary files: Removed
- Log files: Removed
- Cluster: $(if [[ "$cleanup_level" == "cluster" || "$cleanup_level" == "all" ]]; then echo "Removed"; else echo "Preserved"; fi)
- Infrastructure: $(if [[ "$cleanup_level" == "all" ]]; then echo "Removed"; else echo "Preserved"; fi)
- Directories: $(if [[ "$cleanup_level" == "all" ]]; then echo "Removed"; else echo "Preserved"; fi)

Next Steps:
1. Verify that all resources have been cleaned up
2. Check AWS console for any remaining resources
3. If needed, manually clean up any remaining resources
4. Consider backing up important data before cleanup

Notes:
- Some resources may take time to be fully deleted
- Check AWS console for any orphaned resources
- Consider using AWS Cost Explorer to verify cost reduction
EOF
    
    echo "✅ Cleanup report saved to: $report_file"
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
            --sync-output-dir)
                SYNC_OUTPUT_DIR="$2"
                shift 2
                ;;
            --cleanup-level)
                CLEANUP_LEVEL="$2"
                shift 2
                ;;
            --force)
                FORCE="yes"
                shift
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
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}
    INFRA_OUTPUT_DIR=${INFRA_OUTPUT_DIR:-$DEFAULT_INFRA_OUTPUT_DIR}
    SYNC_OUTPUT_DIR=${SYNC_OUTPUT_DIR:-$DEFAULT_SYNC_OUTPUT_DIR}
    CLEANUP_LEVEL=${CLEANUP_LEVEL:-$DEFAULT_CLEANUP_LEVEL}
    FORCE=${FORCE:-no}
    DRY_RUN=${DRY_RUN:-no}
    
    # Validate cleanup level
    case "$CLEANUP_LEVEL" in
        files|cluster|all)
            ;;
        *)
            echo "❌ Invalid cleanup level: $CLEANUP_LEVEL"
            echo "Valid levels: files, cluster, all"
            exit 1
            ;;
    esac
    
    # Display script header
    echo "🧹 OpenShift Disconnected Cluster Cleanup"
    echo "========================================="
    echo ""
    echo "📋 Configuration:"
    echo "   Cluster Name: $CLUSTER_NAME"
    echo "   Installation Directory: $INSTALL_DIR"
    echo "   Infrastructure Directory: $INFRA_OUTPUT_DIR"
    echo "   Sync Directory: $SYNC_OUTPUT_DIR"
    echo "   Cleanup Level: $CLEANUP_LEVEL"
    echo "   Force: $FORCE"
    echo "   Dry Run: $DRY_RUN"
    echo ""
    
    if [[ "$DRY_RUN" == "yes" ]]; then
        echo "🔍 DRY RUN MODE - No cleanup will be performed"
        echo ""
        echo "Would perform cleanup:"
        case "$CLEANUP_LEVEL" in
            files)
                echo "  - Temporary files and logs"
                ;;
            cluster)
                echo "  - Temporary files and logs"
                echo "  - OpenShift cluster"
                ;;
            all)
                echo "  - Temporary files and logs"
                echo "  - OpenShift cluster"
                echo "  - AWS infrastructure (VPC, subnets, etc.)"
                echo "  - All directories"
                ;;
        esac
        echo ""
        echo "To actually perform cleanup, run without --dry-run"
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Perform cleanup based on level
    case "$CLEANUP_LEVEL" in
        files)
            echo "🚀 Starting files cleanup..."
            cleanup_temp_files "$CLUSTER_NAME" "$INSTALL_DIR" "$SYNC_OUTPUT_DIR"
            ;;
        cluster)
            echo "🚀 Starting cluster cleanup..."
            cleanup_temp_files "$CLUSTER_NAME" "$INSTALL_DIR" "$SYNC_OUTPUT_DIR"
            cleanup_cluster "$CLUSTER_NAME" "$INSTALL_DIR" "$FORCE"
            ;;
        all)
            echo "🚀 Starting complete cleanup..."
            cleanup_temp_files "$CLUSTER_NAME" "$INSTALL_DIR" "$SYNC_OUTPUT_DIR"
            cleanup_cluster "$CLUSTER_NAME" "$INSTALL_DIR" "$FORCE"
            cleanup_infrastructure "$CLUSTER_NAME" "$INFRA_OUTPUT_DIR" "$FORCE"
            cleanup_directories "$INSTALL_DIR" "$INFRA_OUTPUT_DIR" "$SYNC_OUTPUT_DIR" "$FORCE"
            ;;
    esac
    
    # Create cleanup report
    create_cleanup_report "$CLUSTER_NAME" "$CLEANUP_LEVEL"
    
    echo ""
    echo "✅ Cleanup completed successfully!"
    echo ""
    echo "📁 Cleanup report saved to: cleanup-report-$CLUSTER_NAME-*.txt"
    echo ""
    echo "🔧 Next steps:"
    echo "1. Review the cleanup report"
    echo "2. Check AWS console for any remaining resources"
    echo "3. Verify cost reduction in AWS Cost Explorer"
    echo "4. If needed, manually clean up any orphaned resources"
    echo ""
    echo "📝 Important notes:"
    echo "   - Some AWS resources may take time to be fully deleted"
    echo "   - Check for any orphaned EBS volumes, load balancers, or security groups"
    echo "   - Consider backing up important data before cleanup"
    echo "   - Monitor AWS costs to ensure cleanup was successful"
}

# Run main function with all arguments
main "$@" 