# 安全删除VPC指南

本指南详细说明如何安全删除通过本项目创建的VPC和所有相关资源。

## 🚨 重要警告

**删除VPC是一个不可逆的操作！** 删除后，所有相关的AWS资源将被永久删除，包括：
- OpenShift集群
- 所有EC2实例
- 网络配置
- 存储卷
- 负载均衡器
- 安全组
- 路由表
- NAT网关

## 📋 删除前检查清单

在删除VPC之前，请确认：

- [ ] 已备份重要的数据和配置
- [ ] 已通知所有相关用户
- [ ] 确认没有生产工作负载在运行
- [ ] 已记录当前的网络配置（如需要）
- [ ] 已检查AWS账单，了解当前成本

## 🛠️ 删除方法

### 方法1：使用自动化删除脚本（推荐）

我们提供了一个专门的删除脚本 `delete-vpc.sh`，它会按正确的顺序删除所有资源。

#### 基本用法

```bash
# 给脚本执行权限
chmod +x delete-vpc.sh

# 基本删除（会提示确认）
./delete-vpc.sh --cluster-name my-cluster

# 强制删除（跳过确认）
./delete-vpc.sh --cluster-name my-cluster --force

# 预览删除（不实际删除）
./delete-vpc.sh --cluster-name my-cluster --dry-run
```

#### 高级选项

```bash
# 指定不同的输出目录
./delete-vpc.sh \
  --cluster-name my-cluster \
  --vpc-output-dir ./custom-vpc-output \
  --bastion-output-dir ./custom-bastion-output \
  --openshift-install-dir ./custom-openshift-install

# 跳过某些组件的删除
./delete-vpc.sh \
  --cluster-name my-cluster \
  --skip-openshift \
  --skip-bastion

# 使用不同的AWS区域
./delete-vpc.sh \
  --cluster-name my-cluster \
  --region us-west-2
```

#### 脚本功能

删除脚本会按以下顺序执行：

1. **OpenShift集群删除**
   - 使用 `openshift-install destroy cluster` 删除集群
   - 删除所有相关的AWS资源（EC2实例、负载均衡器、安全组等）

2. **Bastion主机删除**
   - 终止bastion EC2实例
   - 等待实例完全终止

3. **SSH密钥对删除**
   - 删除集群相关的SSH密钥对
   - 删除bastion主机相关的SSH密钥对

4. **VPC堆栈删除**
   - 删除CloudFormation堆栈
   - 自动删除所有VPC相关资源（子网、路由表、NAT网关等）

5. **输出目录清理**
   - 删除本地生成的配置文件
   - 清理临时文件

### 方法2：手动删除

如果自动化脚本无法使用，可以手动删除资源。

#### 步骤1：删除OpenShift集群

```bash
# 进入OpenShift安装目录
cd openshift-install

# 删除集群
./openshift-install destroy cluster --log-level=info
```

#### 步骤2：删除Bastion主机

```bash
# 获取bastion实例ID
INSTANCE_ID=$(cat ../bastion-output/bastion-instance-id)

# 终止实例
aws ec2 terminate-instances --instance-ids $INSTANCE_ID

# 等待实例终止
aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID
```

#### 步骤3：删除SSH密钥对

```bash
# 删除集群密钥对
aws ec2 delete-key-pair --key-name my-cluster-key

# 删除bastion密钥对
aws ec2 delete-key-pair --key-name my-cluster-bastion-key
```

#### 步骤4：删除VPC堆栈

```bash
# 获取堆栈名称
STACK_NAME=$(cat ../vpc-output/stack-name)

# 删除CloudFormation堆栈
aws cloudformation delete-stack --stack-name $STACK_NAME

# 等待堆栈删除完成
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME
```

#### 步骤5：清理本地文件

```bash
# 删除输出目录
rm -rf vpc-output bastion-output openshift-install

# 删除SSH密钥文件
rm -f *.pem
```

## 🔍 验证删除

删除完成后，验证所有资源都已正确删除：

### 检查CloudFormation堆栈

```bash
# 检查堆栈状态
aws cloudformation describe-stacks --stack-name my-cluster-vpc-1234567890

# 应该返回错误，表示堆栈不存在
```

### 检查VPC

```bash
# 获取VPC ID
VPC_ID=$(cat vpc-output/vpc-id)

# 检查VPC是否存在
aws ec2 describe-vpcs --vpc-ids $VPC_ID

# 应该返回错误，表示VPC不存在
```

### 检查EC2实例

```bash
# 检查是否有相关的EC2实例
aws ec2 describe-instances \
  --filters "Name=tag:kubernetes.io/cluster/my-cluster,Values=owned" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text

# 应该返回空结果
```

### 检查SSH密钥对

