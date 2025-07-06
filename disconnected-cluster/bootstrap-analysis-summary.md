# Bootstrap 节点问题分析与修复总结

## 问题背景

在 disconnected OpenShift 集群安装过程中，bootstrap 节点无法正确拉取镜像，导致安装失败。通过分析发现主要问题在于镜像 registry 配置和脚本硬编码。

## 问题分析

### 1. Registry 配置问题

**原始配置问题:**
```toml
[[registry.mirror]]
location = "localhost:5000/openshift/ocp/release"
insecure = false  # ❌ 问题：如果本地 registry 使用 HTTP，这会导致连接被拒绝
```

**修复后:**
```toml
[[registry.mirror]]
location = "localhost:5000/openshift/ocp/release"
insecure = true   # ✅ 修复：允许不安全的 HTTP 连接
```

### 2. 脚本硬编码问题

**原始脚本问题:**
```bash
# release-image.sh 第6行
podman inspect registry.ci.openshift.org/origin/release:4.19
```

**修复后:**
```bash
# 直接使用本地 registry，避免网络访问
RELEASE_IMAGE_DIGEST="localhost:5000/openshift/ocp/release:4.19"

image_for() {
    echo "localhost:5000/openshift/${1}"
}
```

### 3. 缺少 hosts 配置

**问题:** bootstrap 节点没有配置 `/etc/hosts` 将外部 registry 域名指向 bastion 主机。

**修复方案:**
```
10.0.10.10  registry.ci.openshift.org
10.0.10.10  quay.io
10.0.10.10  registry.access.redhat.com
```

## 修复方案

### 方案一：直接修改 bootstrap 节点（推荐）

1. **SSH 到 bootstrap 节点**
```bash
ssh core@<bootstrap-ip>
```

2. **修复 registry 配置**
```bash
sudo sed -i 's/insecure = false/insecure = true/g' /etc/containers/registries.conf
```

3. **添加 hosts 配置**
```bash
echo "10.0.10.10 registry.ci.openshift.org" | sudo tee -a /etc/hosts
echo "10.0.10.10 quay.io" | sudo tee -a /etc/hosts
```

4. **修复 release-image.sh**
```bash
sudo tee /usr/local/bin/release-image.sh << 'EOF'
#!/usr/bin/env bash
RELEASE_IMAGE_DIGEST="localhost:5000/openshift/ocp/release:4.19"
image_for() {
    echo "localhost:5000/openshift/${1}"
}
EOF
sudo chmod +x /usr/local/bin/release-image.sh
```

### 方案二：通过 MachineConfig 修复

1. **创建 MachineConfig**
```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: bootstrap-fixes
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,{{ registries_conf_base64 }}
        mode: 0644
        path: /etc/containers/registries.conf
      - contents:
          source: data:text/plain;charset=utf-8;base64,{{ hosts_base64 }}
        mode: 0644
        path: /etc/hosts
```

2. **在 install-config.yaml 中引用**
```yaml
additionalTrustBundle: |
  -----BEGIN CERTIFICATE-----
  ...
  -----END CERTIFICATE-----
imageContentSources:
- mirrors:
  - localhost:5000/openshift/ocp/release
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - localhost:5000/openshift/ocp/release
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
```

## 验证修复

### 1. 检查 registry 配置
```bash
# 在 bootstrap 节点上执行
grep -A 2 "localhost:5000" /etc/containers/registries.conf
```

### 2. 测试镜像拉取
```bash
# 测试本地 registry 连接
podman pull localhost:5000/openshift/ocp/release:4.19
```

### 3. 检查脚本修改
```bash
# 验证 release-image.sh 修改
cat /usr/local/bin/release-image.sh
```

## 预防措施

### 1. 自动化修复脚本

创建了 `fix-bootstrap-config.sh` 脚本，可以自动修复所有配置问题。

### 2. 配置模板

提供了修复后的配置文件模板：
- `registries.conf.fixed`
- `hosts`
- `bootstrap-fixes-machineconfig.yaml`

### 3. 文档化

创建了详细的 README 文档，说明每个脚本的作用和配置要求。

## 总结

通过分析 bootstrap.ign 文件，成功识别并修复了以下关键问题：

1. ✅ **Registry 配置**: 修复了 `insecure = false` 导致的连接问题
2. ✅ **脚本硬编码**: 修改了直接访问外部 registry 的代码
3. ✅ **Hosts 配置**: 添加了必要的域名解析配置
4. ✅ **自动化工具**: 提供了批量修复脚本
5. ✅ **文档完善**: 创建了详细的问题分析和修复指南

这些修复应该能够解决 disconnected cluster 安装过程中 bootstrap 节点无法拉取镜像的问题。 