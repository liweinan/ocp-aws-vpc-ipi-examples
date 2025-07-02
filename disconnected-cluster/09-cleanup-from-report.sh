#!/bin/bash

# 09-cleanup-from-report.sh
# 基于验证报告进行清理脚本
# 自动清理验证过程中发现的所有资源

set -euo pipefail

# 默认值
DEFAULT_REPORT_FILE=""
DEFAULT_REGION="us-east-1"
DEFAULT_DRY_RUN="no"
DEFAULT_FORCE="no"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 显示使用说明
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Cleanup from Verification Report Script"
    echo "基于验证报告自动清理发现的资源"
    echo ""
    echo "Options:"
    echo "  --report-file         Verification report file (required)"
    echo "  --region              AWS region (default: $DEFAULT_REGION)"
    echo "  --dry-run             Show what would be done without actually doing it"
    echo "  --force               Skip confirmation prompts"
    echo "  --help                Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --report-file verification-report-disconnected-cluster-20250702-210144.txt"
    echo "  $0 --report-file verification-report-disconnected-cluster-20250702-210144.txt --dry-run"
    echo "  $0 --report-file verification-report-disconnected-cluster-20250702-210144.txt --force"
}

# 打印彩色输出
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

# 检查前置条件
check_prerequisites() {
    print_info "检查前置条件..."
    
    # 检查AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found"
        exit 1
    fi
    
    # 检查AWS凭证
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured"
        exit 1
    fi
    
    # 检查报告文件
    if [[ ! -f "$REPORT_FILE" ]]; then
        print_error "报告文件不存在: $REPORT_FILE"
        exit 1
    fi
    
    print_success "前置条件检查通过"
}

# 解析验证报告
parse_verification_report() {
    print_info "解析验证报告: $REPORT_FILE"
    
    local report_content=$(cat "$REPORT_FILE")
    local in_uncleaned=0
    local instances=()
    local security_groups=()
    local vpcs=()
    local ssh_keys=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^Uncleaned\ Resources: ]]; then
            in_uncleaned=1
            continue
        fi
        if [[ $in_uncleaned -eq 1 ]]; then
            if [[ "$line" =~ ^-\ Instance:\ (i-[a-z0-9]+) ]]; then
                instances+=("${BASH_REMATCH[1]}")
            elif [[ "$line" =~ ^-\ SecurityGroup:\ (sg-[a-z0-9]+) ]]; then
                security_groups+=("${BASH_REMATCH[1]}")
            elif [[ "$line" =~ ^-\ VPC:\ (.+)$ ]]; then
                vpcs+=("${BASH_REMATCH[1]}")
            elif [[ "$line" =~ ^-\ KeyPair:\ (.+)$ ]]; then
                ssh_keys+=("${BASH_REMATCH[1]}")
            elif [[ "$line" =~ ^$ ]]; then
                break
            fi
        fi
    done <<< "$report_content"
    PARSED_INSTANCES=("${instances[@]:-}")
    PARSED_SECURITY_GROUPS=("${security_groups[@]:-}")
    PARSED_VPCS=("${vpcs[@]:-}")
    PARSED_SSH_KEYS=("${ssh_keys[@]:-}")
    print_info "解析完成:"
    print_info "  实例: ${#PARSED_INSTANCES[@]} 个"
    print_info "  安全组: ${#PARSED_SECURITY_GROUPS[@]} 个"
    print_info "  VPC: ${#PARSED_VPCS[@]} 个"
    print_info "  SSH密钥对: ${#PARSED_SSH_KEYS[@]} 个"
}

