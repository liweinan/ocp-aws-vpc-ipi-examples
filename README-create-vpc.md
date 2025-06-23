# Enhanced VPC Creation Script

A comprehensive AWS VPC creation script that combines the best features from CI operator and automation scripts. This script creates production-ready VPCs with support for multiple availability zones, shared VPC capabilities, and comprehensive output management.

## Features

### 🏗️ **VPC Architecture**
- **Multi-AZ Support**: Create VPCs with 1-3 availability zones
- **Flexible Subnet Sizing**: Configurable subnet sizes (5-13 bits)
- **Public/Private Subnets**: Both public and private subnets with proper routing
- **NAT Gateways**: Automatic NAT gateway creation for private subnet internet access
- **S3 VPC Endpoints**: Built-in S3 endpoints for better performance

### 🔧 **Advanced Features**
- **Shared VPC Support**: Resource sharing across AWS accounts via AWS RAM
- **Custom DHCP Options**: Optional custom DHCP configuration
- **Additional Subnets**: Support for additional subnets in the same AZ
- **Zone Selection**: Specify exact availability zones to use
- **Public-Only Mode**: Create VPCs with only public subnets

### 📊 **Output Management**
- **Comprehensive Outputs**: All VPC information saved to organized files
- **JSON Outputs**: Machine-readable outputs for automation
- **Summary Reports**: Human-readable summary with next steps
- **CloudFormation Templates**: Reusable templates for future deployments

## Prerequisites

- AWS CLI installed and configured
- Appropriate AWS permissions for VPC, EC2, and CloudFormation
- `jq` command-line tool for JSON processing

## Installation

```bash
# Make the script executable
chmod +x create-vpc.sh

# Verify AWS credentials
aws sts get-caller-identity
```

## Usage

### Basic Usage

```bash
# Create a VPC with default settings (3 AZs, 10.0.0.0/16)
./create-vpc.sh --cluster-name my-cluster

# Create a VPC with custom CIDR and 2 AZs
./create-vpc.sh \
  --cluster-name production-cluster \
  --vpc-cidr 172.16.0.0/16 \
  --availability-zone-count 2 \
  --region us-west-2
```

### Advanced Usage

```bash
# Create a shared VPC with specific zones
./create-vpc.sh \
  --cluster-name shared-cluster \
  --vpc-cidr 10.0.0.0/16 \
  --availability-zone-count 3 \
  --zones-list "us-east-1a,us-east-1b,us-east-1c" \
  --shared-vpc \
  --resource-share-principals "123456789012" \
  --output-dir ./vpc-output

# Create public-only VPC with custom subnet size
./create-vpc.sh \
  --cluster-name public-cluster \
  --public-only \
  --subnet-bits 10 \
  --dhcp-options \
  --output-dir ./public-vpc
```

## Command Line Options

| Option | Description | Default | Required |
|--------|-------------|---------|----------|
| `--region` | AWS region | `us-east-1` | No |
| `--vpc-cidr` | VPC CIDR block | `10.0.0.0/16` | No |
| `--cluster-name` | Cluster name for tagging | `my-cluster` | No |
| `--availability-zone-count` | Number of AZs (1-3) | `3` | No |
| `--subnet-bits` | Subnet size bits (5-13) | `12` | No |
| `--zones-list` | Comma-separated list of specific AZs | Auto-detected | No |
| `--public-only` | Create only public subnets | `false` | No |
| `--shared-vpc` | Enable shared VPC with resource sharing | `false` | No |
| `--resource-share-principals` | AWS account IDs for resource sharing | Empty | No |
| `--additional-subnets` | Create additional subnets in same AZ (0-1) | `0` | No |
| `--dhcp-options` | Create custom DHCP options with domain name | `false` | No |
| `--output-dir` | Directory to save outputs | `./vpc-output` | No |
| `--help` | Display help message | N/A | No |

## Output Files

The script creates the following files in the output directory:

### Core Files
- `vpc-template.yaml` - CloudFormation template used
- `vpc-params.json` - Parameters passed to CloudFormation
- `stack-output.json` - Full CloudFormation stack output
- `vpc-summary.txt` - Human-readable summary

### Resource IDs
- `vpc-id` - VPC ID
- `public-subnet-ids` - Comma-separated public subnet IDs
- `private-subnet-ids` - Comma-separated private subnet IDs
- `availability-zones` - Comma-separated availability zones
- `stack-name` - CloudFormation stack name

## Example Output

