# 集群日志拷贝工具

## 概述
`copy-cluster-logs.sh` 是一个用于从bastion主机拷贝OpenShift集群安装日志到本地的自动化脚本。

## 功能特性

### 🔄 自动化拷贝
- 自动检查SSH连接
- 批量拷贝重要的安装文件
- 生成详细的拷贝报告
- 自动备份现有日志文件

### 📁 拷贝的文件和目录
- **日志文件**:
  - `.openshift_install.log` - 主安装日志
  - `.openshift_install_state.json` - 安装状态文件
  - `metadata.json` - 集群元数据

- **配置文件**:
  - `install-config.yaml.backup` - 安装配置备份
  - `terraform.platform.auto.tfvars.json` - Terraform平台配置
  - `terraform.tfvars.json` - Terraform变量

- **重要目录**:
  - `auth/` - 认证文件 (kubeconfig, kubeadmin密码)
  - `cluster-api/` - 集群API文件
  - `tls/` - TLS证书

### 🛡️ 安全特性
- 使用SSH密钥认证
- 自动备份现有文件
- 不覆盖重要的本地文件
- 添加到`.gitignore`避免意外提交

## 使用方法

### 基本用法
```bash
# 在disconnected-cluster目录中执行
./copy-cluster-logs.sh
```

### 命令行选项
```bash
# 显示帮助信息
./copy-cluster-logs.sh -h

# 详细输出模式
./copy-cluster-logs.sh -v

# 强制覆盖现有文件
./copy-cluster-logs.sh -f
```

## 前置条件

### 1. 基础设施状态
- bastion主机必须正在运行
- SSH密钥文件存在: `infra-output/bastion-key.pem`
- 网络连接正常

### 2. bastion主机配置
默认配置:
- **主机**: 72.44.62.16
- **用户**: ubuntu
- **远程目录**: `/home/ubuntu/disconnected-cluster/openshift-install-dir`

### 3. 本地环境
- 必须在`disconnected-cluster`目录中执行
- 需要有写入权限创建`cluster-logs`目录

## 输出结果

### 本地目录结构
```
disconnected-cluster/
├── cluster-logs/
│   ├── .openshift_install.log
│   ├── .openshift_install_state.json
│   ├── metadata.json
│   ├── install-config.yaml.backup
│   ├── terraform.platform.auto.tfvars.json
│   ├── terraform.tfvars.json
│   ├── auth/
│   │   ├── kubeconfig
│   │   └── kubeadmin-password
│   ├── cluster-api/
│   ├── tls/
│   └── copy-report-YYYYMMDD_HHMMSS.txt
└── copy-cluster-logs.sh
```

### 拷贝报告
脚本会生成详细的拷贝报告，包含:
- 拷贝的文件列表和大小
- 成功/失败状态
- 总计文件数和占用空间
- 时间戳信息

## 有用的后续命令

### 监控安装进度
```bash
# 实时查看安装日志
tail -f cluster-logs/.openshift_install.log

# 查看集群基本信息
cat cluster-logs/metadata.json | jq .

# 查看拷贝报告
cat cluster-logs/copy-report-*.txt
```

### 访问集群
```bash
# 使用拷贝的kubeconfig
export KUBECONFIG=cluster-logs/auth/kubeconfig

# 获取kubeadmin密码
cat cluster-logs/auth/kubeadmin-password
```

## 故障排除

### 常见错误

#### 1. SSH连接失败
```
[ERROR] 无法连接到bastion主机: 72.44.62.16
```
**解决方案**:
- 检查bastion主机是否正在运行
- 确认SSH密钥文件存在
- 验证网络连接

#### 2. SSH密钥不存在
```
[ERROR] SSH密钥文件不存在: infra-output/bastion-key.pem
```
**解决方案**:
- 运行基础设施创建脚本
- 确认密钥文件路径正确

#### 3. 权限错误
```
Permission denied (publickey)
```
**解决方案**:
- 检查SSH密钥文件权限: `chmod 600 infra-output/bastion-key.pem`
- 确认使用正确的用户名: ubuntu

### 调试模式
```bash
# 启用详细输出
./copy-cluster-logs.sh -v

# 手动测试SSH连接
ssh -i infra-output/bastion-key.pem ubuntu@72.44.62.16 "echo 'test'"
```

## 配置自定义

### 修改目标主机
编辑脚本中的配置变量:
```bash
BASTION_HOST="YOUR_BASTION_IP"
BASTION_USER="ubuntu"
SSH_KEY="infra-output/bastion-key.pem"
```

### 修改拷贝目录
```bash
REMOTE_DIR="/home/ubuntu/disconnected-cluster/openshift-install-dir"
LOCAL_DIR="cluster-logs"
```

## 注意事项

### 🔒 安全提醒
- `cluster-logs`目录包含敏感信息，已添加到`.gitignore`
- 不要将认证文件推送到公共仓库
- 定期清理旧的日志文件

### 📦 存储空间
- 日志文件可能很大（几十MB到几GB）
- 脚本会自动备份现有文件
- 定期清理不需要的备份

### 🕒 时间戳
- 所有备份文件都包含时间戳
- 拷贝报告包含完整的时间信息
- 便于追踪不同时间点的安装状态

## 更新日志

### v1.0.0
- 初始版本
- 支持基本的文件拷贝功能
- 生成拷贝报告
- 自动备份现有文件 