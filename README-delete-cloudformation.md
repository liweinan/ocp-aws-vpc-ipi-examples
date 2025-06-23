# CloudFormation VPC删除脚本

这个脚本专门用于删除CloudFormation VPC堆栈，根据同事建议使用 `aws cloudformation delete-stack` 来确保整个stack内创建的所有资源都被正确删除。

## 🚀 快速使用

```bash
# 给脚本执行权限
chmod +x delete-vpc-cloudformation.sh

# 使用集群名称查找并删除
./delete-vpc-cloudformation.sh --cluster-name my-cluster

# 使用具体的堆栈名称删除
./delete-vpc-cloudformation.sh --stack-name my-cluster-vpc-1750419818

# 预览删除（强烈推荐先运行）
./delete-vpc-cloudformation.sh --cluster-name my-cluster --dry-run

# 强制删除（跳过确认）
./delete-vpc-cloudformation.sh --stack-name my-cluster-vpc-1750419818 --force
```

## 📋 参数说明

- `--cluster-name` - 集群名称（用于查找对应的CloudFormation堆栈）
- `--stack-name` - CloudFormation堆栈名称（如果知道具体名称）
- `--region` - AWS区域（默认：us-east-1）
- `--force` - 强制删除，跳过确认
- `--dry-run` - 预览模式，不实际删除
- `--help` - 显示帮助信息

## 🛠️ 脚本特点

### 同事建议的优势
- **完整删除** - 使用 `aws cloudformation delete-stack` 确保所有资源都被删除
- **依赖处理** - CloudFormation会自动处理资源间的依赖关系
- **原子操作** - 要么全部删除成功，要么回滚到原状态
- **审计追踪** - 所有删除操作都有完整的CloudFormation事件记录

### 智能查找
- 如果提供 `--stack-name`，直接使用指定的堆栈名称
- 如果提供 `--cluster-name`，自动查找包含该集群名称的VPC堆栈
- 显示找到的堆栈详细信息和资源列表

## 📊 示例输出

### 使用集群名称查找
```
🗑️  CloudFormation VPC Deletion Script
======================================

📋 Configuration:
   Cluster Name: my-cluster
   Region: us-east-1
   Force Mode: no
   Dry Run: no

ℹ️  Searching for CloudFormation stack with cluster name: my-cluster
ℹ️  Found CloudFormation stack: my-cluster-vpc-1750419818
ℹ️  Stack Details:
  Stack Name: my-cluster-vpc-1750419818
  Stack Status: CREATE_COMPLETE
  Creation Time: 2024-01-01T12:00:00.000Z
  Description: Enhanced VPC for OpenShift IPI Installation
ℹ️  Stack Resources:
| LogicalResourceId | PhysicalResourceId | ResourceType | ResourceStatus |
|------------------|-------------------|--------------|----------------|
| VPC | vpc-0123456789abcdef0 | AWS::EC2::VPC | CREATE_COMPLETE |
| InternetGateway | igw-0123456789abcdef0 | AWS::EC2::InternetGateway | CREATE_COMPLETE |
| PublicSubnet | subnet-0123456789abcdef0 | AWS::EC2::Subnet | CREATE_COMPLETE |
| PrivateSubnet1 | subnet-0123456789abcdef1 | AWS::EC2::Subnet | CREATE_COMPLETE |
| PrivateSubnet2 | subnet-0123456789abcdef2 | AWS::EC2::Subnet | CREATE_COMPLETE |
| PrivateSubnet3 | subnet-0123456789abcdef3 | AWS::EC2::Subnet | CREATE_COMPLETE |

⚠️  重要提醒：这将删除整个CloudFormation stack和所有相关资源！
   - Stack: my-cluster-vpc-1750419818
   - 所有VPC资源（VPC、子网、路由表、安全组等）
   - 所有网络资源（NAT网关、互联网网关等）
   - 其他相关AWS资源

💡 同事建议：使用 aws cloudformation delete-stack 确保所有资源都被正确删除

确定要删除这个CloudFormation stack吗？(y/N): y

🏗️  Deleting CloudFormation Stack
-----------------------------------
ℹ️  Deleting CloudFormation stack: my-cluster-vpc-1750419818
ℹ️  Command: aws cloudformation delete-stack --stack-name my-cluster-vpc-1750419818 --region us-east-1
✅ CloudFormation delete-stack command executed successfully
ℹ️  Waiting for stack deletion to complete...
✅ CloudFormation stack deleted successfully: my-cluster-vpc-1750419818

📊 Deletion Summary
===================
✅ CloudFormation stack deletion completed!
✅ Stack: my-cluster-vpc-1750419818

🎉 根据同事建议，使用 aws cloudformation delete-stack 成功删除了整个stack！
   这确保了stack内创建的所有资源都被正确删除。

💡 Tips:
   - 检查AWS Console确认所有资源都已删除
   - 监控AWS费用确保没有意外收费
   - 如果删除失败，检查是否有依赖关系需要手动处理
   - 同事建议：始终使用 aws cloudformation delete-stack 来删除VPC stack
```

