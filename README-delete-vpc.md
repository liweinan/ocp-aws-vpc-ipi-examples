# Complete VPC Deletion Script

The `delete-vpc.sh` script provides a comprehensive deletion process for VPCs and all related resources when you have the complete output directory structure.

## 🚀 Quick Start

```bash
# Make script executable
chmod +x delete-vpc.sh

# Preview deletion (strongly recommended)
./delete-vpc.sh --cluster-name my-cluster --dry-run

# Execute deletion
./delete-vpc.sh --cluster-name my-cluster

# Force deletion (skip confirmations)
./delete-vpc.sh --cluster-name my-cluster --force
```

## 📋 Features

- **Complete Resource Deletion**: Deletes OpenShift cluster, bastion host, SSH keys, and VPC stack
- **Proper Order**: Deletes resources in the correct dependency order
- **Safety Confirmations**: User confirmation for each major step
- **Dry Run Mode**: Preview operations without executing
- **Flexible Options**: Skip specific components if needed
- **Comprehensive Logging**: Detailed output and error handling

## 🔧 Command Line Options

| Option | Description | Default | Required |
|--------|-------------|---------|----------|
| `--cluster-name` | OpenShift cluster name | N/A | Yes |
| `--vpc-output-dir` | VPC output directory | `./vpc-output` | No |
| `--bastion-output-dir` | Bastion output directory | `./bastion-output` | No |
| `--openshift-install-dir` | OpenShift install directory | `./openshift-install` | No |
| `--region` | AWS region | `us-east-1` | No |
| `--skip-openshift` | Skip OpenShift cluster deletion | `false` | No |
| `--skip-bastion` | Skip bastion host deletion | `false` | No |
| `--force` | Skip confirmation prompts | `false` | No |
| `--dry-run` | Preview operations without executing | `false` | No |
| `--help` | Display help message | N/A | No |

## 🗑️ Deletion Process

The script deletes resources in the following order:

### 1. OpenShift Cluster Deletion
- Uses `openshift-install destroy cluster` command
- Deletes all cluster-related AWS resources (EC2 instances, load balancers, security groups)

### 2. Bastion Host Deletion
- Terminates bastion EC2 instance
- Waits for instance to fully terminate

### 3. SSH Key Pair Deletion
- Deletes cluster-related SSH key pairs
- Deletes bastion host SSH key pairs

### 4. VPC Stack Deletion
- Deletes CloudFormation stack
- Automatically deletes all VPC-related resources (subnets, route tables, NAT gateways)

### 5. Output Directory Cleanup
- Removes local generated configuration files
- Cleans up temporary files

## 📊 Example Output

### Dry Run Mode
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

### Actual Deletion
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

✅ OpenShift cluster: Deleted
✅ Bastion host: Deleted
✅ SSH key pairs: Deleted
✅ VPC stack: Deleted
✅ Output directories: Cleaned up

🎉 Cleanup completed successfully!
```

## 🔄 Advanced Usage

### Skip Specific Components
```bash
# Skip OpenShift cluster deletion
./delete-vpc.sh --cluster-name my-cluster --skip-openshift

# Skip bastion host deletion
./delete-vpc.sh --cluster-name my-cluster --skip-bastion

# Skip both OpenShift and bastion
./delete-vpc.sh --cluster-name my-cluster --skip-openshift --skip-bastion
```

### Custom Directory Paths
```bash
# Use custom output directories
./delete-vpc.sh \
  --cluster-name my-cluster \
  --vpc-output-dir ./custom-vpc-output \
  --bastion-output-dir ./custom-bastion-output \
  --openshift-install-dir ./custom-openshift-install
```

### Different AWS Region
```bash
# Delete resources in different region
./delete-vpc.sh --cluster-name my-cluster --region us-west-2
```

## ⚠️ Important Warnings

### Irreversible Operation
- **VPC deletion is permanent** - All related AWS resources will be permanently deleted
- **No recovery option** - Deleted resources cannot be restored
- **Affects running services** - Any services using the VPC will be affected

### Safety Measures
- Always use `--dry-run` first to preview operations
- Review the list of resources before confirming deletion
- Keep backups of important configuration files
- Use `--force` only in automated environments

## 🆘 Troubleshooting

### Common Issues

1. **OpenShift Cluster Deletion Fails**
   ```bash
   # Check if install directory exists
   ls -la openshift-install/
   
   # Check for auth directory
   ls -la openshift-install/auth/
   
   # Try with debug logging
   cd openshift-install
   ./openshift-install destroy cluster --log-level=debug
   ```

2. **Bastion Instance Termination Fails**
   ```bash
   # Check instance status
   aws ec2 describe-instances --instance-ids i-1234567890abcdef0
   
   # Force terminate if needed
   aws ec2 terminate-instances --instance-ids i-1234567890abcdef0 --force
   ```

3. **VPC Stack Deletion Fails**
   ```bash
   # Check stack events
   aws cloudformation describe-stack-events \
     --stack-name my-cluster-vpc-1703123456
   
   # Check for dependencies
   aws cloudformation describe-stack-resources \
     --stack-name my-cluster-vpc-1703123456
   ```

### Manual Cleanup
If the script fails, you can manually delete resources:

```bash
# 1. Delete OpenShift cluster
cd openshift-install
./openshift-install destroy cluster

# 2. Delete bastion host
INSTANCE_ID=$(cat ../bastion-output/bastion-instance-id)
aws ec2 terminate-instances --instance-ids $INSTANCE_ID

# 3. Delete SSH key pairs
aws ec2 delete-key-pair --key-name my-cluster-key
aws ec2 delete-key-pair --key-name my-cluster-bastion-key

# 4. Delete VPC stack
STACK_NAME=$(cat ../vpc-output/stack-name)
aws cloudformation delete-stack --stack-name $STACK_NAME

# 5. Clean up local files
rm -rf vpc-output bastion-output openshift-install *.pem
```

## 🔍 Verification

After deletion, verify all resources are removed:

```bash
# Check CloudFormation stacks
aws cloudformation describe-stacks --stack-name my-cluster-vpc-1703123456

# Check EC2 instances
aws ec2 describe-instances \
  --filters "Name=tag:kubernetes.io/cluster/my-cluster,Values=owned"

# Check SSH key pairs
aws ec2 describe-key-pairs --key-names my-cluster-key
aws ec2 describe-key-pairs --key-names my-cluster-bastion-key
```

## 💰 Cost Verification

Monitor AWS costs after deletion:

```bash
# Check current costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost
```

## 📚 Related Documentation

- [Delete by Name](README-delete-by-name.md) - When vpc-output directory is lost
- [CloudFormation Deletion](README-delete-cloudformation.md) - Using CloudFormation stack
- [Delete by Owner](README-delete-by-owner.md) - Batch deletion
- [Quick Delete Guide](QUICK-DELETE.md) - Simplified deletion commands
- [Cleanup Script](README-cleanup.md) - Clean up local files
- [Backup Script](README-backup.md) - Create backups before deletion 