#!/bin/bash

# 07-cleanup.sh
# 清理脚本 - 清理disconnected cluster的所有资源
# 包括本地文件、bastion host文件、AWS资源和OpenShift集群

set -euo pipefail

# 默认值
DEFAULT_CLUSTER_NAME="disconnected-cluster"
DEFAULT_INSTALL_DIR="./openshift-install"
DEFAULT_INFRA_OUTPUT_DIR="./infra-output"
DEFAULT_SYNC_OUTPUT_DIR="./sync-output"
DEFAULT_REGION="us-east-1"
DEFAULT_CLEANUP_LEVEL="all"  # all, local, bastion, aws, cluster

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
    echo "Disconnected Cluster Cleanup Script"
    echo "清理disconnected cluster的所有资源"
    echo ""
    echo "Options:"
    echo "  --cluster-name        Cluster name (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --install-dir         Installation directory (default: $DEFAULT_INSTALL_DIR)"
    echo "  --infra-output-dir    Infrastructure output directory (default: $DEFAULT_INFRA_OUTPUT_DIR)"
    echo "  --sync-output-dir     Sync output directory (default: $DEFAULT_SYNC_OUTPUT_DIR)"
    echo "  --region              AWS region (default: $DEFAULT_REGION)"
    echo "  --cleanup-level       Cleanup level: all, local, bastion, aws, cluster (default: $DEFAULT_CLEANUP_LEVEL)"
    echo "  --dry-run             Show what would be done without actually doing it"
    echo "  --force               Skip confirmation prompts"
    echo "  --help                Display this help message"
    echo ""
    echo "Cleanup Levels:"
    echo "  all      - Clean everything (local, bastion, aws, cluster)"
    echo "  local    - Clean local files only"
    echo "  bastion  - Clean bastion host files only"
    echo "  aws      - Clean AWS resources only"
    echo "  cluster  - Clean OpenShift cluster only"
    echo ""
    echo "Examples:"
    echo "  $0 --dry-run                    # 预览将要清理的内容"
    echo "  $0 --force                      # 跳过确认提示"
    echo "  $0 --cleanup-level local        # 只清理本地文件"
    echo "  $0 --cleanup-level aws          # 只清理AWS资源"
    echo "  $0 --cluster-name my-cluster    # 清理特定集群"
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

