# Disconnected Cluster Architecture - 真正的断网集群架构

## 概述

本文档说明了真正的 disconnected OpenShift 集群架构，以及我们对基础设施脚本的修改。

## 真正的 Disconnected Cluster 架构

### ❌ 错误的架构（之前）
```
Internet
    ↓
Bastion Host (公网子网)
    ↓
NAT Gateway (允许私有子网访问互联网)
    ↓
Private Subnets (集群节点，可以访问互联网)
```

**问题：** 这不是真正的 disconnected cluster，因为集群节点仍然可以访问互联网。

### ✅ 正确的架构（现在）
```
Internet
    ↓
Bastion Host (公网子网，有公网IP，可以访问互联网)
    ↓
Private Subnets (集群节点，完全隔离，无互联网访问)
    ↓
镜像仓库 (在 bastion host 上，集群节点通过内网访问)
```

**特点：**
- 集群节点完全无法访问互联网
- 只有 bastion host 可以访问互联网（用于镜像同步）
- 集群节点通过内网访问 bastion host 的镜像仓库

## 主要修改

### 1. 移除 NAT Gateway

**修改前：**
```bash
# 创建 NAT Gateway
local nat_gateway_id=$(aws ec2 create-nat-gateway \
    --subnet-id "$first_public_subnet" \
    --allocation-id "$eip_id" \
    --region "$region" \
    --query 'NatGateway.NatGatewayId' \
    --output text)

# 为私有子网添加互联网路由
aws ec2 create-route \
    --route-table-id "$private_rt_id" \
    --destination-cidr-block 0.0.0.0/0 \
    --nat-gateway-id "$nat_gateway_id" \
    --region "$region"
```

**修改后：**
```bash
# 跳过 NAT Gateway 创建
echo "   Skipping NAT Gateway creation for disconnected cluster..."
echo "   Private subnets will be completely isolated from internet"

# 私有子网无互联网路由
echo "   Private subnets configured with no internet access"
```

### 2. 更新安全组配置

**修改前：**
```bash
# 允许从任何地方访问镜像仓库
aws ec2 authorize-security-group-ingress \
    --group-id "$bastion_sg_id" \
    --protocol tcp \
    --port 5000 \
    --cidr 0.0.0.0/0 \
    --region "$region"
```

**修改后：**
```bash
# 只允许从 VPC 内部访问镜像仓库
aws ec2 authorize-security-group-ingress \
    --group-id "$bastion_sg_id" \
    --protocol tcp \
    --port 5000 \
    --cidr "$vpc_cidr" \
    --region "$region"
```

### 3. 更新操作系统和用户

**修改前：**
- Amazon Linux 2023
- 用户：ec2-user
- 包管理器：dnf

**修改后：**
- Ubuntu 22.04
- 用户：ubuntu
- 包管理器：apt

### 4. 预配置镜像仓库

**修改前：**
- 需要手动设置镜像仓库
- 使用 Docker

**修改后：**
- 自动启动 Podman 镜像仓库
- 预配置认证（admin/admin123）
- 自动创建必要的目录和脚本

## 网络流量说明

### Bastion Host 流量
```
Internet ←→ Bastion Host (SSH, HTTP, HTTPS, 镜像同步)
```

### 集群节点流量
```
集群节点 → Bastion Host (镜像仓库访问)
集群节点 ←→ 集群节点 (集群内部通信)
集群节点 → 无互联网访问
```

### 镜像仓库访问
```
集群节点 → Bastion Host:5000 (HTTP)
集群节点 → Bastion Host:22 (SSH，用于管理)
```

## 安全优势

1. **完全隔离**：集群节点无法访问互联网
2. **最小攻击面**：只有 bastion host 暴露在互联网上
3. **内网通信**：集群节点通过内网访问镜像仓库
4. **访问控制**：镜像仓库只允许 VPC 内部访问

## 使用场景

这种架构适用于：
- 高安全要求的环境
- 政府、金融等合规要求
- 完全离线的工作负载
- 需要严格控制网络访问的场景

## 验证断网状态

可以通过以下方式验证集群确实断网：

```bash
# 在集群节点上测试
curl -I https://www.google.com  # 应该失败
curl -I https://quay.io         # 应该失败
curl -I http://bastion-ip:5000  # 应该成功（内网访问）
```

## 注意事项

1. **镜像同步**：所有需要的镜像必须在安装前同步到 bastion host
2. **更新**：集群更新需要手动同步新镜像
3. **监控**：需要内网监控解决方案
4. **备份**：需要内网备份策略

## 总结

通过这些修改，我们实现了真正的 disconnected OpenShift 集群：
- ✅ 集群节点完全无法访问互联网
- ✅ 只有 bastion host 可以访问互联网
- ✅ 镜像仓库通过内网访问
- ✅ 符合 disconnected cluster 的定义和要求 