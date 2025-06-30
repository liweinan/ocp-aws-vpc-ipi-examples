# OpenShift Disconnected Cluster - Mirror Improvements

## 概述

基于成功的镜像同步经验，我们对脚本进行了以下关键改进：

## 主要改进

### 1. 简化的镜像同步策略

**之前的问题：**
- 尝试同步所有 OpenShift 镜像，包括需要特殊权限的镜像
- 遇到权限错误时整个同步过程失败
- 同步时间过长（30-60分钟）

**改进后：**
- 只同步核心的 OpenShift release 镜像
- 使用 `podman pull/tag/push` 而不是 `oc adm release mirror`
- 同步时间缩短到 5-10 分钟
- 更可靠的错误处理

### 2. 修复的镜像仓库访问

**之前的问题：**
- 使用 HTTPS 访问本地 HTTP 镜像仓库
- 域名解析问题导致登录失败

**改进后：**
- 使用 HTTP 访问本地镜像仓库
- 使用 `localhost` 而不是域名进行 podman 操作
- 添加 `--tls-verify=false` 参数

### 3. 更好的错误处理

**新增功能：**
- 详细的日志记录到 `/home/ubuntu/sync.log`
- 每个步骤的状态检查
- 优雅的错误处理和回退机制
- 清晰的进度指示

### 4. 简化的配置文件

**生成的配置文件：**
- `imageContentSources.yaml` - 镜像内容源配置
- `install-config-template.yaml` - 安装配置模板
- 只包含必要的镜像映射

## 使用方法

### 快速同步（推荐）

```bash
# 使用简化的同步脚本
./simple-sync.sh 4.15.0 fedora-disconnected-cluster 5000 admin admin123
```

### 完整同步

```bash
# 使用完整的同步脚本（包含更多镜像）
./03-sync-images.sh --cluster-name fedora-disconnected-cluster --openshift-version 4.15.0 --bastion-key infra-output/bastion-key.pem
```

## 验证同步结果

```bash
# 检查镜像仓库内容
curl -u admin:admin123 http://localhost:5000/v2/_catalog

# 检查特定镜像的标签
curl -u admin:admin123 http://localhost:5000/v2/openshift/release/tags/list

# 查看同步日志
tail -f /home/ubuntu/sync.log
```

## 关键配置说明

### 镜像仓库配置

```yaml
imageContentSources:
- mirrors:
  - registry.fedora-disconnected-cluster.local:5000/openshift/release
  source: quay.io/openshift-release-dev/ocp-release
```

这个配置告诉 OpenShift 安装程序：
- 当需要 `quay.io/openshift-release-dev/ocp-release` 镜像时
- 使用本地的 `registry.fedora-disconnected-cluster.local:5000/openshift/release` 镜像

### 认证配置

```yaml
pullSecret: '{"auths":{"registry.fedora-disconnected-cluster.local:5000":{"auth":"YWRtaW46YWRtaW4xMjM="}}}'
```

这个配置提供了访问本地镜像仓库的认证信息。

## 故障排除

### 常见问题

1. **镜像仓库访问失败**
   - 检查镜像仓库是否正在运行：`sudo podman ps`
   - 检查端口是否开放：`netstat -tlnp | grep 5000`

2. **Podman 登录失败**
   - 确保使用 `localhost` 而不是域名
   - 添加 `--tls-verify=false` 参数

3. **镜像推送失败**
   - 检查磁盘空间：`df -h`
   - 检查镜像仓库日志：`sudo podman logs mirror-registry`

### 日志文件

- 同步日志：`/home/ubuntu/sync.log`
- 镜像仓库日志：`sudo podman logs mirror-registry`

## 下一步

1. 使用生成的 `install-config-template.yaml` 创建安装配置
2. 添加必要的网络配置（VPC、子网等）
3. 添加 SSH 公钥和镜像仓库证书
4. 运行 OpenShift 安装程序

## 总结

这些改进使得 disconnected OpenShift 集群的镜像同步过程更加：
- **可靠**：更好的错误处理和回退机制
- **快速**：只同步必要的镜像
- **简单**：清晰的日志和进度指示
- **实用**：生成可直接使用的配置文件 