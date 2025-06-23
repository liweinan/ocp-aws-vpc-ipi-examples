# Quick Delete VPC Guide

A simplified deletion guide providing the most commonly used deletion commands.

## 🚨 Important Warning

**Deleting VPCs will permanently delete all related resources, including OpenShift clusters, EC2 instances, network configurations, and more!**

## Method 1: Using Deletion Scripts (Recommended)

```bash
# 1. Make script executable
chmod +x delete-vpc.sh

# 2. Preview deletion (strongly recommended first)
./delete-vpc.sh --cluster-name my-cluster --dry-run

# 3. Execute deletion
./delete-vpc.sh --cluster-name my-cluster
```

## Method 2: Manual Deletion

```bash
# 1. Delete OpenShift cluster
cd openshift-install
./openshift-install destroy cluster

# 2. Delete bastion host
INSTANCE_ID=$(cat ../bastion-output/bastion-instance-id)
aws ec2 terminate-instances --instance-ids $INSTANCE_ID

# 3. Delete VPC stack
STACK_NAME=$(cat ../vpc-output/stack-name)
aws cloudformation delete-stack --stack-name $STACK_NAME

# 4. Clean up local files
rm -rf vpc-output bastion-output openshift-install *.pem
```

## Verification

```bash
# Check if related resources still exist
aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/my-cluster,Values=owned"
aws cloudformation describe-stacks --stack-name my-cluster-vpc-*
```

## Common Questions

**Q: What if deletion fails?**
A: Check error messages, usually dependent resources need to be deleted first.

**Q: Can I skip certain steps?**
A: Use `--skip-openshift` or `--skip-bastion` parameters.

**Q: How to force deletion?**
A: Use `--force` parameter to skip confirmation prompts.

For detailed instructions, refer to [Complete Deletion Guide](README-delete-vpc.md). 