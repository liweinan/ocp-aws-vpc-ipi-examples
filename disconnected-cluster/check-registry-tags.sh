#!/bin/bash

# 检查registry中可用的镜像标签

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

# Registry认证信息
REGISTRY_USER="admin"
REGISTRY_PASSWORD="admin123"
REGISTRY_URL="10.0.10.10:5000"

echo "=== Registry Tags Check ==="
echo "时间: $(date)"
echo "Registry URL: $REGISTRY_URL"
echo "Registry User: $REGISTRY_USER"
echo ""

# 检查SSH密钥
if [[ ! -f "$SSH_KEY" ]]; then
    print_error "SSH密钥不存在: $SSH_KEY"
    exit 1
fi

print_info "开始检查registry中的镜像标签..."

# 在bootstrap节点上执行检查
ssh -i "$SSH_KEY" ubuntu@"$BASTION_IP" "ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no core@$BOOTSTRAP_IP" << 'REGISTRY_TAGS_CHECK'

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

# Registry认证信息
REGISTRY_USER="admin"
REGISTRY_PASSWORD="admin123"
REGISTRY_URL="10.0.10.10:5000"

echo "=== Registry Tags Check on Bootstrap Node ==="
echo "主机名: $(hostname)"
echo "时间: $(date)"
echo ""

# 1. 获取registry中的所有镜像
print_info "1. 获取registry中的所有镜像..."
echo "Registry中的镜像列表:"
curl -s -k -u "$REGISTRY_USER:$REGISTRY_PASSWORD" "https://$REGISTRY_URL/v2/_catalog" | jq -r '.repositories[]' | sort
echo ""

# 2. 检查关键镜像的标签
print_info "2. 检查关键镜像的标签..."

# 关键镜像列表
KEY_IMAGES=(
    "openshift/ocp/release"
    "openshift/installer"
    "openshift/cli"
    "openshift/hyperkube"
    "openshift/etcd"
    "openshift/coredns"
)

for image in "${KEY_IMAGES[@]}"; do
    echo "检查镜像: $image"
    echo "可用标签:"
    if curl -s -k -u "$REGISTRY_USER:$REGISTRY_PASSWORD" "https://$REGISTRY_URL/v2/$image/tags/list" 2>/dev/null | jq -r '.tags[]?' 2>/dev/null | head -10; then
        print_success "获取标签成功"
    else
        print_error "获取标签失败或没有标签"
    fi
    echo ""
done

# 3. 检查release镜像的详细信息
print_info "3. 检查release镜像的详细信息..."
echo "openshift/ocp/release 镜像信息:"
echo "所有标签:"
curl -s -k -u "$REGISTRY_USER:$REGISTRY_PASSWORD" "https://$REGISTRY_URL/v2/openshift/ocp/release/tags/list" | jq .
echo ""

# 4. 尝试拉取不同的标签
print_info "4. 尝试拉取不同的标签..."

# 测试不同的标签
TEST_TAGS=(
    "4.19"
    "latest"
    "4.19.0"
    "4.19.0-0.nightly"
    "4.19.0-0.okd"
)

for tag in "${TEST_TAGS[@]}"; do
    echo "测试标签: $tag"
    if timeout 30 podman pull --tls-verify=false "$REGISTRY_URL/openshift/ocp/release:$tag" >/dev/null 2>&1; then
        print_success "标签 $tag 拉取成功"
    else
        print_error "标签 $tag 拉取失败"
    fi
    echo ""
done

# 5. 检查installer和cli镜像的标签
print_info "5. 检查installer和cli镜像的标签..."

echo "openshift/installer 标签:"
curl -s -k -u "$REGISTRY_USER:$REGISTRY_PASSWORD" "https://$REGISTRY_URL/v2/openshift/installer/tags/list" | jq . 2>/dev/null || echo "无法获取installer标签"
echo ""

echo "openshift/cli 标签:"
curl -s -k -u "$REGISTRY_USER:$REGISTRY_PASSWORD" "https://$REGISTRY_URL/v2/openshift/cli/tags/list" | jq . 2>/dev/null || echo "无法获取cli标签"
echo ""

# 6. 尝试拉取installer和cli的latest标签
print_info "6. 尝试拉取installer和cli的latest标签..."

echo "测试拉取 openshift/installer:latest"
if timeout 30 podman pull --tls-verify=false "$REGISTRY_URL/openshift/installer:latest" >/dev/null 2>&1; then
    print_success "installer:latest 拉取成功"
else
    print_error "installer:latest 拉取失败"
fi
echo ""

echo "测试拉取 openshift/cli:latest"
if timeout 30 podman pull --tls-verify=false "$REGISTRY_URL/openshift/cli:latest" >/dev/null 2>&1; then
    print_success "cli:latest 拉取成功"
else
    print_error "cli:latest 拉取失败"
fi
echo ""

# 7. 显示当前本地镜像
print_info "7. 显示当前本地镜像..."
echo "当前本地镜像:"
podman images
echo ""

print_success "Registry标签检查完成！"

REGISTRY_TAGS_CHECK

if [[ $? -eq 0 ]]; then
    print_success "Registry标签检查完成！"
else
    print_error "检查过程中出现错误"
    exit 1
fi

echo ""
print_info "📋 检查总结:"
echo "1. 检查了registry中的所有镜像"
echo "2. 检查了关键镜像的可用标签"
echo "3. 测试了不同标签的拉取"
echo "4. 检查了installer和cli镜像的标签"
echo "5. 尝试拉取了latest标签"
</rewritten_file> 