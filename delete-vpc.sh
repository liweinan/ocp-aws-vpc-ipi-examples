#!/bin/bash

# Safe VPC Deletion Script for AWS
# This script safely deletes VPC and all associated resources created by the VPC automation scripts

set -euo pipefail

# Default values
DEFAULT_REGION="us-east-1"
DEFAULT_CLUSTER_NAME="my-cluster"
DEFAULT_OUTPUT_DIR="./vpc-output"
DEFAULT_BASTION_OUTPUT_DIR="./bastion-output"
DEFAULT_OPENSHIFT_INSTALL_DIR="./openshift-install"

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
    echo "  --cluster-name             Cluster name to delete (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --region                   AWS region (default: $DEFAULT_REGION)"
    echo "  --vpc-output-dir           VPC output directory (default: $DEFAULT_OUTPUT_DIR)"
    echo "  --bastion-output-dir       Bastion output directory (default: $DEFAULT_BASTION_OUTPUT_DIR)"
    echo "  --openshift-install-dir    OpenShift install directory (default: $DEFAULT_OPENSHIFT_INSTALL_DIR)"
    echo "  --force                    Force deletion without confirmation"
    echo "  --dry-run                  Show what would be deleted without actually deleting"
    echo "  --skip-openshift           Skip OpenShift cluster deletion"
    echo "  --skip-bastion             Skip bastion host deletion"
    echo "  --help                     Display this help message"
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

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_id="$2"
    local region="$3"
    
    # Build AWS CLI command with profile if set
    local aws_cmd="aws"
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        aws_cmd="aws --profile ${AWS_PROFILE}"
    fi
    
    case "$resource_type" in
        "stack")
            $aws_cmd cloudformation describe-stacks --stack-name "$resource_id" --region "$region" &> /dev/null
            ;;
        "instance")
            $aws_cmd ec2 describe-instances --instance-ids "$resource_id" --region "$region" &> /dev/null
            ;;
        "vpc")
            $aws_cmd ec2 describe-vpcs --vpc-ids "$resource_id" --region "$region" &> /dev/null
            ;;
        "key-pair")
            $aws_cmd ec2 describe-key-pairs --key-names "$resource_id" --region "$region" &> /dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to get stack resources
get_stack_resources() {
    local stack_name="$1"
    local region="$2"
    
    # Build AWS CLI command with profile if set
    local aws_cmd="aws"
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        aws_cmd="aws --profile ${AWS_PROFILE}"
    fi
    
    $aws_cmd cloudformation list-stack-resources \
        --stack-name "$stack_name" \
        --region "$region" \
        --query 'StackResourceSummaries[?ResourceStatus!=`DELETE_COMPLETE`].[LogicalResourceId,PhysicalResourceId,ResourceType,ResourceStatus]' \
        --output table
}

# Function to delete OpenShift cluster
delete_openshift_cluster() {
    local install_dir="$1"
    local dry_run="$2"
    
    if [[ ! -d "$install_dir" ]]; then
        print_warning "OpenShift install directory not found: $install_dir"
        return 0
    fi
    
    if [[ ! -f "$install_dir/openshift-install" ]]; then
        print_warning "OpenShift installer not found in: $install_dir"
        return 0
    fi
    
    print_info "Checking for OpenShift cluster in: $install_dir"
    
    if [[ "$dry_run" == "yes" ]]; then
        print_info "DRY RUN: Would delete OpenShift cluster from $install_dir"
        return 0
    fi
    
    print_warning "This will delete the OpenShift cluster and all associated AWS resources"
    read -p "Do you want to proceed with OpenShift cluster deletion? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "OpenShift cluster deletion skipped"
        return 0
    fi
    
    print_info "Deleting OpenShift cluster..."
    cd "$install_dir"
    ./openshift-install destroy cluster --log-level=info
    
    if [[ $? -eq 0 ]]; then
        print_success "OpenShift cluster deleted successfully"
    else
        print_error "Failed to delete OpenShift cluster"
        return 1
    fi
}

# Function to delete bastion host
delete_bastion_host() {
    local bastion_dir="$1"
    local region="$2"
    local dry_run="$3"
    
    if [[ ! -d "$bastion_dir" ]]; then
        print_warning "Bastion output directory not found: $bastion_dir"
        return 0
    fi
    
    local instance_id_file="$bastion_dir/bastion-instance-id"
    if [[ ! -f "$instance_id_file" ]]; then
        print_warning "Bastion instance ID file not found: $instance_id_file"
        return 0
    fi
    
    local instance_id=$(cat "$instance_id_file" | tr -d '\n')
    if [[ -z "$instance_id" ]]; then
        print_warning "Empty bastion instance ID"
        return 0
    fi
    
    # Build AWS CLI command with profile if set
    local aws_cmd="aws"
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        aws_cmd="aws --profile ${AWS_PROFILE}"
    fi
    
    if ! resource_exists "instance" "$instance_id" "$region"; then
        print_warning "Bastion instance not found: $instance_id"
        return 0
    fi
    
    print_info "Found bastion instance: $instance_id"
    
    if [[ "$dry_run" == "yes" ]]; then
        print_info "DRY RUN: Would terminate bastion instance: $instance_id"
        return 0
    fi
    
    print_warning "This will terminate the bastion host instance"
    read -p "Do you want to proceed with bastion host deletion? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Bastion host deletion skipped"
        return 0
    fi
    
    print_info "Terminating bastion instance: $instance_id"
    $aws_cmd ec2 terminate-instances --instance-ids "$instance_id" --region "$region"
    
    print_info "Waiting for instance termination..."
    $aws_cmd ec2 wait instance-terminated --instance-ids "$instance_id" --region "$region"
    
    print_success "Bastion host deleted successfully"
}

