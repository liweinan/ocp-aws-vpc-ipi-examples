# 按AWS账户所有者删除VPC

这个脚本允许您通过AWS账户所有者ID来查找和删除VPC CloudFormation堆栈，特别适用于批量删除或管理多个VPC的场景。

## 🚀 快速使用

```bash
# 给脚本执行权限
chmod +x delete-vpc-by-owner.sh

# 预览删除指定账户中的所有VPC堆栈
./delete-vpc-by-owner.sh --owner-id 123456789012 --dry-run

# 删除指定账户中的所有VPC堆栈
./delete-vpc-by-owner.sh --owner-id 123456789012

# 删除特定集群的VPC堆栈
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern my-cluster

# 强制删除（跳过确认）
./delete-vpc-by-owner.sh --owner-id 123456789012 --force
```

## 📋 参数说明

- `--owner-id` - AWS账户所有者ID（必需）
- `--region` - AWS区域（默认：us-east-1）
- `--filter-pattern` - 过滤VPC堆栈的模式（默认：vpc）
- `--force` - 强制删除，跳过确认
- `--dry-run` - 预览模式，不实际删除
- `--help` - 显示帮助信息

## 🛠️ 脚本特点

### 批量操作能力
- **多堆栈处理** - 可以同时处理多个CloudFormation堆栈
- **智能过滤** - 通过模式匹配过滤特定的堆栈
- **验证机制** - 只删除包含VPC资源的堆栈
- **进度监控** - 显示删除进度和结果

### 安全特性
- **预览模式** - 可以预览将要删除的堆栈
- **用户确认** - 默认需要用户确认每个删除操作
- **账户验证** - 验证指定的账户ID与当前账户是否匹配
- **状态检查** - 只处理状态正常的堆栈

## 📊 示例输出

### 预览模式
```
[INFO] Using AWS Account: 123456789012
[INFO] Searching for VPC CloudFormation stacks in account 123456789012 (region: us-east-1)...
[INFO] Validating stacks contain VPC resources...
[INFO] ✓ my-cluster-vpc-1750419818 (contains VPC resources)
[INFO] ✓ test-cluster-vpc-1750419820 (contains VPC resources)
[INFO] ✗ other-stack-1750419825 (no VPC resources, skipping)

[WARNING] Found 2 VPC CloudFormation stack(s) to delete:

  - my-cluster-vpc-1750419818 (Status: CREATE_COMPLETE, Created: 2024-01-01T12:00:00.000Z)
  - test-cluster-vpc-1750419820 (Status: CREATE_COMPLETE, Created: 2024-01-01T13:00:00.000Z)

Are you sure you want to delete these stacks? (yes/no): no
[INFO] Deletion cancelled
```

### 实际删除
```
[INFO] Using AWS Account: 123456789012
[INFO] Searching for VPC CloudFormation stacks in account 123456789012 (region: us-east-1)...
[INFO] Validating stacks contain VPC resources...
[INFO] ✓ my-cluster-vpc-1750419818 (contains VPC resources)

[WARNING] Found 1 VPC CloudFormation stack(s) to delete:

  - my-cluster-vpc-1750419818 (Status: CREATE_COMPLETE, Created: 2024-01-01T12:00:00.000Z)

Are you sure you want to delete these stacks? (yes/no): yes
[INFO] Force mode enabled, proceeding with deletion...
[INFO] Deleting CloudFormation stack: my-cluster-vpc-1750419818
[SUCCESS] Successfully initiated deletion of stack: my-cluster-vpc-1750419818
[INFO] Stack deletion is in progress. You can monitor it with:
[INFO]   aws cloudformation describe-stacks --stack-name my-cluster-vpc-1750419818 --region us-east-1
[INFO] Waiting for stack 'my-cluster-vpc-1750419818' to be deleted...
[INFO] Stack 'my-cluster-vpc-1750419818' status: DELETE_IN_PROGRESS (waiting...)
[SUCCESS] Stack 'my-cluster-vpc-1750419818' has been successfully deleted
[SUCCESS] Deletion process completed. Successfully processed 1 of 1 stack(s)
```

## 🔍 查找AWS账户ID

如果您不确定AWS账户ID：

