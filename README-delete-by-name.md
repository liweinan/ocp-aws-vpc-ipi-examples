# Delete VPC by Name Script

The `delete-vpc-by-name.sh` script allows you to delete VPCs and all related resources using only the VPC name, even when you've lost the `vpc-output` directory.

## 🚀 Quick Start

```bash
# Make script executable
chmod +x delete-vpc-by-name.sh

# Preview deletion (strongly recommended)
./delete-vpc-by-name.sh --vpc-name my-cluster-vpc-1234567890 --dry-run

# Execute deletion
./delete-vpc-by-name.sh --vpc-name my-cluster-vpc-1234567890

# Force deletion (skip confirmations)
./delete-vpc-by-name.sh --vpc-name my-cluster-vpc-1234567890 --force
```

## 📋 Features

- **Smart VPC Discovery**: Automatically finds VPC by name tag
- **CloudFormation Priority**: Uses CloudFormation stack deletion for safety
- **Fallback Methods**: Multiple deletion strategies if primary method fails
- **Detailed Information**: Shows VPC details and related resources
- **Safety Confirmations**: User confirmation for destructive operations
- **Dry Run Mode**: Preview operations without executing

## 🔧 Command Line Options

| Option | Description | Default | Required |
|--------|-------------|---------|----------|
| `--vpc-name` | VPC name to delete | N/A | Yes |
| `--region` | AWS region | `us-east-1` | No |
| `--force` | Skip confirmation prompts | `false` | No |
| `--dry-run` | Preview operations without executing | `false` | No |
| `--help` | Display help message | N/A | No |

## 🔍 Finding VPC Names

If you're unsure of the exact VPC name, use these commands:

```bash
# List all VPCs with their names
aws ec2 describe-vpcs \
  --query 'Vpcs[].{Name:Tags[?Key==`Name`].Value|[0],VpcId:VpcId,CidrBlock:CidrBlock}' \
  --output table

# Find VPCs containing specific keywords
aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=*my-cluster*" \
  --query 'Vpcs[].{Name:Tags[?Key==`Name`].Value|[0],VpcId:VpcId,CidrBlock:CidrBlock}' \
  --output table
```

## 🛠️ Script Functionality

The script performs the following operations:

1. **VPC Discovery**: Searches for VPC by name tag
2. **Resource Detection**: Identifies all related AWS resources
3. **CloudFormation Check**: Looks for associated CloudFormation stack
4. **Safe Deletion**: Prioritizes CloudFormation stack deletion
5. **Fallback Cleanup**: Uses alternative methods if needed

## 📊 Example Output

### Dry Run Mode
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

### Actual Deletion
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

## ⚠️ Important Notes

### VPC Name Format
- Typically follows pattern: `cluster-name-vpc-timestamp`
- Example: `my-cluster-vpc-1703123456`

### Dependency Handling
- Script automatically handles all dependent resource deletion
- CloudFormation stack deletion is prioritized for safety
- Fallback methods available if CloudFormation deletion fails

### Safety Features
- User confirmation required by default (unless `--force` is used)
- CloudFormation stack deletion ensures complete resource cleanup
- Detailed resource information displayed before deletion

## 🆘 Troubleshooting

### VPC Not Found
```bash
# Check if VPC name is correct
aws ec2 describe-vpcs --query 'Vpcs[].Tags[?Key==`Name`].Value' --output text

# Check CloudFormation stacks
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE
```

### Deletion Fails
```bash
# Check for dependent resources
aws ec2 describe-instances --filters "Name=vpc-id,Values=vpc-0123456789abcdef0"

# Manual deletion of dependent resources
aws ec2 delete-subnet --subnet-id subnet-0123456789abcdef0
aws ec2 delete-route-table --route-table-id rtb-0123456789abcdef0
```

## 💡 Usage Recommendations

1. **Always Preview First**: Use `--dry-run` to see what will be deleted
2. **Backup Important Data**: Ensure important data is backed up before deletion
3. **Check Dependencies**: Verify no other services depend on this VPC
4. **Monitor Costs**: Check AWS billing to confirm cost changes after deletion

## 🔄 Alternative Deletion Options

### Other Deletion Scripts

1. **CloudFormation Deletion Script**
   ```bash
   # Use CloudFormation stack name
   ./delete-vpc-cloudformation.sh --stack-name my-cluster-vpc-1750419818
   
   # Use cluster name to find stack
   ./delete-vpc-cloudformation.sh --cluster-name my-cluster
   ```

2. **Batch Deletion by Owner**
   ```bash
   # Delete all VPC stacks in account
   ./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern vpc
   
   # Delete specific cluster VPC stacks
   ./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern my-cluster
   ```

3. **Complete Deletion Script** (requires vpc-output directory)
   ```bash
   # Use complete deletion script
   ./delete-vpc.sh --cluster-name my-cluster
   ```

## 📋 Script Selection Guide

| Scenario | Recommended Script | When to Use |
|----------|-------------------|-------------|
| Lost vpc-output directory | `delete-vpc-by-name.sh` | Only need VPC name |
| Know CloudFormation stack name | `delete-vpc-cloudformation.sh` | Direct stack deletion |
| Batch delete multiple VPCs | `delete-vpc-by-owner.sh` | Bulk operations |
| Have complete output directory | `delete-vpc.sh` | Most comprehensive process |

This script is particularly useful when you've lost the `vpc-output` directory but still need to delete the VPC.

## 📚 Related Documentation

- [Complete Deletion Guide](README-delete-vpc.md) - When you have output directories
- [CloudFormation Deletion Guide](README-delete-cloudformation.md) - Using CloudFormation stacks
- [Batch Deletion Guide](README-delete-by-owner.md) - Multiple VPC deletion
- [Quick Delete Guide](QUICK-DELETE.md) - Simplified deletion commands 