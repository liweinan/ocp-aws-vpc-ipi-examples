# CloudFormation Alternative for Disconnected Cluster Infrastructure

## Overview

This document explains the CloudFormation-based alternative to the original `01-create-infrastructure.sh` script. Based on the `aws-provision-vpc-disconnected` pattern from OpenShift CI, this approach creates all VPC endpoints through CloudFormation instead of individual AWS CLI calls.

## Files Created

### 1. CloudFormation Template
- **File**: `vpc-disconnected-template.yaml`
- **Purpose**: Comprehensive CloudFormation template with all required VPC endpoints
- **Features**: All missing endpoints from the original template (EC2, ELB, Route53, STS, EBS)

### 2. Alternative Script
- **File**: `01-create-infrastructure-cloudformation.sh`
- **Purpose**: Uses CloudFormation template instead of individual AWS CLI calls
- **Features**: Same output format as original script for compatibility

## Comparison: Individual CLI vs CloudFormation

| Aspect | Original Script | CloudFormation Alternative |
|--------|----------------|---------------------------|
| **VPC Endpoints Creation** | Individual `aws ec2 create-vpc-endpoint` calls | Single CloudFormation stack |
| **Deployment Time** | 5-7 minutes | 8-12 minutes |
| **Rollback Capability** | Manual cleanup required | Automatic CloudFormation rollback |
| **Infrastructure as Code** | Imperative (bash commands) | Declarative (YAML template) |
| **Dependency Management** | Manual ordering in script | Automatic CloudFormation dependencies |
| **Output Format** | Compatible with existing scripts | ✅ Same output format |
| **Cost** | Same (~$36/month for endpoints) | Same (~$36/month for endpoints) |

## Advantages of CloudFormation Approach

### ✅ **Infrastructure as Code**
```yaml
# Declarative definition
EC2Endpoint:
  Type: AWS::EC2::VPCEndpoint
  Properties:
    VpcId: !Ref VPC
    ServiceName: !Sub 'com.amazonaws.${AWS::Region}.ec2'
    VpcEndpointType: Interface
    PrivateDnsEnabled: true
```

### ✅ **Automatic Rollback**
- If any resource creation fails, CloudFormation automatically rolls back
- No partial deployments that require manual cleanup

### ✅ **Better Dependency Management**
- CloudFormation handles resource dependencies automatically
- No need to manually order resource creation

### ✅ **Stack-level Operations**
- Update entire infrastructure by updating the template
- Delete all resources with a single stack deletion
- Version control for infrastructure changes

### ✅ **Compliance and Auditing**
- CloudFormation events provide detailed audit trail
- Stack drift detection shows manual changes

## Usage

### Creating Infrastructure

```bash
# Basic usage
cd disconnected-cluster
./01-create-infrastructure-cloudformation.sh --cluster-name my-cluster

# With custom settings
./01-create-infrastructure-cloudformation.sh \
  --cluster-name my-disconnected-cluster \
  --region us-east-1 \
  --vpc-cidr 10.1.0.0/16 \
  --private-subnet-cidr 10.1.100.0/24 \
  --public-subnet-cidr 10.1.10.0/24 \
  --sno

# Dry run to see what would be created
./01-create-infrastructure-cloudformation.sh --dry-run --cluster-name test-cluster
```

### Deleting Infrastructure

```bash
# Delete all resources
./01-create-infrastructure-cloudformation.sh --delete --cluster-name my-cluster
```

## Output Compatibility

The CloudFormation alternative produces the **same output files** as the original script:

```
infra-output/
├── vpc-id                              # VPC identifier
├── public-subnet-ids                   # Public subnet ID
├── private-subnet-ids                  # Private subnet ID
├── availability-zones                  # AZ used
├── region                             # AWS region
├── vpc-cidr                           # VPC CIDR block
├── bastion-security-group-id          # Bastion SG ID
├── cluster-security-group-id          # Cluster SG ID
├── vpc-endpoints-security-group-id    # VPC endpoints SG ID
├── s3-endpoint-id                     # S3 Gateway endpoint
├── ec2-endpoint-id                    # EC2 Interface endpoint
├── elb-endpoint-id                    # ELB Interface endpoint
├── route53-endpoint-id                # Route53 Interface endpoint
├── sts-endpoint-id                    # STS Interface endpoint
├── ebs-endpoint-id                    # EBS Interface endpoint
├── nat-gateway-id                     # 'none' for disconnected
├── eip-id                             # 'none' for disconnected
├── bastion-instance-id                # Bastion instance ID
├── bastion-public-ip                  # Bastion public IP
├── bastion-key.pem                    # SSH private key
├── bastion-key.pem.pub                # SSH public key
└── cloudformation-stack-name          # Stack name for reference
```

## VPC Endpoints Included

Based on the analysis in `VPC-Endpoints-Comparison.md`, the CloudFormation template includes **all required endpoints**:

