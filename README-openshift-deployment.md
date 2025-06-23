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

- **Version Compatibility**: Uses `openshift-install create install-config` for guaranteed compatibility
- **Manual Configuration**: User manually completes interactive installer prompts
- **Automatic VPC Integration**: Script automatically patches VPC, subnets, and region settings
- **Automatic Tool Download**: Downloads OpenShift installer and CLI if needed
- **Flexible Configuration**: Customizable node counts and instance types
- **Network Options**: Support for different network types and publish strategies
- **Dry Run Mode**: Generate config without installing
- **Automatic Backup**: Always creates backup of install-config.yaml

#### Prerequisites:

The script requires the following tools to be installed:

| Tool | Purpose | Installation |
|------|---------|--------------|
| `yq` | YAML file manipulation | `brew install yq` (macOS)<br>`apt-get install yq` (Ubuntu)<br>[Download](https://github.com/mikefarah/yq) |
| `wget` | Download OpenShift installer | `brew install wget` (macOS)<br>`apt-get install wget` (Ubuntu) |
| `tar` | Extract OpenShift installer | Usually pre-installed |
| `aws` | AWS CLI for credentials | `brew install awscli` (macOS)<br>`apt-get install awscli` (Ubuntu) |
| `openshift-install` | OpenShift installer | Downloaded automatically by script |

**Quick Installation (macOS):**
```bash
brew install yq wget awscli
```

**Quick Installation (Ubuntu/Debian):**
```bash
sudo apt-get update
sudo apt-get install yq wget awscli
```

#### Benefits of This Approach:

- **Guaranteed Compatibility**: Uses official `openshift-install create install-config` for perfect version compatibility
- **User Control**: You have full control over the initial configuration process
- **Automatic VPC Integration**: Script handles the complex VPC patching automatically
- **No Automation Complexity**: Avoids issues with expect scripts or automated input
- **Reliable**: Works consistently across different OpenShift versions and environments
- **Transparent**: You can see exactly what configuration is being applied

#### How It Works:

1. **Manual Configuration**: User manually completes `openshift-install create install-config` interactive prompts
2. **VPC Integration**: Script automatically patches the generated config with VPC information from `create-vpc.sh` output
3. **Tool Management**: Downloads OpenShift installer and CLI if not present
4. **Installation**: Runs `openshift-install create cluster` with the patched configuration

#### Interactive Configuration Process:

When you run the script, it will guide you through the manual configuration:

```bash
🔧 Please manually complete the openshift-install create install-config process...
   The installer will prompt you for:
   - SSH Public Key
   - Platform (select: aws)
   - Region (use: us-east-1)
   - Base Domain (use: qe.devcluster.openshift.com)
   - Cluster Name (use: weli-test-cluster)
   - Pull Secret
```

**Recommended values for each prompt:**
- **SSH Public Key**: Your SSH public key for cluster access
- **Platform**: Select `aws`
- **Region**: Use the region from your VPC (shown in script output)
- **Base Domain**: Your base domain for the cluster
- **Cluster Name**: Your desired cluster name
- **Pull Secret**: Your Red Hat pull secret JSON content

#### Key Options:

| Option | Description | Default |
|--------|-------------|---------|
| `--vpc-output-dir` | Directory containing VPC output files | `./vpc-output` |
| `--openshift-version` | OpenShift version to install | `4.18.15` |
| `--install-dir` | Installation directory | `./openshift-install` |
| `--publish-strategy` | Publish strategy: External or Internal | `Internal` |
| `--dry-run` | Generate config only, don't install | `false` |

**Note:** Cluster name, base domain, SSH key, and pull secret are entered manually during the interactive `openshift-install create install-config` process.

#### Usage Examples:

```bash
# Basic deployment with default settings
./deploy-openshift.sh --dry-run

# Custom OpenShift version and publish strategy
./deploy-openshift.sh \
  --openshift-version 4.17.0 \
  --publish-strategy External \
  --dry-run

# Custom installation directory
./deploy-openshift.sh \
  --install-dir ./my-cluster \
  --dry-run

# Production deployment (without --dry-run)
./deploy-openshift.sh \
  --openshift-version 4.18.15 \
  --publish-strategy External
```

**During the interactive process, you'll be prompted for:**
- SSH Public Key
- Platform (select: aws)
- Region (use the one shown in script output)
- Base Domain
- Cluster Name
- Pull Secret

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

1. **Missing Required Tools**
   ```bash
   # If you see "Required tools not found" error:
   
   # Check what's missing
   which yq wget tar aws
   
   # Install missing tools (macOS)
   brew install yq wget awscli
   
   # Install missing tools (Ubuntu)
   sudo apt-get update
   sudo apt-get install yq wget awscli
   ```

2. **VPC Creation Fails**
   ```bash
   # Check AWS credentials
   aws sts get-caller-identity
   
   # Check CloudFormation events
   aws cloudformation describe-stack-events \
     --stack-name my-cluster-vpc-1234567890
   ```

3. **OpenShift Installation Fails**
   ```bash
   # Check installer logs
   tail -f openshift-install/.openshift_install.log
   
   # Validate install-config.yaml
   ./openshift-install create manifests --dir=.
   
   # Check version compatibility
   ./openshift-install version
   ```

4. **Configuration Compatibility Issues**
   ```bash
   # The script uses openshift-install create install-config for guaranteed compatibility
   # If you encounter issues during manual configuration:
   
   # Check the generated install-config.yaml
   cat install-config.yaml
   
   # Validate the configuration
   ./openshift-install create manifests --dir=.
   
   # Check OpenShift version compatibility
   ./openshift-install version
   
   # If VPC patching failed, check the backup file
   ls -la install-config.yaml.backup.*
   ```

5. **YAML Patching Issues**
   ```bash
   # If yq fails to patch the install-config.yaml:
   
   # Check yq version
   yq --version
   
   # Verify the YAML file is valid
   yq eval '.' install-config.yaml
   
   # Check if the file exists and is readable
   ls -la install-config.yaml
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
./deploy-openshift.sh --dry-run

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