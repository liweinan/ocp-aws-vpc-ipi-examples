#!/bin/bash

# Comprehensive AWS Resource Cleanup Script
# Automatically cleans up all AWS resources related to disconnected cluster
# Handles dependencies in the correct order

set -euo pipefail

# Configuration
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
CLUSTER_NAME="${1:-disconnected-cluster}"
DRY_RUN="${2:-no}"
FORCE="${3:-no}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Show script header
echo "🧹 Comprehensive AWS Resource Cleanup Script"
echo "============================================="
echo ""
echo "📋 Configuration:"
echo "   Cluster Name: $CLUSTER_NAME"
echo "   Region: $REGION"
echo "   Dry Run: $DRY_RUN"
echo "   Force: $FORCE"
echo ""

# Function to check AWS credentials
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured or invalid"
        exit 1
    fi
    print_success "AWS credentials verified"
}

# Function to find and delete load balancers
cleanup_load_balancers() {
    print_info "🔍 Finding load balancers for cluster: $CLUSTER_NAME"
    
    local load_balancers=$(aws elbv2 describe-load-balancers \
        --region "$REGION" \
        --query "LoadBalancers[?contains(LoadBalancerName, '$CLUSTER_NAME')].LoadBalancerArn" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$load_balancers" ]]; then
        print_info "No load balancers found"
        return 0
    fi
    
    print_info "Found $(echo "$load_balancers" | wc -w | tr -d ' ') load balancer(s)"
    
    for lb_arn in $load_balancers; do
        if [[ "$DRY_RUN" == "yes" ]]; then
            print_info "DRY RUN: Would delete load balancer: $lb_arn"
        else
            print_info "Deleting load balancer: $lb_arn"
            if aws elbv2 delete-load-balancer --load-balancer-arn "$lb_arn" --region "$REGION" &> /dev/null; then
                print_success "Deleted load balancer: $lb_arn"
            else
                print_warning "Failed to delete load balancer: $lb_arn"
            fi
        fi
    done
    
    if [[ "$DRY_RUN" != "yes" && -n "$load_balancers" ]]; then
        print_info "Waiting for load balancers to be fully deleted..."
        sleep 30
    fi
}

# Function to find and delete network interfaces
cleanup_network_interfaces() {
    print_info "🔍 Finding network interfaces for cluster: $CLUSTER_NAME"
    
    local network_interfaces=$(aws ec2 describe-network-interfaces \
        --region "$REGION" \
        --filters "Name=description,Values=*$CLUSTER_NAME*" \
        --query 'NetworkInterfaces[].NetworkInterfaceId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$network_interfaces" ]]; then
        print_info "No network interfaces found"
        return 0
    fi
    
    print_info "Found $(echo "$network_interfaces" | wc -w | tr -d ' ') network interface(s)"
    
    for eni_id in $network_interfaces; do
        if [[ "$DRY_RUN" == "yes" ]]; then
            print_info "DRY RUN: Would delete network interface: $eni_id"
        else
            print_info "Deleting network interface: $eni_id"
            if aws ec2 delete-network-interface --network-interface-id "$eni_id" --region "$REGION" &> /dev/null; then
                print_success "Deleted network interface: $eni_id"
            else
                print_warning "Failed to delete network interface: $eni_id"
            fi
        fi
    done
}

# Function to find and delete security groups (only orphaned ones)
cleanup_orphaned_security_groups() {
    print_info "🔍 Finding orphaned security groups for cluster: $CLUSTER_NAME"
    
    # Find security groups that are not attached to any VPC
    local orphaned_sgs=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --filters "Name=group-name,Values=*$CLUSTER_NAME*" \
        --query 'SecurityGroups[?GroupName!=`default` && VpcId==null].GroupId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$orphaned_sgs" ]]; then
        print_info "No orphaned security groups found"
        return 0
    fi
    
    print_info "Found $(echo "$orphaned_sgs" | wc -w | tr -d ' ') orphaned security group(s)"
    
    for sg_id in $orphaned_sgs; do
        if [[ "$DRY_RUN" == "yes" ]]; then
            print_info "DRY RUN: Would delete orphaned security group: $sg_id"
        else
            print_info "Deleting orphaned security group: $sg_id"
            
            # Remove all ingress rules
            aws ec2 revoke-security-group-ingress --group-id "$sg_id" --protocol all --port -1 --cidr 0.0.0.0/0 --region "$REGION" 2>/dev/null || true
            aws ec2 revoke-security-group-egress --group-id "$sg_id" --protocol all --port -1 --cidr 0.0.0.0/0 --region "$REGION" 2>/dev/null || true
            
            if aws ec2 delete-security-group --group-id "$sg_id" --region "$REGION" &> /dev/null; then
                print_success "Deleted orphaned security group: $sg_id"
            else
                print_warning "Failed to delete orphaned security group: $sg_id"
            fi
        fi
    done
}

# Function to find and delete VPCs
cleanup_vpcs() {
    print_info "🔍 Finding VPCs for cluster: $CLUSTER_NAME"
    
    local vpcs=$(aws ec2 describe-vpcs \
        --region "$REGION" \
        --filters "Name=tag:Name,Values=*$CLUSTER_NAME*" \
        --query 'Vpcs[].VpcId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$vpcs" ]]; then
        print_info "No VPCs found"
        return 0
    fi
    
    print_info "Found $(echo "$vpcs" | wc -w | tr -d ' ') VPC(s)"
    
    for vpc_id in $vpcs; do
        if [[ "$DRY_RUN" == "yes" ]]; then
            print_info "DRY RUN: Would delete VPC: $vpc_id"
        else
            print_info "Deleting VPC: $vpc_id"
            
            # Use the enhanced force-delete-vpc script
            if [[ -f "./force-delete-vpc.sh" ]]; then
                if ./force-delete-vpc.sh "$vpc_id" "$REGION" &> /dev/null; then
                    print_success "Deleted VPC: $vpc_id"
                else
                    print_warning "Failed to delete VPC: $vpc_id"
                fi
            else
                print_warning "force-delete-vpc.sh not found, trying manual deletion"
                if aws ec2 delete-vpc --vpc-id "$vpc_id" --region "$REGION" &> /dev/null; then
                    print_success "Deleted VPC: $vpc_id"
                else
                    print_warning "Failed to delete VPC: $vpc_id"
                fi
            fi
        fi
    done
}

# Function to find and delete SSH key pairs
cleanup_ssh_keys() {
    print_info "🔍 Finding SSH key pairs for cluster: $CLUSTER_NAME"
    
    local ssh_keys=$(aws ec2 describe-key-pairs \
        --region "$REGION" \
        --query "KeyPairs[?contains(KeyName, '$CLUSTER_NAME')].KeyName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$ssh_keys" ]]; then
        print_info "No SSH key pairs found"
        return 0
    fi
    
    print_info "Found $(echo "$ssh_keys" | wc -w | tr -d ' ') SSH key pair(s)"
    
    for key_name in $ssh_keys; do
        if [[ "$DRY_RUN" == "yes" ]]; then
            print_info "DRY RUN: Would delete SSH key pair: $key_name"
        else
            print_info "Deleting SSH key pair: $key_name"
            if aws ec2 delete-key-pair --key-name "$key_name" --region "$REGION" &> /dev/null; then
                print_success "Deleted SSH key pair: $key_name"
            else
                print_warning "Failed to delete SSH key pair: $key_name"
            fi
        fi
    done
}

# Function to find and delete instances
cleanup_instances() {
    print_info "🔍 Finding instances for cluster: $CLUSTER_NAME"
    
    local instances=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" "Name=instance-state-name,Values=running,stopped,pending" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$instances" ]]; then
        print_info "No running instances found"
        return 0
    fi
    
    print_info "Found $(echo "$instances" | wc -w | tr -d ' ') instance(s)"
    
    for instance_id in $instances; do
        if [[ "$DRY_RUN" == "yes" ]]; then
            print_info "DRY RUN: Would terminate instance: $instance_id"
        else
            print_info "Terminating instance: $instance_id"
            if aws ec2 terminate-instances --instance-ids "$instance_id" --region "$REGION" &> /dev/null; then
                print_success "Terminated instance: $instance_id"
            else
                print_warning "Failed to terminate instance: $instance_id"
            fi
        fi
    done
    
    if [[ "$DRY_RUN" != "yes" && -n "$instances" ]]; then
        print_info "Waiting for instances to be terminated..."
        for instance_id in $instances; do
            aws ec2 wait instance-terminated --instance-ids "$instance_id" --region "$REGION" 2>/dev/null || true
        done
    fi
}

