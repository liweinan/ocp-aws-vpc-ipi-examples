#!/bin/bash

# 03.5-copy-infra-and-tools.sh
# 在 03-04 步之间运行，将 infra-output 和 04-prepare-install-config.sh 拷贝到 bastion host，并安装依赖工具

set -euo pipefail

BASTION_IP=$(cat ./infra-output/bastion-public-ip)
SSH_KEY=./infra-output/bastion-key.pem

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 1. 拷贝 infra-output 目录
printf "${BLUE}📦 拷贝 infra-output 到 bastion...${NC}\n"
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -r ./infra-output ubuntu@"$BASTION_IP":/home/ubuntu/

# 2. 拷贝 04-prepare-install-config.sh
printf "${BLUE}📦 拷贝 04-prepare-install-config.sh 到 bastion...${NC}\n"
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no ./04-prepare-install-config.sh ubuntu@"$BASTION_IP":/home/ubuntu/

# 3. 在 bastion host 上安装依赖工具
echo -e "${BLUE}🔧 在 bastion host 上安装依赖工具...${NC}"
ssh -i "$SSH_KEY" ubuntu@"$BASTION_IP" -o StrictHostKeyChecking=no '
  set -e
  sudo apt-get update
  sudo apt-get install -y jq curl tar
  if ! command -v yq >/dev/null 2>&1; then
    if command -v snap >/dev/null 2>&1; then
      sudo snap install yq
    else
      echo "yq not found and snapd not available, please install yq manually."; exit 1
    fi
  fi
  if ! command -v aws >/dev/null 2>&1; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip -o /tmp/awscliv2.zip -d /tmp/
    sudo /tmp/aws/install || true
    rm -rf /tmp/aws /tmp/awscliv2.zip
  fi
  echo "\n依赖工具安装完成："
  yq --version || true
  jq --version || true
  aws --version || true
  curl --version | head -n1 || true
  tar --version | head -n1 || true
'

printf "${GREEN}✅ 所有内容和依赖已准备好，可在 bastion host 上执行 04-prepare-install-config.sh${NC}\n" 