# 清理EC2实例
cleanup_instances() {
    local dry_run="$1"
    local force="$2"
    
    if [[ ${#PARSED_INSTANCES[@]} -eq 0 ]]; then
        print_info "没有发现需要清理的实例"
        return 0
    fi
    
    print_info "清理EC2实例..."
    
    local instance_ids=()
    for instance_info in "${PARSED_INSTANCES[@]}"; do
        local instance_id=$(echo "$instance_info" | cut -d: -f1)
        local instance_name=$(echo "$instance_info" | cut -d: -f2)
        instance_ids+=("$instance_id")
        
        if [[ "$dry_run" == "yes" ]]; then
            print_info "DRY RUN: 将终止实例 $instance_id ($instance_name)"
        else
            print_info "终止实例: $instance_id ($instance_name)"
            if aws ec2 terminate-instances --instance-ids "$instance_id" --region "$REGION" &> /dev/null; then
                print_success "已终止实例: $instance_id"
            else
                print_warning "终止实例失败: $instance_id"
            fi
        fi
    done
    
    if [[ "$dry_run" != "yes" && ${#instance_ids[@]} -gt 0 ]]; then
        print_info "等待实例终止完成..."
        for instance_id in "${instance_ids[@]}"; do
            aws ec2 wait instance-terminated --instance-ids "$instance_id" --region "$REGION" 2>/dev/null || true
        done
    fi
}

# 清理安全组
cleanup_security_groups() {
    local dry_run="$1"
    local force="$2"
    
    if [[ ${#PARSED_SECURITY_GROUPS[@]} -eq 0 ]]; then
        print_info "没有发现需要清理的安全组"
        return 0
    fi
    
    print_info "清理安全组..."
    
    for sg_info in "${PARSED_SECURITY_GROUPS[@]}"; do
        local sg_id=$(echo "$sg_info" | cut -d: -f1)
        local sg_name=$(echo "$sg_info" | cut -d: -f2)
        
        if [[ "$dry_run" == "yes" ]]; then
            print_info "DRY RUN: 将删除安全组 $sg_id ($sg_name)"
        else
            print_info "删除安全组: $sg_id ($sg_name)"
            
            # 尝试删除安全组规则
            print_info "  清理安全组规则: $sg_id"
            aws ec2 revoke-security-group-ingress --group-id "$sg_id" --protocol all --port -1 --cidr 0.0.0.0/0 --region "$REGION" 2>/dev/null || true
            aws ec2 revoke-security-group-egress --group-id "$sg_id" --protocol all --port -1 --cidr 0.0.0.0/0 --region "$REGION" 2>/dev/null || true
            
            # 尝试删除安全组
            if aws ec2 delete-security-group --group-id "$sg_id" --region "$REGION" &> /dev/null; then
                print_success "已删除安全组: $sg_id"
            else
                print_warning "删除安全组失败: $sg_id (可能仍在使用中)"
            fi
        fi
    done
}

# 清理VPC
cleanup_vpcs() {
    local dry_run="$1"
    local force="$2"
    
    if [[ ${#PARSED_VPCS[@]} -eq 0 ]]; then
        print_info "没有发现需要清理的VPC"
        return 0
    fi
    
    print_info "清理VPC..."
    
    for vpc_name in "${PARSED_VPCS[@]}"; do
        # 通过VPC名称查找VPC ID
        local vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$vpc_name" --query 'Vpcs[0].VpcId' --output text --region "$REGION" 2>/dev/null)
        
        if [[ "$vpc_id" == "None" || -z "$vpc_id" ]]; then
            print_warning "找不到VPC: $vpc_name"
            continue
        fi
        
        if [[ "$dry_run" == "yes" ]]; then
            print_info "DRY RUN: 将删除VPC $vpc_id ($vpc_name)"
        else
            print_info "删除VPC: $vpc_id ($vpc_name)"
            
            # 使用force-delete-vpc.sh脚本删除VPC
            if [[ -f "./force-delete-vpc.sh" ]]; then
                if ./force-delete-vpc.sh "$vpc_id" "$REGION" &> /dev/null; then
                    print_success "已删除VPC: $vpc_id"
                else
                    print_warning "删除VPC失败: $vpc_id"
                fi
            else
                print_warning "找不到force-delete-vpc.sh脚本，请手动删除VPC: $vpc_id"
            fi
        fi
    done
}

# 清理SSH密钥对
cleanup_ssh_keys() {
    local dry_run="$1"
    local force="$2"
    
    if [[ ${#PARSED_SSH_KEYS[@]} -eq 0 ]]; then
        print_info "没有发现需要清理的SSH密钥对"
        return 0
    fi
    
    print_info "清理SSH密钥对..."
    
    for key_name in "${PARSED_SSH_KEYS[@]}"; do
        if [[ "$dry_run" == "yes" ]]; then
            print_info "DRY RUN: 将删除SSH密钥对 $key_name"
        else
            print_info "删除SSH密钥对: $key_name"
            if aws ec2 delete-key-pair --key-name "$key_name" --region "$REGION" &> /dev/null; then
                print_success "已删除SSH密钥对: $key_name"
            else
                print_warning "删除SSH密钥对失败: $key_name"
            fi
        fi
    done
}

# 生成清理报告
generate_cleanup_report() {
    local report_file="cleanup-from-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$report_file" <<EOF
Cleanup from Verification Report
===============================
Source Report: $REPORT_FILE
Date: $(date)
Region: $REGION
Dry Run: $DRY_RUN

Resources Found:
- Instances: ${#PARSED_INSTANCES[@]}
- Security Groups: ${#PARSED_SECURITY_GROUPS[@]}
- VPCs: ${#PARSED_VPCS[@]}
- SSH Keys: ${#PARSED_SSH_KEYS[@]}

Cleanup Summary:
- Instances: $([[ "$DRY_RUN" == "yes" ]] && echo "Would terminate" || echo "Terminated")
- Security Groups: $([[ "$DRY_RUN" == "yes" ]] && echo "Would delete" || echo "Deleted")
- VPCs: $([[ "$DRY_RUN" == "yes" ]] && echo "Would delete" || echo "Deleted")
- SSH Keys: $([[ "$DRY_RUN" == "yes" ]] && echo "Would delete" || echo "Deleted")

Next Steps:
1. Verify that all resources have been cleaned up
2. Check AWS console for any remaining resources
3. Run verification script again to confirm cleanup
4. Consider using AWS Cost Explorer to verify cost reduction

Notes:
- Some resources may take time to be fully deleted
- Check AWS console for any orphaned resources
- Consider using AWS Cost Explorer to verify cost reduction
EOF
    
    print_success "清理报告已生成: $report_file"
}

# 主函数
main() {
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --report-file)
                REPORT_FILE="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="yes"
                shift
                ;;
            --force)
                FORCE="yes"
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                print_error "未知选项: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # 设置默认值
    REPORT_FILE=${REPORT_FILE:-$DEFAULT_REPORT_FILE}
    REGION=${REGION:-$DEFAULT_REGION}
    DRY_RUN=${DRY_RUN:-$DEFAULT_DRY_RUN}
    FORCE=${FORCE:-$DEFAULT_FORCE}
    
    # 检查必需参数
    if [[ -z "$REPORT_FILE" ]]; then
        print_error "必须指定报告文件"
        usage
        exit 1
    fi
    
    # 显示脚本头部
    echo "🧹 Cleanup from Verification Report Script"
    echo "=========================================="
    echo ""
    echo "📋 Configuration:"
    echo "   Report File: $REPORT_FILE"
    echo "   Region: $REGION"
    echo "   Dry Run: $DRY_RUN"
    echo "   Force: $FORCE"
    echo ""
    
    # 检查前置条件
    check_prerequisites
    
    # 解析验证报告
    parse_verification_report
    
    # 显示将要清理的资源
    local total_resources=$((${#PARSED_INSTANCES[@]} + ${#PARSED_SECURITY_GROUPS[@]} + ${#PARSED_VPCS[@]} + ${#PARSED_SSH_KEYS[@]}))
    
    if [[ $total_resources -eq 0 ]]; then
        print_info "没有发现需要清理的资源"
        exit 0
    fi
    
    echo ""
    print_warning "发现 $total_resources 个资源需要清理:"
    echo "  实例: ${#PARSED_INSTANCES[@]} 个"
    echo "  安全组: ${#PARSED_SECURITY_GROUPS[@]} 个"
    echo "  VPC: ${#PARSED_VPCS[@]} 个"
    echo "  SSH密钥对: ${#PARSED_SSH_KEYS[@]} 个"
    echo ""
    
    if [[ "$DRY_RUN" == "yes" ]]; then
        print_info "DRY RUN: 将清理上述资源"
    else
        if [[ "$FORCE" != "yes" ]]; then
            print_warning "⚠️  这将永久删除AWS资源!"
            read -p "确定要删除这些资源吗? (yes/no): " -r
            echo
            if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                print_info "清理已取消"
                exit 0
            fi
        fi
    fi
    
    # 执行清理操作
    cleanup_instances "$DRY_RUN" "$FORCE"
    cleanup_security_groups "$DRY_RUN" "$FORCE"
    cleanup_vpcs "$DRY_RUN" "$FORCE"
    cleanup_ssh_keys "$DRY_RUN" "$FORCE"
    
    # 生成清理报告
    generate_cleanup_report
    
    echo ""
    if [[ "$DRY_RUN" == "yes" ]]; then
        print_success "Dry run 完成 - 没有实际删除任何资源"
    else
        print_success "基于报告的清理完成!"
    fi
    
    echo ""
    echo "💡 Tips:"
    echo "  - 使用 --dry-run 预览将要删除的资源"
    echo "  - 使用 --force 跳过确认提示"
    echo "  - 运行验证脚本确认清理结果"
    echo "  - 检查AWS控制台确认资源已完全删除"
    echo "  - 使用AWS Cost Explorer验证成本减少"
}

# 运行主函数
main "$@" 