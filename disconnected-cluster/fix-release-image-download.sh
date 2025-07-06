#!/bin/bash

# 修复release-image-download.sh脚本，使其使用正确的本地registry

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

echo "=== Fix Release Image Download Script ==="
echo "时间: $(date)"
echo "Bastion IP: $BASTION_IP"
echo "Bootstrap IP: $BOOTSTRAP_IP"
echo ""

# 检查SSH密钥
if [[ ! -f "$SSH_KEY" ]]; then
    print_error "SSH密钥不存在: $SSH_KEY"
    exit 1
fi

print_info "开始修复release-image-download.sh脚本..."

# 在bootstrap节点上执行修复
ssh -i "$SSH_KEY" ubuntu@"$BASTION_IP" "ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no core@$BOOTSTRAP_IP" << 'FIX_RELEASE_IMAGE'

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

echo "=== Fix Release Image Download Script on Bootstrap Node ==="
echo "主机名: $(hostname)"
echo "时间: $(date)"
echo ""

# 1. 备份原始脚本
print_info "1. 备份原始脚本..."
if [[ -f /usr/local/bin/release-image-download.sh ]]; then
    sudo cp /usr/local/bin/release-image-download.sh /usr/local/bin/release-image-download.sh.backup
    print_success "脚本已备份"
else
    print_error "release-image-download.sh不存在"
    exit 1
fi
echo ""

# 2. 检查当前脚本内容
print_info "2. 检查当前脚本内容..."
echo "当前release-image-download.sh的RELEASE_IMAGE设置:"
grep "RELEASE_IMAGE=" /usr/local/bin/release-image-download.sh || echo "未找到RELEASE_IMAGE设置"
echo ""

# 3. 修复脚本
print_info "3. 修复脚本..."

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

release_image_issue="/etc/issue.d/50_release-image.issue"
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

# 4. 验证修复后的脚本
print_info "4. 验证修复后的脚本..."
echo "修复后的RELEASE_IMAGE设置:"
grep "RELEASE_IMAGE=" /usr/local/bin/release-image-download.sh
echo ""

echo "修复后的脚本内容（前20行）:"
head -20 /usr/local/bin/release-image-download.sh
echo ""

# 5. 重启release-image.service
print_info "5. 重启release-image.service..."
sudo systemctl stop release-image.service
sudo systemctl start release-image.service
print_success "服务已重启"
echo ""

# 6. 检查服务状态
print_info "6. 检查服务状态..."
echo "release-image.service状态:"
sudo systemctl status release-image.service --no-pager || echo "服务状态检查失败"
echo ""

# 7. 等待一段时间后检查日志
print_info "7. 等待服务运行并检查日志..."
sleep 10

echo "最近的release-image.service日志:"
sudo journalctl -u release-image.service --no-pager -n 10 2>/dev/null || echo "无法获取日志"
echo ""

# 8. 测试镜像拉取
print_info "8. 测试镜像拉取..."
echo "测试拉取RELEASE_IMAGE_DIGEST:"
source /usr/local/bin/release-image.sh
echo "RELEASE_IMAGE_DIGEST: $RELEASE_IMAGE_DIGEST"

if timeout 60 podman pull --tls-verify=false "$RELEASE_IMAGE_DIGEST"; then
    print_success "镜像拉取成功"
else
    print_error "镜像拉取失败"
fi
echo ""

# 9. 检查镜像是否存在
print_info "9. 检查镜像是否存在..."
if podman image exists "$RELEASE_IMAGE_DIGEST"; then
    print_success "镜像已存在"
    echo "镜像信息:"
    podman images | grep "$RELEASE_IMAGE_DIGEST"
else
    print_error "镜像不存在"
fi
echo ""

print_success "Release image download脚本修复完成！"

FIX_RELEASE_IMAGE

if [[ $? -eq 0 ]]; then
    print_success "Release image download脚本修复完成！"
else
    print_error "修复过程中出现错误"
    exit 1
fi

echo ""
print_info "📋 修复总结:"
echo "1. 备份了原始脚本"
echo "2. 修复了RELEASE_IMAGE设置"
echo "3. 添加了--tls-verify=false参数"
echo "4. 重启了release-image.service"
echo "5. 验证了修复效果"
echo "6. 测试了镜像拉取功能"

EOF

FIX_RELEASE_IMAGE 