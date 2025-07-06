# Bootstrap 节点手工安装指南

## 概述

这个指南说明如何在bootstrap节点上手工执行安装过程，使用ignition生成的脚本。

## 登录到Bootstrap节点

```bash
# 从本地登录到bastion
ssh -i ./ci-operator/disconnected-cluster/infra-output/bastion-key.pem ubuntu@72.44.62.16

# 从bastion登录到bootstrap节点
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no core@10.0.100.175
```

## 使用手工安装脚本

### 1. 复制脚本到bootstrap节点

脚本已经复制到bastion的`/tmp/`目录。从bastion复制到bootstrap：

```bash
# 在bastion上执行
scp /tmp/manual-bootstrap-install.sh core@10.0.100.175:/tmp/
```

### 2. 在bootstrap节点上执行脚本

```bash
# 登录到bootstrap节点后
chmod +x /tmp/manual-bootstrap-install.sh
/tmp/manual-bootstrap-install.sh
```

## 脚本功能

脚本提供以下选项：

### 选项1: 启动release-image服务
- 启动`release-image.service`来下载OpenShift release镜像
- 监控下载进度
- 这是安装的第一步

### 选项2: 启动bootkube服务
- 启动`bootkube.service`来初始化集群
- 监控集群启动进度
- 这应该在release-image完成后执行

### 选项3: 手工运行脚本
- 直接执行`/usr/local/bin/release-image-download.sh`
- 直接执行`/usr/local/bin/bootkube.sh`
- 适合调试或服务不可用时

### 选项4: 监控安装
- 显示监控命令
- 检查服务状态
- 查看日志

### 选项5: 检查安装状态
- 检查auth目录和kubeconfig
- 验证集群可访问性
- 显示服务状态

### 选项6: 故障排除
- 显示故障排除命令
- 检查系统资源
- 验证网络连接

## 推荐的安装流程

### 第一步：检查环境
```bash
/tmp/manual-bootstrap-install.sh
# 选择选项5: Check installation status
```

### 第二步：启动release-image服务
```bash
/tmp/manual-bootstrap-install.sh
# 选择选项1: Start release-image service
```

等待release-image下载完成。你可以通过以下命令监控：
```bash
journalctl -f -u release-image.service
```

### 第三步：启动bootkube服务
```bash
/tmp/manual-bootstrap-install.sh
# 选择选项2: Start bootkube service
```

等待bootkube完成。你可以通过以下命令监控：
```bash
journalctl -f -u bootkube.service
```

### 第四步：验证安装
```bash
/tmp/manual-bootstrap-install.sh
# 选择选项5: Check installation status
```

## 关键监控命令

### 监控所有相关服务
```bash
journalctl -b -f -u release-image.service -u bootkube.service
```

### 检查API服务器
```bash
curl -k https://localhost:6443/healthz
```

### 检查集群状态
```bash
export KUBECONFIG=/opt/openshift/auth/kubeconfig
oc get nodes
oc get clusteroperators
```

### 检查服务状态
```bash
systemctl status release-image.service
systemctl status bootkube.service
systemctl status kubelet.service
```

## 故障排除

### 如果release-image服务失败
1. 检查registry连接：
   ```bash
   curl -k -u admin:admin123 https://10.0.10.10:5000/v2/
   ```

2. 检查registries.conf：
   ```bash
   cat /etc/containers/registries.conf
   ```

3. 检查hosts文件：
   ```bash
   grep "10.0.10.10" /etc/hosts
   ```

### 如果bootkube服务失败
1. 检查系统资源：
   ```bash
   free -h
   df -h
   ```

2. 检查容器运行时：
   ```bash
   podman ps
   podman images
   ```

3. 检查日志：
   ```bash
   journalctl -b -u bootkube.service
   ```

## 重要注意事项

1. **Bootstrap节点是临时的**：一旦master节点完全启动，bootstrap节点将被销毁

2. **安装时间**：完整的安装过程通常需要20-30分钟

3. **网络要求**：确保bootstrap节点可以访问bastion的registry (10.0.10.10:5000)

4. **资源要求**：确保有足够的内存和磁盘空间

5. **服务顺序**：必须先完成release-image下载，再启动bootkube

## 成功标志

安装成功的标志：
- `release-image.service` 状态为 `active`
- `bootkube.service` 状态为 `active`
- `/opt/openshift/auth/kubeconfig` 文件存在
- API服务器响应正常
- 可以访问集群API

## 完成安装

一旦bootstrap节点完成其工作，master节点将接管集群控制。你可以：

1. 等待master节点完全启动
2. 使用master节点的kubeconfig访问集群
3. 销毁bootstrap节点（通常由安装程序自动完成） 