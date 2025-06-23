#!/bin/bash

# CloudFormation VPC Deletion Script
# 根据同事建议：使用 aws cloudformation delete-stack 来删除整个VPC stack
# 这会保证整个stack内创建的所有resource都被删除

set -euo pipefail

# Default values
DEFAULT_REGION="us-east-1"
DEFAULT_CLUSTER_NAME="my-cluster"
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
    echo ""
    echo "CloudFormation VPC Deletion Script"
    echo "使用 aws cloudformation delete-stack 删除整个VPC stack"
    echo "这会保证整个stack内创建的所有resource都被删除"
    echo ""
    echo "Options:"
    echo "  --cluster-name          Cluster name (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --stack-name            CloudFormation stack name (如果知道具体名称)"
    echo "  --region                AWS region (default: $DEFAULT_REGION)"
    echo "  --force                 Force deletion without confirmation"
    echo "  --dry-run               Show what would be deleted without actually deleting"
    echo "  --help                  Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --cluster-name my-cluster"
    echo "  $0 --stack-name my-cluster-vpc-1750419818"
    echo "  $0 --cluster-name my-cluster --dry-run"
    echo "  $0 --stack-name my-cluster-vpc-1750419818 --force"
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

# Function to find CloudFormation stack by cluster name
find_stack_by_cluster_name() {
    local cluster_name="$1"
    local region="$2"
    
    # Build AWS CLI command with profile if set
    local aws_cmd="aws"
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        aws_cmd="aws --profile ${AWS_PROFILE}"
    fi
    
    # 查找包含cluster name的CloudFormation stack
    local stack_name=$($aws_cmd cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --region "$region" \
        --query "StackSummaries[?contains(StackName, \`$cluster_name\`) && contains(StackName, \`vpc\`)].StackName" \
        --output text)
    
    if [[ "$stack_name" == "None" || -z "$stack_name" ]]; then
        return 1
    fi
    
    echo "$stack_name"
}

# Function to get stack details
get_stack_details() {
    local stack_name="$1"
    local region="$2"
    
    # Build AWS CLI command with profile if set
    local aws_cmd="aws"
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        aws_cmd="aws --profile ${AWS_PROFILE}"
    fi
    
    $aws_cmd cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$region" \
        --query 'Stacks[0]' \
        --output json
}

# Function to list stack resources
list_stack_resources() {
    local stack_name="$1"
    local region="$2"
    
    # Build AWS CLI command with profile if set
    local aws_cmd="aws"
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        aws_cmd="aws --profile ${AWS_PROFILE}"
    fi
    
    print_info "Stack Resources:"
    
    local resources=$($aws_cmd cloudformation list-stack-resources \
        --stack-name "$stack_name" \
        --region "$region" \
        --query 'StackResourceSummaries[?ResourceStatus!=`DELETE_COMPLETE`].[LogicalResourceId,PhysicalResourceId,ResourceType,ResourceStatus]' \
        --output table)
    
    if [[ -n "$resources" ]]; then
        echo "$resources"
    else
        print_info "  No active resources found"
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
        print_info "DRY RUN: Command: $aws_cmd cloudformation delete-stack --stack-name $stack_name --region $region"
        return 0
    fi
    
    print_info "Deleting CloudFormation stack: $stack_name"
    print_info "Command: $aws_cmd cloudformation delete-stack --stack-name $stack_name --region $region"
    
    # 执行删除命令
    $aws_cmd cloudformation delete-stack --stack-name "$stack_name" --region "$region"
    
    if [[ $? -eq 0 ]]; then
        print_success "CloudFormation delete-stack command executed successfully"
        print_info "Waiting for stack deletion to complete..."
        
        # 等待删除完成
        $aws_cmd cloudformation wait stack-delete-complete --stack-name "$stack_name" --region "$region"
        
        if [[ $? -eq 0 ]]; then
            print_success "CloudFormation stack deleted successfully: $stack_name"
        else
            print_warning "Stack deletion may still be in progress. Check AWS Console for status."
        fi
    else
        print_error "Failed to delete CloudFormation stack: $stack_name"
        return 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --stack-name)
            STACK_NAME="$2"
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
CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
REGION=${REGION:-$DEFAULT_REGION}
FORCE=${FORCE:-$DEFAULT_FORCE}
DRY_RUN=${DRY_RUN:-$DEFAULT_DRY_RUN}

# Validate AWS credentials
validate_aws_credentials

