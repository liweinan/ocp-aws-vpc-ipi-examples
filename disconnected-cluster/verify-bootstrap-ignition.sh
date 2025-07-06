#!/bin/bash

# 验证bootstrap ignition中的配置是否与实际工作一致

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# 配置
BASTION_IP="72.44.62.16"
BOOTSTRAP_IP="10.0.100.175"
SSH_KEY="./ci-operator/disconnected-cluster/infra-output/bastion-key.pem"

echo "=== Bootstrap Ignition Configuration Verification ==="
echo "时间: $(date)"
echo "Bastion IP: $BASTION_IP"
echo "Bootstrap IP: $BOOTSTRAP_IP"
echo ""

# 检查SSH密钥
if [[ ! -f "$SSH_KEY" ]]; then
    print_error "SSH密钥不存在: $SSH_KEY"
    exit 1
fi

print_info "开始验证bootstrap ignition配置..."

# 在bootstrap节点上执行验证
ssh -i "$SSH_KEY" ubuntu@"$BASTION_IP" "ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no core@$BOOTSTRAP_IP" << 'IGNITION_VERIFY'

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

echo "=== Bootstrap Ignition Configuration Verification ==="
echo "主机名: $(hostname)"
echo "时间: $(date)"
echo ""

# 1. 检查当前release-image.sh配置
print_info "1. 检查当前release-image.sh配置..."
echo "当前release-image.sh内容:"
if [[ -f /usr/local/bin/release-image.sh ]]; then
    cat /usr/local/bin/release-image.sh
else
    print_error "release-image.sh不存在"
fi
echo ""

# 2. 检查当前registries.conf配置
print_info "2. 检查当前registries.conf配置..."
echo "当前registries.conf内容:"
if [[ -f /etc/containers/registries.conf ]]; then
    cat /etc/containers/registries.conf
else
    print_error "registries.conf不存在"
fi
echo ""

# 3. 检查当前hosts配置
print_info "3. 检查当前hosts配置..."
echo "当前/etc/hosts内容:"
cat /etc/hosts
echo ""

# 4. 检查当前镜像列表
print_info "4. 检查当前镜像列表..."
echo "当前本地镜像:"
podman images
echo ""

# 5. 测试release-image.sh中的镜像拉取
print_info "5. 测试release-image.sh中的镜像拉取..."

# 加载release-image.sh
if [[ -f /usr/local/bin/release-image.sh ]]; then
    source /usr/local/bin/release-image.sh
    
    echo "RELEASE_IMAGE_DIGEST: $RELEASE_IMAGE_DIGEST"
    
    # 测试release镜像拉取
    echo "测试拉取release镜像: $RELEASE_IMAGE_DIGEST"
    if timeout 60 podman pull --tls-verify=false "$RELEASE_IMAGE_DIGEST"; then
        print_success "Release镜像拉取成功"
    else
        print_error "Release镜像拉取失败"
    fi
    echo ""
    
    # 测试其他镜像
    TEST_IMAGES=("machine-config-operator" "etcd" "cli" "installer")
    for img in "${TEST_IMAGES[@]}"; do
        echo "测试镜像: $img"
        img_spec=$(image_for "$img")
        echo "镜像规格: $img_spec"
        if timeout 60 podman pull --tls-verify=false "$img_spec"; then
            print_success "镜像 $img 拉取成功"
        else
            print_error "镜像 $img 拉取失败"
        fi
        echo ""
    done
else
    print_error "无法加载release-image.sh"
fi

# 6. 检查bootstrap服务状态
print_info "6. 检查bootstrap服务状态..."
echo "release-image.service状态:"
systemctl status release-image.service --no-pager || echo "服务不存在或未运行"
echo ""

echo "bootkube.service状态:"
systemctl status bootkube.service --no-pager || echo "服务不存在或未运行"
echo ""

# 7. 检查bootstrap日志
print_info "7. 检查bootstrap日志..."
echo "最近的release-image.service日志:"
journalctl -u release-image.service --no-pager -n 20 2>/dev/null || echo "无法获取日志"
echo ""

echo "最近的bootkube.service日志:"
journalctl -u bootkube.service --no-pager -n 20 2>/dev/null || echo "无法获取日志"
echo ""

# 8. 测试registry连通性
print_info "8. 测试registry连通性..."

# Registry认证信息
REGISTRY_USER="admin"
REGISTRY_PASSWORD="admin123"

echo "测试localhost:5000连通性:"
if curl -s -k -u "$REGISTRY_USER:$REGISTRY_PASSWORD" --connect-timeout 10 "https://localhost:5000/v2/_catalog" >/dev/null 2>&1; then
    print_success "localhost:5000连通性正常"
else
    print_error "localhost:5000连通性失败"
fi
echo ""

echo "测试10.0.10.10:5000连通性:"
if curl -s -k -u "$REGISTRY_USER:$REGISTRY_PASSWORD" --connect-timeout 10 "https://10.0.10.10:5000/v2/_catalog" >/dev/null 2>&1; then
    print_success "10.0.10.10:5000连通性正常"
else
    print_error "10.0.10.10:5000连通性失败"
fi
echo ""

# 9. 检查配置差异
print_info "9. 检查配置差异..."

echo "Ignition中的release-image.sh vs 当前配置:"
echo "Ignition配置:"
echo "RELEASE_IMAGE_DIGEST=\"localhost:5000/openshift/ocp/release:4.19\""
echo ""
echo "当前配置:"
if [[ -f /usr/local/bin/release-image.sh ]]; then
    grep "RELEASE_IMAGE_DIGEST" /usr/local/bin/release-image.sh || echo "未找到RELEASE_IMAGE_DIGEST"
fi
echo ""

# 10. 总结
print_info "10. 配置验证总结..."

echo "配置状态:"
if [[ -f /usr/local/bin/release-image.sh ]] && grep -q "localhost:5000" /usr/local/bin/release-image.sh; then
    echo "  release-image.sh: ✅ 使用localhost:5000"
else
    echo "  release-image.sh: ❌ 配置不正确"
fi

if [[ -f /etc/containers/registries.conf ]] && grep -q "localhost:5000" /etc/containers/registries.conf; then
    echo "  registries.conf: ✅ 包含localhost:5000配置"
else
    echo "  registries.conf: ❌ 配置不正确"
fi

if grep -q "10.0.10.10.*registry.ci.openshift.org" /etc/hosts; then
    echo "  /etc/hosts: ✅ 包含registry重定向"
else
    echo "  /etc/hosts: ❌ 配置不正确"
fi

echo ""
print_success "Bootstrap ignition配置验证完成！"

IGNITION_VERIFY

if [[ $? -eq 0 ]]; then
    print_success "Bootstrap ignition配置验证完成！"
else
    print_error "验证过程中出现错误"
    exit 1
fi

echo ""
print_info "📋 验证总结:"
echo "1. 检查了release-image.sh配置"
echo "2. 检查了registries.conf配置"
echo "3. 检查了hosts配置"
echo "4. 检查了镜像列表"
echo "5. 测试了镜像拉取功能"
echo "6. 检查了bootstrap服务状态"
echo "7. 检查了bootstrap日志"
echo "8. 测试了registry连通性"
echo "9. 检查了配置差异"
echo "10. 总结了配置状态" 