#!/bin/bash

# 08-verify-cleanup.sh
# 验证清理脚本 - 检查disconnected cluster的清理是否完全成功
# 验证本地文件、bastion host、AWS资源和OpenShift集群的清理状态

set -euo pipefail

# 默认值
DEFAULT_CLUSTER_NAME="disconnected-cluster"
DEFAULT_INSTALL_DIR="./openshift-install"
DEFAULT_INFRA_OUTPUT_DIR="./infra-output"
DEFAULT_SYNC_OUTPUT_DIR="./sync-output"
DEFAULT_REGION="us-east-1"
DEFAULT_VERIFY_LEVEL="all"  # all, local, bastion, aws, cluster

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 在脚本开头定义全局数组
UNCLEANED_INSTANCES=()
UNCLEANED_SECURITY_GROUPS=()
UNCLEANED_VPCS=()
UNCLEANED_SSH_KEYS=()

# 显示使用说明
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Disconnected Cluster Cleanup Verification Script"
    echo "验证disconnected cluster的清理是否完全成功"
    echo ""
    echo "Options:"
    echo "  --cluster-name        Cluster name (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --install-dir         Installation directory (default: $DEFAULT_INSTALL_DIR)"
    echo "  --infra-output-dir    Infrastructure output directory (default: $DEFAULT_INFRA_OUTPUT_DIR)"
    echo "  --sync-output-dir     Sync output directory (default: $DEFAULT_SYNC_OUTPUT_DIR)"
    echo "  --region              AWS region (default: $DEFAULT_REGION)"
    echo "  --verify-level        Verify level: all, local, bastion, aws, cluster (default: $DEFAULT_VERIFY_LEVEL)"
    echo "  --skip-local          Skip local file verification (useful during cleanup process)"
    echo "  --help                Display this help message"
    echo ""
    echo "Verify Levels:"
    echo "  all      - Verify everything (local, bastion, aws, cluster)"
    echo "  local    - Verify local files only"
    echo "  bastion  - Verify bastion host only"
    echo "  aws      - Verify AWS resources only"
    echo "  cluster  - Verify OpenShift cluster only"
    echo ""
    echo "Examples:"
    echo "  $0 --verify-level local        # 只验证本地文件"
    echo "  $0 --verify-level aws          # 只验证AWS资源"
    echo "  $0 --cluster-name my-cluster   # 验证特定集群"
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
    
    print_success "前置条件检查通过"
}

# 验证本地文件清理
verify_local_files() {
    print_info "验证本地文件清理..."
    
    local issues_found=0
    local items_to_check=(
        "$INSTALL_DIR"
        "$INFRA_OUTPUT_DIR"
        "$SYNC_OUTPUT_DIR"
        "./backups"
        "./logs"
        "install-config.yaml"
        "install-config.yaml.backup"
        "kubeconfig"
        "auth/kubeconfig"
    )
    
    # 检查目录
    for item in "${items_to_check[@]}"; do
        if [[ -d "$item" ]]; then
            local file_count=$(find "$item" -type f 2>/dev/null | wc -l)
            print_warning "发现未清理的目录: $item ($file_count 个文件)"
            ((issues_found++))
        elif [[ -f "$item" ]]; then
            print_warning "发现未清理的文件: $item"
            ((issues_found++))
        fi
    done
    
    # 检查.pem和.key文件
    for pem_file in *.pem *.key; do
        if [[ -f "$pem_file" ]]; then
            print_warning "发现未清理的密钥文件: $pem_file"
            ((issues_found++))
        fi
    done
    
    if [[ $issues_found -eq 0 ]]; then
        print_success "本地文件清理验证通过 - 所有文件已清理"
    else
        print_error "本地文件清理验证失败 - 发现 $issues_found 个未清理的项目"
    fi
    
    return $issues_found
}