# Build AWS CLI command with profile if set
AWS_CMD="aws"
if [[ -n "${AWS_PROFILE:-}" ]]; then
    AWS_CMD="aws --profile ${AWS_PROFILE}"
fi

echo "🗑️  CloudFormation VPC Deletion Script"
echo "======================================"
echo ""
echo "📋 Configuration:"
echo "   Cluster Name: $CLUSTER_NAME"
if [[ -n "${STACK_NAME:-}" ]]; then
    echo "   Stack Name: $STACK_NAME"
fi
echo "   Region: $REGION"
echo "   Force Mode: $FORCE"
echo "   Dry Run: $DRY_RUN"
echo ""

if [[ "$DRY_RUN" == "yes" ]]; then
    print_info "DRY RUN MODE - No resources will be actually deleted"
    echo ""
fi

# 确定要删除的stack名称
if [[ -n "${STACK_NAME:-}" ]]; then
    # 如果直接提供了stack名称
    TARGET_STACK_NAME="$STACK_NAME"
    print_info "Using provided stack name: $TARGET_STACK_NAME"
else
    # 根据cluster name查找stack
    print_info "Searching for CloudFormation stack with cluster name: $CLUSTER_NAME"
    TARGET_STACK_NAME=$(find_stack_by_cluster_name "$CLUSTER_NAME" "$REGION")
    
    if [[ $? -ne 0 ]]; then
        print_error "CloudFormation stack not found for cluster: $CLUSTER_NAME"
        print_info "Available stacks in region $REGION:"
        $AWS_CMD cloudformation list-stacks \
            --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
            --region "$REGION" \
            --query 'StackSummaries[].{StackName:StackName,CreationTime:CreationTime}' \
            --output table
        exit 1
    fi
    
    print_info "Found CloudFormation stack: $TARGET_STACK_NAME"
fi

# 验证stack是否存在
if ! $AWS_CMD cloudformation describe-stacks --stack-name "$TARGET_STACK_NAME" --region "$REGION" &> /dev/null; then
    print_error "CloudFormation stack not found: $TARGET_STACK_NAME"
    exit 1
fi

# 获取stack详情
print_info "Stack Details:"
STACK_DETAILS=$(get_stack_details "$TARGET_STACK_NAME" "$REGION")
echo "$STACK_DETAILS" | jq -r '. | "  Stack Name: \(.StackName)\n  Stack Status: \(.StackStatus)\n  Creation Time: \(.CreationTime)\n  Description: \(.Description // "N/A")"'

# 列出stack资源
list_stack_resources "$TARGET_STACK_NAME" "$REGION"

# 跳过确认如果force模式启用
if [[ "$FORCE" != "yes" && "$DRY_RUN" != "yes" ]]; then
    echo ""
    print_warning "⚠️  重要提醒：这将删除整个CloudFormation stack和所有相关资源！"
    echo "   - Stack: $TARGET_STACK_NAME"
    echo "   - 所有VPC资源（VPC、子网、路由表、安全组等）"
    echo "   - 所有网络资源（NAT网关、互联网网关等）"
    echo "   - 其他相关AWS资源"
    echo ""
    print_info "💡 同事建议：使用 aws cloudformation delete-stack 确保所有资源都被正确删除"
    echo ""
    read -p "确定要删除这个CloudFormation stack吗？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "删除操作已取消"
        exit 0
    fi
fi

# 删除CloudFormation stack
echo "🏗️  Deleting CloudFormation Stack"
echo "-----------------------------------"
delete_cloudformation_stack "$TARGET_STACK_NAME" "$REGION" "$DRY_RUN"

# 最终总结
echo ""
echo "📊 Deletion Summary"
echo "==================="
if [[ "$DRY_RUN" == "yes" ]]; then
    print_info "DRY RUN COMPLETED - No resources were actually deleted"
    echo ""
    echo "要执行实际删除，请运行脚本时不使用 --dry-run"
else
    print_success "CloudFormation stack deletion completed!"
    echo "✅ Stack: $TARGET_STACK_NAME"
    echo ""
    echo "🎉 根据同事建议，使用 aws cloudformation delete-stack 成功删除了整个stack！"
    echo "   这确保了stack内创建的所有资源都被正确删除。"
fi

echo ""
echo "💡 Tips:"
echo "   - 检查AWS Console确认所有资源都已删除"
echo "   - 监控AWS费用确保没有意外收费"
echo "   - 如果删除失败，检查是否有依赖关系需要手动处理"
echo "   - 同事建议：始终使用 aws cloudformation delete-stack 来删除VPC stack"
echo "" 