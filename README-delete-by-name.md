# 通过VPC名称删除VPC

这个脚本允许您只通过VPC名称来删除VPC和所有相关资源，即使您丢失了 `vpc-output` 目录。

## 🚀 快速使用

```bash
# 给脚本执行权限
chmod +x delete-vpc-by-name.sh

# 预览删除（强烈推荐先运行）
./delete-vpc-by-name.sh --vpc-name my-cluster-vpc-1234567890 --dry-run

# 执行删除
./delete-vpc-by-name.sh --vpc-name my-cluster-vpc-1234567890

# 强制删除（跳过确认）
./delete-vpc-by-name.sh --vpc-name my-cluster-vpc-1234567890 --force
```

## 📋 参数说明

- `--vpc-name` - VPC名称（必需）
- `--region` - AWS区域（默认：us-east-1）
- `--force` - 强制删除，跳过确认
- `--dry-run` - 预览模式，不实际删除
- `--help` - 显示帮助信息

## 🔍 查找VPC名称

如果您不确定VPC的确切名称，可以使用以下命令查找：

```bash
# 列出所有VPC及其名称
aws ec2 describe-vpcs \
  --query 'Vpcs[].{Name:Tags[?Key==`Name`].Value|[0],VpcId:VpcId,CidrBlock:CidrBlock}' \
  --output table

# 查找包含特定关键词的VPC
aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=*my-cluster*" \
  --query 'Vpcs[].{Name:Tags[?Key==`Name`].Value|[0],VpcId:VpcId,CidrBlock:CidrBlock}' \
  --output table
```

## 🛠️ 脚本功能

这个脚本会：

1. **自动查找VPC** - 通过名称标签查找VPC
2. **智能检测** - 如果找不到VPC，会尝试查找CloudFormation堆栈
3. **显示详细信息** - 显示VPC的详细信息和相关资源
4. **安全删除** - 优先使用CloudFormation堆栈删除（更安全）
5. **错误处理** - 如果直接删除失败，会尝试其他方法

## 📊 示例输出

### 预览模式
```
🗑️  Delete VPC by Name Script
==============================

📋 Configuration:
   VPC Name: my-cluster-vpc-1703123456
   Region: us-east-1
   Force Mode: no
   Dry Run: yes

ℹ️  DRY RUN MODE - No resources will be actually deleted

ℹ️  Searching for VPC with name: my-cluster-vpc-1703123456
ℹ️  Found VPC: vpc-0123456789abcdef0
ℹ️  VPC Details:
  VPC ID: vpc-0123456789abcdef0
  CIDR Block: 10.0.0.0/16
  State: available
  DNS Hostnames: true
  DNS Support: true
ℹ️  VPC Resources:
  Subnets: subnet-0123456789abcdef0 subnet-0123456789abcdef1
  Route Tables: rtb-0123456789abcdef0
  Security Groups: sg-0123456789abcdef0
  Internet Gateways: igw-0123456789abcdef0
  NAT Gateways: nat-0123456789abcdef0

🏗️  Deleting CloudFormation Stack
-----------------------------------
ℹ️  DRY RUN: Would delete CloudFormation stack: my-cluster-vpc-1703123456

📊 Deletion Summary
===================
ℹ️  DRY RUN COMPLETED - No resources were actually deleted

To perform actual deletion, run the script without --dry-run
```

### 实际删除
```
🗑️  Delete VPC by Name Script
==============================

📋 Configuration:
   VPC Name: my-cluster-vpc-1703123456
   Region: us-east-1
   Force Mode: no
   Dry Run: no

ℹ️  Searching for VPC with name: my-cluster-vpc-1703123456
ℹ️  Found VPC: vpc-0123456789abcdef0
ℹ️  VPC Details:
  VPC ID: vpc-0123456789abcdef0
  CIDR Block: 10.0.0.0/16
  State: available
  DNS Hostnames: true
  DNS Support: true
ℹ️  VPC Resources:
  Subnets: subnet-0123456789abcdef0 subnet-0123456789abcdef1
  Route Tables: rtb-0123456789abcdef0
  Security Groups: sg-0123456789abcdef0
  Internet Gateways: igw-0123456789abcdef0
  NAT Gateways: nat-0123456789abcdef0

⚠️  This will delete the VPC and all associated resources!
   - CloudFormation Stack: my-cluster-vpc-1703123456

Do you want to proceed? (y/N): y

🏗️  Deleting CloudFormation Stack
-----------------------------------
ℹ️  Deleting CloudFormation stack: my-cluster-vpc-1703123456
ℹ️  Waiting for stack deletion to complete...
✅ CloudFormation stack deleted successfully: my-cluster-vpc-1703123456

📊 Deletion Summary
===================
✅ VPC deletion completed successfully!
✅ CloudFormation Stack: my-cluster-vpc-1703123456

🎉 Cleanup completed successfully!
```

## ⚠️ 注意事项

1. **VPC名称格式** - 通常格式为 `cluster-name-vpc-timestamp`
2. **依赖资源** - 脚本会自动处理所有依赖资源的删除
3. **CloudFormation优先** - 如果找到CloudFormation堆栈，会优先使用堆栈删除
4. **安全确认** - 默认需要用户确认，除非使用 `--force` 参数

## 🆘 故障排除

### 找不到VPC
```bash
# 检查VPC名称是否正确
aws ec2 describe-vpcs --query 'Vpcs[].Tags[?Key==`Name`].Value' --output text

# 检查CloudFormation堆栈
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE
```

### 删除失败
```bash
# 检查是否有依赖资源
aws ec2 describe-instances --filters "Name=vpc-id,Values=vpc-0123456789abcdef0"

# 手动删除依赖资源
aws ec2 delete-subnet --subnet-id subnet-0123456789abcdef0
aws ec2 delete-route-table --route-table-id rtb-0123456789abcdef0
```

## 💡 使用建议

1. **总是先预览** - 使用 `--dry-run` 查看将要删除的资源
2. **备份重要数据** - 删除前确保重要数据已备份
3. **检查依赖** - 确保没有其他服务依赖此VPC
4. **监控成本** - 删除后检查AWS账单确认成本变化

这个脚本特别适用于您丢失了 `vpc-output` 目录但仍然需要删除VPC的情况。 