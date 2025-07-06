#!/bin/bash

# 修复 bootstrap 配置脚本
# 解决 disconnected cluster 中的镜像拉取问题

set -euo pipefail

echo "开始修复 bootstrap 配置..."

# 1. 修复 registries.conf 中的 insecure 设置
echo "1. 修复 registries.conf..."
sed -i.bak 's/insecure = false/insecure = true/g' ci-operator/disconnected-cluster/bootstrap-scripts/registries.conf

# 2. 修复 release-image.sh 中的硬编码 registry
echo "2. 修复 release-image.sh..."
cat > ci-operator/disconnected-cluster/bootstrap-scripts/release-image.sh << 'EOF'
#!/usr/bin/env bash
# This library provides an `image_for` helper function which can get the
# pull spec for a specific image in a release.

# 使用本地 registry mirror 而不是直接访问外部 registry
RELEASE_IMAGE_DIGEST="localhost:5000/openshift/ocp/release:4.19"

image_for() {
    # 直接使用本地 registry，避免网络访问
    echo "localhost:5000/openshift/${1}"
}
EOF

# 3. 创建修复后的 registries.conf
echo "3. 创建修复后的 registries.conf..."
cat > ci-operator/disconnected-cluster/bootstrap-scripts/registries.conf.fixed << 'EOF'
[[registry]]
location = "registry.ci.openshift.org/ocp/4.19.2/release"
insecure = false
mirror-by-digest-only = true

[[registry.mirror]]
location = "localhost:5000/openshift/ocp/release"
insecure = true

[[registry]]
location = "registry.ci.openshift.org/ocp/4.19/release"
insecure = false
mirror-by-digest-only = true

[[registry.mirror]]
location = "localhost:5000/openshift/ocp/release"
insecure = true

[[registry]]
location = "registry.ci.openshift.org/origin/release"
insecure = false
mirror-by-digest-only = true

[[registry.mirror]]
location = "localhost:5000/openshift/ocp/release"
insecure = true

[[registry]]
location = "registry.ci.openshift.org/ocp/4.19.2/installer"
insecure = false
mirror-by-digest-only = true

[[registry.mirror]]
location = "localhost:5000/openshift/installer"
insecure = true

[[registry]]
location = "registry.ci.openshift.org/ocp/4.19.2/cli"
insecure = false
mirror-by-digest-only = true

[[registry.mirror]]
location = "localhost:5000/openshift/cli"
insecure = true

[[registry]]
location = "registry.ci.openshift.org/ocp/4.19.2/machine-config-operator"
insecure = false
mirror-by-digest-only = true

[[registry.mirror]]
location = "localhost:5000/openshift/machine-config-operator"
insecure = true

[[registry]]
location = "registry.ci.openshift.org/ocp/4.19.2/cluster-version-operator"
insecure = false
mirror-by-digest-only = true

[[registry.mirror]]
location = "localhost:5000/openshift/cluster-version-operator"
insecure = true

[[registry]]
location = "registry.ci.openshift.org/ocp/4.19.2/etcd"
insecure = false
mirror-by-digest-only = true

[[registry.mirror]]
location = "localhost:5000/openshift/etcd"
insecure = true

[[registry]]
location = "registry.ci.openshift.org/ocp/4.19.2/hyperkube"
insecure = false
mirror-by-digest-only = true

[[registry.mirror]]
location = "localhost:5000/openshift/hyperkube"
insecure = true

[[registry]]
location = "registry.ci.openshift.org/ocp/4.19.2/oauth-server"
insecure = false
mirror-by-digest-only = true

[[registry.mirror]]
location = "localhost:5000/openshift/oauth-server"
insecure = true

[[registry]]
location = "registry.ci.openshift.org/ocp/4.19.2/oauth-proxy"
insecure = false
mirror-by-digest-only = true

[[registry.mirror]]
location = "localhost:5000/openshift/oauth-proxy"
insecure = true

[[registry]]
location = "registry.ci.openshift.org/ocp/4.19.2/console"
insecure = false
mirror-by-digest-only = true

[[registry.mirror]]
location = "localhost:5000/openshift/console"
insecure = true

[[registry]]
location = "registry.ci.openshift.org/ocp/4.19.2/haproxy-router"
insecure = false
mirror-by-digest-only = true

[[registry.mirror]]
location = "localhost:5000/openshift/haproxy-router"
insecure = true

[[registry]]
location = "registry.ci.openshift.org/ocp/4.19.2/coredns"
insecure = false
mirror-by-digest-only = true

[[registry.mirror]]
location = "localhost:5000/openshift/coredns"
insecure = true

[[registry]]
location = "registry.ci.openshift.org/openshift"
insecure = false
mirror-by-digest-only = true

[[registry.mirror]]
location = "localhost:5000/openshift"
insecure = true

[[registry]]
location = "registry.ci.openshift.org/origin"
insecure = false
mirror-by-digest-only = true

[[registry.mirror]]
location = "localhost:5000/openshift"
insecure = true

[[registry]]
location = "quay.io/openshift-release-dev/ocp-release"
insecure = false
mirror-by-digest-only = true

[[registry.mirror]]
location = "localhost:5000/openshift/ocp/release"
insecure = true

[[registry]]
location = "quay.io/openshift-release-dev/ocp-v4.0-art-dev"
insecure = false
mirror-by-digest-only = true

[[registry.mirror]]
location = "localhost:5000/openshift/ocp/release"
insecure = true
EOF

# 4. 创建 hosts 配置
echo "4. 创建 hosts 配置..."
cat > ci-operator/disconnected-cluster/bootstrap-scripts/hosts << 'EOF'
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
10.0.10.10  registry.ci.openshift.org
10.0.10.10  quay.io
10.0.10.10  registry.access.redhat.com
EOF

# 5. 创建 MachineConfig 来应用这些修复
echo "5. 创建 MachineConfig..."
cat > ci-operator/disconnected-cluster/bootstrap-fixes-machineconfig.yaml << 'EOF'
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
      - contents:
          source: data:text/plain;charset=utf-8;base64,{{ release_image_sh_base64 }}
        mode: 0755
        path: /usr/local/bin/release-image.sh
    systemd:
      units:
      - contents: |
          [Unit]
          Description=Apply bootstrap fixes
          Before=kubelet.service
          
          [Service]
          Type=oneshot
          ExecStart=/bin/bash -c 'echo "Bootstrap fixes applied"'
          RemainAfterExit=yes
          
          [Install]
          WantedBy=multi-user.target
        name: bootstrap-fixes.service
EOF

echo ""
echo "修复完成！"
echo ""
echo "修复内容:"
echo "1. ✅ registries.conf - 将所有 mirror 的 insecure 设置为 true"
echo "2. ✅ release-image.sh - 修改为使用本地 registry"
echo "3. ✅ 创建了修复后的配置文件"
echo "4. ✅ 创建了 hosts 配置"
echo "5. ✅ 创建了 MachineConfig 模板"
echo ""
echo "下一步:"
echo "1. 将修复后的文件应用到 bootstrap 节点"
echo "2. 或者修改 install-config.yaml 添加 MachineConfig"
echo "3. 重新生成 bootstrap.ign 文件" 