```
🚀 Starting VPC creation...
📋 Configuration:
   Region: us-east-1
   VPC CIDR: 10.0.0.0/16
   Cluster Name: my-cluster
   AZ Count: 3
   Subnet Bits: 12
   Zones: us-east-1a,us-east-1b,us-east-1c
   Public Only: no
   Shared VPC: no
   Output Dir: ./vpc-output

📝 Creating CloudFormation template...
📋 Creating parameters file...
🏗️  Creating VPC stack: my-cluster-vpc-1703123456
📍 Region: us-east-1
🌐 VPC CIDR: 10.0.0.0/16
🏢 Availability Zones: us-east-1a,us-east-1b,us-east-1c
🌍 Public Only: no
🤝 Shared VPC: no

⏳ Waiting for stack creation to complete...
📊 Getting stack outputs...

✅ VPC creation completed successfully!

📁 Output directory: ./vpc-output
🆔 VPC ID: vpc-0123456789abcdef0
🌐 Public Subnets: subnet-0123456789abcdef0,subnet-0123456789abcdef1,subnet-0123456789abcdef2
🔒 Private Subnets: subnet-0123456789abcdef3,subnet-0123456789abcdef4,subnet-0123456789abcdef5
📍 Availability Zones: us-east-1a,us-east-1b,us-east-1c

📋 Summary saved to: ./vpc-output/vpc-summary.txt

To delete the VPC stack:
aws cloudformation delete-stack --region us-east-1 --stack-name my-cluster-vpc-1703123456
```

## Use Cases

### 1. **OpenShift IPI Installation**
```bash
./create-vpc.sh \
  --cluster-name openshift-cluster \
  --availability-zone-count 3 \
  --output-dir ./openshift-vpc
```

### 2. **Development Environment**
```bash
./create-vpc.sh \
  --cluster-name dev-cluster \
  --availability-zone-count 1 \
  --public-only \
  --output-dir ./dev-vpc
```

### 3. **Shared Infrastructure**
```bash
./create-vpc.sh \
  --cluster-name shared-infra \
  --shared-vpc \
  --resource-share-principals "123456789012,987654321098" \
  --output-dir ./shared-vpc
```

### 4. **High Availability Setup**
```bash
./create-vpc.sh \
  --cluster-name ha-cluster \
  --availability-zone-count 3 \
  --subnet-bits 10 \
  --zones-list "us-east-1a,us-east-1b,us-east-1c" \
  --output-dir ./ha-vpc
```

## Cleanup

To delete the VPC and all associated resources:

```bash
# Get the stack name from the output
STACK_NAME=$(cat ./vpc-output/stack-name)
aws cloudformation delete-stack --region us-east-1 --stack-name $STACK_NAME
```

## Next Steps

After creating the VPC, the next steps depend on your deployment strategy:

### For Private Cluster Installation:
1. **Create Bastion Host**: `./create-bastion.sh --cluster-name my-cluster`
2. **Generate install-config.yaml**: `./deploy-openshift.sh --dry-run`
3. **Upload configuration to bastion host**
4. **Install cluster from bastion host**

### For External Cluster Installation:
1. **Deploy OpenShift Cluster**: `./deploy-openshift.sh --publish-strategy External`
2. **Optional: Create Bastion Host**: `./create-bastion.sh --cluster-name my-cluster`

See [OpenShift Deployment Guide](README-openshift-deployment.md) for detailed instructions.

## Comparison with Other Scripts

| Feature | This Script | CI Operator Script | Basic Automation |
|---------|-------------|-------------------|------------------|
| Multi-AZ Support | ✅ | ✅ | ❌ |
| Shared VPC | ✅ | ✅ | ❌ |
| S3 Endpoints | ✅ | ✅ | ❌ |
| DHCP Options | ✅ | ✅ | ❌ |
| Zone Selection | ✅ | ✅ | ❌ |
| Bastion Host | ❌ | ❌ | ✅ |
| Install Config | ❌ | ❌ | ✅ |
| CI Integration | ❌ | ✅ | ❌ |
| Error Handling | ✅ | ✅ | Basic |
| Output Management | ✅ | ✅ | Basic |

## Troubleshooting

### Common Issues

1. **AWS Credentials Not Configured**
   ```bash
   aws configure
   ```

2. **Insufficient Permissions**
   - Ensure your AWS user/role has permissions for VPC, EC2, and CloudFormation
   - For shared VPC, additional RAM permissions are required

3. **Region Not Available**
   - Check available regions: `aws ec2 describe-regions`
   - Verify AZ availability in your region

4. **CIDR Conflicts**
   - Ensure VPC CIDR doesn't conflict with existing VPCs
   - Use different CIDR ranges for multiple VPCs

### Debug Mode

To see detailed CloudFormation events:

```bash
# Get stack events
aws cloudformation describe-stack-events \
  --region us-east-1 \
  --stack-name my-cluster-vpc-1703123456
```

## Contributing

This script is designed to be modular and extensible. Key areas for enhancement:

- Additional VPC endpoints (EC2, ECS, etc.)
- Custom security groups
- Integration with other AWS services
- Support for IPv6
- Enhanced monitoring and logging

## License

This script is provided as-is for educational and operational purposes. Please ensure compliance with your organization's policies and AWS best practices. 