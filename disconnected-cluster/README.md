# OpenShift Disconnected Cluster Installation Guide

本指南介绍如何在AWS上安装一个完全断网的OpenShift集群，包括镜像仓库的搭建和配置。

## 概述

Disconnected cluster（断网集群）是一个完全隔离的OpenShift环境，不依赖外部网络连接。这种部署方式适用于：
- 高安全要求的环境
- 合规性要求（如政府、金融等）
- 网络隔离的生产环境
- 离线开发和测试环境

## 安装流程

整个安装过程分为以下几个步骤：

1. **准备基础设施** - 创建VPC、子网、安全组等
2. **复制凭证** - 将AWS凭证、SSH密钥和pull secret复制到bastion host
3. **搭建镜像仓库** - 在bastion host上部署私有镜像仓库
4. **同步镜像** - 从外部环境同步OpenShift镜像到私有仓库
5. **配置安装环境** - 准备disconnected cluster的安装配置
6. **创建和修改Manifests** - 生成并自定义OpenShift manifests以支持断网环境
7. **安装集群** - 使用私有镜像仓库安装OpenShift集群
8. **验证和配置** - 验证集群功能并配置后续使用

## 脚本说明

| 脚本 | 用途 | 说明 |
|------|------|------|
| `01-create-infrastructure.sh` | 创建基础设施 | 创建VPC、子网、安全组等基础资源 |
| `01.5-copy-credentials.sh` | 复制凭证 | 将AWS凭证、SSH密钥和pull secret复制到bastion host |
| `02-setup-mirror-registry.sh` | 搭建镜像仓库 | 在bastion host上部署私有镜像仓库 |
| `03-sync-images.sh` | 同步镜像 | 从外部同步OpenShift镜像到私有仓库 |
| `04-prepare-install-config.sh` | 准备安装配置 | 生成disconnected cluster的安装配置 |
| `05-install-cluster.sh` | 安装集群 | 创建manifests、修改配置、安装OpenShift集群 |
| `06-verify-cluster.sh` | 验证集群 | 验证集群功能和镜像仓库配置 |
| `07-cleanup.sh` | 清理资源 | 清理安装过程中产生的临时文件 |

## 前置条件

### 本地环境要求
- AWS CLI 已配置并具有足够权限
- OpenShift CLI (oc) 4.18+
- Docker 或 Podman
- jq, yq 工具
- SSH 密钥对

### 网络要求
- 能够访问互联网的机器（用于同步镜像）
- 能够访问AWS的机器
- 足够的存储空间（至少100GB用于镜像同步）

### AWS权限要求
- EC2 完整权限
- VPC 完整权限
- IAM 权限（创建角色和策略）
- S3 权限（可选，用于镜像存储）

## 快速开始

```bash
# 1. 创建基础设施
./01-create-infrastructure.sh --cluster-name my-disconnected-cluster --region us-east-1

# 2. 复制凭证到bastion host
./01.5-copy-credentials.sh

# 3. 搭建镜像仓库
./02-setup-mirror-registry.sh --cluster-name my-disconnected-cluster

# 4. 同步镜像（需要网络连接）
./03-sync-images.sh --cluster-name my-disconnected-cluster --openshift-version 4.18.15

# 5. 准备安装配置
./04-prepare-install-config.sh --cluster-name my-disconnected-cluster --base-domain example.com

# 6. 安装集群（包含manifest创建和修改）
./05-install-cluster.sh --cluster-name my-disconnected-cluster

# 7. 验证集群
./06-verify-cluster.sh --cluster-name my-disconnected-cluster
```

## 详细配置

### 镜像仓库配置

镜像仓库将部署在bastion host上，提供以下服务：
- **Registry**: 存储OpenShift镜像
- **Web UI**: 镜像仓库管理界面
- **Authentication**: 基本认证保护
- **TLS**: 自签名证书

### 网络配置

- **VPC**: 私有VPC，无互联网网关
- **子网**: 私有子网，通过NAT网关访问镜像仓库
- **安全组**: 严格的安全组规则
- **路由**: 自定义路由表

### 存储配置

- **镜像存储**: 本地存储或EBS卷
- **日志存储**: 本地存储
- **备份**: 可选的S3备份

### Manifest配置和验证

对于disconnected cluster，`04-prepare-install-config.sh`和`05-install-cluster.sh`脚本会自动创建、验证和修改必要的manifests。

#### 04脚本的Manifest处理

`04-prepare-install-config.sh`脚本现在包含完整的manifest创建和验证流程：

1. **备份install-config.yaml**
   ```bash
   # 在创建manifests之前自动备份
   cp install-config.yaml install-config.yaml.backup
   ```

2. **创建manifests**
   ```bash
   # 使用AWS_PROFILE=static确保凭证正确
   AWS_PROFILE=static openshift-install create manifests
   ```