# Function to delete SSH key pairs
delete_ssh_key_pairs() {
    local cluster_name="$1"
    local region="$2"
    local dry_run="$3"
    
    # Build AWS CLI command with profile if set
    local aws_cmd="aws"
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        aws_cmd="aws --profile ${AWS_PROFILE}"
    fi
    
    local key_names=("${cluster_name}-key" "${cluster_name}-bastion-key")
    
    for key_name in "${key_names[@]}"; do
        if resource_exists "key-pair" "$key_name" "$region"; then
            print_info "Found SSH key pair: $key_name"
            
            if [[ "$dry_run" == "yes" ]]; then
                print_info "DRY RUN: Would delete SSH key pair: $key_name"
            else
                print_info "Deleting SSH key pair: $key_name"
                $aws_cmd ec2 delete-key-pair --key-name "$key_name" --region "$region"
                print_success "SSH key pair deleted: $key_name"
            fi
        else
            print_info "SSH key pair not found: $key_name"
        fi
    done
}

# Function to delete VPC stack
delete_vpc_stack() {
    local vpc_dir="$1"
    local region="$2"
    local dry_run="$3"
    
    if [[ ! -d "$vpc_dir" ]]; then
        print_error "VPC output directory not found: $vpc_dir"
        return 1
    fi
    
    local stack_name_file="$vpc_dir/stack-name"
    if [[ ! -f "$stack_name_file" ]]; then
        print_error "Stack name file not found: $stack_name_file"
        return 1
    fi
    
    local stack_name=$(cat "$stack_name_file" | tr -d '\n')
    if [[ -z "$stack_name" ]]; then
        print_error "Empty stack name"
        return 1
    fi
    
    # Build AWS CLI command with profile if set
    local aws_cmd="aws"
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        aws_cmd="aws --profile ${AWS_PROFILE}"
    fi
    
    if ! resource_exists "stack" "$stack_name" "$region"; then
        print_warning "VPC stack not found: $stack_name"
        return 0
    fi
    
    print_info "Found VPC stack: $stack_name"
    
    if [[ "$dry_run" == "yes" ]]; then
        print_info "DRY RUN: Would delete VPC stack: $stack_name"
        print_info "DRY RUN: Stack resources that would be deleted:"
        get_stack_resources "$stack_name" "$region"
        return 0
    fi
    
    print_warning "This will delete the VPC and all associated resources (subnets, NAT gateways, etc.)"
    read -p "Do you want to proceed with VPC stack deletion? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "VPC stack deletion skipped"
        return 0
    fi
    
    print_info "Deleting VPC stack: $stack_name"
    $aws_cmd cloudformation delete-stack --stack-name "$stack_name" --region "$region"
    
    print_info "Waiting for stack deletion to complete..."
    $aws_cmd cloudformation wait stack-delete-complete --stack-name "$stack_name" --region "$region"
    
    print_success "VPC stack deleted successfully"
}

# Function to cleanup output directories
cleanup_output_directories() {
    local vpc_dir="$1"
    local bastion_dir="$2"
    local openshift_dir="$3"
    local dry_run="$4"
    
    local dirs_to_clean=()
    
    if [[ -d "$vpc_dir" ]]; then
        dirs_to_clean+=("$vpc_dir")
    fi
    
    if [[ -d "$bastion_dir" ]]; then
        dirs_to_clean+=("$bastion_dir")
    fi
    
    if [[ -d "$openshift_dir" ]]; then
        dirs_to_clean+=("$openshift_dir")
    fi
    
    if [[ ${#dirs_to_clean[@]} -eq 0 ]]; then
        print_info "No output directories to clean"
        return 0
    fi
    
    if [[ "$dry_run" == "yes" ]]; then
        print_info "DRY RUN: Would remove directories:"
        for dir in "${dirs_to_clean[@]}"; do
            print_info "  - $dir"
        done
        return 0
    fi
    
    print_warning "This will remove all output directories and generated files"
    read -p "Do you want to proceed with cleanup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Directory cleanup skipped"
        return 0
    fi
    
    for dir in "${dirs_to_clean[@]}"; do
        print_info "Removing directory: $dir"
        rm -rf "$dir"
        print_success "Removed: $dir"
    done
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --vpc-output-dir)
            VPC_OUTPUT_DIR="$2"
            shift 2
            ;;
        --bastion-output-dir)
            BASTION_OUTPUT_DIR="$2"
            shift 2
            ;;
        --openshift-install-dir)
            OPENSHIFT_INSTALL_DIR="$2"
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
        --skip-openshift)
            SKIP_OPENSHIFT="yes"
            shift
            ;;
        --skip-bastion)
            SKIP_BASTION="yes"
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
CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
REGION=${REGION:-$DEFAULT_REGION}
VPC_OUTPUT_DIR=${VPC_OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}
BASTION_OUTPUT_DIR=${BASTION_OUTPUT_DIR:-$DEFAULT_BASTION_OUTPUT_DIR}
OPENSHIFT_INSTALL_DIR=${OPENSHIFT_INSTALL_DIR:-$DEFAULT_OPENSHIFT_INSTALL_DIR}
FORCE=${FORCE:-no}
DRY_RUN=${DRY_RUN:-no}
SKIP_OPENSHIFT=${SKIP_OPENSHIFT:-no}
SKIP_BASTION=${SKIP_BASTION:-no}