```bash
# 检查密钥对是否存在
aws ec2 describe-key-pairs --key-names my-cluster-key
aws ec2 describe-key-pairs --key-names my-cluster-bastion-key

# 应该返回错误，表示密钥对不存在
```

## 🚨 常见问题和解决方案

### 问题1：删除失败 - 依赖资源存在

**症状：** CloudFormation堆栈删除失败，提示有依赖资源

**解决方案：**
```bash
# 查看堆栈事件，了解具体错误
aws cloudformation describe-stack-events \
  --stack-name my-cluster-vpc-1234567890

# 手动删除依赖资源，然后重试堆栈删除
```

### 问题2：OpenShift集群删除失败

**症状：** `openshift-install destroy cluster` 命令失败

**解决方案：**
```bash
# 检查安装目录是否存在
ls -la openshift-install/

# 检查是否有正确的配置文件
ls -la openshift-install/auth/

# 尝试强制删除
./openshift-install destroy cluster --log-level=debug
```

### 问题3：Bastion实例无法终止

**症状：** EC2实例终止失败

**解决方案：**
```bash
# 检查实例状态
aws ec2 describe-instances --instance-ids i-1234567890abcdef0

# 强制终止实例
aws ec2 terminate-instances --instance-ids i-1234567890abcdef0 --force
```

### 问题4：SSH密钥对删除失败

**症状：** 密钥对仍在使用中

**解决方案：**
```bash
# 检查哪些实例在使用密钥对
aws ec2 describe-instances \
  --filters "Name=key-name,Values=my-cluster-key" \
  --query 'Reservations[].Instances[].InstanceId'

# 先删除使用密钥对的实例，再删除密钥对
```

## 💰 成本优化

### 删除前成本检查

```bash
# 检查当前AWS成本
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost

# 检查特定资源的成本
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --filter '{"And":[{"Dimensions":{"Key":"SERVICE","Values":["Amazon EC2"]}},{"Tags":{"Key":"ClusterName","Values":["my-cluster"]}}]}'
```

### 删除后成本验证

```bash
# 删除后等待几天，然后检查成本变化
aws ce get-cost-and-usage \
  --time-period Start=2024-02-01,End=2024-02-28 \
  --granularity MONTHLY \
  --metrics BlendedCost
```

## 🔒 安全考虑

### 数据保护

- 确保删除前已备份重要数据
- 检查是否有持久化存储卷需要保留
- 验证没有敏感信息遗留在日志文件中

### 权限管理

- 使用最小权限原则
- 确保删除操作有适当的审计日志
- 考虑使用AWS CloudTrail记录所有操作

### 网络安全

- 删除前检查是否有其他服务依赖此VPC
- 确保没有遗留的安全组规则
- 验证所有网络ACL已正确清理

## 📚 相关文档