3. **验证关键manifest文件**
   - **image-content-source-policy.yaml**: 验证镜像内容源策略
   - **openshift-config-secret-pull-secret.yaml**: 验证pull secret配置
   - **网络配置**: 验证subnet和VPC配置

#### 05脚本的Manifest处理

`05-install-cluster.sh`脚本会进一步修改manifests以支持disconnected环境：

#### 自动创建的Manifests

1. **disconnected-cluster-config.yaml**
   - 配置集群类型为disconnected
   - 设置镜像仓库URL和用户信息
   - 存储在`openshift-config`命名空间

2. **registry-network-policy.yaml**
   - 配置网络策略以允许镜像仓库访问
   - 确保集群内服务可以访问本地镜像仓库
   - 应用在`openshift-image-registry`命名空间

#### Manifest验证检查清单

在运行安装之前，脚本会自动验证以下内容：

```bash
# 1. 验证install-config.yaml语法
yq eval '.' install-config.yaml

# 2. 验证镜像仓库可访问性
curl -k -s -u admin:admin123 https://localhost:5000/v2/_catalog

# 3. 验证image content source policy
grep "localhost:5000" manifests/image-content-source-policy.yaml

# 4. 验证pull secret
grep "localhost:5000" manifests/openshift-config-secret-pull-secret.yaml

# 5. 验证网络配置
grep "subnet-" manifests/cluster-config.yaml
```

#### 手动验证Manifests

如果需要手动验证manifests，可以使用以下命令：

```bash
# 检查manifest文件结构
ls -la openshift-install/manifests/

# 验证image content source policy
cat openshift-install/manifests/image-content-source-policy.yaml

# 验证pull secret（解码查看内容）
echo "eyJhdXRocyI6eyJsb2NhbGhvc3Q6NTAwMCI6eyJhdXRoIjoiWVdSdGFXNDZZV1J0YVc0eE1qTT0ifX19" | base64 -d | jq .

# 验证网络配置
grep -A 10 -B 5 'subnet' openshift-install/manifests/cluster-config.yaml
```

#### 常见Manifest问题及解决方案

1. **imageContentSources已弃用警告**
   ```
   level=warning msg=imageContentSources is deprecated, please use ImageDigestSources
   ```
   - 这是正常的警告，当前配置仍然有效
   - 新版本推荐使用ImageDigestSources，但向后兼容

2. **Pull Secret不包含localhost:5000**
   - 确保04脚本正确生成了包含localhost:5000的pull secret
   - 检查registry认证信息是否正确

3. **网络配置错误**
   - 验证subnet ID是否正确
   - 确认VPC和region配置匹配

4. **证书验证失败**
   - 检查additionalTrustBundle配置
   - 验证registry证书是否正确

#### 调试模式

脚本默认使用debug日志级别，提供详细的安装过程信息：

```bash
# 查看详细安装日志
tail -f logs/install-*.log

# 查看manifest创建日志
grep "manifest" logs/install-*.log
```

## 故障排除

### 常见问题

1. **镜像同步失败**
   - 检查网络连接
   - 验证镜像仓库可访问性
   - 检查存储空间

2. **集群安装失败**
   - 检查镜像仓库配置
   - 验证install-config.yaml
   - 查看安装日志

3. **节点无法拉取镜像**
   - 检查镜像仓库DNS解析
   - 验证安全组规则
   - 检查证书配置

4. **Manifest创建失败**
   - 检查install-config.yaml语法
   - 验证镜像仓库可访问性
   - 查看debug日志获取详细信息

5. **Manifest验证失败**
   - 检查网络策略配置
   - 验证镜像内容源配置
   - 确认证书配置正确

### 日志位置

- **安装日志**: `./logs/install-*.log`
- **镜像同步日志**: `./logs/sync-*.log`
- **基础设施日志**: `./logs/infra-*.log`
- **Manifest日志**: 包含在安装日志中，使用debug级别查看

## 清理

```bash
# 清理所有资源
./07-cleanup.sh --cluster-name my-disconnected-cluster --force
```

## 注意事项

1. **存储空间**: 确保有足够的存储空间用于镜像同步
2. **网络带宽**: 镜像同步需要大量带宽，建议在非高峰期进行
3. **安全**: 定期更新镜像仓库的认证信息
4. **备份**: 定期备份镜像仓库数据
5. **监控**: 监控镜像仓库的性能和可用性
6. **Manifests**: 确保disconnected cluster的manifests正确配置，特别是镜像内容源和网络策略
7. **调试**: 使用debug日志级别进行故障排除，提供更详细的安装信息

## 相关文档

- [OpenShift Disconnected Installation](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-restricted-networks.html)
- [Mirror Registry for Red Hat OpenShift](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-restricted-networks.html#installation-mirror-repository_installing-aws-restricted-networks)
- [AWS VPC Documentation](https://docs.aws.amazon.com/vpc/) 