# Validate AWS credentials
validate_aws_credentials

# Build AWS CLI command with profile if set
AWS_CMD="aws"
if [[ -n "${AWS_PROFILE:-}" ]]; then
    AWS_CMD="aws --profile ${AWS_PROFILE}"
fi

echo "🗑️  Safe VPC Deletion Script"
echo "=============================="
echo ""
echo "📋 Configuration:"
echo "   Cluster Name: $CLUSTER_NAME"
echo "   Region: $REGION"
echo "   VPC Output Dir: $VPC_OUTPUT_DIR"
echo "   Bastion Output Dir: $BASTION_OUTPUT_DIR"
echo "   OpenShift Install Dir: $OPENSHIFT_INSTALL_DIR"
echo "   Force Mode: $FORCE"
echo "   Dry Run: $DRY_RUN"
echo "   Skip OpenShift: $SKIP_OPENSHIFT"
echo "   Skip Bastion: $SKIP_BASTION"
echo ""

if [[ "$DRY_RUN" == "yes" ]]; then
    print_info "DRY RUN MODE - No resources will be actually deleted"
    echo ""
fi

# Skip confirmation if force mode is enabled
if [[ "$FORCE" != "yes" && "$DRY_RUN" != "yes" ]]; then
    print_warning "This script will delete the following resources:"
    echo "   - OpenShift cluster (if exists)"
    echo "   - Bastion host (if exists)"
    echo "   - VPC and all associated resources"
    echo "   - SSH key pairs"
    echo "   - Output directories"
    echo ""
    read -p "Do you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Deletion cancelled"
        exit 0
    fi
fi

# Step 1: Delete OpenShift cluster
if [[ "$SKIP_OPENSHIFT" != "yes" ]]; then
    echo "🔴 Step 1: OpenShift Cluster Deletion"
    echo "----------------------------------------"
    delete_openshift_cluster "$OPENSHIFT_INSTALL_DIR" "$DRY_RUN"
    echo ""
else
    print_info "Skipping OpenShift cluster deletion"
fi

# Step 2: Delete bastion host
if [[ "$SKIP_BASTION" != "yes" ]]; then
    echo "🖥️  Step 2: Bastion Host Deletion"
    echo "-----------------------------------"
    delete_bastion_host "$BASTION_OUTPUT_DIR" "$REGION" "$DRY_RUN"
    echo ""
else
    print_info "Skipping bastion host deletion"
fi

# Step 3: Delete SSH key pairs
echo "🔑 Step 3: SSH Key Pair Deletion"
echo "----------------------------------"
delete_ssh_key_pairs "$CLUSTER_NAME" "$REGION" "$DRY_RUN"
echo ""

# Step 4: Delete VPC stack
echo "🌐 Step 4: VPC Stack Deletion"
echo "-------------------------------"
delete_vpc_stack "$VPC_OUTPUT_DIR" "$REGION" "$DRY_RUN"
echo ""

# Step 5: Cleanup output directories
echo "🧹 Step 5: Output Directory Cleanup"
echo "------------------------------------"
cleanup_output_directories "$VPC_OUTPUT_DIR" "$BASTION_OUTPUT_DIR" "$OPENSHIFT_INSTALL_DIR" "$DRY_RUN"
echo ""

# Final summary
echo "📊 Deletion Summary"
echo "==================="
if [[ "$DRY_RUN" == "yes" ]]; then
    print_info "DRY RUN COMPLETED - No resources were actually deleted"
    echo ""
    echo "To perform actual deletion, run the script without --dry-run"
else
    print_success "All resources have been successfully deleted!"
    echo ""
    echo "✅ OpenShift cluster: Deleted (if existed)"
    echo "✅ Bastion host: Deleted (if existed)"
    echo "✅ SSH key pairs: Deleted"
    echo "✅ VPC stack: Deleted"
    echo "✅ Output directories: Cleaned up"
    echo ""
    echo "🎉 Cleanup completed successfully!"
fi

echo ""
echo "💡 Tips:"
echo "   - Check AWS Console to verify all resources are deleted"
echo "   - Monitor AWS costs to ensure no unexpected charges"
echo "   - Keep backup of important configuration files if needed"
echo "" 