- [AWS CloudFormation 删除堆栈](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-console-delete-stack.html)
- [OpenShift 集群删除](https://docs.openshift.com/container-platform/4.12/installing/installing_aws/installing-aws-customizations.html#installation-delete-cluster_installing-aws-customizations)
- [AWS EC2 实例终止](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/terminating-instances.html)
- [AWS VPC 删除](https://docs.aws.amazon.com/vpc/latest/userguide/delete-vpc.html)

## 🆘 获取帮助

如果遇到问题：

1. 检查脚本的错误输出
2. 查看AWS CloudFormation控制台中的堆栈事件
3. 检查AWS CloudTrail日志
4. 联系AWS支持（如果适用）

## 📝 示例输出

### 成功删除示例

```
🗑️  Safe VPC Deletion Script
==============================

📋 Configuration:
   Cluster Name: my-cluster
   Region: us-east-1
   VPC Output Dir: ./vpc-output
   Bastion Output Dir: ./bastion-output
   OpenShift Install Dir: ./openshift-install
   Force Mode: no
   Dry Run: no
   Skip OpenShift: no
   Skip Bastion: no

🔴 Step 1: OpenShift Cluster Deletion
----------------------------------------
ℹ️  Checking for OpenShift cluster in: ./openshift-install
⚠️  This will delete the OpenShift cluster and all associated AWS resources
Do you want to proceed with OpenShift cluster deletion? (y/N): y
ℹ️  Deleting OpenShift cluster...
✅ OpenShift cluster deleted successfully

🖥️  Step 2: Bastion Host Deletion
-----------------------------------
ℹ️  Found bastion instance: i-1234567890abcdef0
⚠️  This will terminate the bastion host instance
Do you want to proceed with bastion host deletion? (y/N): y
ℹ️  Terminating bastion instance: i-1234567890abcdef0
ℹ️  Waiting for instance termination...
✅ Bastion host deleted successfully

🔑 Step 3: SSH Key Pair Deletion
----------------------------------
ℹ️  Found SSH key pair: my-cluster-key
ℹ️  Deleting SSH key pair: my-cluster-key
✅ SSH key pair deleted: my-cluster-key
ℹ️  Found SSH key pair: my-cluster-bastion-key
ℹ️  Deleting SSH key pair: my-cluster-bastion-key
✅ SSH key pair deleted: my-cluster-bastion-key

🌐 Step 4: VPC Stack Deletion
-------------------------------
ℹ️  Found VPC stack: my-cluster-vpc-1703123456
⚠️  This will delete the VPC and all associated resources (subnets, NAT gateways, etc.)
Do you want to proceed with VPC stack deletion? (y/N): y
ℹ️  Deleting VPC stack: my-cluster-vpc-1703123456
ℹ️  Waiting for stack deletion to complete...
✅ VPC stack deleted successfully

🧹 Step 5: Output Directory Cleanup
------------------------------------
⚠️  This will remove all output directories and generated files
Do you want to proceed with cleanup? (y/N): y
ℹ️  Removing directory: ./vpc-output
✅ Removed: ./vpc-output
ℹ️  Removing directory: ./bastion-output
✅ Removed: ./bastion-output
ℹ️  Removing directory: ./openshift-install
✅ Removed: ./openshift-install

📊 Deletion Summary
===================
✅ All resources have been successfully deleted!

✅ OpenShift cluster: Deleted (if existed)
✅ Bastion host: Deleted (if existed)
✅ SSH key pairs: Deleted
✅ VPC stack: Deleted
✅ Output directories: Cleaned up

🎉 Cleanup completed successfully!

💡 Tips:
   - Check AWS Console to verify all resources are deleted
   - Monitor AWS costs to ensure no unexpected charges
   - Keep backup of important configuration files if needed
```

### 预览模式示例

```
🗑️  Safe VPC Deletion Script
==============================

📋 Configuration:
   Cluster Name: my-cluster
   Region: us-east-1
   VPC Output Dir: ./vpc-output
   Bastion Output Dir: ./bastion-output
   OpenShift Install Dir: ./openshift-install
   Force Mode: no
   Dry Run: yes
   Skip OpenShift: no
   Skip Bastion: no

ℹ️  DRY RUN MODE - No resources will be actually deleted

🔴 Step 1: OpenShift Cluster Deletion
----------------------------------------
ℹ️  Checking for OpenShift cluster in: ./openshift-install
ℹ️  DRY RUN: Would delete OpenShift cluster from ./openshift-install

🖥️  Step 2: Bastion Host Deletion
-----------------------------------
ℹ️  Found bastion instance: i-1234567890abcdef0
ℹ️  DRY RUN: Would terminate bastion instance: i-1234567890abcdef0

🔑 Step 3: SSH Key Pair Deletion
----------------------------------
ℹ️  Found SSH key pair: my-cluster-key
ℹ️  DRY RUN: Would delete SSH key pair: my-cluster-key
ℹ️  Found SSH key pair: my-cluster-bastion-key
ℹ️  DRY RUN: Would delete SSH key pair: my-cluster-bastion-key

🌐 Step 4: VPC Stack Deletion
-------------------------------
ℹ️  Found VPC stack: my-cluster-vpc-1703123456
ℹ️  DRY RUN: Would delete VPC stack: my-cluster-vpc-1703123456
ℹ️  DRY RUN: Stack resources that would be deleted:
| LogicalResourceId | PhysicalResourceId | ResourceType | ResourceStatus |
|------------------|-------------------|--------------|----------------|
| VPC | vpc-0123456789abcdef0 | AWS::EC2::VPC | CREATE_COMPLETE |
| InternetGateway | igw-0123456789abcdef0 | AWS::EC2::InternetGateway | CREATE_COMPLETE |
| PublicSubnet | subnet-0123456789abcdef0 | AWS::EC2::Subnet | CREATE_COMPLETE |
| PrivateSubnet1 | subnet-0123456789abcdef1 | AWS::EC2::Subnet | CREATE_COMPLETE |
| PrivateSubnet2 | subnet-0123456789abcdef2 | AWS::EC2::Subnet | CREATE_COMPLETE |
| PrivateSubnet3 | subnet-0123456789abcdef3 | AWS::EC2::Subnet | CREATE_COMPLETE |

🧹 Step 5: Output Directory Cleanup
------------------------------------
ℹ️  DRY RUN: Would remove directories:
  - ./vpc-output
  - ./bastion-output
  - ./openshift-install

📊 Deletion Summary
===================
ℹ️  DRY RUN COMPLETED - No resources were actually deleted

To perform actual deletion, run the script without --dry-run
``` 