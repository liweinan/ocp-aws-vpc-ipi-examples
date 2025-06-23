# Quick Delete VPC Guide

A simplified deletion guide providing the most commonly used deletion commands.

## 🚨 Important Warning

**Deleting VPCs will permanently delete all related resources, including OpenShift clusters, EC2 instances, network configurations, and more!**

## Method 1: Using Deletion Scripts (Recommended)

### Step 1: Delete OpenShift Cluster (Recommended First Step)

```bash
# 1. Make script executable
chmod +x delete-cluster.sh

# 2. Preview cluster deletion (strongly recommended first)
./delete-cluster.sh --dry-run

# 3. Delete the OpenShift cluster
./delete-cluster.sh
```

### Step 2: Delete VPC Infrastructure

```bash
# 1. Make script executable
chmod +x delete-vpc.sh

# 2. Preview VPC deletion (strongly recommended first)
./delete-vpc.sh --cluster-name my-cluster --dry-run

# 3. Execute VPC deletion
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
# Check if cluster resources still exist
./delete-cluster.sh --dry-run

# Check if VPC resources still exist
aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/my-cluster,Values=owned"
aws cloudformation describe-stacks --stack-name my-cluster-vpc-*
```

## Common Questions

**Q: What if deletion fails?**
A: Check error messages, usually dependent resources need to be deleted first.

**Q: Can I skip certain steps?**
A: Use `--skip-openshift` or `--skip-bastion` parameters with delete-vpc.sh.

**Q: How to force deletion?**
A: Use `--force` parameter to skip confirmation prompts.

**Q: Should I delete the cluster or VPC first?**
A: It's recommended to delete the OpenShift cluster first using `delete-cluster.sh`, then delete the VPC infrastructure.

For detailed instructions, refer to:
- [Cluster Deletion Guide](README-delete-cluster.md)
- [Complete Deletion Guide](README-delete-vpc.md) 