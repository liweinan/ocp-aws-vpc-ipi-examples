#!/bin/bash

# VPC Deletion Script by AWS Account Owner ID
# Finds and deletes VPC CloudFormation stacks in a specific AWS account
# Useful when you don't know the exact stack names

set -euo pipefail

# Check if jq is available
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required but not installed. Please install jq to continue."
    echo "Installation:"
    echo "  macOS: brew install jq"
    echo "  Ubuntu/Debian: sudo apt-get install jq"
    echo "  CentOS/RHEL: sudo yum install jq"
    exit 1
fi

# Setup logging
LOG_DIR="./logs"
LOG_FILE="${LOG_DIR}/delete-vpc-by-owner-$(date +%Y%m%d-%H%M%S).log"

# Create logs directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Function to log messages
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Default values
DEFAULT_REGION="us-east-1"
DEFAULT_OWNER_ID=""
DEFAULT_FORCE="no"
DEFAULT_DRY_RUN="no"
DEFAULT_FILTER_PATTERN="vpc"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "VPC Deletion Script by AWS Account Owner ID"
    echo "Finds and deletes VPC CloudFormation stacks in a specific AWS account"
    echo ""
    echo "Options:"
    echo "  --owner-id              AWS Account Owner ID (required)"
    echo "  --region                AWS region (default: $DEFAULT_REGION)"
    echo "  --filter-pattern        Pattern to filter VPC stacks (default: $DEFAULT_FILTER_PATTERN)"
    echo "  --force                 Skip confirmation prompts"
    echo "  --dry-run               Show what would be deleted without actually deleting"
    echo "  --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --owner-id <YOUR_OWNER_ID> --dry-run"
    echo "  $0 --owner-id <YOUR_OWNER_ID> --filter-pattern my-cluster"
    echo "  $0 --owner-id <YOUR_OWNER_ID> --force"
}

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
    log_message "INFO" "$1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
    log_message "SUCCESS" "$1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
    log_message "WARNING" "$1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    log_message "ERROR" "$1"
}

# Function to validate AWS credentials
validate_aws_credentials() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS credentials not configured or invalid"
        print_info "Please configure AWS credentials using:"
        print_info "  aws configure"
        print_info "  or set AWS_PROFILE environment variable"
        exit 1
    fi
    
    local current_account=$(aws sts get-caller-identity --query 'Account' --output text)
    print_info "Using AWS Account: $current_account"
}

# Function to get AWS account owner ID
get_owner_id() {
    if [[ -n "$OWNER_ID" ]]; then
        echo "$OWNER_ID"
    else
        aws sts get-caller-identity --query 'Account' --output text
    fi
}

# Function to find VPC CloudFormation stacks
find_vpc_stacks() {
    local owner_id="$1"
    local region="$2"
    local filter_pattern="$3"
    
    print_info "Searching for VPC CloudFormation stacks in account $owner_id (region: $region)..."
    log_message "DEBUG" "Filter pattern: $filter_pattern"
    
    # Get all CloudFormation stacks with better error handling
    local aws_cmd="aws cloudformation list-stacks --region $region --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query \"StackSummaries[?contains(StackName, '$filter_pattern')].{Name:StackName,Status:StackStatus,CreationTime:CreationTime}\" --output json"
    
    log_message "DEBUG" "Executing AWS CLI command: $aws_cmd"
    
    local stacks_json
    local aws_output
    local aws_exit_code
    
    # Capture both stdout and stderr
    aws_output=$(aws cloudformation list-stacks \
        --region "$region" \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --query "StackSummaries[?contains(StackName, '$filter_pattern')].{Name:StackName,Status:StackStatus,CreationTime:CreationTime}" \
        --output json 2>&1)
    aws_exit_code=$?
    
    # Log the raw AWS CLI output
    log_message "DEBUG" "AWS CLI exit code: $aws_exit_code"
    log_message "DEBUG" "AWS CLI raw output: $aws_output"
    
    if [[ $aws_exit_code -ne 0 ]]; then
        print_warning "Failed to list CloudFormation stacks (exit code: $aws_exit_code): $aws_output"
        echo "[]"
        return 0
    fi

    # 如果返回空字符串，自动转为 []
    if [[ -z "$aws_output" ]]; then
        log_message "DEBUG" "AWS CLI returned empty string, converting to empty array"
        aws_output="[]"
    fi

    # Validate JSON output
    if ! echo "$aws_output" | jq empty 2>/dev/null; then
        print_warning "Invalid JSON response from AWS CLI: $aws_output"
        log_message "ERROR" "JSON validation failed for AWS CLI output"
        echo "[]"
        return 0
    fi
    
    # Log the validated JSON
    log_message "DEBUG" "Valid JSON received, stack count: $(echo "$aws_output" | jq length)"
    
    if [[ "$aws_output" == "[]" ]]; then
        print_warning "No CloudFormation stacks found matching pattern '$filter_pattern'"
        return 0
    fi
    
    printf '%s' "$aws_output"
}

