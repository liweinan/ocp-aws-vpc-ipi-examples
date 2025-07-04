#!/bin/bash

# 04-copy-infra-and-tools.sh
# 在 03 步之后运行，将 infra-output 和后续安装脚本拷贝到 bastion host，并安装所有依赖工具

set -euo pipefail

BASTION_IP=$(cat ./infra-output/bastion-public-ip)
SSH_KEY=./infra-output/bastion-key.pem

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 1. 在 bastion host 上创建目标目录
printf "${BLUE}📁 创建 bastion host 目录结构...${NC}\n"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$BASTION_IP" "mkdir -p /home/ubuntu/disconnected-cluster"

# 2. 拷贝 infra-output 目录
printf "${BLUE}📦 拷贝 infra-output 到 bastion...${NC}\n"
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -r ./infra-output ubuntu@"$BASTION_IP":/home/ubuntu/disconnected-cluster/

# 3. 拷贝安装相关脚本到 bastion
printf "${BLUE}📦 拷贝安装相关脚本到 bastion...${NC}\n"
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no ./05-setup-mirror-registry.sh ubuntu@"$BASTION_IP":/home/ubuntu/disconnected-cluster/ 2>/dev/null || echo "05-setup-mirror-registry.sh not found, skipping..."
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no ./06-sync-images-robust.sh ubuntu@"$BASTION_IP":/home/ubuntu/disconnected-cluster/ 2>/dev/null || echo "06-sync-images-robust.sh not found, skipping..."
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no ./sync-single-image.sh ubuntu@"$BASTION_IP":/home/ubuntu/disconnected-cluster/ 2>/dev/null || echo "sync-single-image.sh not found, skipping..."
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no ./07-prepare-install-config.sh ubuntu@"$BASTION_IP":/home/ubuntu/disconnected-cluster/ 2>/dev/null || echo "07-prepare-install-config.sh not found, skipping..."
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no ./08-install-cluster.sh ubuntu@"$BASTION_IP":/home/ubuntu/disconnected-cluster/ 2>/dev/null || echo "08-install-cluster.sh not found, skipping..."
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no ./09-verify-cluster.sh ubuntu@"$BASTION_IP":/home/ubuntu/disconnected-cluster/ 2>/dev/null || echo "09-verify-cluster.sh not found, skipping..."
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no ./10-cleanup.sh ubuntu@"$BASTION_IP":/home/ubuntu/disconnected-cluster/ 2>/dev/null && echo "10-cleanup.sh uploaded to bastion." || echo "10-cleanup.sh not found, skipping..."

# 4. 在 bastion host 上安装依赖工具
echo -e "${BLUE}🔧 在 bastion host 上安装依赖工具...${NC}"
ssh -i "$SSH_KEY" ubuntu@"$BASTION_IP" -o StrictHostKeyChecking=no '
  set -e
  echo "📦 更新包列表..."
  sudo apt-get update
  
  echo "📦 安装基础工具..."
  sudo apt-get install -y jq curl tar wget unzip apache2-utils
  
  echo "📦 安装容器工具..."
  if ! command -v podman >/dev/null 2>&1; then
    sudo apt-get install -y podman
    echo "✅ podman 安装完成"
  else
    echo "✅ podman 已安装"
  fi
  
  echo "ℹ️  跳过 docker 安装 (在断网环境中使用 podman 即可)"
  
  echo "📦 安装 yq..."
  if ! command -v yq >/dev/null 2>&1; then
    if command -v snap >/dev/null 2>&1; then
      sudo snap install yq
      echo "✅ yq 通过 snap 安装完成"
    else
      # 备用方案：直接下载二进制文件
      wget -qO /tmp/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
      sudo chmod +x /tmp/yq
      sudo mv /tmp/yq /usr/local/bin/yq
      echo "✅ yq 通过二进制文件安装完成"
    fi
  else
    echo "✅ yq 已安装"
  fi
  
  echo "📦 安装 AWS CLI..."
  if ! command -v aws >/dev/null 2>&1; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip -o /tmp/awscliv2.zip -d /tmp/
    sudo /tmp/aws/install || true
    rm -rf /tmp/aws /tmp/awscliv2.zip
    echo "✅ AWS CLI 安装完成"
  else
    echo "✅ AWS CLI 已安装"
  fi
  
  echo "📦 安装 OpenSSL..."
  if ! command -v openssl >/dev/null 2>&1; then
    sudo apt-get install -y openssl
    echo "✅ OpenSSL 安装完成"
  else
    echo "✅ OpenSSL 已安装"
  fi
  
  echo "📦 安装 oc 客户端..."
  if ! command -v oc >/dev/null 2>&1; then
    wget -O /tmp/openshift-client-linux.tar.gz https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz
    sudo tar -xzf /tmp/openshift-client-linux.tar.gz -C /usr/local/bin/
    sudo chmod +x /usr/local/bin/oc /usr/local/bin/kubectl
    rm -f /tmp/openshift-client-linux.tar.gz
    echo "✅ oc 客户端安装完成"
  else
    echo "✅ oc 客户端已安装"
  fi
  
  echo ""
  echo "🔍 验证安装的工具版本："
  echo "   yq: $(yq --version 2>/dev/null || echo "未安装")"
  echo "   jq: $(jq --version 2>/dev/null || echo "未安装")"
  echo "   aws: $(aws --version 2>/dev/null || echo "未安装")"
  echo "   curl: $(curl --version 2>/dev/null | head -n1 || echo "未安装")"
  echo "   tar: $(tar --version 2>/dev/null | head -n1 || echo "未安装")"
  echo "   wget: $(wget --version 2>/dev/null | head -n1 || echo "未安装")"
  echo "   unzip: $(unzip -v 2>/dev/null | head -n1 || echo "未安装")"
  echo "   podman: $(podman --version 2>/dev/null || echo "未安装")"
  echo "   openssl: $(openssl version 2>/dev/null || echo "未安装")"
  echo "   apache2-utils: $(htpasswd -h 2>/dev/null | head -n1 || echo "未安装")"
  echo "   oc: $(oc version --client 2>/dev/null || echo "未安装")"
  
  echo ""
  echo "🔧 设置容器工具权限..."
  echo "✅ podman 无需额外权限设置，可直接使用"
'

printf "${GREEN}✅ 所有内容和依赖已准备好，可在 bastion host 上执行后续步骤：${NC}\n"
printf "${GREEN}   - 05-setup-mirror-registry.sh (设置镜像仓库)${NC}\n"
printf "${GREEN}   - 06-sync-images-robust.sh (同步镜像，改进版)${NC}\n"
printf "${GREEN}   - 07-prepare-install-config.sh (准备安装配置)${NC}\n"
printf "${GREEN}   - 08-install-cluster.sh (安装集群)${NC}\n"
printf "${GREEN}   - 09-verify-cluster.sh (验证集群)${NC}\n"
printf "${YELLOW}📝 注意：所有工具已安装完毕，镜像同步脚本已更新为改进版本${NC}\n" 