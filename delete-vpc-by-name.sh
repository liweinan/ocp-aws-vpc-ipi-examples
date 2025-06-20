#!/bin/bash

# Delete VPC by Name Script
# This script deletes a VPC and all its associated resources by VPC name

set -euo pipefail

# Default values
DEFAULT_REGION="us-east-1"
DEFAULT_FORCE="no"
DEFAULT_DRY_RUN="no"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --vpc-name              VPC name to delete (required)"
    echo "  --region                AWS region (default: $DEFAULT_REGION)"
    echo "  --force                 Force deletion without confirmation"
    echo "  --dry-run               Show what would be deleted without actually deleting"
    echo "  --help                  Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --vpc-name my-cluster-vpc-1234567890"
    echo "  $0 --vpc-name my-cluster-vpc-1234567890 --dry-run"
    echo "  $0 --vpc-name my-cluster-vpc-1234567890 --force"
    exit 1
}

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to validate AWS credentials
validate_aws_credentials() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        exit 1
    fi

    # Build AWS CLI command with profile if set
    local aws_cmd="aws"
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        aws_cmd="aws --profile ${AWS_PROFILE}"
    fi

    if ! $aws_cmd sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured"
        exit 1
    fi
}

# Function to find VPC by name
find_vpc_by_name() {
    local vpc_name="$1"
    local region="$2"
    
    # Build AWS CLI command with profile if set
    local aws_cmd="aws"
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        aws_cmd="aws --profile ${AWS_PROFILE}"
    fi
    
    local vpc_id=$($aws_cmd ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=$vpc_name" \
        --region "$region" \
        --query 'Vpcs[0].VpcId' \
        --output text)
    
    if [[ "$vpc_id" == "None" || -z "$vpc_id" ]]; then
        return 1
    fi
    
    echo "$vpc_id"
}

# Function to find CloudFormation stack by VPC name
find_stack_by_vpc_name() {
    local vpc_name="$1"
    local region="$2"
    
    # Build AWS CLI command with profile if set
    local aws_cmd="aws"
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        aws_cmd="aws --profile ${AWS_PROFILE}"
    fi
    
    local stack_name=$($aws_cmd cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --region "$region" \
        --query "StackSummaries[?contains(StackName, \`$vpc_name\`)].StackName" \
        --output text)
    
    if [[ "$stack_name" == "None" || -z "$stack_name" ]]; then
        return 1
    fi
    
    echo "$stack_name"
}

# Function to get VPC details
get_vpc_details() {
    local vpc_id="$1"
    local region="$2"
    
    # Build AWS CLI command with profile if set
    local aws_cmd="aws"
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        aws_cmd="aws --profile ${AWS_PROFILE}"
    fi
    
    $aws_cmd ec2 describe-vpcs \
        --vpc-ids "$vpc_id" \
        --region "$region" \
        --query 'Vpcs[0]' \
        --output json
}

# Function to list VPC resources
list_vpc_resources() {
    local vpc_id="$1"
    local region="$2"
    
    # Build AWS CLI command with profile if set
    local aws_cmd="aws"
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        aws_cmd="aws --profile ${AWS_PROFILE}"
    fi
    
    print_info "VPC Resources:"
    
    # Subnets
    local subnets=$($aws_cmd ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --region "$region" \
        --query 'Subnets[].SubnetId' \
        --output text)
    if [[ -n "$subnets" ]]; then
        print_info "  Subnets: $subnets"
    fi
    
    # Route Tables
    local route_tables=$($aws_cmd ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --region "$region" \
        --query 'RouteTables[].RouteTableId' \
        --output text)
    if [[ -n "$route_tables" ]]; then
        print_info "  Route Tables: $route_tables"
    fi
    
    # Security Groups
    local security_groups=$($aws_cmd ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --region "$region" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
        --output text)
    if [[ -n "$security_groups" ]]; then
        print_info "  Security Groups: $security_groups"
    fi
    
    # Internet Gateways
    local internet_gateways=$($aws_cmd ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=$vpc_id" \
        --region "$region" \
        --query 'InternetGateways[].InternetGatewayId' \
        --output text)
    if [[ -n "$internet_gateways" ]]; then
        print_info "  Internet Gateways: $internet_gateways"
    fi
    
    # NAT Gateways
    local nat_gateways=$($aws_cmd ec2 describe-nat-gateways \
        --filter "Name=vpc-id,Values=$vpc_id" \
        --region "$region" \
        --query 'NatGateways[].NatGatewayId' \
        --output text)
    if [[ -n "$nat_gateways" ]]; then
        print_info "  NAT Gateways: $nat_gateways"
    fi
    
    # EC2 Instances
    local instances=$($aws_cmd ec2 describe-instances \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=instance-state-name,Values=running,stopped" \
        --region "$region" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text)
    if [[ -n "$instances" ]]; then
        print_info "  EC2 Instances: $instances"
    fi
    
    # Load Balancers
    local load_balancers=$($aws_cmd elbv2 describe-load-balancers \
        --region "$region" \
        --query "LoadBalancers[?VpcId==\`$vpc_id\`].LoadBalancerArn" \
        --output text 2>/dev/null || echo "")
    if [[ -n "$load_balancers" ]]; then
        print_info "  Load Balancers: $load_balancers"
    fi
}

# Function to delete VPC directly
delete_vpc_directly() {
    local vpc_id="$1"
    local region="$2"
    local dry_run="$3"
    
    # Build AWS CLI command with profile if set
    local aws_cmd="aws"
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        aws_cmd="aws --profile ${AWS_PROFILE}"
    fi
    
    if [[ "$dry_run" == "yes" ]]; then
        print_info "DRY RUN: Would delete VPC: $vpc_id"
        return 0
    fi
    
    print_info "Deleting VPC: $vpc_id"
    
    # Delete VPC (this will fail if there are dependencies)
    if $aws_cmd ec2 delete-vpc --vpc-id "$vpc_id" --region "$region"; then
        print_success "VPC deleted successfully: $vpc_id"
        return 0
    else
        print_error "Failed to delete VPC directly. VPC may have dependencies."
        print_info "Try deleting the CloudFormation stack instead, or manually delete dependencies."
        return 1
    fi
}

# Function to delete CloudFormation stack
delete_cloudformation_stack() {
    local stack_name="$1"
    local region="$2"
    local dry_run="$3"
    
    # Build AWS CLI command with profile if set
    local aws_cmd="aws"
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        aws_cmd="aws --profile ${AWS_PROFILE}"
    fi
    
    if [[ "$dry_run" == "yes" ]]; then
        print_info "DRY RUN: Would delete CloudFormation stack: $stack_name"
        return 0
    fi
    
    print_info "Deleting CloudFormation stack: $stack_name"
    $aws_cmd cloudformation delete-stack --stack-name "$stack_name" --region "$region"
    
    print_info "Waiting for stack deletion to complete..."
    $aws_cmd cloudformation wait stack-delete-complete --stack-name "$stack_name" --region "$region"
    
    print_success "CloudFormation stack deleted successfully: $stack_name"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --vpc-name)
            VPC_NAME="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
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

# Set default values if not provided
REGION=${REGION:-$DEFAULT_REGION}
FORCE=${FORCE:-$DEFAULT_FORCE}
DRY_RUN=${DRY_RUN:-$DEFAULT_DRY_RUN}

# Validate required parameters
if [[ -z "${VPC_NAME:-}" ]]; then
    print_error "VPC name is required"
    usage
fi

# Validate AWS credentials
validate_aws_credentials

# Build AWS CLI command with profile if set
AWS_CMD="aws"
if [[ -n "${AWS_PROFILE:-}" ]]; then
    AWS_CMD="aws --profile ${AWS_PROFILE}"
fi

echo "🗑️  Delete VPC by Name Script"
echo "=============================="
echo ""
echo "📋 Configuration:"
echo "   VPC Name: $VPC_NAME"
echo "   Region: $REGION"
echo "   Force Mode: $FORCE"
echo "   Dry Run: $DRY_RUN"
echo ""

if [[ "$DRY_RUN" == "yes" ]]; then
    print_info "DRY RUN MODE - No resources will be actually deleted"
    echo ""
fi

# Find VPC by name
print_info "Searching for VPC with name: $VPC_NAME"
VPC_ID=$(find_vpc_by_name "$VPC_NAME" "$REGION")

if [[ $? -ne 0 ]]; then
    print_error "VPC not found with name: $VPC_NAME"
    print_info "Trying to find CloudFormation stack..."
    
    # Try to find CloudFormation stack
    STACK_NAME=$(find_stack_by_vpc_name "$VPC_NAME" "$REGION")
    
    if [[ $? -ne 0 ]]; then
        print_error "Neither VPC nor CloudFormation stack found with name: $VPC_NAME"
        print_info "Available VPCs in region $REGION:"
        $AWS_CMD ec2 describe-vpcs \
            --region "$REGION" \
            --query 'Vpcs[].{Name:Tags[?Key==`Name`].Value|[0],VpcId:VpcId,CidrBlock:CidrBlock}' \
            --output table
        exit 1
    else
        print_info "Found CloudFormation stack: $STACK_NAME"
        STACK_FOUND="yes"
    fi
else
    print_info "Found VPC: $VPC_ID"
    VPC_FOUND="yes"
fi

# Get VPC details if found
if [[ "${VPC_FOUND:-}" == "yes" ]]; then
    print_info "VPC Details:"
    VPC_DETAILS=$(get_vpc_details "$VPC_ID" "$REGION")
    echo "$VPC_DETAILS" | jq -r '. | "  VPC ID: \(.VpcId)\n  CIDR Block: \(.CidrBlock)\n  State: \(.State)\n  DNS Hostnames: \(.EnableDnsHostnames)\n  DNS Support: \(.EnableDnsSupport)"'
    
    # List VPC resources
    list_vpc_resources "$VPC_ID" "$REGION"
fi

# Skip confirmation if force mode is enabled
if [[ "$FORCE" != "yes" && "$DRY_RUN" != "yes" ]]; then
    echo ""
    print_warning "This will delete the VPC and all associated resources!"
    if [[ "${VPC_FOUND:-}" == "yes" ]]; then
        echo "   - VPC: $VPC_ID"
    fi
    if [[ "${STACK_FOUND:-}" == "yes" ]]; then
        echo "   - CloudFormation Stack: $STACK_NAME"
    fi
    echo ""
    read -p "Do you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Deletion cancelled"
        exit 0
    fi
fi

# Delete resources
if [[ "${STACK_FOUND:-}" == "yes" ]]; then
    # Delete CloudFormation stack (preferred method)
    echo "🏗️  Deleting CloudFormation Stack"
    echo "-----------------------------------"
    delete_cloudformation_stack "$STACK_NAME" "$REGION" "$DRY_RUN"
elif [[ "${VPC_FOUND:-}" == "yes" ]]; then
    # Try to delete VPC directly
    echo "🌐 Deleting VPC Directly"
    echo "-------------------------"
    if ! delete_vpc_directly "$VPC_ID" "$REGION" "$DRY_RUN"; then
        print_warning "Direct VPC deletion failed. Trying to find CloudFormation stack..."
        
        # Try to find stack again
        STACK_NAME=$(find_stack_by_vpc_name "$VPC_NAME" "$REGION")
        if [[ $? -eq 0 ]]; then
            print_info "Found CloudFormation stack: $STACK_NAME"
            echo "🏗️  Deleting CloudFormation Stack"
            echo "-----------------------------------"
            delete_cloudformation_stack "$STACK_NAME" "$REGION" "$DRY_RUN"
        else
            print_error "Could not find CloudFormation stack. Manual deletion may be required."
            print_info "You may need to manually delete dependencies before deleting the VPC."
            exit 1
        fi
    fi
fi

# Final summary
echo ""
echo "📊 Deletion Summary"
echo "==================="
if [[ "$DRY_RUN" == "yes" ]]; then
    print_info "DRY RUN COMPLETED - No resources were actually deleted"
    echo ""
    echo "To perform actual deletion, run the script without --dry-run"
else
    print_success "VPC deletion completed successfully!"
    if [[ "${VPC_FOUND:-}" == "yes" ]]; then
        echo "✅ VPC: $VPC_ID"
    fi
    if [[ "${STACK_FOUND:-}" == "yes" ]]; then
        echo "✅ CloudFormation Stack: $STACK_NAME"
    fi
    echo ""
    echo "🎉 Cleanup completed successfully!"
fi

echo ""
echo "💡 Tips:"
echo "   - Check AWS Console to verify all resources are deleted"
echo "   - Monitor AWS costs to ensure no unexpected charges"
echo "   - If deletion failed, check for dependencies and delete them manually"
echo "" 