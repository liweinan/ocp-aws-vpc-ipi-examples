# CloudFormation VPC Deletion Script

The `delete-vpc-cloudformation.sh` script is specifically designed to delete CloudFormation VPC stacks, ensuring all resources created within the stack are properly deleted.

## 🚀 Quick Start

```bash
# Make script executable
chmod +x delete-vpc-cloudformation.sh

# Delete using cluster name
./delete-vpc-cloudformation.sh --cluster-name my-cluster

# Delete using specific stack name
./delete-vpc-cloudformation.sh --stack-name my-cluster-vpc-1750419818

# Preview deletion (strongly recommended)
./delete-vpc-cloudformation.sh --cluster-name my-cluster --dry-run

# Force deletion (skip confirmations)
./delete-vpc-cloudformation.sh --stack-name my-cluster-vpc-1750419818 --force
```

## 📋 Features

- **Complete Resource Deletion**: Uses `aws cloudformation delete-stack` to ensure all resources are deleted
- **Dependency Handling**: CloudFormation automatically handles resource dependencies
- **Atomic Operations**: Either all resources are deleted or the operation rolls back
- **Audit Trail**: Complete CloudFormation event records for all deletion operations
- **Smart Discovery**: Can find stacks by cluster name or use specific stack names
- **Safety Confirmations**: User confirmation for destructive operations

## 🔧 Command Line Options

| Option | Description | Default | Required |
|--------|-------------|---------|----------|
| `--cluster-name` | Cluster name to find corresponding CloudFormation stack | N/A | No* |
| `--stack-name` | Specific CloudFormation stack name | N/A | No* |
| `--region` | AWS region | `us-east-1` | No |
| `--force` | Skip confirmation prompts | `false` | No |
| `--dry-run` | Preview operations without executing | `false` | No |
| `--help` | Display help message | N/A | No |

*Either `--cluster-name` or `--stack-name` is required

## 🛠️ Script Advantages

### CloudFormation Benefits
- **Complete Deletion**: Ensures all resources created by the stack are deleted
- **Dependency Management**: Automatically handles resource dependencies
- **Atomic Operations**: Either succeeds completely or rolls back
- **Audit Compliance**: Complete event records for compliance and troubleshooting

### Intelligent Discovery
- If `--stack-name` is provided, uses the specified stack name directly
- If `--cluster-name` is provided, automatically finds VPC stacks containing the cluster name
- Displays detailed stack information and resource lists

## 📊 Example Output

### Using Cluster Name
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

⚠️  Important: This will delete the entire CloudFormation stack and all related resources!
   - Stack: my-cluster-vpc-1750419818
   - All VPC resources (VPC, subnets, route tables, security groups)
   - All network resources (NAT gateways, internet gateways)
   - Other related AWS resources

💡 Recommendation: Using aws cloudformation delete-stack ensures all resources are properly deleted

Do you want to delete this CloudFormation stack? (y/N): y

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

🎉 Successfully deleted the entire stack using aws cloudformation delete-stack!
   This ensures all resources created within the stack are properly deleted.

💡 Tips:
   - Check AWS Console to confirm all resources are deleted
   - Monitor AWS costs to ensure no unexpected charges
   - If deletion fails, check for dependencies that need manual handling
   - Recommendation: Always use aws cloudformation delete-stack for VPC stacks
```

### Dry Run Mode
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

To perform actual deletion, run the script without --dry-run
```

## 🔍 Finding CloudFormation Stacks

If you're unsure of the exact stack name:

```bash
# List all CloudFormation stacks
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query 'StackSummaries[].{StackName:StackName,CreationTime:CreationTime}' \
  --output table

# Find stacks containing specific keywords
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[?contains(StackName, 'my-cluster')].{StackName:StackName,CreationTime:CreationTime}" \
  --output table

# Find VPC-related stacks
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[?contains(StackName, 'vpc')].{StackName:StackName,CreationTime:CreationTime}" \
  --output table
```

## ⚠️ Important Warnings

### Pre-Deletion Checklist
1. **Confirm Stack Name**: Ensure you're deleting the correct CloudFormation stack
2. **Check Stack Status**: Verify stack status is `CREATE_COMPLETE` or `UPDATE_COMPLETE`
3. **Backup Important Data**: Backup any important data if needed
4. **Notify Team Members**: Ensure no one else is using this environment

### Security Considerations
- **Complete Deletion**: Ensures all resources created through CloudFormation are deleted
- **Security**: Avoids leaving orphaned resources that could pose security risks
- **Cost Control**: Prevents orphaned resources from continuing to incur charges
- **Audit Compliance**: Complete deletion records for compliance purposes

## 🆘 Troubleshooting

### Stack Deletion Failures
```bash
# View stack events to understand deletion failure
aws cloudformation describe-stack-events \
  --stack-name my-cluster-vpc-1750419818 \
  --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`].{LogicalResourceId:LogicalResourceId,ResourceStatusReason:ResourceStatusReason}' \
  --output table

# Check stack status
aws cloudformation describe-stacks \
  --stack-name my-cluster-vpc-1750419818 \
  --query 'Stacks[0].StackStatus' \
  --output text
```

### Dependency Issues
```bash
# View stack resources
aws cloudformation list-stack-resources \
  --stack-name my-cluster-vpc-1750419818 \
  --query 'StackResourceSummaries[?ResourceStatus!=`DELETE_COMPLETE`].{LogicalResourceId:LogicalResourceId,ResourceType:ResourceType,ResourceStatus:ResourceStatus}' \
  --output table
```

## 💡 Usage Recommendations

1. **Always Preview First**: Use `--dry-run` to see what will be deleted
2. **Use Stack Names**: If you know the exact stack name, use `--stack-name` for direct access
3. **Monitor Progress**: Deletion may take several minutes, monitor in AWS Console
4. **Verify Results**: After deletion, confirm all resources are removed

## 🔄 Alternative Deletion Scripts

| Script | Use Case | When to Use |
|--------|----------|-------------|
| `delete-vpc-cloudformation.sh` | Know CloudFormation stack | Most secure, ensures complete deletion |
| `delete-vpc-by-name.sh` | Only know VPC name | Smart discovery, flexible |
| `delete-vpc-by-owner.sh` | Batch delete multiple VPCs | Bulk operations, high efficiency |
| `delete-vpc.sh` | Have complete output directory | Most comprehensive deletion process |

**Recommended**: Use `delete-vpc-cloudformation.sh` as the primary deletion method since it uses `aws cloudformation delete-stack` to ensure all resources are properly deleted.

## 📚 Related Documentation

- [Complete Deletion Guide](README-delete-vpc.md) - When you have output directories
- [Delete by Name Guide](README-delete-by-name.md) - When you only know VPC name
- [Batch Deletion Guide](README-delete-by-owner.md) - Multiple VPC deletion
- [Quick Delete Guide](QUICK-DELETE.md) - Simplified deletion commands
- [AWS CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/) - Official AWS documentation 