# 清理本地文件
cleanup_local_files() {
    local dry_run="$1"
    local force="$2"
    
    print_info "清理本地文件..."
    
    local found_items=()
    
    # 检查并清理目录
    local dirs=(
        "$INSTALL_DIR"
        "$INFRA_OUTPUT_DIR"
        "$SYNC_OUTPUT_DIR"
        "./backups"
        "./logs"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local file_count=$(find "$dir" -type f 2>/dev/null | wc -l)
            print_info "找到目录: $dir ($file_count 个文件)"
            found_items+=("$dir")
        fi
    done
    
    # 检查并清理文件
    local files=(
        "install-config.yaml"
        "install-config.yaml.backup"
        "*.pem"
        "*.key"
        "kubeconfig"
        "auth/kubeconfig"
    )
    
    for pattern in "${files[@]}"; do
        for file in $pattern; do
            if [[ -f "$file" ]]; then
                print_info "找到文件: $file"
                found_items+=("$file")
            fi
        done
    done
    
    if [[ ${#found_items[@]} -eq 0 ]]; then
        print_info "没有找到需要清理的本地文件"
        return 0
    fi
    
    echo ""
    print_warning "找到 ${#found_items[@]} 个本地项目需要清理:"
    for item in "${found_items[@]}"; do
        echo "  - $item"
    done
    echo ""
    
    if [[ "$dry_run" == "yes" ]]; then
        print_info "DRY RUN: 将删除上述项目"
        return 0
    fi
    
    if [[ "$force" != "yes" ]]; then
        read -p "确定要删除这些本地文件和目录吗? (yes/no): " -r
        echo
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_info "本地清理已取消"
            return 1
        fi
    fi
    
    # 删除目录
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir"
            print_success "已删除目录: $dir"
        fi
    done
    
    # 删除文件
    for pattern in "${files[@]}"; do
        for file in $pattern; do
            if [[ -f "$file" ]]; then
                rm -f "$file"
                print_success "已删除文件: $file"
            fi
        done
    done
    
    return 0
}

# 清理bastion host文件
cleanup_bastion_files() {
    local dry_run="$1"
    local force="$2"
    
    print_info "清理bastion host文件..."
    
    # 检查bastion IP
    if [[ ! -f "$INFRA_OUTPUT_DIR/bastion-public-ip" ]]; then
        print_warning "找不到bastion IP文件，跳过bastion清理"
        return 0
    fi
    
    local bastion_ip=$(cat "$INFRA_OUTPUT_DIR/bastion-public-ip")
    local ssh_key="$INFRA_OUTPUT_DIR/bastion-key.pem"
    
    if [[ ! -f "$ssh_key" ]]; then
        print_warning "找不到SSH密钥文件，跳过bastion清理"
        return 0
    fi
    
    # 检查SSH连接
    if ! ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$bastion_ip" "echo 'SSH connection test'" &> /dev/null; then
        print_warning "无法连接到bastion host，跳过bastion清理"
        return 0
    fi
    
    print_info "连接到bastion host: $bastion_ip"
    
    # 在bastion上清理文件
    local cleanup_commands=(
        "rm -rf /home/ubuntu/disconnected-cluster/openshift-install"
        "rm -rf /home/ubuntu/disconnected-cluster/sync-output"
        "rm -f /home/ubuntu/disconnected-cluster/install-config.yaml"
        "rm -f /home/ubuntu/disconnected-cluster/install-config.yaml.backup"
        "rm -f /home/ubuntu/disconnected-cluster/auth/kubeconfig"
        "rm -rf /home/ubuntu/disconnected-cluster/backups"
        "rm -rf /home/ubuntu/disconnected-cluster/logs"
        "rm -f /home/ubuntu/disconnected-cluster/*.pem"
        "rm -f /home/ubuntu/disconnected-cluster/*.key"
    )
    
    if [[ "$dry_run" == "yes" ]]; then
        print_info "DRY RUN: 将在bastion上执行以下清理命令:"
        for cmd in "${cleanup_commands[@]}"; do
            echo "  $cmd"
        done
        return 0
    fi
    
    if [[ "$force" != "yes" ]]; then
        read -p "确定要在bastion host上清理文件吗? (yes/no): " -r
        echo
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_info "Bastion清理已取消"
            return 1
        fi
    fi
    
    for cmd in "${cleanup_commands[@]}"; do
        if ssh -i "$ssh_key" -o StrictHostKeyChecking=no ubuntu@"$bastion_ip" "$cmd" 2>/dev/null; then
            print_success "Bastion清理命令执行成功: $cmd"
        else
            print_warning "Bastion清理命令可能失败: $cmd"
        fi
    done
    
    return 0
}

# 清理AWS资源
cleanup_aws_resources() {
    local dry_run="$1"
    local force="$2"
    
    print_info "清理AWS资源..."
    
    # 检查infra-output目录
    if [[ ! -d "$INFRA_OUTPUT_DIR" ]]; then
        print_warning "找不到infra-output目录，跳过AWS资源清理"
        return 0
    fi
    
    # 读取基础设施信息
    local vpc_id=""
    local region="$REGION"
    local bastion_instance_id=""
    local cluster_sg_id=""
    local bastion_sg_id=""
    local eip_id=""
    local nat_gateway_id=""
    
    if [[ -f "$INFRA_OUTPUT_DIR/vpc-id" ]]; then
        vpc_id=$(cat "$INFRA_OUTPUT_DIR/vpc-id")
    fi
    
    if [[ -f "$INFRA_OUTPUT_DIR/region" ]]; then
        region=$(cat "$INFRA_OUTPUT_DIR/region")
    fi
    
    if [[ -f "$INFRA_OUTPUT_DIR/bastion-instance-id" ]]; then
        bastion_instance_id=$(cat "$INFRA_OUTPUT_DIR/bastion-instance-id")
    fi
    
    if [[ -f "$INFRA_OUTPUT_DIR/cluster-security-group-id" ]]; then
        cluster_sg_id=$(cat "$INFRA_OUTPUT_DIR/cluster-security-group-id")
    fi
    
    if [[ -f "$INFRA_OUTPUT_DIR/bastion-security-group-id" ]]; then
        bastion_sg_id=$(cat "$INFRA_OUTPUT_DIR/bastion-security-group-id")
    fi
    
    if [[ -f "$INFRA_OUTPUT_DIR/eip-id" ]]; then
        eip_id=$(cat "$INFRA_OUTPUT_DIR/eip-id")
    fi
    
    if [[ -f "$INFRA_OUTPUT_DIR/nat-gateway-id" ]]; then
        nat_gateway_id=$(cat "$INFRA_OUTPUT_DIR/nat-gateway-id")
    fi
    
    local found_resources=()
    
    # 检查资源是否存在
    if [[ -n "$bastion_instance_id" && "$bastion_instance_id" != "None" ]]; then
        if aws ec2 describe-instances --instance-ids "$bastion_instance_id" --region "$region" &> /dev/null; then
            print_info "找到bastion实例: $bastion_instance_id"
            found_resources+=("Bastion Instance: $bastion_instance_id")
        fi
    fi
    
    if [[ -n "$cluster_sg_id" && "$cluster_sg_id" != "None" ]]; then
        if aws ec2 describe-security-groups --group-ids "$cluster_sg_id" --region "$region" &> /dev/null; then
            print_info "找到集群安全组: $cluster_sg_id"
            found_resources+=("Cluster Security Group: $cluster_sg_id")
        fi
    fi
    
    if [[ -n "$bastion_sg_id" && "$bastion_sg_id" != "None" ]]; then
        if aws ec2 describe-security-groups --group-ids "$bastion_sg_id" --region "$region" &> /dev/null; then
            print_info "找到bastion安全组: $bastion_sg_id"
            found_resources+=("Bastion Security Group: $bastion_sg_id")
        fi
    fi
    
    if [[ -n "$eip_id" && "$eip_id" != "None" ]]; then
        if aws ec2 describe-addresses --allocation-ids "$eip_id" --region "$region" &> /dev/null; then
            print_info "找到弹性IP: $eip_id"
            found_resources+=("Elastic IP: $eip_id")
        fi
    fi
    
    if [[ -n "$nat_gateway_id" && "$nat_gateway_id" != "None" ]]; then
        if aws ec2 describe-nat-gateways --nat-gateway-ids "$nat_gateway_id" --region "$region" &> /dev/null; then
            print_info "找到NAT网关: $nat_gateway_id"
            found_resources+=("NAT Gateway: $nat_gateway_id")
        fi
    fi
    
    if [[ -n "$vpc_id" && "$vpc_id" != "None" ]]; then
        if aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$region" &> /dev/null; then
            print_info "找到VPC: $vpc_id"
            found_resources+=("VPC: $vpc_id")
        fi
    fi
    
    # 检查SSH密钥对
    local ssh_keys=("${CLUSTER_NAME}-bastion-key")
    for key_name in "${ssh_keys[@]}"; do
        if aws ec2 describe-key-pairs --key-names "$key_name" --region "$region" &> /dev/null; then
            print_info "找到SSH密钥对: $key_name"
            found_resources+=("SSH Key Pair: $key_name")
        fi
    done
    
    if [[ ${#found_resources[@]} -eq 0 ]]; then
        print_info "没有找到需要清理的AWS资源"
        return 0
    fi
    
    echo ""
    print_warning "找到 ${#found_resources[@]} 个AWS资源需要清理:"
    for resource in "${found_resources[@]}"; do
        echo "  - $resource"
    done
    echo ""
    
    if [[ "$dry_run" == "yes" ]]; then
        print_info "DRY RUN: 将删除上述AWS资源"
        return 0
    fi
    
    if [[ "$force" != "yes" ]]; then
        print_warning "⚠️  这将永久删除AWS资源!"
        read -p "确定要删除这些AWS资源吗? (yes/no): " -r
        echo
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_info "AWS清理已取消"
            return 1
        fi
    fi
    
    # 删除bastion实例
    if [[ -n "$bastion_instance_id" && "$bastion_instance_id" != "None" ]]; then
        if aws ec2 describe-instances --instance-ids "$bastion_instance_id" --region "$region" &> /dev/null; then
            aws ec2 terminate-instances --instance-ids "$bastion_instance_id" --region "$region"
            print_success "已终止bastion实例: $bastion_instance_id"
        fi
    fi
    
    # 删除NAT网关
    if [[ -n "$nat_gateway_id" && "$nat_gateway_id" != "None" ]]; then
        if aws ec2 describe-nat-gateways --nat-gateway-ids "$nat_gateway_id" --region "$region" &> /dev/null; then
            aws ec2 delete-nat-gateway --nat-gateway-id "$nat_gateway_id" --region "$region"
            print_success "已删除NAT网关: $nat_gateway_id"
        fi
    fi
    
    # 删除弹性IP
    if [[ -n "$eip_id" && "$eip_id" != "None" ]]; then
        if aws ec2 describe-addresses --allocation-ids "$eip_id" --region "$region" &> /dev/null; then
            aws ec2 release-address --allocation-id "$eip_id" --region "$region"
            print_success "已释放弹性IP: $eip_id"
        fi
    fi
    
    # 删除安全组
    if [[ -n "$cluster_sg_id" && "$cluster_sg_id" != "None" ]]; then
        if aws ec2 describe-security-groups --group-ids "$cluster_sg_id" --region "$region" &> /dev/null; then
            aws ec2 delete-security-group --group-id "$cluster_sg_id" --region "$region"
            print_success "已删除集群安全组: $cluster_sg_id"
        fi
    fi
    
    if [[ -n "$bastion_sg_id" && "$bastion_sg_id" != "None" ]]; then
        if aws ec2 describe-security-groups --group-ids "$bastion_sg_id" --region "$region" &> /dev/null; then
            aws ec2 delete-security-group --group-id "$bastion_sg_id" --region "$region"
            print_success "已删除bastion安全组: $bastion_sg_id"
        fi
    fi
    
    # 删除SSH密钥对
    for key_name in "${ssh_keys[@]}"; do
        if aws ec2 describe-key-pairs --key-names "$key_name" --region "$region" &> /dev/null; then
            aws ec2 delete-key-pair --key-name "$key_name" --region "$region"
            print_success "已删除SSH密钥对: $key_name"
        fi
    done
    
    # 删除VPC（这会删除所有子网、路由表等）
    if [[ -n "$vpc_id" && "$vpc_id" != "None" ]]; then
        if aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$region" &> /dev/null; then
            # 使用force-delete-vpc.sh脚本
            if [[ -f "./force-delete-vpc.sh" ]]; then
                ./force-delete-vpc.sh "$vpc_id" "$region"
                print_success "已删除VPC: $vpc_id"
            else
                print_warning "找不到force-delete-vpc.sh脚本，请手动删除VPC: $vpc_id"
            fi
        fi
    fi
    
    return 0
}

# 清理OpenShift集群
cleanup_openshift_cluster() {
    local dry_run="$1"
    local force="$2"
    
    print_info "清理OpenShift集群..."
    
    # 检查bastion IP和SSH密钥
    if [[ ! -f "$INFRA_OUTPUT_DIR/bastion-public-ip" ]] || [[ ! -f "$INFRA_OUTPUT_DIR/bastion-key.pem" ]]; then
        print_warning "找不到bastion信息，跳过集群清理"
        return 0
    fi
    
    local bastion_ip=$(cat "$INFRA_OUTPUT_DIR/bastion-public-ip")
    local ssh_key="$INFRA_OUTPUT_DIR/bastion-key.pem"
    
    # 检查SSH连接
    if ! ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$bastion_ip" "echo 'SSH connection test'" &> /dev/null; then
        print_warning "无法连接到bastion host，跳过集群清理"
        return 0
    fi
    
    print_info "连接到bastion host: $bastion_ip"
    
    # 检查集群是否正在运行
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
    
    if [[ "$cluster_status" == "not_found" ]]; then
        print_info "找不到集群配置文件，跳过集群清理"
        return 0
    elif [[ "$cluster_status" == "not_running" ]]; then
        print_info "集群未运行，跳过集群清理"
        return 0
    elif [[ "$cluster_status" == "error" ]]; then
        print_warning "无法检查集群状态，跳过集群清理"
        return 0
    fi
    
    print_info "找到运行中的集群，准备清理..."
    
    if [[ "$dry_run" == "yes" ]]; then
        print_info "DRY RUN: 将删除OpenShift集群"
        return 0
    fi
    
    if [[ "$force" != "yes" ]]; then
        print_warning "⚠️  这将永久删除OpenShift集群!"
        read -p "确定要删除OpenShift集群吗? (yes/no): " -r
        echo
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_info "集群清理已取消"
            return 1
        fi
    fi
    
    # 在bastion上执行集群删除
    ssh -i "$ssh_key" -o StrictHostKeyChecking=no ubuntu@"$bastion_ip" "
        cd /home/ubuntu/disconnected-cluster
        if [[ -d openshift-install ]]; then
            cd openshift-install
            if [[ -f openshift-install ]]; then
                echo '正在删除OpenShift集群...'
                ./openshift-install destroy cluster --dir=. --log-level=info
                echo '集群删除完成'
            else
                echo '找不到openshift-install二进制文件'
            fi
        else
            echo '找不到openshift-install目录'
        fi
    "
    
    print_success "OpenShift集群清理完成"
    return 0
}

# 生成清理报告
generate_cleanup_report() {
    local report_file="cleanup-report-${CLUSTER_NAME}-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$report_file" <<EOF
OpenShift Disconnected Cluster Cleanup Report
============================================
Cluster: $CLUSTER_NAME
Cleanup Level: $CLEANUP_LEVEL
Date: $(date)

Cleanup Summary:
- Local files: $([[ "$CLEANUP_LEVEL" == "all" || "$CLEANUP_LEVEL" == "local" ]] && echo "Removed" || echo "Skipped")
- Bastion files: $([[ "$CLEANUP_LEVEL" == "all" || "$CLEANUP_LEVEL" == "bastion" ]] && echo "Removed" || echo "Skipped")
- AWS resources: $([[ "$CLEANUP_LEVEL" == "all" || "$CLEANUP_LEVEL" == "aws" ]] && echo "Removed" || echo "Skipped")
- Cluster: $([[ "$CLEANUP_LEVEL" == "all" || "$CLEANUP_LEVEL" == "cluster" ]] && echo "Removed" || echo "Skipped")

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
    
    print_success "清理报告已生成: $report_file"
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
            --cleanup-level)
                CLEANUP_LEVEL="$2"
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
    CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}
    INFRA_OUTPUT_DIR=${INFRA_OUTPUT_DIR:-$DEFAULT_INFRA_OUTPUT_DIR}
    SYNC_OUTPUT_DIR=${SYNC_OUTPUT_DIR:-$DEFAULT_SYNC_OUTPUT_DIR}
    REGION=${REGION:-$DEFAULT_REGION}
    CLEANUP_LEVEL=${CLEANUP_LEVEL:-$DEFAULT_CLEANUP_LEVEL}
    DRY_RUN=${DRY_RUN:-no}
    FORCE=${FORCE:-no}
    
    # 显示脚本头部
    echo "🧹 Disconnected Cluster Cleanup Script"
    echo "====================================="
    echo ""
    echo "📋 Configuration:"
    echo "   Cluster Name: $CLUSTER_NAME"
    echo "   Install Directory: $INSTALL_DIR"
    echo "   Infra Output Directory: $INFRA_OUTPUT_DIR"
    echo "   Sync Output Directory: $SYNC_OUTPUT_DIR"
    echo "   Region: $REGION"
    echo "   Cleanup Level: $CLEANUP_LEVEL"
    echo "   Dry Run: $DRY_RUN"
    echo "   Force: $FORCE"
    echo ""
    
    # 检查前置条件
    check_prerequisites
    
    # 根据清理级别执行相应的清理操作
    case "$CLEANUP_LEVEL" in
        "all")
            # 先验证清理前的状态
            print_info "执行清理前验证..."
            if [[ -f "./08-verify-cleanup.sh" ]]; then
                ./08-verify-cleanup.sh --verify-level all --cluster-name "$CLUSTER_NAME" --region "$REGION" || true
            fi
            
            # 执行清理操作
            cleanup_openshift_cluster "$DRY_RUN" "$FORCE"
            cleanup_aws_resources "$DRY_RUN" "$FORCE"
            cleanup_bastion_files "$DRY_RUN" "$FORCE"
            cleanup_local_files "$DRY_RUN" "$FORCE"
            ;;
        "local")
            cleanup_local_files "$DRY_RUN" "$FORCE"
            ;;
        "bastion")
            cleanup_bastion_files "$DRY_RUN" "$FORCE"
            ;;
        "aws")
            cleanup_aws_resources "$DRY_RUN" "$FORCE"
            ;;
        "cluster")
            cleanup_openshift_cluster "$DRY_RUN" "$FORCE"
            ;;
        *)
            print_error "无效的清理级别: $CLEANUP_LEVEL"
            usage
            exit 1
            ;;
    esac
    
    # 生成清理报告
    if [[ "$DRY_RUN" != "yes" ]]; then
        generate_cleanup_report
        
        # 清理完成后再次验证
        if [[ "$CLEANUP_LEVEL" == "all" ]] && [[ -f "./08-verify-cleanup.sh" ]]; then
            echo ""
            print_info "执行清理后验证..."
            ./08-verify-cleanup.sh --verify-level all --cluster-name "$CLUSTER_NAME" --region "$REGION" --skip-local || true
        fi
    fi
    
    echo ""
    if [[ "$DRY_RUN" == "yes" ]]; then
        print_success "Dry run 完成 - 没有实际删除任何文件或资源"
    else
        print_success "清理完成!"
    fi
    
    echo ""
    echo "💡 Tips:"
    echo "  - 使用 --dry-run 预览将要删除的内容"
    echo "  - 使用 --force 跳过确认提示"
    echo "  - 使用 --cleanup-level 指定清理范围"
    echo "  - 检查AWS控制台确认资源已完全删除"
    echo "  - 使用AWS Cost Explorer验证成本减少"
}

# 运行主函数
main "$@" 