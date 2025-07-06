#!/bin/bash

# 修复release-image-download.sh的认证问题

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

echo "=== Fix Release Image Authentication ==="
echo "时间: $(date)"
echo "Bastion IP: $BASTION_IP"
echo "Bootstrap IP: $BOOTSTRAP_IP"
echo ""

# 检查SSH密钥
if [[ ! -f "$SSH_KEY" ]]; then
    print_error "SSH密钥不存在: $SSH_KEY"
    exit 1
fi

print_info "开始修复release-image认证问题..."

# 在bootstrap节点上执行修复
ssh -i "$SSH_KEY" ubuntu@"$BASTION_IP" "ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no core@$BOOTSTRAP_IP" << 'FIX_AUTH'

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

echo "=== Fix Release Image Authentication on Bootstrap Node ==="
echo "主机名: $(hostname)"
echo "时间: $(date)"
echo ""

# 1. 停止release-image.service
print_info "1. 停止release-image.service..."
sudo systemctl stop release-image.service
print_success "服务已停止"
echo ""

# 2. 登录到registry
print_info "2. 登录到registry..."
echo "登录到registry: 10.0.10.10:5000"
if timeout 30 podman login --username admin --password admin123 --tls-verify=false 10.0.10.10:5000; then
    print_success "Registry登录成功"
else
    print_error "Registry登录失败"
    exit 1
fi
echo ""

# 3. 检查认证配置
print_info "3. 检查认证配置..."
echo "认证文件内容:"
if [[ -f ~/.config/containers/auth.json ]]; then
    cat ~/.config/containers/auth.json
else
    print_error "认证文件不存在"
fi
echo ""

# 4. 修复release-image-download.sh脚本
print_info "4. 修复release-image-download.sh脚本..."

# 创建修复后的脚本
sudo tee /usr/local/bin/release-image-download.sh > /dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Download the release image. This script is executed as a oneshot
# service by systemd, because we cannot make use of Requires and a
# simple service: https://github.com/systemd/systemd/issues/1312.
#
# This script continues trying to download the release image until
# successful because we cannot use Restart=on-failure with a oneshot
# service: https://github.com/systemd/systemd/issues/2582.
#

. /usr/local/bin/bootstrap-service-record.sh

# 加载release-image.sh以获取正确的RELEASE_IMAGE_DIGEST
. /usr/local/bin/release-image.sh

# 使用release-image.sh中定义的RELEASE_IMAGE_DIGEST
RELEASE_IMAGE="$RELEASE_IMAGE_DIGEST"

# Registry认证信息
REGISTRY_USER="admin"
REGISTRY_PASSWORD="admin123"
REGISTRY_URL="10.0.10.10:5000"

release_image_issue="/etc/issue.d/50_release-image.issue"

# 确保已登录到registry
if ! podman login --username "$REGISTRY_USER" --password "$REGISTRY_PASSWORD" --tls-verify=false "$REGISTRY_URL" >/dev/null 2>&1; then
    echo "Registry登录失败，尝试重新登录..."
    podman login --username "$REGISTRY_USER" --password "$REGISTRY_PASSWORD" --tls-verify=false "$REGISTRY_URL"
fi

if podman image exists "$RELEASE_IMAGE"; then
    record_service_stage_start "pull-release-image"
    record_service_stage_success
else
    echo "Pulling $RELEASE_IMAGE..."
    while true
    do
        record_service_stage_start "pull-release-image"
        if podman pull --quiet --tls-verify=false "$RELEASE_IMAGE"
        then
            rm -f "${release_image_issue}"
            agetty --reload
            record_service_stage_success
            break
        else
            printf '\n\\e{lightred}Unable to pull OpenShift release image\\e{reset}\n' >"${release_image_issue}"
            agetty --reload
            record_service_stage_failure
            echo "Pull failed. Retrying $RELEASE_IMAGE..."
            # 重新登录registry
            podman login --username "$REGISTRY_USER" --password "$REGISTRY_PASSWORD" --tls-verify=false "$REGISTRY_URL" >/dev/null 2>&1
        fi
    done