### 预览模式
```
🗑️  CloudFormation VPC Deletion Script
======================================

📋 Configuration:
   Stack Name: my-cluster-vpc-1750419818
   Region: us-east-1
   Force Mode: no
   Dry Run: yes

ℹ️  DRY RUN MODE - No resources will be actually deleted

ℹ️  Using provided stack name: my-cluster-vpc-1750419818
ℹ️  Stack Details:
  Stack Name: my-cluster-vpc-1750419818
  Stack Status: CREATE_COMPLETE
  Creation Time: 2024-01-01T12:00:00.000Z
  Description: Enhanced VPC for OpenShift IPI Installation
ℹ️  Stack Resources:
| LogicalResourceId | PhysicalResourceId | ResourceType | ResourceStatus |
|------------------|-------------------|--------------|----------------|
| VPC | vpc-0123456789abcdef0 | AWS::EC2::VPC | CREATE_COMPLETE |
| InternetGateway | igw-0123456789abcdef0 | AWS::EC2::InternetGateway | CREATE_COMPLETE |
| PublicSubnet | subnet-0123456789abcdef0 | AWS::EC2::Subnet | CREATE_COMPLETE |

🏗️  Deleting CloudFormation Stack
-----------------------------------
ℹ️  DRY RUN: Would delete CloudFormation stack: my-cluster-vpc-1750419818
ℹ️  DRY RUN: Command: aws cloudformation delete-stack --stack-name my-cluster-vpc-1750419818 --region us-east-1

📊 Deletion Summary
===================
ℹ️  DRY RUN COMPLETED - No resources were actually deleted

要执行实际删除，请运行脚本时不使用 --dry-run
```

## 🔍 查找CloudFormation堆栈

如果您不确定堆栈的确切名称：

```bash
# 列出所有CloudFormation堆栈
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query 'StackSummaries[].{StackName:StackName,CreationTime:CreationTime}' \
  --output table

# 查找包含特定关键词的堆栈
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[?contains(StackName, 'my-cluster')].{StackName:StackName,CreationTime:CreationTime}" \
  --output table

# 查找VPC相关的堆栈
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[?contains(StackName, 'vpc')].{StackName:StackName,CreationTime:CreationTime}" \
  --output table
```

## ⚠️ 重要提醒

### 删除前检查
1. **确认堆栈名称** - 确保删除的是正确的CloudFormation堆栈
2. **检查资源状态** - 确认堆栈状态为 `CREATE_COMPLETE` 或 `UPDATE_COMPLETE`
3. **备份重要数据** - 如果有重要数据，先备份
4. **通知相关人员** - 确保没有其他人在使用这个环境

### 同事建议的优势
- **完整性** - 确保所有通过CloudFormation创建的资源都被删除
- **安全性** - 避免遗漏资源导致的安全风险
- **成本控制** - 避免遗漏资源导致的持续收费
- **审计合规** - 完整的删除记录便于审计

## 🆘 故障排除

### 堆栈删除失败
```bash
# 查看堆栈事件，了解删除失败的原因
aws cloudformation describe-stack-events \
  --stack-name my-cluster-vpc-1750419818 \
  --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`].{LogicalResourceId:LogicalResourceId,ResourceStatusReason:ResourceStatusReason}' \
  --output table

# 查看堆栈状态
aws cloudformation describe-stacks \
  --stack-name my-cluster-vpc-1750419818 \
  --query 'Stacks[0].StackStatus' \
  --output text
```

### 依赖资源问题
```bash
# 查看堆栈资源
aws cloudformation list-stack-resources \
  --stack-name my-cluster-vpc-1750419818 \
  --query 'StackResourceSummaries[?ResourceStatus!=`DELETE_COMPLETE`].{LogicalResourceId:LogicalResourceId,ResourceType:ResourceType,ResourceStatus:ResourceStatus}' \
  --output table
```

## 💡 使用建议

1. **总是先预览** - 使用 `--dry-run` 查看将要删除的资源
2. **使用堆栈名称** - 如果知道确切的堆栈名称，直接使用 `--stack-name`
3. **监控删除进度** - 删除过程可能需要几分钟，可以在AWS Console中监控
4. **检查删除结果** - 删除完成后，确认所有资源都已删除

## 🔄 与其他脚本的区别

| 脚本 | 适用场景 | 优势 |
|------|----------|------|
| `delete-vpc-cloudformation.sh` | 知道CloudFormation堆栈 | 最安全，确保完整删除 |
| `delete-vpc-by-name.sh` | 只知道VPC名称 | 智能查找，灵活 |
| `delete-vpc-by-owner.sh` | 批量删除多个VPC | 批量操作，效率高 |
| `delete-vpc.sh` | 有完整输出目录 | 最完整的删除流程 |

根据同事建议，**推荐优先使用 `delete-vpc-cloudformation.sh`**，因为它使用 `aws cloudformation delete-stack` 确保所有资源都被正确删除。 