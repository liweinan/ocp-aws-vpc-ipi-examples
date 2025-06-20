# 快速删除VPC指南

这是一个简化的删除指南，提供最常用的删除命令。

## 🚨 重要警告

**删除VPC会永久删除所有相关资源，包括OpenShift集群、EC2实例、网络配置等！**

## 方法1：使用删除脚本（推荐）

```bash
# 1. 给脚本执行权限
chmod +x delete-vpc.sh

# 2. 预览删除（强烈推荐先运行）
./delete-vpc.sh --cluster-name my-cluster --dry-run

# 3. 执行删除
./delete-vpc.sh --cluster-name my-cluster
```

## 方法2：手动删除

```bash
# 1. 删除OpenShift集群
cd openshift-install
./openshift-install destroy cluster

# 2. 删除Bastion主机
INSTANCE_ID=$(cat ../bastion-output/bastion-instance-id)
aws ec2 terminate-instances --instance-ids $INSTANCE_ID

# 3. 删除VPC堆栈
STACK_NAME=$(cat ../vpc-output/stack-name)
aws cloudformation delete-stack --stack-name $STACK_NAME

# 4. 清理本地文件
rm -rf vpc-output bastion-output openshift-install *.pem
```

## 验证删除

```bash
# 检查是否还有相关资源
aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/my-cluster,Values=owned"
aws cloudformation describe-stacks --stack-name my-cluster-vpc-*
```

## 常见问题

**Q: 删除失败怎么办？**
A: 检查错误信息，通常需要先删除依赖资源。

**Q: 可以跳过某些步骤吗？**
A: 使用 `--skip-openshift` 或 `--skip-bastion` 参数。

**Q: 如何强制删除？**
A: 使用 `--force` 参数跳过确认提示。

详细说明请参考 [完整删除指南](README-delete-vpc.md)。 