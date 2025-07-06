# Bootstrap Configuration Summary

## 概述

本文档总结了为确保disconnected OpenShift集群的bootstrap节点可以正常拉取镜像而进行的所有配置修改。

## 主要修改

### 1. 修改 `07-prepare-install-config.sh`

#### 1.1 改进的install-config.yaml生成
- **正确的imageContentSources配置**: 确保所有镜像源都正确映射到本地registry
- **完整的registry镜像配置**: 包括release镜像、openshift镜像等
- **正确的pullSecret配置**: 包含本地registry的认证信息
- **additionalTrustBundle**: 包含registry的TLS证书

#### 1.2 新增bootstrap配置文件生成
- **registries.conf**: 容器运行时registry配置，设置insecure=true
- **hosts-config.yaml**: /etc/hosts配置，映射registry域名到bastion IP
- **registry-config.yaml**: OpenShift registry配置
- **auth-config.yaml**: 认证配置文件
- **release-image-config.yaml**: release镜像脚本配置

#### 1.3 新增apply_bootstrap_configs函数
- 自动将bootstrap配置文件复制到manifests目录
- 创建组合的bootstrap配置
- 确保所有配置在集群安装时被应用

### 2. 修改 `02-create-bastion.sh`

#### 2.1 改进的bastion host userdata
- **完整的registry设置**: 包括认证、TLS证书、podman配置
- **自动registry启动**: 使用podman运行registry容器
- **正确的认证配置**: htpasswd认证，用户名admin，密码admin123
- **TLS证书生成**: 自签名证书，包含多个SAN

### 3. 新增 `verify-bootstrap-config.sh`

#### 3.1 全面的验证功能
- **install-config.yaml验证**: 检查imageContentSources、pullSecret等
- **manifests验证**: 检查生成的manifest文件
- **registry可访问性验证**: 测试registry连接和镜像存在性
- **网络连通性验证**: 检查网络配置和hosts文件
- **容器运行时配置验证**: 检查registries.conf和认证配置
- **release镜像脚本验证**: 检查release-image.sh和release-image-download.sh

## 关键配置点

### 1. Registry配置
```yaml
# registries.conf
unqualified-search-registries = ["10.0.10.10:5000"]

[[registry]]
  location = "10.0.10.10:5000"
  insecure = true
  prefix = ""
```

### 2. Hosts配置
```bash
# /etc/hosts
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
10.0.10.10 registry.ci.openshift.org
10.0.10.10 quay.io
```

### 3. Release镜像脚本
```bash
# /usr/local/bin/release-image.sh
RELEASE_IMAGE_DIGEST="10.0.10.10:5000/openshift/ocp/release:4.19"

image_for() {
    echo "10.0.10.10:5000/openshift/${1}"
}
```

### 4. 认证配置
```json
{
  "auths": {
    "10.0.10.10:5000": {
      "auth": "YWRtaW46YWRtaW4xMjM="
    }
  }
}
```

## 安装流程

### 1. 基础设施创建
```bash
./01-create-infrastructure.sh --cluster-name my-cluster
./02-create-bastion.sh --cluster-name my-cluster
```

### 2. 工具和凭证复制
```bash
./03-copy-credentials.sh
./04-copy-infra-and-tools.sh
```

### 3. Registry设置
```bash
./05-setup-mirror-registry.sh --cluster-name my-cluster
./06-sync-images-robust.sh my-cluster
```

### 4. 安装配置准备
```bash
./07-prepare-install-config.sh --cluster-name my-cluster
```

### 5. 配置验证
```bash
./verify-bootstrap-config.sh --cluster-name my-cluster
```

### 6. 集群安装
```bash
./08-install-cluster.sh
```

## 验证要点

### 1. Registry可访问性
- ✅ Registry在localhost:5000可访问
- ✅ 认证正常工作 (admin/admin123)
- ✅ 包含必要的OpenShift镜像

### 2. 网络配置
- ✅ /etc/hosts包含正确的域名映射
- ✅ registries.conf配置正确
- ✅ insecure=true设置正确

### 3. 认证配置
- ✅ Docker认证配置包含本地registry
- ✅ Pull secret包含本地registry认证
- ✅ Release镜像脚本包含认证逻辑

### 4. 镜像可用性
- ✅ openshift/ocp/release:4.19存在
- ✅ openshift/cli:4.19.2存在
- ✅ openshift/installer:4.19.2存在
- ✅ openshift/machine-config-operator:4.19.2存在

## 故障排除

### 1. Registry连接问题
```bash
# 检查registry状态
curl -k -u admin:admin123 https://localhost:5000/v2/_catalog

# 检查registry日志
sudo podman logs mirror-registry
```

### 2. 认证问题
```bash
# 测试registry登录
podman login --username admin --password admin123 --tls-verify=false localhost:5000

# 检查认证配置
cat /root/.docker/config.json
```

### 3. 网络问题
```bash
# 检查hosts配置
cat /etc/hosts

# 检查网络连通性
ping 10.0.10.10
nc -z 10.0.10.10 5000
```

### 4. 镜像拉取问题
```bash
# 测试镜像拉取
podman pull --tls-verify=false localhost:5000/openshift/ocp/release:4.19

# 检查release镜像脚本
cat /usr/local/bin/release-image.sh
cat /usr/local/bin/release-image-download.sh
```

## 成功标准

当所有配置正确时，bootstrap节点应该能够：

1. ✅ 成功连接到本地registry (10.0.10.10:5000)
2. ✅ 使用正确的认证信息 (admin/admin123)
3. ✅ 绕过TLS验证 (insecure=true)
4. ✅ 成功拉取所有必要的OpenShift镜像
5. ✅ 完成bootstrap过程并启动集群

## 注意事项

1. **IP地址**: 确保bastion host的IP地址正确配置为10.0.10.10
2. **认证信息**: 默认使用admin/admin123，可在脚本中修改
3. **TLS证书**: 使用自签名证书，需要设置insecure=true
4. **镜像同步**: 确保所有必要的镜像都已同步到本地registry
5. **网络路由**: 确保bootstrap节点可以访问bastion host

## 总结

通过这些配置修改，disconnected OpenShift集群的bootstrap节点现在应该能够：

- 正确配置registry访问
- 使用本地镜像而不是外部registry
- 成功完成bootstrap过程
- 启动完整的OpenShift集群

所有配置都基于我们之前的成功经验，确保bootstrap节点可以正常拉取镜像并完成集群安装。 