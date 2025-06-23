# OpenShift Deployment Workflow

A complete workflow for deploying OpenShift clusters on AWS using the enhanced VPC infrastructure. This guide covers the entire process from VPC creation to OpenShift cluster deployment and bastion host setup.

## 📋 Overview

This workflow consists of three main scripts that work together:

1. **`create-vpc.sh`** - Creates a production-ready VPC with multi-AZ support
2. **`deploy-openshift.sh`** - Deploys OpenShift cluster using the VPC
3. **`create-bastion.sh`** - Creates a bastion host for cluster access

## 🚀 Quick Start

### Prerequisites

- AWS CLI installed and configured
- Red Hat pull secret (get from [Red Hat Console](https://console.redhat.com/openshift/install/pull-secret))
- SSH public key
- `jq` command-line tool
- `wget` for downloading OpenShift tools

### Step 1: Create VPC

```bash
# Create VPC with default settings
./create-vpc.sh --cluster-name my-openshift-cluster

# Or with custom configuration
./create-vpc.sh \
  --cluster-name production-cluster \
  --vpc-cidr 172.16.0.0/16 \
  --availability-zone-count 3 \
  --region us-west-2
```

### Step 2: Deploy OpenShift Cluster

```bash
# Deploy with default settings (uses vpc-output directory)
./deploy-openshift.sh \
  --cluster-name my-openshift-cluster \
  --base-domain example.com \
  --pull-secret "$(cat pull-secret.json)" \
  --ssh-key "$(cat ~/.ssh/id_rsa.pub)"

# Or with custom configuration
./deploy-openshift.sh \
  --cluster-name production-cluster \
  --base-domain mycompany.com \
  --pull-secret-file pull-secret.json \
  --ssh-key-file ~/.ssh/id_rsa.pub \
  --compute-nodes 5 \
  --control-plane-nodes 3 \
  --compute-instance-type m5.2xlarge \
  --control-plane-instance-type m5.xlarge \
  --publish-strategy External \
  --network-type OVNKubernetes
```

### Step 3: Create Bastion Host (Optional)

```bash
# Create bastion host with default settings
./create-bastion.sh --cluster-name my-openshift-cluster

# Or with custom configuration
./create-bastion.sh \
  --cluster-name production-cluster \
  --instance-type t3.small \
  --openshift-version 4.15.0
```

## 📁 Directory Structure

After running the scripts, you'll have the following structure:

```
.
├── vpc-output/                 # VPC creation output
│   ├── vpc-id
│   ├── private-subnet-ids
│   ├── public-subnet-ids
│   ├── availability-zones
│   ├── vpc-summary.txt
│   └── ...
├── openshift-install/          # OpenShift installation
│   ├── install-config.yaml
│   ├── openshift-install
│   ├── oc
│   ├── kubectl
│   ├── auth/
│   └── ...
└── bastion-output/             # Bastion host output
    ├── bastion-instance-id
    ├── bastion-public-ip
    ├── bastion-summary.txt
    └── ...
```

## 🔧 Detailed Usage

### VPC Creation (`create-vpc.sh`)

Creates a production-ready VPC with the following features:

- **Multi-AZ Support**: 1-3 availability zones
- **Public/Private Subnets**: Proper routing with NAT gateways
- **S3 VPC Endpoints**: For better performance
- **Resource Sharing**: Support for shared VPC across accounts
- **Comprehensive Outputs**: All VPC information saved to files

#### Key Options:

```bash
--region                    # AWS region (default: us-east-1)
--vpc-cidr                 # VPC CIDR block (default: 10.0.0.0/16)
--availability-zone-count  # Number of AZs (1-3, default: 3)
--subnet-bits              # Subnet size bits (5-13, default: 12)
--public-only              # Create only public subnets
--shared-vpc               # Enable shared VPC with resource sharing
--output-dir               # Directory to save outputs
```

### OpenShift Deployment (`deploy-openshift.sh`)

Deploys OpenShift cluster using the VPC infrastructure with version-compatible configuration:

- **Version Compatibility**: Generates install-config.yaml with proper OpenShift 4.x format
- **Automatic Tool Download**: Downloads OpenShift installer and CLI
- **VPC Integration**: Uses VPC output for configuration
- **Flexible Configuration**: Customizable node counts and instance types
- **Network Options**: Support for different network types and publish strategies
- **Dry Run Mode**: Generate config without installing
- **Automatic Backup**: Always creates backup of install-config.yaml

#### How It Works:

1. **Configuration Generation**: Creates install-config.yaml with proper OpenShift 4.x format
2. **VPC Integration**: Incorporates VPC information from create-vpc.sh output
3. **Tool Management**: Downloads OpenShift installer and CLI if not present
4. **Installation**: Runs openshift-install create cluster with generated config

#### Key Options:

```bash
--vpc-output-dir           # Directory containing VPC output
--cluster-name             # OpenShift cluster name
--base-domain              # Base domain for the cluster
--openshift-version        # OpenShift version to install
--pull-secret              # Red Hat pull secret
--ssh-key                  # SSH public key
--compute-nodes            # Number of compute nodes (default: 3)
--control-plane-nodes      # Number of control plane nodes (default: 3)
--compute-instance-type    # Compute node instance type
--control-plane-instance-type # Control plane instance type
--publish-strategy         # External or Internal (default: Internal)
--network-type             # OpenShiftSDN or OVNKubernetes
--dry-run                  # Generate config only, don't install
```

### Bastion Host Creation (`create-bastion.sh`)

Creates a bastion host for secure cluster access:

- **Pre-configured Tools**: OpenShift CLI, kubectl, AWS CLI
- **Security Group**: Proper SSH access configuration
- **SSH Key Management**: Automatic key pair creation
- **Environment Setup**: Ready-to-use OpenShift environment
- **Helpful Scripts**: Setup and access scripts included

#### Key Options:

```bash
--vpc-output-dir           # Directory containing VPC output
--cluster-name             # Cluster name for tagging
--instance-type            # Bastion instance type (default: t3.micro)
--ssh-key-name             # SSH key pair name
--openshift-version        # OpenShift version to install on bastion
--output-dir               # Directory to save bastion info
```

## 🎯 Use Cases

### Development Environment

```bash
# Quick development setup
./create-vpc.sh --cluster-name dev-cluster --availability-zone-count 1
./deploy-openshift.sh \
  --cluster-name dev-cluster \
  --base-domain dev.example.com \
  --pull-secret "$(cat pull-secret.json)" \
  --ssh-key "$(cat ~/.ssh/id_rsa.pub)" \
  --compute-nodes 1 \
  --control-plane-nodes 1 \
  --compute-instance-type m5.large
```

### Production Environment

```bash
# Production setup with high availability
./create-vpc.sh \
  --cluster-name prod-cluster \
  --availability-zone-count 3 \
  --vpc-cidr 172.16.0.0/16 \
  --region us-west-2

./deploy-openshift.sh \
  --cluster-name prod-cluster \
  --base-domain mycompany.com \
  --pull-secret-file pull-secret.json \
  --ssh-key-file ~/.ssh/id_rsa.pub \
  --compute-nodes 5 \
  --control-plane-nodes 3 \
  --compute-instance-type m5.2xlarge \
  --control-plane-instance-type m5.xlarge \
  --publish-strategy External \
  --network-type OVNKubernetes

./create-bastion.sh \
  --cluster-name prod-cluster \
  --instance-type t3.small
```

### Shared Infrastructure

```bash
# Shared VPC setup
./create-vpc.sh \
  --cluster-name shared-cluster \
  --shared-vpc \
  --resource-share-principals "123456789012,987654321098" \
  --availability-zone-count 3

./deploy-openshift.sh \
  --cluster-name shared-cluster \
  --base-domain shared.example.com \
  --pull-secret "$(cat pull-secret.json)" \
  --ssh-key "$(cat ~/.ssh/id_rsa.pub)"
```

## 🔐 Security Considerations

### VPC Security
- Private subnets for worker nodes
- NAT gateways for outbound internet access
- S3 VPC endpoints for better performance
- Proper security group configurations

### Bastion Host Security
- Located in public subnet for access
- SSH access restricted to specific IPs (configurable)
- Pre-configured with necessary tools
- Temporary access solution

### OpenShift Security
- Internal publish strategy by default
- Proper RBAC configuration
- Secure cluster communication
- Encrypted storage and networking

## 📊 Cost Optimization

### Development
- Use single AZ for development
- Smaller instance types (m5.large)
- Fewer compute nodes (1-2)
- Internal publish strategy

### Production
- Multi-AZ for high availability
- Larger instance types for performance
- More compute nodes for scalability
- External publish strategy if needed

### Cost Monitoring
```bash
# Check AWS costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost

# List OpenShift resources
aws ec2 describe-instances \
  --filters "Name=tag:kubernetes.io/cluster/*,Values=owned"
```

## 🛠️ Troubleshooting

### Common Issues

1. **VPC Creation Fails**
   ```bash
   # Check AWS credentials
   aws sts get-caller-identity
   
   # Check CloudFormation events
   aws cloudformation describe-stack-events \
     --stack-name my-cluster-vpc-1234567890
   ```

2. **OpenShift Installation Fails**
   ```bash
   # Check installer logs
   tail -f openshift-install/.openshift_install.log
   
   # Validate install-config.yaml
   ./openshift-install create manifests --dir=.
   
   # Check version compatibility
   ./openshift-install version
   ```

3. **Configuration Compatibility Issues**
   ```bash
   # The script generates install-config.yaml with proper OpenShift 4.x format
   # If you encounter version-specific issues:
   
   # Check the generated install-config.yaml
   cat install-config.yaml
   
   # Validate the configuration
   ./openshift-install create manifests --dir=.
   
   # Check OpenShift version compatibility
   ./openshift-install version
   ```

4. **Bastion Host Issues**
   ```bash
   # Check instance status
   aws ec2 describe-instances --instance-ids i-1234567890abcdef0
   
   # Check security group
   aws ec2 describe-security-groups --group-ids sg-1234567890abcdef0
   ```

### Version Compatibility

The script now uses `openshift-install create install-config` to ensure compatibility with different OpenShift versions:

- **Automatic Version Detection**: The installer generates configuration compatible with the specified version
- **VPC Integration**: After generating the base config, the script updates it with VPC information
- **Backup Protection**: Always creates a backup before modifying the configuration

### Debug Mode

```bash
# VPC creation with verbose output
./create-vpc.sh --output-dir ./debug-vpc

# OpenShift deployment with dry run
./deploy-openshift.sh \
  --dry-run \
  --pull-secret "$(cat pull-secret.json)" \
  --ssh-key "$(cat ~/.ssh/id_rsa.pub)"

# Check the generated configuration
cat openshift-install/install-config.yaml
```

## 🧹 Cleanup

### Destroy OpenShift Cluster
```bash
cd openshift-install
./openshift-install destroy cluster
```

### Terminate Bastion Host
```bash
# Get instance ID
INSTANCE_ID=$(cat bastion-output/bastion-instance-id)

# Terminate instance
aws ec2 terminate-instances --instance-ids $INSTANCE_ID
```

### Delete VPC Stack
```bash
# Get stack name
STACK_NAME=$(cat vpc-output/stack-name)

# Delete stack
aws cloudformation delete-stack --stack-name $STACK_NAME
```

## 📚 Additional Resources

- [OpenShift Documentation](https://docs.openshift.com/)
- [AWS VPC Documentation](https://docs.aws.amazon.com/vpc/)
- [OpenShift IPI Installation](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-default.html)
- [Red Hat Pull Secret](https://console.redhat.com/openshift/install/pull-secret)

## 🤝 Contributing

This workflow is designed to be modular and extensible. Key areas for enhancement:

- Additional network configurations
- Custom security group rules
- Integration with other AWS services
- Support for different OpenShift versions
- Enhanced monitoring and logging

## 📄 License

This workflow is provided as-is for educational and operational purposes. Please ensure compliance with your organization's policies and AWS best practices. 