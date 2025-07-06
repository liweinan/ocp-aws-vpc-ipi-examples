#!/bin/bash

# 检查bastion host上的registry配置

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
SSH_KEY="./ci-operator/disconnected-cluster/infra-output/bastion-key.pem"

echo "=== Bastion Registry Check ==="
echo "时间: $(date)"
echo "Bastion IP: $BASTION_IP"
echo ""

# 检查SSH密钥
if [[ ! -f "$SSH_KEY" ]]; then
    print_error "SSH密钥不存在: $SSH_KEY"
    exit 1
fi

print_info "开始检查bastion registry配置..."

# 在bastion host上执行检查
ssh -i "$SSH_KEY" ubuntu@"$BASTION_IP" << 'BASTION_CHECK'

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

echo "=== Bastion Registry Check ==="
echo "主机名: $(hostname)"
echo "时间: $(date)"
echo ""

# 1. 检查registry容器状态
print_info "1. 检查registry容器状态..."
echo "Docker容器列表:"
sudo docker ps -a | grep registry || echo "未找到registry容器"
echo ""

# 2. 检查registry服务状态
print_info "2. 检查registry服务状态..."
echo "Registry服务状态:"
sudo systemctl status registry 2>/dev/null || echo "Registry服务未运行"
echo ""

# 3. 检查端口监听
print_info "3. 检查端口监听..."
echo "端口5000监听状态:"
sudo netstat -tlnp | grep :5000 || echo "端口5000未监听"
echo ""

# 4. 检查registry配置
print_info "4. 检查registry配置..."
if [[ -f /etc/docker-distribution/registry/config.yml ]]; then
    echo "Registry配置文件:"
    cat /etc/docker-distribution/registry/config.yml
else
    echo "Registry配置文件不存在"
fi
echo ""

# 5. 测试本地registry访问
print_info "5. 测试本地registry访问..."
echo "测试HTTP访问:"
curl -s http://localhost:5000/v2/_catalog || echo "HTTP访问失败"
echo ""

echo "测试HTTPS访问:"
curl -s -k https://localhost:5000/v2/_catalog || echo "HTTPS访问失败"
echo ""

# 6. 检查registry日志
print_info "6. 检查registry日志..."
echo "最近的registry日志:"
sudo journalctl -u registry --no-pager -n 20 2>/dev/null || echo "无法获取registry日志"
echo ""

# 7. 检查镜像列表
print_info "7. 检查镜像列表..."
echo "Registry中的镜像:"
curl -s http://localhost:5000/v2/_catalog | jq . 2>/dev/null || curl -s http://localhost:5000/v2/_catalog || echo "无法获取镜像列表"
echo ""

# 8. 检查认证配置
print_info "8. 检查认证配置..."
echo "检查是否有认证配置:"
if [[ -f /etc/docker-distribution/registry/config.yml ]]; then
    grep -A 10 -B 10 "auth" /etc/docker-distribution/registry/config.yml || echo "未找到认证配置"
else
    echo "配置文件不存在"
fi
echo ""

# 9. 测试镜像拉取
print_info "9. 测试镜像拉取..."
echo "测试从本地registry拉取镜像:"
if sudo docker pull localhost:5000/openshift/ocp/release:4.19 2>/dev/null; then
    print_success "本地拉取成功"
else
    print_error "本地拉取失败"
    echo "尝试查看详细错误:"
    sudo docker pull localhost:5000/openshift/ocp/release:4.19 2>&1 | head -5
fi
echo ""

print_success "Bastion registry检查完成！"

BASTION_CHECK

if [[ $? -eq 0 ]]; then
    print_success "Bastion registry检查完成！"
else
    print_error "检查过程中出现错误"
    exit 1
fi

echo ""
print_info "📋 检查总结:"
echo "1. 检查了registry容器状态"
echo "2. 检查了registry服务状态"
echo "3. 检查了端口监听"
echo "4. 检查了registry配置"
echo "5. 测试了本地访问"
echo "6. 检查了日志"
echo "7. 检查了镜像列表"
echo "8. 检查了认证配置"
echo "9. 测试了镜像拉取"
</rewritten_file> 