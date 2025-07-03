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

1. **创建基础设施** - 创建VPC、子网、安全组等
2. **创建Bastion主机** - 部署跳板机用于后续操作
3. **复制凭证** - 将AWS凭证、SSH密钥和pull secret复制到bastion host
4. **搭建镜像仓库** - 在bastion host上部署私有镜像仓库
5. **同步镜像** - 从外部环境同步OpenShift镜像到私有仓库
6. **复制基础设施信息和工具** - 将必要的文件复制到bastion host
7. **准备安装配置** - 准备disconnected cluster的安装配置
8. **安装集群** - 使用私有镜像仓库安装OpenShift集群
9. **验证集群** - 验证集群功能并配置后续使用
10. **清理资源** - 清理安装过程中产生的临时文件和资源

## 脚本说明

| 脚本 | 用途 | 说明 |
|------|------|------|
| `01-create-infrastructure.sh` | 创建基础设施 | 创建VPC、子网、安全组等基础资源，支持SNO模式 |
| `02-create-bastion.sh` | 创建Bastion主机 | 部署跳板机，配置必要的工具和环境 |
| `03-copy-credentials.sh` | 复制凭证 | 将AWS凭证、SSH密钥和pull secret复制到bastion host |
| `04-setup-mirror-registry.sh` | 搭建镜像仓库 | 在bastion host上部署私有镜像仓库 |
| `05-sync-images.sh` | 同步镜像 | 从外部同步OpenShift镜像到私有仓库 |
| `06-copy-infra-and-tools.sh` | 复制基础设施信息 | 将基础设施信息和工具复制到bastion host |
| `07-prepare-install-config.sh` | 准备安装配置 | 生成disconnected cluster的安装配置 |
| `08-install-cluster.sh` | 安装集群 | 创建manifests、修改配置、安装OpenShift集群 |
| `09-verify-cluster.sh` | 验证集群 | 验证集群功能和镜像仓库配置 |
| `10-cleanup.sh` | 清理资源 | 清理本地文件、bastion文件、AWS资源和集群 |
| `11-verify-cleanup.sh` | 验证清理 | 验证清理操作是否完成 |
| `12-cleanup-from-report.sh` | 基于报告清理 | 根据清理报告清理特定资源 |
| `13-comprehensive-cleanup.sh` | 全面清理 | 执行全面的资源清理 |

## 辅助脚本

| 脚本 | 用途 | 说明 |
|------|------|------|
| `simple-sync.sh` | 简单镜像同步 | 简化的镜像同步脚本 |
| `check-sync-status.sh` | 检查同步状态 | 检查镜像同步状态 |
| `copy-from-bastion.sh` | 从bastion复制文件 | 从bastion host复制文件到本地 |
| `force-delete-vpc.sh` | 强制删除VPC | 强制删除VPC和相关资源 |
| `test-ami.sh` | 测试AMI | 测试AMI可用性 |

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

# 2. 创建Bastion主机
./02-create-bastion.sh --cluster-name my-disconnected-cluster

# 3. 复制凭证到bastion host
./03-copy-credentials.sh --cluster-name my-disconnected-cluster

# 4. 搭建镜像仓库
./04-setup-mirror-registry.sh --cluster-name my-disconnected-cluster

# 5. 同步镜像（需要网络连接）
./05-sync-images.sh --cluster-name my-disconnected-cluster --openshift-version 4.18.15

# 6. 复制基础设施信息和工具
./06-copy-infra-and-tools.sh --cluster-name my-disconnected-cluster

# 7. 准备安装配置
./07-prepare-install-config.sh --cluster-name my-disconnected-cluster --base-domain example.com

# 8. 安装集群（包含manifest创建和修改）
./08-install-cluster.sh --cluster-name my-disconnected-cluster

# 9. 验证集群
./09-verify-cluster.sh --cluster-name my-disconnected-cluster

# 10. 清理资源（可选）
./10-cleanup.sh --cluster-name my-disconnected-cluster --dry-run
```

## 详细配置

### 镜像仓库配置

镜像仓库将部署在bastion host上，提供以下服务：
- **Registry**: 存储OpenShift镜像
- **Web UI**: 镜像仓库管理界面
- **Authentication**: 基本认证保护
- **TLS**: 自签名证书

### 网络配置

- **VPC**: 私有VPC，支持单节点(SNO)和多节点部署
- **子网**: 私有子网和公有子网，通过NAT网关访问
- **安全组**: 严格的安全组规则
- **路由**: 自定义路由表

### 存储配置

- **镜像存储**: 本地存储或EBS卷
- **日志存储**: 本地存储
- **备份**: 可选的S3备份

### Manifest配置和验证

对于disconnected cluster，`07-prepare-install-config.sh`和`08-install-cluster.sh`脚本会自动创建、验证和修改必要的manifests。

#### 07脚本的Manifest处理

`07-prepare-install-config.sh`脚本包含完整的manifest创建和验证流程：

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

#### 08脚本的Manifest处理

`08-install-cluster.sh`脚本会进一步修改manifests以支持disconnected环境：

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

## 清理选项

脚本提供了多种清理级别：

1. **全面清理** (`--cleanup-level all`)
   - 清理本地文件
   - 清理bastion host文件
   - 清理AWS资源
   - 清理OpenShift集群

2. **分级清理**
   - `--cleanup-level local`: 只清理本地文件
   - `--cleanup-level bastion`: 只清理bastion host文件
   - `--cleanup-level aws`: 只清理AWS资源
   - `--cleanup-level cluster`: 只清理OpenShift集群

3. **验证清理**
   - `11-verify-cleanup.sh`: 验证清理操作是否完成
   - `12-cleanup-from-report.sh`: 根据清理报告清理特定资源
   - `13-comprehensive-cleanup.sh`: 执行全面的资源清理

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

### 调试模式

脚本默认使用debug日志级别，提供详细的安装过程信息：

```bash
# 查看详细安装日志
tail -f logs/install-*.log

# 查看manifest创建日志
grep "manifest" logs/install-*.log
```

## 注意事项

1. **存储空间**: 确保有足够的存储空间用于镜像同步
2. **网络带宽**: 镜像同步需要大量带宽，建议在非高峰期进行
3. **安全**: 定期更新镜像仓库的认证信息
4. **备份**: 定期备份镜像仓库数据
5. **监控**: 监控镜像仓库的性能和可用性
6. **Manifests**: 确保disconnected cluster的manifests正确配置，特别是镜像内容源和网络策略
7. **调试**: 使用debug日志级别进行故障排除，提供更详细的安装信息
8. **清理**: 使用适当的清理级别避免意外删除重要资源

## 相关文档

- [OpenShift Disconnected Installation](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-restricted-networks.html)
- [Mirror Registry for Red Hat OpenShift](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-restricted-networks.html#installation-mirror-repository_installing-aws-restricted-networks)
- [AWS VPC Documentation](https://docs.aws.amazon.com/vpc/)

## 附加文档

- `README-improvements.md`: 改进建议和最佳实践
- `README-certificate-improvements.md`: 证书配置改进
- `README-disconnected-architecture.md`: 断网架构说明
- `README-mirror-improvements.md`: 镜像仓库改进
- `AWS-VPC-Network-Structure.md`: AWS VPC网络结构说明 