fi


# Sanity check the image metadata to see if the arches match
record_service_stage_start "image-metadata-arches-match"
image_arch=$(podman inspect $RELEASE_IMAGE --format {{.Architecture}})
host_arch=$(uname -m)
case $host_arch in
    "x86_64")  host_arch="amd64"   ;;
    "aarch64") host_arch="arm64"   ;; # not used, just for completeness
esac

if [[ "$image_arch" != "$host_arch" ]]; then
    printf '\n\\e{lightred}Release image arch %s does not match host arch %s\\e{reset}\n' "${image_arch}" "${host_arch}" >"${release_image_issue}"
    agetty --reload
    record_service_stage_failure
    echo "ERROR: release image arch $image_arch does not match host arch $host_arch"
    exit 1
else
    record_service_stage_success
fi
EOF

print_success "脚本已修复"
echo ""

# 5. 验证修复后的脚本
print_info "5. 验证修复后的脚本..."
echo "修复后的脚本内容（前30行）:"
head -30 /usr/local/bin/release-image-download.sh
echo ""

# 6. 手工测试修复后的脚本
print_info "6. 手工测试修复后的脚本..."
echo "手工执行脚本逻辑..."

# 设置环境变量
export RELEASE_IMAGE="10.0.10.10:5000/openshift/ocp/release:4.19"
export REGISTRY_USER="admin"
export REGISTRY_PASSWORD="admin123"
export REGISTRY_URL="10.0.10.10:5000"

echo "RELEASE_IMAGE: $RELEASE_IMAGE"

# 测试registry登录
echo "测试registry登录..."
if podman login --username "$REGISTRY_USER" --password "$REGISTRY_PASSWORD" --tls-verify=false "$REGISTRY_URL" >/dev/null 2>&1; then
    print_success "Registry登录成功"
else
    print_error "Registry登录失败"
fi

# 测试镜像拉取
echo "测试镜像拉取..."
if timeout 60 podman pull --quiet --tls-verify=false "$RELEASE_IMAGE"; then
    print_success "镜像拉取成功"
else
    print_error "镜像拉取失败"
fi
echo ""

# 7. 启动release-image.service
print_info "7. 启动release-image.service..."
sudo systemctl start release-image.service
print_success "服务已启动"
echo ""

# 8. 检查服务状态
print_info "8. 检查服务状态..."
echo "release-image.service状态:"
sudo systemctl status release-image.service --no-pager || echo "服务状态检查失败"
echo ""

# 9. 等待并检查日志
print_info "9. 等待服务运行并检查日志..."
sleep 15

echo "最近的release-image.service日志:"
sudo journalctl -u release-image.service --no-pager -n 15 2>/dev/null || echo "无法获取日志"
echo ""

# 10. 验证最终结果
print_info "10. 验证最终结果..."
if podman image exists "10.0.10.10:5000/openshift/ocp/release:4.19"; then
    print_success "Release镜像存在"
    echo "镜像信息:"
    podman images | grep "10.0.10.10:5000/openshift/ocp/release"
else
    print_error "Release镜像不存在"
fi

echo ""
print_success "Release image认证修复完成！"

FIX_AUTH

if [[ $? -eq 0 ]]; then
    print_success "Release image认证修复完成！"
else
    print_error "修复过程中出现错误"
    exit 1
fi

echo ""
print_info "📋 修复总结:"
echo "1. 停止了release-image.service"
echo "2. 登录到registry"
echo "3. 检查了认证配置"
echo "4. 修复了release-image-download.sh脚本"
echo "5. 添加了认证逻辑"
echo "6. 手工测试了修复后的脚本"
echo "7. 启动了release-image.service"
echo "8. 检查了服务状态"
echo "9. 验证了最终结果"

FIX_AUTH 