# Bootstrap Scripts 说明

这个目录包含了从 `bootstrap.ign` 文件中提取的所有脚本和配置文件。

## 核心脚本文件

### 1. 镜像拉取相关
- **`node-image-pull.sh`** - 拉取 CoreOS 节点镜像
  - 使用 `ostree container image pull` 命令
  - 调用 `image_for` 函数获取镜像路径
  - 处理镜像内容检出到本地文件系统

- **`release-image.sh`** - 处理 release 镜像
  - 使用 `podman inspect` 命令获取镜像信息
  - **问题**: 硬编码了 `registry.ci.openshift.org/origin/release:4.19`
  - 没有使用 registry 配置中的 mirror 设置

- **`release-image-download.sh`** - 下载 release 镜像

### 2. 系统服务相关
- **`node-image-pull.service`** - systemd 服务，负责拉取节点镜像
- **`node-image-overlay.service`** - systemd 服务，处理镜像覆盖层
- **`node-image-overlay.target`** - systemd target，协调镜像处理流程
- **`node-image-finish.service`** - systemd 服务，完成镜像处理

### 3. 集群启动相关
- **`bootkube.sh`** - 主要的集群启动脚本
  - 渲染各种 Kubernetes 组件清单
  - 启动 etcd、API server、controller manager、scheduler
  - 处理镜像配置和认证

- **`kubelet.sh`** - 配置和启动 kubelet
- **`crio-configure.sh`** - 配置 CRI-O 容器运行时

### 4. 认证和证书相关
- **`approve-csr.sh`** - 自动批准证书签名请求
- **`wait-for-ha-api.sh`** - 等待高可用 API 服务器就绪

### 5. 调试和诊断相关
- **`bootstrap-cluster-gather.sh`** - 收集集群诊断信息
- **`bootstrap-service-record.sh`** - 记录服务状态
- **`bootstrap-verify-api-server-urls.sh`** - 验证 API 服务器 URL
- **`installer-gather.sh`** - 收集安装器日志
- **`installer-masters-gather.sh`** - 收集 master 节点信息
- **`report-progress.sh`** - 报告安装进度

## 配置文件

### 1. Registry 配置
- **`registries.conf`** - 容器镜像 registry 配置
  - **问题**: 所有 mirror 都设置为 `insecure = false`
  - 如果本地 registry 使用 HTTP，这会导致连接被拒绝
  - **需要修复**: 将 mirror 的 `insecure = false` 改为 `insecure = true`

### 2. Docker 配置
- **`docker-config.json`** - Docker 认证配置
  - 包含 localhost:5000 的认证信息

### 3. 系统配置
- **`proxy.sh`** - 代理配置（当前为空）
- **`motd`** - 登录消息
- **`10-default-env.conf`** - systemd 默认环境配置

## 关键问题分析

### 1. Registry 配置问题
```toml
[[registry.mirror]]
location = "localhost:5000/openshift/ocp/release"
insecure = false  # ❌ 应该是 true
```

### 2. 脚本硬编码问题
```bash
# release-image.sh 第6行
podman inspect registry.ci.openshift.org/origin/release:4.19
```

### 3. 缺少 hosts 配置
没有配置 `/etc/hosts` 将 `registry.ci.openshift.org` 指向 bastion

## 修复建议

### 1. 修复 registry 配置
将所有 mirror 的 `insecure = false` 改为 `insecure = true`

### 2. 修复脚本
修改 `release-image.sh` 使用 mirror 配置或直接使用 localhost:5000

### 3. 添加 hosts 配置
在 `/etc/hosts` 中添加：
```
10.0.10.10 registry.ci.openshift.org
```

## 文件统计
- 总文件数: 28 个
- 脚本文件: 17 个
- 配置文件: 11 个
- 最大文件: `bootkube.sh` (22,934 字节)
- 最小文件: `motd` (3 字节) 