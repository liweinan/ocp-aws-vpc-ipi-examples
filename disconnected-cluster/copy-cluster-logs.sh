#!/bin/bash

# OpenShift集群安装日志拷贝脚本
# 从bastion主机拷贝安装日志到本地cluster-logs目录

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
BASTION_HOST="72.44.62.16"
BASTION_USER="ubuntu"
SSH_KEY="infra-output/bastion-key.pem"
REMOTE_DIR="/home/ubuntu/disconnected-cluster/openshift-install-dir"
LOCAL_DIR="cluster-logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# 函数：打印彩色消息
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

# 函数：检查SSH密钥是否存在
check_ssh_key() {
    if [[ ! -f "$SSH_KEY" ]]; then
        print_error "SSH密钥文件不存在: $SSH_KEY"
        print_info "请确保已经运行了基础设施创建脚本"
        exit 1
    fi
}

# 函数：检查bastion主机连接
check_bastion_connection() {
    print_info "检查bastion主机连接..."
    if ! ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$BASTION_USER@$BASTION_HOST" "echo 'Connection test successful'" > /dev/null 2>&1; then
        print_error "无法连接到bastion主机: $BASTION_HOST"
        print_info "请检查:"
        print_info "1. bastion主机是否正在运行"
        print_info "2. 网络连接是否正常"
        print_info "3. SSH密钥是否正确"
        exit 1
    fi
    print_success "bastion主机连接正常"
}

# 函数：创建本地日志目录
create_local_dir() {
    print_info "创建本地日志目录..."
    mkdir -p "$LOCAL_DIR"
    
    # 创建带时间戳的备份目录
    if [[ -d "$LOCAL_DIR" ]] && [[ "$(ls -A $LOCAL_DIR 2>/dev/null)" ]]; then
        BACKUP_DIR="${LOCAL_DIR}_backup_${TIMESTAMP}"
        print_warning "本地日志目录非空，创建备份: $BACKUP_DIR"
        cp -r "$LOCAL_DIR" "$BACKUP_DIR"
    fi
    
    print_success "本地日志目录准备完成: $LOCAL_DIR"
}

# 函数：拷贝文件
copy_file() {
    local filename="$1"
    local description="$2"
    
    print_info "拷贝 $description ($filename)..."
    
    if scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$BASTION_USER@$BASTION_HOST:$REMOTE_DIR/$filename" "$LOCAL_DIR/" 2>/dev/null; then
        local filesize=$(ls -lh "$LOCAL_DIR/$filename" 2>/dev/null | awk '{print $5}' || echo "未知大小")
        print_success "✓ $description 拷贝成功 ($filesize)"
        return 0
    else
        print_warning "✗ $description 拷贝失败或文件不存在"
        return 1
    fi
}

# 函数：拷贝目录
copy_directory() {
    local dirname="$1"
    local description="$2"
    
    print_info "拷贝 $description 目录 ($dirname)..."
    
    if scp -r -i "$SSH_KEY" -o StrictHostKeyChecking=no "$BASTION_USER@$BASTION_HOST:$REMOTE_DIR/$dirname" "$LOCAL_DIR/" 2>/dev/null; then
        local filecount=$(find "$LOCAL_DIR/$dirname" -type f 2>/dev/null | wc -l || echo "0")
        print_success "✓ $description 目录拷贝成功 ($filecount 个文件)"
        return 0
    else
        print_warning "✗ $description 目录拷贝失败或目录不存在"
        return 1
    fi
}