| Endpoint | Type | Cost/Month | Status |
|----------|------|------------|---------|
| **S3** | Gateway | $0.00 | ✅ Included |
| **EC2** | Interface | $7.20 | ✅ Fixed (was missing) |
| **ELB** | Interface | $7.20 | ✅ Fixed (was missing) |
| **Route53** | Interface | $7.20 | ✅ Fixed (was missing) |
| **STS** | Interface | $7.20 | ✅ Fixed (was missing) |
| **EBS** | Interface | $7.20 | ✅ Fixed (was missing) |
| **Total** | | **$36.00** | ✅ Complete |

## Advanced Usage

### Custom VPC Endpoints

To add additional VPC endpoints, modify the CloudFormation template:

```yaml
# Example: Adding SSM endpoint
SSMEndpoint:
  Type: AWS::EC2::VPCEndpoint
  Properties:
    VpcId: !Ref VPC
    ServiceName: !Sub 'com.amazonaws.${AWS::Region}.ssm'
    VpcEndpointType: Interface
    SubnetIds:
      - !Ref PrivateSubnet
    SecurityGroupIds:
      - !Ref VPCEndpointsSecurityGroup
    PrivateDnsEnabled: true
```

### Custom Template Location

```bash
# Use custom template file
./01-create-infrastructure-cloudformation.sh \
  --template-file ./custom-vpc-template.yaml \
  --cluster-name my-cluster
```

### Multi-node vs SNO Configuration

```bash
# Single Node OpenShift (default)
./01-create-infrastructure-cloudformation.sh --sno --cluster-name sno-cluster

# Multi-node cluster
./01-create-infrastructure-cloudformation.sh --no-sno --cluster-name multi-cluster
```

## Troubleshooting

### CloudFormation Stack Creation Failed

1. **Check stack events**:
```bash
aws cloudformation describe-stack-events \
  --stack-name disconnected-cluster-vpc-infrastructure \
  --region us-east-1 \
  --query 'StackEvents[].[Timestamp,ResourceStatus,ResourceType,ResourceStatusReason]' \
  --output table
```

2. **Common issues**:
   - **CIDR conflicts**: Modify VPC/subnet CIDRs
   - **Service limits**: Check VPC endpoint limits in your region
   - **Permissions**: Ensure IAM permissions for VPC endpoint creation

### Template Validation

```bash
# Validate template before use
aws cloudformation validate-template \
  --template-body file://vpc-disconnected-template.yaml \
  --region us-east-1
```

### Stack Deletion Issues

```bash
# Force delete stack (if needed)
aws cloudformation delete-stack \
  --stack-name disconnected-cluster-vpc-infrastructure \
  --region us-east-1

# Check deletion status
aws cloudformation describe-stacks \
  --stack-name disconnected-cluster-vpc-infrastructure \
  --region us-east-1
```

## Migration from Original Script

### If You Already Used the Original Script

1. **Clean up existing resources**:
```bash
./10-cleanup.sh --cleanup-level aws --force
```

2. **Use CloudFormation alternative**:
```bash
./01-create-infrastructure-cloudformation.sh --cluster-name your-cluster
```

### Keeping the Same Output Structure

The CloudFormation alternative maintains the same output file structure, so all subsequent scripts (`02-create-bastion.sh`, `04-setup-mirror-registry.sh`, etc.) work without modification.

## Cost Comparison

Both approaches have the **same cost** because they create identical resources:

| Resource | Cost/Month |
|----------|------------|
| VPC endpoints (5 Interface) | $36.00 |
| Bastion host (t3.medium) | ~$25.00 |
| **Total Infrastructure** | **~$61.00** |

*SNO cluster nodes and storage costs are additional*

## Next Steps

After creating infrastructure with CloudFormation:

1. **Create bastion host** (automatically included)
2. **Setup mirror registry**:
   ```bash
   ./04-setup-mirror-registry.sh --cluster-name your-cluster
   ```
3. **Continue with existing workflow** - all subsequent scripts work identically

## Best Practices

### 1. Version Control
- Keep the CloudFormation template in version control
- Track changes to infrastructure as code

### 2. Environment Separation
- Use different cluster names for different environments
- Consider separate AWS accounts for production

### 3. Backup Strategy
- Export CloudFormation template before changes
- Keep infrastructure outputs backed up

### 4. Monitoring
- Set up CloudWatch alarms for VPC endpoint usage
- Monitor costs with AWS Cost Explorer

### 5. Security
- Regularly review security group rules
- Monitor VPC flow logs for unusual traffic

## Summary

The CloudFormation alternative provides a more robust, maintainable approach to creating disconnected cluster infrastructure while maintaining full compatibility with existing scripts. It addresses all the missing VPC endpoints identified in the analysis and provides better infrastructure management capabilities. 