# Function to validate stack is a VPC stack
validate_vpc_stack() {
    local stack_name="$1"
    local region="$2"
    
    # Check if stack contains VPC resources
    local vpc_resources=$(aws cloudformation list-stack-resources \
        --stack-name "$stack_name" \
        --region "$region" \
        --query "StackResourceSummaries[?ResourceType=='AWS::EC2::VPC'].LogicalResourceId" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$vpc_resources" ]]; then
        return 0  # Stack contains VPC resources
    else
        return 1  # Stack doesn't contain VPC resources
    fi
}

# Function to get stack details
get_stack_details() {
    local stack_name="$1"
    local region="$2"
    
    local details=$(aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$region" \
        --query "Stacks[0].{Name:StackName,Status:StackStatus,CreationTime:CreationTime,Description:Description}" \
        --output json 2>/dev/null || echo "{}")
    
    echo "$details"
}

# Function to delete CloudFormation stack
delete_stack() {
    local stack_name="$1"
    local region="$2"
    local dry_run="$3"
    
    if [[ "$dry_run" == "yes" ]]; then
        print_info "DRY RUN: Would delete CloudFormation stack: $stack_name"
        return 0
    fi
    
    print_info "Deleting CloudFormation stack: $stack_name"
    
    if aws cloudformation delete-stack --stack-name "$stack_name" --region "$region"; then
        print_success "Successfully initiated deletion of stack: $stack_name"
        print_info "Stack deletion is in progress. You can monitor it with:"
        print_info "  aws cloudformation describe-stacks --stack-name $stack_name --region $region"
        return 0
    else
        print_error "Failed to delete stack: $stack_name"
        return 1
    fi
}

# Function to confirm deletion
confirm_deletion() {
    local stacks="$1"
    
    # Validate JSON before processing
    if ! echo "$stacks" | jq empty 2>/dev/null; then
        print_error "Invalid JSON in stacks data"
        return 1
    fi
    
    local count=$(echo "$stacks" | jq length)
    
    if [[ "$count" -eq 0 ]]; then
        print_warning "No VPC stacks found to delete"
        return 1
    fi
    
    echo ""
    print_warning "Found $count VPC CloudFormation stack(s) to delete:"
    echo ""
    
    echo "$stacks" | jq -r '.[] | "  - \(.Name) (Status: \(.Status), Created: \(.CreationTime))"'
    echo ""
    
    if [[ "$FORCE" == "yes" ]]; then
        print_info "Force mode enabled, proceeding with deletion..."
        return 0
    fi
    
    read -p "Are you sure you want to delete these stacks? (yes/no): " -r
    echo
    
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        return 0
    else
        print_info "Deletion cancelled"
        return 1
    fi
}

# Function to wait for stack deletion
wait_for_deletion() {
    local stack_name="$1"
    local region="$2"
    local max_wait=1800  # 30 minutes
    local wait_time=0
    local interval=30
    
    print_info "Waiting for stack '$stack_name' to be deleted..."
    
    while [[ $wait_time -lt $max_wait ]]; do
        local status=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --region "$region" \
            --query 'Stacks[0].StackStatus' \
            --output text 2>/dev/null || echo "DELETE_COMPLETE")
        
        if [[ "$status" == "DELETE_COMPLETE" ]]; then
            print_success "Stack '$stack_name' has been successfully deleted"
            return 0
        elif [[ "$status" == "DELETE_FAILED" ]]; then
            print_error "Stack '$stack_name' deletion failed"
            return 1
        else
            print_info "Stack '$stack_name' status: $status (waiting...)"
            sleep $interval
            wait_time=$((wait_time + interval))
        fi
    done
    
    print_warning "Timeout waiting for stack '$stack_name' deletion"
    return 1
}

# Main execution
main() {
    # Log script start
    log_message "INFO" "Script started: $0 $*"
    print_info "Log file: $LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --owner-id)
                OWNER_ID="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --filter-pattern)
                FILTER_PATTERN="$2"
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
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Set default values
    REGION="${REGION:-$DEFAULT_REGION}"
    OWNER_ID="${OWNER_ID:-$DEFAULT_OWNER_ID}"
    FORCE="${FORCE:-$DEFAULT_FORCE}"
    DRY_RUN="${DRY_RUN:-$DEFAULT_DRY_RUN}"
    FILTER_PATTERN="${FILTER_PATTERN:-$DEFAULT_FILTER_PATTERN}"
    
    # Validate required parameters
    if [[ -z "$OWNER_ID" ]]; then
        print_error "AWS Account Owner ID is required"
        print_info "Use --owner-id to specify the AWS account ID"
        print_info "Or use --help for more information"
        exit 1
    fi
    
    # Validate AWS credentials
    validate_aws_credentials
    
    # Get current account for comparison
    local current_account=$(aws sts get-caller-identity --query 'Account' --output text)
    if [[ "$OWNER_ID" != "$current_account" ]]; then
        print_warning "Specified owner ID ($OWNER_ID) differs from current AWS account ($current_account)"
        print_warning "Make sure you have the correct permissions for account $OWNER_ID"
    fi
    
    # 临时文件保存 JSON
    local VPC_STACKS_JSON="/tmp/vpc_stacks_$$.json"
    find_vpc_stacks "$OWNER_ID" "$REGION" "$FILTER_PATTERN" > "$VPC_STACKS_JSON"
    
    # Validate stacks JSON before processing
    if ! jq empty "$VPC_STACKS_JSON" 2>/dev/null; then
        print_error "Invalid JSON response when finding VPC stacks (see $VPC_STACKS_JSON)"
        exit 1
    fi
    
    # Filter stacks that actually contain VPC resources
    local vpc_stacks="[]"
    local stack_count=$(jq length "$VPC_STACKS_JSON")
    
    if [[ $stack_count -gt 0 ]]; then
        print_info "Validating stacks contain VPC resources..."
        
        for i in $(seq 0 $((stack_count - 1))); do
            local stack_name=$(jq -r ".[$i].Name" "$VPC_STACKS_JSON")
            
            if validate_vpc_stack "$stack_name" "$REGION"; then
                local stack_info=$(jq ".[$i]" "$VPC_STACKS_JSON")
                vpc_stacks=$(echo "$vpc_stacks" | jq ". += [${stack_info}]")
                print_info "✓ $stack_name (contains VPC resources)"
            else
                print_info "✗ $stack_name (no VPC resources, skipping)"
            fi
        done
    fi
    
    # Confirm deletion
    if ! confirm_deletion "$vpc_stacks"; then
        rm -f "$VPC_STACKS_JSON"
        exit 0
    fi
    
    # Delete stacks
    local success_count=0
    local total_count=$(echo "$vpc_stacks" | jq length)
    
    if [[ $total_count -gt 0 ]]; then
        echo "$vpc_stacks" | jq -r '.[].Name' | while read -r stack_name; do
            if delete_stack "$stack_name" "$REGION" "$DRY_RUN"; then
                success_count=$((success_count + 1))
                
                # Wait for deletion if not dry run
                if [[ "$DRY_RUN" == "no" ]]; then
                    wait_for_deletion "$stack_name" "$REGION" || true
                fi
            fi
        done
        
        if [[ "$DRY_RUN" == "yes" ]]; then
            print_success "Dry run completed. Would delete $total_count VPC stack(s)"
        else
            print_success "Deletion process completed. Successfully processed $success_count of $total_count stack(s)"
        fi
    else
        print_info "No VPC stacks found to delete"
    fi
    rm -f "$VPC_STACKS_JSON"
}

# Run main function with all arguments
main "$@" 