# 函数：拷贝bootstrap失败日志包
copy_log_bundles() {
    print_info "检查bootstrap失败日志包..."
    
    # 查找log bundle文件
    local log_bundles
    log_bundles=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$BASTION_USER@$BASTION_HOST" "find $REMOTE_DIR -name 'log-bundle-*.tar.gz' 2>/dev/null" || true)
    
    if [[ -z "$log_bundles" ]]; then
        print_info "未找到bootstrap失败日志包（可能安装正常进行中）"
        return 0
    fi
    
    # 拷贝找到的所有log bundle文件
    if [[ -n "$log_bundles" ]]; then
        while IFS= read -r bundle_path; do
            if [[ -n "$bundle_path" ]]; then
                local bundle_filename=$(basename "$bundle_path")
                print_info "拷贝bootstrap失败日志 ($bundle_filename)..."
                
                if scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$BASTION_USER@$BASTION_HOST:$bundle_path" "$LOCAL_DIR/" 2>/dev/null; then
                    local filesize=$(ls -lh "$LOCAL_DIR/$bundle_filename" 2>/dev/null | awk '{print $5}' || echo "未知大小")
                    print_success "✓ Bootstrap失败日志拷贝成功 ($filesize)"
                    print_warning "⚠️  检测到bootstrap失败，建议查看日志包进行故障排除"
                else
                    print_warning "✗ Bootstrap失败日志拷贝失败"
                fi
            fi
        done <<< "$log_bundles"
    fi
}

# 函数：生成拷贝报告
generate_report() {
    local report_file="$LOCAL_DIR/copy-report-${TIMESTAMP}.txt"
    
    print_info "生成拷贝报告..."
    
    {
        echo "OpenShift集群安装日志拷贝报告"
        echo "=================================="
        echo "拷贝时间: $(date)"
        echo "源主机: $BASTION_USER@$BASTION_HOST"
        echo "源目录: $REMOTE_DIR"
        echo "目标目录: $LOCAL_DIR"
        echo ""
        echo "拷贝的文件:"
        echo "----------"
        
        if [[ -f "$LOCAL_DIR/.openshift_install.log" ]]; then
            echo "✓ .openshift_install.log - $(ls -lh "$LOCAL_DIR/.openshift_install.log" | awk '{print $5}')"
        fi
        
        if [[ -f "$LOCAL_DIR/.openshift_install_state.json" ]]; then
            echo "✓ .openshift_install_state.json - $(ls -lh "$LOCAL_DIR/.openshift_install_state.json" | awk '{print $5}')"
        fi
        
        if [[ -f "$LOCAL_DIR/metadata.json" ]]; then
            echo "✓ metadata.json - $(ls -lh "$LOCAL_DIR/metadata.json" | awk '{print $5}')"
        fi
        
        if [[ -f "$LOCAL_DIR/install-config.yaml.backup" ]]; then
            echo "✓ install-config.yaml.backup - $(ls -lh "$LOCAL_DIR/install-config.yaml.backup" | awk '{print $5}')"
        fi
        
        if [[ -f "$LOCAL_DIR/terraform.platform.auto.tfvars.json" ]]; then
            echo "✓ terraform.platform.auto.tfvars.json - $(ls -lh "$LOCAL_DIR/terraform.platform.auto.tfvars.json" | awk '{print $5}')"
        fi
        
        if [[ -f "$LOCAL_DIR/terraform.tfvars.json" ]]; then
            echo "✓ terraform.tfvars.json - $(ls -lh "$LOCAL_DIR/terraform.tfvars.json" | awk '{print $5}')"
        fi
        
        if [[ -d "$LOCAL_DIR/auth" ]]; then
            echo "✓ auth/ - $(find "$LOCAL_DIR/auth" -type f | wc -l) 个文件"
        fi
        
        if [[ -d "$LOCAL_DIR/.clusterapi_output" ]]; then
            echo "✓ .clusterapi_output/ - $(find "$LOCAL_DIR/.clusterapi_output" -type f | wc -l) 个文件"
        fi
        
        if [[ -d "$LOCAL_DIR/tls" ]]; then
            echo "✓ tls/ - $(find "$LOCAL_DIR/tls" -type f | wc -l) 个文件"
        fi
        
        # 检查log bundle文件
        local log_bundles=$(find "$LOCAL_DIR" -name "log-bundle-*.tar.gz" 2>/dev/null)
        if [[ -n "$log_bundles" ]]; then
            echo ""
            echo "Bootstrap失败日志包:"
            echo "-------------------"
            while IFS= read -r bundle; do
                if [[ -f "$bundle" ]]; then
                    echo "⚠️  $(basename "$bundle") - $(ls -lh "$bundle" | awk '{print $5}')"
                fi
            done <<< "$log_bundles"
        fi
        
        echo ""
        echo "总计文件数: $(find "$LOCAL_DIR" -type f | wc -l)"
        echo "总计大小: $(du -sh "$LOCAL_DIR" 2>/dev/null | awk '{print $1}' || echo "计算失败")"
        
    } > "$report_file"
    
    print_success "拷贝报告生成: $report_file"
}

