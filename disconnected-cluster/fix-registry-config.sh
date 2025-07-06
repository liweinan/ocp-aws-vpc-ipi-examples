#!/bin/bash

# 修复registry配置的脚本

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

echo "=== Registry Configuration Fix ==="
echo "时间: $(date)"
echo "Bastion IP: $BASTION_IP"
echo "Bootstrap IP: $BOOTSTRAP_IP"
echo ""

# 检查SSH密钥
if [[ ! -f "$SSH_KEY" ]]; then
    print_error "SSH密钥不存在: $SSH_KEY"
    exit 1
fi

print_info "开始修复registry配置..."

# 在bootstrap节点上执行修复
ssh -i "$SSH_KEY" ubuntu@"$BASTION_IP" "ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no core@$BOOTSTRAP_IP" << 'REGISTRY_FIX'

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

echo "=== Registry Configuration Fix on Bootstrap Node ==="
echo "主机名: $(hostname)"
echo "时间: $(date)"
echo ""

# 1. 备份当前配置
print_info "1. 备份当前配置..."
sudo cp /etc/containers/registries.conf /etc/containers/registries.conf.backup
print_success "配置已备份"
echo ""

# 2. 创建正确的registries.conf
print_info "2. 创建正确的registries.conf..."

sudo tee /etc/containers/registries.conf > /dev/null << 'EOF'
unqualified-search-registries = ["docker.io"]

[[registry]]
prefix = "registry.ci.openshift.org"
location = "registry.ci.openshift.org"
mirror-by-digest-only = true

[[registry.mirror]]
location = "10.0.10.10:5000"
insecure = true

[[registry]]
prefix = "quay.io"
location = "quay.io"
mirror-by-digest-only = true

[[registry.mirror]]
location = "10.0.10.10:5000"
insecure = true

[[registry]]
prefix = "10.0.10.10:5000"
location = "10.0.10.10:5000"
insecure = true


EOF

print_success "registries.conf 已更新"
echo ""

# 3. 验证配置
print_info "3. 验证配置..."
echo "新的registries.conf内容:"
cat /etc/containers/registries.conf
echo ""

# 4. 重启容器运行时服务
print_info "4. 重启容器运行时服务..."
sudo systemctl restart crio
sudo systemctl restart crio-wipe
print_success "容器运行时服务已重启"
echo ""

# 5. 测试registry连通性
print_info "5. 测试registry连通性..."

echo "测试HTTP连接到10.0.10.10:5000:"
if curl -s --connect-timeout 10 http://10.0.10.10:5000/v2/_catalog; then
    print_success "HTTP连接成功"
else
    print_error "HTTP连接失败"
fi
echo ""

echo "测试HTTPS连接到10.0.10.10:5000:"
if curl -s --connect-timeout 10 -k https://10.0.10.10:5000/v2/_catalog; then
    print_success "HTTPS连接成功"
else
    print_error "HTTPS连接失败"
fi
echo ""

# 6. 测试镜像拉取
print_info "6. 测试镜像拉取..."

echo "测试拉取镜像: 10.0.10.10:5000/openshift/ocp/release:4.19"
if timeout 60 podman pull 10.0.10.10:5000/openshift/ocp/release:4.19; then
    print_success "镜像拉取成功"
else
    print_error "镜像拉取失败"
    echo "尝试使用HTTP协议:"
    timeout 30 podman pull --tls-verify=false 10.0.10.10:5000/openshift/ocp/release:4.19 || echo "仍然失败"
fi
echo ""

# 7. 检查镜像列表
print_info "7. 检查镜像列表..."
echo "当前镜像:"
podman images
echo ""

# 8. 测试registry.ci.openshift.org解析
print_info "8. 测试registry.ci.openshift.org解析..."
echo "域名解析结果:"
nslookup registry.ci.openshift.org
echo ""

echo "测试registry.ci.openshift.org连接:"
if curl -s --connect-timeout 10 http://registry.ci.openshift.org/v2/_catalog; then
    print_success "registry.ci.openshift.org HTTP连接成功"
else
    print_error "registry.ci.openshift.org HTTP连接失败"
fi
echo ""

# 9. 测试通过registry.ci.openshift.org拉取镜像
print_info "9. 测试通过registry.ci.openshift.org拉取镜像..."
echo "测试拉取镜像: registry.ci.openshift.org/openshift/ocp/release:4.19"
if timeout 60 podman pull registry.ci.openshift.org/openshift/ocp/release:4.19; then
    print_success "通过registry.ci.openshift.org拉取成功"
else
    print_error "通过registry.ci.openshift.org拉取失败"
fi
echo ""

print_success "Registry配置修复完成！"

REGISTRY_FIX

if [[ $? -eq 0 ]]; then
    print_success "Registry配置修复完成！"
else
    print_error "修复过程中出现错误"
    exit 1
fi

echo ""
print_info "📋 修复总结:"
echo "1. 更新了registries.conf配置"
echo "2. 设置了正确的insecure标志"
echo "3. 重启了容器运行时服务"
echo "4. 测试了registry连通性"
echo "5. 测试了镜像拉取功能"
</rewritten_file> 