# Batch VPC Deletion by AWS Account Owner

The `delete-vpc-by-owner.sh` script allows you to find and delete VPC CloudFormation stacks by AWS account owner ID, particularly useful for batch deletion or managing multiple VPCs.

## 🚀 Quick Start

```bash
# Make script executable
chmod +x delete-vpc-by-owner.sh

# Preview deletion of all VPC stacks in account
./delete-vpc-by-owner.sh --owner-id 123456789012 --dry-run

# Delete all VPC stacks in account
./delete-vpc-by-owner.sh --owner-id 123456789012

# Delete specific cluster VPC stacks
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern my-cluster

# Force deletion (skip confirmations)
./delete-vpc-by-owner.sh --owner-id 123456789012 --force
```

## 📋 Features

- **Batch Operations**: Process multiple CloudFormation stacks simultaneously
- **Smart Filtering**: Filter stacks by pattern matching
- **Validation**: Only delete stacks containing VPC resources
- **Progress Monitoring**: Display deletion progress and results
- **Safety Features**: Preview mode and user confirmations
- **Account Verification**: Validate specified account ID against current account

## 🔧 Command Line Options

| Option | Description | Default | Required |
|--------|-------------|---------|----------|
| `--owner-id` | AWS account owner ID | N/A | Yes |
| `--region` | AWS region | `us-east-1` | No |
| `--filter-pattern` | Filter VPC stacks by pattern | `vpc` | No |
| `--force` | Skip confirmation prompts | `false` | No |
| `--dry-run` | Preview operations without executing | `false` | No |
| `--help` | Display help message | N/A | No |

## 🛠️ Script Capabilities

### Batch Processing
- **Multi-Stack Handling**: Can process multiple CloudFormation stacks at once
- **Intelligent Filtering**: Filter specific stacks using pattern matching
- **Validation Mechanism**: Only delete stacks containing VPC resources
- **Progress Tracking**: Show deletion progress and results

### Safety Features
- **Preview Mode**: Preview stacks to be deleted before execution
- **User Confirmation**: Require user confirmation for each deletion operation
- **Account Validation**: Verify specified account ID matches current account
- **Status Checking**: Only process stacks in normal status

## 📊 Example Output

### Dry Run Mode
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

### Actual Deletion
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

## 🔍 Finding AWS Account ID

If you're unsure of your AWS account ID:

```bash
# View current AWS account ID
aws sts get-caller-identity --query 'Account' --output text

# View current account details
aws sts get-caller-identity

# View all available accounts (if you have organization permissions)
aws organizations list-accounts --query 'Accounts[].{Id:Id,Name:Name,Status:Status}' --output table
```

## 🎯 Use Cases

### Batch Cleanup of Test Environments
```bash
# Delete all test cluster VPCs
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern test

# Delete all development environment VPCs
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern dev
```

### Project-Specific Cleanup
```bash
# Delete all VPCs for a specific project
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern project-name

# Delete VPCs from a specific time period
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern 17504198
```

### Cross-Region Cleanup
```bash
# Delete VPCs in us-west-2 region
./delete-vpc-by-owner.sh --owner-id 123456789012 --region us-west-2

# Delete VPCs in multiple regions (run separately)
./delete-vpc-by-owner.sh --owner-id 123456789012 --region us-east-1
./delete-vpc-by-owner.sh --owner-id 123456789012 --region us-west-2
```

## ⚠️ Important Warnings

### Batch Deletion Risks
1. **Large Impact**: Batch deletion affects multiple environments
2. **Irreversible Operation**: Deleted resources cannot be recovered
3. **Dependencies**: Ensure no services depend on these VPCs
4. **Permissions**: Requires sufficient permissions to delete all stacks

### Safety Recommendations
- **Always Preview First**: Use `--dry-run` to see stacks to be deleted
- **Batch in Small Groups**: Don't delete too many stacks at once
- **Backup Important Data**: Ensure important data is backed up before deletion
- **Notify Team Members**: Ensure no one else is using these environments

## 🆘 Troubleshooting

### Permission Issues
```bash
# Check current permissions
aws sts get-caller-identity

# Check CloudFormation permissions
aws cloudformation list-stacks --max-items 1

# Check EC2 permissions
aws ec2 describe-vpcs --max-items 1
```

### Stack Deletion Failures
```bash
# View failed stacks
aws cloudformation list-stacks \
  --stack-status-filter DELETE_FAILED \
  --query 'StackSummaries[].{StackName:StackName,DeletionTime:DeletionTime}' \
  --output table

# View stack events
aws cloudformation describe-stack-events \
  --stack-name failed-stack-name \
  --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`].{LogicalResourceId:LogicalResourceId,ResourceStatusReason:ResourceStatusReason}' \
  --output table
```

### Account ID Mismatch
```bash
# Confirm current account ID
aws sts get-caller-identity --query 'Account' --output text

# If using different AWS profile
AWS_PROFILE=other-profile aws sts get-caller-identity --query 'Account' --output text
```

## 💡 Usage Recommendations

### Gradual Deletion
```bash
# Step 1: Preview stacks to be deleted
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern test --dry-run

# Step 2: Delete small batches
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern test-cluster-1

# Step 3: Delete remaining stacks
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern test-cluster-2
```

### Pattern Filtering
```bash
# Filter by time (delete stacks from specific date)
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern 17504198

# Filter by environment
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern dev
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern staging
./delete-vpc-by-owner.sh --owner-id 123456789012 --filter-pattern prod
```

### Monitoring and Verification
```bash
# Verify deletion after completion
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[?contains(StackName, 'vpc')].StackName" \
  --output text

# Check VPCs
aws ec2 describe-vpcs \
  --query 'Vpcs[].{VpcId:VpcId,Name:Tags[?Key==`Name`].Value|[0]}' \
  --output table
```

## 🔄 Comparison with Other Scripts

| Script | Use Case | Advantages |
|--------|----------|------------|
| `delete-vpc-by-owner.sh` | Batch delete multiple VPCs | Batch operations, high efficiency |
| `delete-vpc-cloudformation.sh` | Single stack deletion | Most secure, ensures complete deletion |
| `delete-vpc-by-name.sh` | Only know VPC name | Smart discovery, flexible |
| `delete-vpc.sh` | Have complete output directory | Most comprehensive deletion process |

This script is particularly useful for scenarios requiring batch management of multiple VPC stacks, such as cleaning up test environments or project migrations.

## 📚 Related Documentation

- [Complete Deletion Guide](README-delete-vpc.md) - When you have output directories
- [Delete by Name Guide](README-delete-by-name.md) - When you only know VPC name
- [CloudFormation Deletion Guide](README-delete-cloudformation.md) - Using CloudFormation stacks
- [Quick Delete Guide](QUICK-DELETE.md) - Simplified deletion commands
- [AWS Organizations Documentation](https://docs.aws.amazon.com/organizations/) - Multi-account management 