# 函数：显示使用帮助
show_usage() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help          显示此帮助信息"
    echo "  -v, --verbose       详细输出"
    echo "  -f, --force         强制覆盖现有文件"
    echo ""
    echo "描述:"
    echo "  从bastion主机拷贝OpenShift集群安装日志到本地cluster-logs目录"
    echo ""
    echo "示例:"
    echo "  $0                  # 标准拷贝"
    echo "  $0 -v               # 详细输出"
    echo "  $0 -f               # 强制覆盖"
}

# 主函数
main() {
    # 解析命令行参数
    VERBOSE=false
    FORCE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            *)
                print_error "未知参数: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    print_info "开始拷贝OpenShift集群安装日志..."
    print_info "时间戳: $TIMESTAMP"
    
    # 检查前置条件
    check_ssh_key
    check_bastion_connection
    
    # 创建本地目录
    create_local_dir
    
    # 拷贝核心日志文件
    print_info "拷贝核心日志文件..."
    copy_file ".openshift_install.log" "主安装日志"
    copy_file ".openshift_install_state.json" "安装状态文件"
    copy_file "metadata.json" "集群元数据"
    
    # 拷贝配置文件
    print_info "拷贝配置文件..."
    copy_file "install-config.yaml.backup" "安装配置备份"
    copy_file "terraform.platform.auto.tfvars.json" "Terraform平台配置"
    copy_file "terraform.tfvars.json" "Terraform变量"
    
    # 拷贝目录
    print_info "拷贝重要目录..."
    copy_directory "auth" "认证文件"
    copy_directory ".clusterapi_output" "集群API文件"
    copy_directory "tls" "TLS证书"
    
    # 拷贝bootstrap失败日志包
    copy_log_bundles
    
    # 生成报告
    generate_report
    
    # 显示总结
    print_success "===================="
    print_success "日志拷贝完成!"
    print_success "===================="
    print_info "本地目录: $LOCAL_DIR"
    print_info "文件总数: $(find "$LOCAL_DIR" -type f | wc -l)"
    print_info "目录大小: $(du -sh "$LOCAL_DIR" 2>/dev/null | awk '{print $1}' || echo "计算失败")"
    
    # 提供有用的后续命令
    echo ""
    print_info "有用的后续命令:"
    echo "  查看最新日志: tail -f $LOCAL_DIR/.openshift_install.log"
    echo "  查看集群状态: cat $LOCAL_DIR/metadata.json | jq ."
    echo "  查看拷贝报告: cat $LOCAL_DIR/copy-report-${TIMESTAMP}.txt"
    
    # 检查是否有bootstrap失败日志包
    local log_bundles=$(find "$LOCAL_DIR" -name "log-bundle-*.tar.gz" 2>/dev/null)
    if [[ -n "$log_bundles" ]]; then
        echo ""
        print_warning "检测到bootstrap失败日志包，故障排除命令："
        while IFS= read -r bundle; do
            if [[ -f "$bundle" ]]; then
                local bundle_name=$(basename "$bundle")
                echo "  解压日志包: tar -xzf $LOCAL_DIR/$bundle_name -C $LOCAL_DIR/"
                echo "  查看bootstrap日志: grep -i error $LOCAL_DIR/bootstrap-*"
            fi
        done <<< "$log_bundles"
    fi
    
    print_success "日志拷贝脚本执行完成!"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 