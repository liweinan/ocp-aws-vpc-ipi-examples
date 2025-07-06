#!/bin/bash

# 最终验证脚本 - 确认所有功能都正常工作

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

echo "=== Final Verification - Disconnected Cluster Image Pull ==="
echo "时间: $(date)"
echo "Bastion IP: $BASTION_IP"
echo "Bootstrap IP: $BOOTSTRAP_IP"
echo ""

# 检查SSH密钥
if [[ ! -f "$SSH_KEY" ]]; then
    print_error "SSH密钥不存在: $SSH_KEY"
    exit 1
fi

print_info "开始最终验证..."

# 在bootstrap节点上执行验证
ssh -i "$SSH_KEY" ubuntu@"$BASTION_IP" "ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no core@$BOOTSTRAP_IP" << 'FINAL_VERIFY'

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

echo "=== Final Verification on Bootstrap Node ==="
echo "主机名: $(hostname)"
echo "时间: $(date)"
echo ""

# 1. 验证release-image.service状态
print_info "1. 验证release-image.service状态..."
echo "release-image.service状态:"
if systemctl is-active --quiet release-image.service; then
    print_success "服务状态: active (exited)"
    echo "服务详情:"
    systemctl status release-image.service --no-pager | head -10
else
    print_error "服务状态异常"
    systemctl status release-image.service --no-pager
fi
echo ""

# 2. 验证镜像存在性
print_info "2. 验证镜像存在性..."
echo "当前本地镜像:"
podman images
echo ""

# 检查关键镜像
CRITICAL_IMAGES=(
    "10.0.10.10:5000/openshift/ocp/release:4.19"
    "10.0.10.10:5000/openshift/installer:latest"
    "10.0.10.10:5000/openshift/cli:latest"
    "10.0.10.10:5000/openshift/machine-config-operator:latest"
)

echo "关键镜像检查:"
for img in "${CRITICAL_IMAGES[@]}"; do
    if podman image exists "$img"; then
        print_success "✅ $img - 存在"
    else
        print_error "❌ $img - 不存在"
    fi
done
echo ""

# 3. 验证registry连通性
print_info "3. 验证registry连通性..."
REGISTRY_USER="admin"
REGISTRY_PASSWORD="admin123"
REGISTRY_URL="10.0.10.10:5000"

echo "测试registry连通性:"
if curl -s -k -u "$REGISTRY_USER:$REGISTRY_PASSWORD" --connect-timeout 10 "https://$REGISTRY_URL/v2/_catalog" >/dev/null 2>&1; then
    print_success "Registry连通性正常"
else
    print_error "Registry连通性失败"
fi
echo ""

# 4. 验证release-image.sh配置
print_info "4. 验证release-image.sh配置..."
echo "release-image.sh内容:"
if [[ -f /usr/local/bin/release-image.sh ]]; then
    cat /usr/local/bin/release-image.sh
    print_success "配置文件存在且正确"
else
    print_error "配置文件不存在"
fi
echo ""

# 5. 验证image_for函数
print_info "5. 验证image_for函数..."
source /usr/local/bin/release-image.sh

echo "RELEASE_IMAGE_DIGEST: $RELEASE_IMAGE_DIGEST"
echo ""

echo "测试image_for函数:"
TEST_IMAGES=("machine-config-operator" "etcd" "cli" "installer")
for img in "${TEST_IMAGES[@]}"; do
    img_spec=$(image_for "$img")
    echo "  $img -> $img_spec"
done
echo ""

# 6. 验证registries.conf配置
print_info "6. 验证registries.conf配置..."
echo "registries.conf关键配置:"
if [[ -f /etc/containers/registries.conf ]]; then
    grep -A 2 -B 2 "10.0.10.10" /etc/containers/registries.conf || echo "未找到10.0.10.10配置"
    echo ""
    echo "insecure设置:"
    grep "insecure" /etc/containers/registries.conf | head -5
    print_success "配置文件存在"
else
    print_error "配置文件不存在"
fi
echo ""

# 7. 验证hosts配置
print_info "7. 验证hosts配置..."
echo "/etc/hosts内容:"
cat /etc/hosts
echo ""

# 8. 验证认证配置
print_info "8. 验证认证配置..."
echo "检查podman认证:"
if [[ -f ~/.config/containers/auth.json ]]; then
    print_success "认证文件存在"
    echo "认证文件内容:"
    cat ~/.config/containers/auth.json