# 验证bastion host清理
verify_bastion_host() {
    print_info "验证bastion host清理..."
    
    # 检查是否有备份的bastion信息
    local bastion_info_found=false
    local backup_files=(
        "./backups/bastion-public-ip"
        "./backups/bastion-key.pem"
        "./backups/bastion-instance-id"
    )
    
    for backup_file in "${backup_files[@]}"; do
        if [[ -f "$backup_file" ]]; then
            bastion_info_found=true
            break
        fi
    done
    
    if [[ "$bastion_info_found" == "false" ]]; then
        print_info "没有找到bastion信息，无法验证bastion清理状态"
        return 0
    fi
    
    # 尝试连接bastion
    local bastion_ip=""
    local ssh_key=""
    
    if [[ -f "./backups/bastion-public-ip" ]]; then
        bastion_ip=$(cat "./backups/bastion-public-ip")
    fi
    
    if [[ -f "./backups/bastion-key.pem" ]]; then
        ssh_key="./backups/bastion-key.pem"
        chmod 600 "$ssh_key"
    fi
    
    if [[ -n "$bastion_ip" && -n "$ssh_key" ]]; then
        print_info "尝试连接bastion host: $bastion_ip"
        
        if ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$bastion_ip" "echo 'SSH connection test'" &> /dev/null; then
            print_warning "Bastion host仍然可以访问: $bastion_ip"
            
            # 检查bastion上的文件
            local bastion_files=$(ssh -i "$ssh_key" -o StrictHostKeyChecking=no ubuntu@"$bastion_ip" "
                find /home/ubuntu/disconnected-cluster -type f 2>/dev/null | wc -l
            " 2>/dev/null || echo "0")
            
            if [[ "$bastion_files" -gt 0 ]]; then
                print_warning "Bastion上仍有 $bastion_files 个文件未清理"
                return 1
            else
                print_success "Bastion host文件清理验证通过"
            fi
        else
            print_success "Bastion host无法访问，可能已被删除"
        fi
    else
        print_info "Bastion信息不完整，跳过验证"
    fi
    
    return 0
}

# 验证AWS资源清理
verify_aws_resources() {
    print_info "验证AWS资源清理..."
    
    local issues_found=0
    
    # 检查是否有备份的AWS资源信息
    local aws_info_found=false
    local backup_files=(
        "./backups/vpc-id"
        "./backups/bastion-instance-id"
        "./backups/cluster-security-group-id"
        "./backups/bastion-security-group-id"
    )
    
    for backup_file in "${backup_files[@]}"; do
        if [[ -f "$backup_file" ]]; then
            aws_info_found=true
            break
        fi
    done
    
    if [[ "$aws_info_found" == "false" ]]; then
        print_info "没有找到AWS资源信息，尝试通过标签查找资源"
        
        # 通过标签查找资源
        local tagged_resources=$(aws ec2 describe-instances \
            --region "$REGION" \
            --filters "Name=tag:Name,Values=*${CLUSTER_NAME}*" "Name=instance-state-name,Values=running,stopped" \
            --query 'Reservations[].Instances[].{InstanceId:InstanceId,Name:Tags[?Key==`Name`].Value|[0]}' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$tagged_resources" ]]; then
            print_warning "发现标记的实例:"
            local instance_count=0
            while read -r instance_id name; do
                if [[ -n "$instance_id" && "$instance_id" != "None" ]]; then
                    print_warning "  - $instance_id ($name)"
                    UNCLEANED_INSTANCES+=("$instance_id")
                    ((instance_count++))
                fi
            done <<< "$tagged_resources"
            ((issues_found += instance_count))
        fi
        
        # 检查安全组
        local security_groups=$(aws ec2 describe-security-groups \
            --region "$REGION" \
            --filters "Name=group-name,Values=*${CLUSTER_NAME}*" \
            --query 'SecurityGroups[].{GroupId:GroupId,GroupName:GroupName}' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$security_groups" ]]; then
            print_warning "发现标记的安全组:"
            local sg_count=0
            while read -r group_id group_name; do
                if [[ -n "$group_id" && "$group_id" != "None" ]]; then
                    print_warning "  - $group_id ($group_name)"
                    UNCLEANED_SECURITY_GROUPS+=("$group_id")
                    ((sg_count++))
                fi
            done <<< "$security_groups"
            ((issues_found += sg_count))
        fi
        
        # 检查VPC
        local vpcs=$(aws ec2 describe-vpcs \
            --region "$REGION" \
            --filters "Name=tag:Name,Values=*${CLUSTER_NAME}*" \
            --query 'Vpcs[].{VpcId:VpcId,Name:Tags[?Key==`Name`].Value|[0]}' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$vpcs" ]]; then
            print_warning "发现标记的VPC:"
            local vpc_count=0
            while read -r vpc_id name; do
                if [[ -n "$vpc_id" && "$vpc_id" != "None" ]]; then
                    print_warning "  - $vpc_id ($name)"
                    UNCLEANED_VPCS+=("$vpc_id")
                    ((vpc_count++))
                fi
            done <<< "$vpcs"
            ((issues_found += vpc_count))
        fi
        
        # 检查SSH密钥对
        local ssh_keys=$(aws ec2 describe-key-pairs \
            --region "$REGION" \
            --query "KeyPairs[?contains(KeyName, '${CLUSTER_NAME}')].{KeyName:KeyName}" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$ssh_keys" ]]; then
            print_warning "发现SSH密钥对:"
            local key_count=0
            while read -r key_name; do
                if [[ -n "$key_name" && "$key_name" != "None" ]]; then
                    print_warning "  - $key_name"
                    UNCLEANED_SSH_KEYS+=("$key_name")
                    ((key_count++))
                fi
            done <<< "$ssh_keys"
            ((issues_found += key_count))
        fi
    else
        # 使用备份信息验证
        local vpc_id=""
        local bastion_instance_id=""
        local cluster_sg_id=""
        local bastion_sg_id=""
        
        if [[ -f "./backups/vpc-id" ]]; then
            vpc_id=$(cat "./backups/vpc-id")
        fi
        
        if [[ -f "./backups/bastion-instance-id" ]]; then
            bastion_instance_id=$(cat "./backups/bastion-instance-id")
        fi
        
        if [[ -f "./backups/cluster-security-group-id" ]]; then
            cluster_sg_id=$(cat "./backups/cluster-security-group-id")
        fi
        
        if [[ -f "./backups/bastion-security-group-id" ]]; then
            bastion_sg_id=$(cat "./backups/bastion-security-group-id")
        fi
        
        # 验证VPC
        if [[ -n "$vpc_id" && "$vpc_id" != "None" ]]; then
            if aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$REGION" &> /dev/null; then
                print_warning "VPC仍然存在: $vpc_id"
                UNCLEANED_VPCS+=("$vpc_id")
                ((issues_found++))
            else
                print_success "VPC已删除: $vpc_id"
            fi
        fi
        
        # 验证实例
        if [[ -n "$bastion_instance_id" && "$bastion_instance_id" != "None" ]]; then
            if aws ec2 describe-instances --instance-ids "$bastion_instance_id" --region "$REGION" &> /dev/null; then
                print_warning "Bastion实例仍然存在: $bastion_instance_id"
                UNCLEANED_INSTANCES+=("$bastion_instance_id")
                ((issues_found++))
            else
                print_success "Bastion实例已删除: $bastion_instance_id"
            fi
        fi
        
        # 验证安全组
        if [[ -n "$cluster_sg_id" && "$cluster_sg_id" != "None" ]]; then
            if aws ec2 describe-security-groups --group-ids "$cluster_sg_id" --region "$REGION" &> /dev/null; then
                print_warning "集群安全组仍然存在: $cluster_sg_id"
                UNCLEANED_SECURITY_GROUPS+=("$cluster_sg_id")
                ((issues_found++))
            else
                print_success "集群安全组已删除: $cluster_sg_id"
            fi
        fi
        
        if [[ -n "$bastion_sg_id" && "$bastion_sg_id" != "None" ]]; then
            if aws ec2 describe-security-groups --group-ids "$bastion_sg_id" --region "$REGION" &> /dev/null; then
                print_warning "Bastion安全组仍然存在: $bastion_sg_id"
                UNCLEANED_SECURITY_GROUPS+=("$bastion_sg_id")
                ((issues_found++))
            else
                print_success "Bastion安全组已删除: $bastion_sg_id"
            fi
        fi
    fi
    
    if [[ $issues_found -eq 0 ]]; then
        print_success "AWS资源清理验证通过 - 所有资源已清理"
    else
        print_error "AWS资源清理验证失败 - 发现 $issues_found 个未清理的资源"
    fi
    
    return $issues_found
}

# 验证OpenShift集群清理
verify_openshift_cluster() {
    print_info "验证OpenShift集群清理..."
    
    # 检查是否有备份的bastion信息
    if [[ ! -f "./backups/bastion-public-ip" ]] || [[ ! -f "./backups/bastion-key.pem" ]]; then
        print_info "没有找到bastion信息，无法验证集群清理状态"
        return 0
    fi
    
    local bastion_ip=$(cat "./backups/bastion-public-ip")
    local ssh_key="./backups/bastion-key.pem"
    
    # 检查SSH连接
    if ! ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$bastion_ip" "echo 'SSH connection test'" &> /dev/null; then
        print_success "Bastion host无法访问，集群可能已被删除"
        return 0
    fi
    
    print_info "连接到bastion host: $bastion_ip"
    
    # 检查集群是否仍在运行
    local cluster_status=$(ssh -i "$ssh_key" -o StrictHostKeyChecking=no ubuntu@"$bastion_ip" "
        if [[ -f /home/ubuntu/disconnected-cluster/openshift-install/auth/kubeconfig ]]; then
            export KUBECONFIG=/home/ubuntu/disconnected-cluster/openshift-install/auth/kubeconfig
            if oc whoami &> /dev/null; then
                echo 'running'
            else
                echo 'not_running'
            fi
        else
            echo 'not_found'
        fi
    " 2>/dev/null || echo "error")
    
    if [[ "$cluster_status" == "running" ]]; then
        print_warning "OpenShift集群仍在运行"
        return 1
    elif [[ "$cluster_status" == "not_running" ]]; then
        print_success "OpenShift集群已停止运行"
    elif [[ "$cluster_status" == "not_found" ]]; then
        print_success "OpenShift集群配置文件已删除"
    else
        print_info "无法确定集群状态"
    fi
    
    return 0
}

# 生成验证报告
generate_verification_report() {
    local report_file="verification-report-${CLUSTER_NAME}-$(date +%Y%m%d-%H%M%S).txt"
    local total_issues=$1
    
    cat > "$report_file" <<EOF
OpenShift Disconnected Cluster Cleanup Verification Report
=========================================================
Cluster: $CLUSTER_NAME
Verify Level: $VERIFY_LEVEL
Date: $(date)
Total Issues Found: $total_issues

Verification Summary:
- Local files: $([[ "$VERIFY_LEVEL" == "all" || "$VERIFY_LEVEL" == "local" ]] && echo "Verified" || echo "Skipped")
- Bastion host: $([[ "$VERIFY_LEVEL" == "all" || "$VERIFY_LEVEL" == "bastion" ]] && echo "Verified" || echo "Skipped")
- AWS resources: $([[ "$VERIFY_LEVEL" == "all" || "$VERIFY_LEVEL" == "aws" ]] && echo "Verified" || echo "Skipped")
- Cluster: $([[ "$VERIFY_LEVEL" == "all" || "$VERIFY_LEVEL" == "cluster" ]] && echo "Verified" || echo "Skipped")

Verification Result: $([[ $total_issues -eq 0 ]] && echo "PASSED" || echo "FAILED")

Uncleaned Resources:
EOF
    # 追加所有未清理资源ID
    if [[ -n "${UNCLEANED_INSTANCES:-}" ]]; then
      for id in ${UNCLEANED_INSTANCES[@]}; do
        echo "- Instance: $id" >> "$report_file"
      done
    fi
    if [[ -n "${UNCLEANED_SECURITY_GROUPS:-}" ]]; then
      for id in ${UNCLEANED_SECURITY_GROUPS[@]}; do
        echo "- SecurityGroup: $id" >> "$report_file"
      done
    fi
    if [[ -n "${UNCLEANED_VPCS:-}" ]]; then
      for id in ${UNCLEANED_VPCS[@]}; do
        echo "- VPC: $id" >> "$report_file"
      done
    fi
    if [[ -n "${UNCLEANED_SSH_KEYS:-}" ]]; then
      for id in ${UNCLEANED_SSH_KEYS[@]}; do
        echo "- KeyPair: $id" >> "$report_file"
      done
    fi
    cat >> "$report_file" <<EOF

Next Steps:
1. If verification failed, review the issues above
2. Manually clean up any remaining resources
3. Re-run verification after cleanup
4. Consider using AWS Cost Explorer to verify cost reduction

Notes:
- Some resources may take time to be fully deleted
- Check AWS console for any orphaned resources
- Consider using AWS Cost Explorer to verify cost reduction
EOF
    
    if [[ $total_issues -eq 0 ]]; then
        print_success "验证报告已生成: $report_file (PASSED)"
    else
        print_warning "验证报告已生成: $report_file (FAILED - $total_issues issues)"
    fi
}

# 主函数
main() {
    # 解析命令行参数
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
            --region)
                REGION="$2"
                shift 2
                ;;
            --verify-level)
                VERIFY_LEVEL="$2"
                shift 2
                ;;
            --skip-local)
                SKIP_LOCAL="yes"
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
    CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}
    INFRA_OUTPUT_DIR=${INFRA_OUTPUT_DIR:-$DEFAULT_INFRA_OUTPUT_DIR}
    SYNC_OUTPUT_DIR=${SYNC_OUTPUT_DIR:-$DEFAULT_SYNC_OUTPUT_DIR}
    REGION=${REGION:-$DEFAULT_REGION}
    VERIFY_LEVEL=${VERIFY_LEVEL:-$DEFAULT_VERIFY_LEVEL}
    SKIP_LOCAL=${SKIP_LOCAL:-no}
    
    # 显示脚本头部
    echo "🔍 Disconnected Cluster Cleanup Verification Script"
    echo "=================================================="
    echo ""
    echo "📋 Configuration:"
    echo "   Cluster Name: $CLUSTER_NAME"
    echo "   Install Directory: $INSTALL_DIR"
    echo "   Infra Output Directory: $INFRA_OUTPUT_DIR"
    echo "   Sync Output Directory: $SYNC_OUTPUT_DIR"
    echo "   Region: $REGION"
    echo "   Verify Level: $VERIFY_LEVEL"
    echo ""
    
    # 检查前置条件
    check_prerequisites
    
    local total_issues=0
    
    # 根据验证级别执行相应的验证操作
    case "$VERIFY_LEVEL" in
        "all")
            if [[ "$SKIP_LOCAL" != "yes" ]]; then
                verify_local_files || ((total_issues++))
            else
                print_info "跳过本地文件验证"
            fi
            verify_bastion_host || ((total_issues++))
            verify_aws_resources || ((total_issues++))
            verify_openshift_cluster || ((total_issues++))
            ;;
        "local")
            verify_local_files || ((total_issues++))
            ;;
        "bastion")
            verify_bastion_host || ((total_issues++))
            ;;
        "aws")
            verify_aws_resources || ((total_issues++))
            ;;
        "cluster")
            verify_openshift_cluster || ((total_issues++))
            ;;
        *)
            print_error "无效的验证级别: $VERIFY_LEVEL"
            usage
            exit 1
            ;;
    esac
    
    # 生成验证报告
    generate_verification_report $total_issues
    
    echo ""
    if [[ $total_issues -eq 0 ]]; then
        print_success "验证完成 - 所有清理操作都成功!"
    else
        print_error "验证完成 - 发现 $total_issues 个问题需要处理"
    fi
    
    echo ""
    echo "💡 Tips:"
    echo "  - 使用 --verify-level 指定验证范围"
    echo "  - 检查生成的验证报告了解详细信息"
    echo "  - 手动清理任何剩余的资源"
    echo "  - 使用AWS Cost Explorer验证成本减少"
    
    exit $total_issues
}

# 运行主函数
main "$@" 