# Main cleanup function
main_cleanup() {
    print_info "Starting comprehensive cleanup for cluster: $CLUSTER_NAME"
    
    # Cleanup in dependency order
    cleanup_instances
    cleanup_load_balancers
    cleanup_network_interfaces
    cleanup_orphaned_security_groups
    cleanup_vpcs
    cleanup_ssh_keys
    
    print_success "Comprehensive cleanup completed!"
}

# Show usage
show_usage() {
    echo "Usage: $0 [cluster-name] [dry-run] [force]"
    echo ""
    echo "Arguments:"
    echo "  cluster-name  Name of the cluster to clean up (default: disconnected-cluster)"
    echo "  dry-run       Set to 'yes' to preview changes without executing (default: no)"
    echo "  force         Set to 'yes' to skip confirmations (default: no)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Clean up disconnected-cluster"
    echo "  $0 my-cluster                         # Clean up my-cluster"
    echo "  $0 disconnected-cluster yes           # Dry run for disconnected-cluster"
    echo "  $0 disconnected-cluster no yes        # Force cleanup for disconnected-cluster"
}

# Main execution
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_usage
    exit 0
fi

# Check AWS credentials
check_aws_credentials

# Confirm before proceeding (unless force is set)
if [[ "$FORCE" != "yes" && "$DRY_RUN" != "yes" ]]; then
    echo ""
    echo "⚠️  WARNING: This will delete ALL AWS resources related to cluster '$CLUSTER_NAME'"
    echo "   This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Cleanup cancelled by user"
        exit 0
    fi
fi

# Run cleanup
main_cleanup

echo ""
echo "💡 Tips:"
echo "  - Run verification script to confirm cleanup"
echo "  - Check AWS console for any remaining resources"
echo "  - Use AWS Cost Explorer to verify cost reduction" 