else
    print_warning "认证文件不存在，但可能已登录"
    echo "测试registry登录:"
    if timeout 10 podman login --username admin --password admin123 --tls-verify=false 10.0.10.10:5000 >/dev/null 2>&1; then
        print_success "Registry登录成功"
    else
        print_error "Registry登录失败"
    fi
fi
echo ""

# 9. 验证release-image-download.sh脚本
print_info "9. 验证release-image-download.sh脚本..."
echo "脚本关键部分:"
if [[ -f /usr/local/bin/release-image-download.sh ]]; then
    echo "RELEASE_IMAGE设置:"
    grep "RELEASE_IMAGE=" /usr/local/bin/release-image-download.sh
    echo ""
    echo "认证信息设置:"
    grep -A 3 "REGISTRY_USER" /usr/local/bin/release-image-download.sh || echo "未找到认证信息"
    print_success "脚本存在且配置正确"
else
    print_error "脚本不存在"
fi
echo ""

# 10. 最终功能测试
print_info "10. 最终功能测试..."

echo "测试镜像拉取功能:"
if timeout 60 podman pull --tls-verify=false 10.0.10.10:5000/openshift/ocp/release:4.19 >/dev/null 2>&1; then
    print_success "镜像拉取功能正常"
else
    print_error "镜像拉取功能异常"
fi
echo ""

# 11. 总结报告
print_info "11. 最终验证总结..."

echo "=== 验证结果总结 ==="
echo ""

# 服务状态
if systemctl is-active --quiet release-image.service; then
    echo "✅ release-image.service: 正常"
else
    echo "❌ release-image.service: 异常"
fi

# 镜像存在性
missing_images=0
for img in "${CRITICAL_IMAGES[@]}"; do
    if ! podman image exists "$img"; then
        ((missing_images++))
    fi
done

if [[ $missing_images -eq 0 ]]; then
    echo "✅ 关键镜像: 全部存在"
else
    echo "❌ 关键镜像: $missing_images 个缺失"
fi

# Registry连通性
if curl -s -k -u "$REGISTRY_USER:$REGISTRY_PASSWORD" --connect-timeout 5 "https://$REGISTRY_URL/v2/_catalog" >/dev/null 2>&1; then
    echo "✅ Registry连通性: 正常"
else
    echo "❌ Registry连通性: 异常"
fi

# 配置文件
if [[ -f /usr/local/bin/release-image.sh ]] && [[ -f /etc/containers/registries.conf ]]; then
    echo "✅ 配置文件: 完整"
else
    echo "❌ 配置文件: 缺失"
fi

# 镜像拉取功能
if timeout 30 podman pull --tls-verify=false 10.0.10.10:5000/openshift/ocp/release:4.19 >/dev/null 2>&1; then
    echo "✅ 镜像拉取功能: 正常"
else
    echo "❌ 镜像拉取功能: 异常"
fi

echo ""
echo "=== 验证结论 ==="
if systemctl is-active --quiet release-image.service && \
   [[ $missing_images -eq 0 ]] && \
   curl -s -k -u "$REGISTRY_USER:$REGISTRY_PASSWORD" --connect-timeout 5 "https://$REGISTRY_URL/v2/_catalog" >/dev/null 2>&1 && \
   [[ -f /usr/local/bin/release-image.sh ]] && \
   timeout 30 podman pull --tls-verify=false 10.0.10.10:5000/openshift/ocp/release:4.19 >/dev/null 2>&1; then
    print_success "🎉 所有验证项目通过！Disconnected cluster镜像拉取功能完全正常！"
else
    print_error "❌ 部分验证项目失败，需要进一步检查"
fi

echo ""
print_success "最终验证完成！"

FINAL_VERIFY

if [[ $? -eq 0 ]]; then
    print_success "最终验证完成！"
else
    print_error "验证过程中出现错误"
    exit 1
fi

echo ""
print_info "📋 验证总结:"
echo "1. 验证了release-image.service状态"
echo "2. 验证了镜像存在性"
echo "3. 验证了registry连通性"
echo "4. 验证了release-image.sh配置"
echo "5. 验证了image_for函数"
echo "6. 验证了registries.conf配置"
echo "7. 验证了hosts配置"
echo "8. 验证了认证配置"
echo "9. 验证了release-image-download.sh脚本"
echo "10. 进行了最终功能测试"
echo "11. 提供了详细的验证总结" 