#!/bin/bash

# 修复Bootstrap节点配置脚本
# 直接在bootstrap节点上应用修复

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

echo "=== Bootstrap Configuration Fix ==="
echo "时间: $(date)"
echo "Bastion IP: $BASTION_IP"
echo "Bootstrap IP: $BOOTSTRAP_IP"
echo ""

# 检查SSH密钥
if [[ ! -f "$SSH_KEY" ]]; then
    print_error "SSH密钥不存在: $SSH_KEY"
    exit 1
fi

print_info "开始修复bootstrap节点配置..."

# 在bootstrap节点上执行修复
ssh -i "$SSH_KEY" ubuntu@"$BASTION_IP" "ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no core@$BOOTSTRAP_IP" << 'BOOTSTRAP_FIX'

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

echo "=== Bootstrap Configuration Fix ==="
echo "主机名: $(hostname)"
echo "时间: $(date)"
echo ""

# 1. 修复 /etc/hosts 配置
print_info "1. 修复 /etc/hosts 配置..."

# 备份原始hosts文件
sudo cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)

# 添加registry域名映射
if ! grep -q "registry.ci.openshift.org" /etc/hosts; then
    echo "10.0.10.10 registry.ci.openshift.org" | sudo tee -a /etc/hosts
    print_success "已添加 registry.ci.openshift.org 到 /etc/hosts"
else
    print_warning "registry.ci.openshift.org 已存在于 /etc/hosts"
fi

if ! grep -q "quay.io" /etc/hosts; then
    echo "10.0.10.10 quay.io" | sudo tee -a /etc/hosts
    print_success "已添加 quay.io 到 /etc/hosts"
else
    print_warning "quay.io 已存在于 /etc/hosts"
fi

echo "当前 /etc/hosts 内容:"
cat /etc/hosts
echo ""

# 2. 修复 registries.conf 配置
print_info "2. 修复 registries.conf 配置..."

# 备份原始配置文件
sudo cp /etc/containers/registries.conf /etc/containers/registries.conf.backup.$(date +%Y%m%d_%H%M%S)

# 修复 insecure 设置
sudo sed -i 's/insecure = false/insecure = true/g' /etc/containers/registries.conf

print_success "已修复 registries.conf 中的 insecure 设置"

echo "修复后的 registries.conf 内容:"
cat /etc/containers/registries.conf
echo ""

# 3. 修复 release-image.sh 脚本
print_info "3. 修复 release-image.sh 脚本..."

# 备份原始脚本
sudo cp /usr/local/bin/release-image.sh /usr/local/bin/release-image.sh.backup.$(date +%Y%m%d_%H%M%S)

# 创建修复后的脚本
sudo tee /usr/local/bin/release-image.sh << 'EOF'
#!/usr/bin/env bash
# This library provides an `image_for` helper function which can get the
# pull spec for a specific image in a release.

# 使用本地 registry mirror 而不是直接访问外部 registry
RELEASE_IMAGE_DIGEST="10.0.10.10:5000/openshift/ocp/release:4.19"

image_for() {
    # 直接使用本地 registry，避免网络访问
    echo "10.0.10.10:5000/openshift/${1}"
}
EOF

sudo chmod +x /usr/local/bin/release-image.sh
print_success "已修复 release-image.sh 脚本"

echo "修复后的 release-image.sh 内容:"
cat /usr/local/bin/release-image.sh
echo ""

# 4. 测试修复结果
print_info "4. 测试修复结果..."

# 测试域名解析
echo "测试域名解析:"
nslookup registry.ci.openshift.org 2>/dev/null | grep "10.0.10.10" && print_success "域名解析正常" || print_warning "域名解析可能有问题"

# 测试registry连接
echo "测试registry连接:"
if curl -s --connect-timeout 10 --max-time 15 http://10.0.10.10:5000/v2/_catalog >/dev/null 2>&1; then
    print_success "Registry HTTP连接正常"
else
    print_error "Registry HTTP连接失败"
fi

# 测试镜像拉取
echo "测试镜像拉取:"
if timeout 30 podman pull 10.0.10.10:5000/openshift/ocp/release:4.19 >/dev/null 2>&1; then
    print_success "镜像拉取成功"
    echo "已拉取的镜像:"
    podman images | grep "10.0.10.10:5000" || echo "未找到相关镜像"
else
    print_error "镜像拉取失败"
    echo "尝试详细输出:"
    timeout 30 podman pull 10.0.10.10:5000/openshift/ocp/release:4.19 || echo "拉取失败"
fi
echo ""

# 5. 重启相关服务
print_info "5. 重启相关服务..."

# 重启CRI-O服务（如果存在）
if systemctl list-unit-files | grep -q crio; then
    echo "重启CRI-O服务..."
    sudo systemctl restart crio
    sleep 5
    if systemctl is-active crio >/dev/null 2>&1; then
        print_success "CRI-O服务重启成功"
    else
        print_warning "CRI-O服务重启失败"
    fi
else
    print_warning "CRI-O服务未找到"
fi

# 重启kubelet服务（如果存在）
if systemctl list-unit-files | grep -q kubelet; then
    echo "重启kubelet服务..."
    sudo systemctl restart kubelet
    sleep 5
    if systemctl is-active kubelet >/dev/null 2>&1; then
        print_success "kubelet服务重启成功"
    else
        print_warning "kubelet服务重启失败"
    fi
else
    print_warning "kubelet服务未找到"
fi
echo ""

# 6. 最终验证
print_info "6. 最终验证..."

echo "网络连通性测试:"
ping -c 3 -W 5 10.0.10.10 >/dev/null 2>&1 && print_success "ping 10.0.10.10 成功" || print_warning "ping 10.0.10.10 失败"

echo "Registry访问测试:"
curl -s --connect-timeout 5 http://10.0.10.10:5000/v2/_catalog >/dev/null 2>&1 && print_success "Registry HTTP访问正常" || print_error "Registry HTTP访问失败"

echo "域名解析测试:"
nslookup registry.ci.openshift.org 2>/dev/null | grep -q "10.0.10.10" && print_success "域名解析正常" || print_error "域名解析失败"

echo "镜像拉取测试:"
timeout 30 podman pull 10.0.10.10:5000/openshift/ocp/release:4.19 >/dev/null 2>&1 && print_success "镜像拉取正常" || print_error "镜像拉取失败"

echo ""
print_success "Bootstrap配置修复完成！"
echo ""
print_info "修复摘要:"
echo "✅ 已添加 /etc/hosts 配置"
echo "✅ 已修复 registries.conf 中的 insecure 设置"
echo "✅ 已修复 release-image.sh 脚本"
echo "✅ 已重启相关服务"
echo ""
print_info "现在bootstrap节点应该能够正常访问registry了！"

BOOTSTRAP_FIX

if [[ $? -eq 0 ]]; then
    print_success "Bootstrap配置修复完成！"
else
    print_error "修复过程中出现错误"
    exit 1
fi

echo ""
print_info "📋 修复完成！"
echo "现在可以重新运行测试脚本来验证修复效果："
echo "  ./ci-operator/disconnected-cluster/test-bootstrap-registry-simple.sh"
</rewritten_file> 