```bash
# 查看当前AWS账户ID
aws sts get-caller-identity --query 'Account' --output text

# 查看当前账户的详细信息
aws sts get-caller-identity

# 查看所有可用的账户（如果有组织权限）
aws organizations list-accounts --query 'Accounts[].{Id:Id,Name:Name,Status:Status}' --output table
```

## 🎯 使用场景

### 1. 批量清理测试环境
```bash
# 删除所有测试集群的VPC
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern test

# 删除所有开发环境的VPC
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern dev
```

### 2. 清理特定项目
```bash
# 删除特定项目的所有VPC
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern project-name

# 删除特定时间段的VPC
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern 17504198
```

### 3. 跨区域清理
```bash
# 在us-west-2区域删除VPC
./delete-vpc-by-owner.sh --owner-id 123456789012 --region us-west-2

# 在多个区域执行删除（需要分别运行）
./delete-vpc-by-owner.sh --owner-id 123456789012 --region us-east-1
./delete-vpc-by-owner.sh --owner-id 123456789012 --region us-west-2
```

## ⚠️ 重要提醒

### 批量删除风险
1. **影响范围大** - 批量删除会影响多个环境
2. **不可逆操作** - 删除后无法恢复
3. **依赖关系** - 确保没有服务依赖这些VPC
4. **权限要求** - 需要足够的权限删除所有堆栈

### ⚠️ 需要注意：
**脚本会删除账户内**所有**匹配 `vpc` 模式的 CloudFormation stacks**
- 如果账户内有其他人创建的 VPC stacks，也会被删除
- 建议使用 `--filter-pattern` 参数进行更精确的过滤
- 在共享账户中使用时要特别小心

### 安全建议
- **总是先预览** - 使用 `--dry-run` 查看将要删除的堆栈
- **分批删除** - 不要一次性删除太多堆栈
- **备份重要数据** - 删除前确保重要数据已备份
- **通知相关人员** - 确保没有其他人在使用这些环境

## 🆘 故障排除

### 权限问题
```bash
# 检查当前权限
aws sts get-caller-identity

# 检查CloudFormation权限
aws cloudformation list-stacks --max-items 1

# 检查EC2权限
aws ec2 describe-vpcs --max-items 1
```

### 堆栈删除失败
```bash
# 查看失败的堆栈
aws cloudformation list-stacks \
  --stack-status-filter DELETE_FAILED \
  --query 'StackSummaries[].{StackName:StackName,DeletionTime:DeletionTime}' \
  --output table

# 查看堆栈事件
aws cloudformation describe-stack-events \
  --stack-name failed-stack-name \
  --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`].{LogicalResourceId:LogicalResourceId,ResourceStatusReason:ResourceStatusReason}' \
  --output table
```

### 账户ID不匹配
```bash
# 确认当前账户ID
aws sts get-caller-identity --query 'Account' --output text

# 如果使用不同的AWS配置文件
AWS_PROFILE=other-profile aws sts get-caller-identity --query 'Account' --output text
```

## 💡 使用建议

### 1. 渐进式删除
```bash
# 第一步：预览要删除的堆栈
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern test --dry-run

# 第二步：删除少量堆栈
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern test-cluster-1

# 第三步：删除剩余堆栈
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern test-cluster-2
```

### 2. 使用模式过滤
```bash
# 按时间过滤（删除特定日期的堆栈）
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern 17504198

# 按环境过滤
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern dev
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern staging
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern prod
```

### 3. 监控和验证
```bash
# 删除后验证
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[?contains(StackName, 'vpc')].StackName" \
  --output text

# 检查VPC
aws ec2 describe-vpcs \
  --query 'Vpcs[].{VpcId:VpcId,Name:Tags[?Key==`Name`].Value|[0]}' \
  --output table
```

## 🔄 与其他脚本的区别

| 脚本 | 适用场景 | 优势 |
|------|----------|------|
| `delete-vpc-by-owner.sh` | 批量删除多个VPC | 批量操作，效率高 |
| `delete-vpc-cloudformation.sh` | 单个堆栈删除 | 最安全，确保完整删除 |
| `delete-vpc-by-name.sh` | 只知道VPC名称 | 智能查找，灵活 |
| `delete-vpc.sh` | 有完整输出目录 | 最完整的删除流程 |

这个脚本特别适用于需要批量管理多个VPC堆栈的场景，如清理测试环境、项目迁移等。 