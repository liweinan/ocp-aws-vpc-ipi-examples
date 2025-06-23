# Bastion Host Creation Script

The `create-bastion.sh` script creates a bastion host for accessing private OpenShift clusters with pre-installed OpenShift tools.

## 📋 Workflow Order

**Important**: For private cluster installations, the correct workflow order is:

1. **Create VPC** (`create-vpc.sh`)
2. **Create Bastion Host** (`create-bastion.sh`) ← You are here
3. **Generate install-config.yaml** locally (`deploy-openshift.sh --dry-run`)
4. **Upload configuration to bastion host**
5. **Install cluster from bastion host**

This order ensures that the bastion host is available before you need to upload cluster configuration files.

## 🚀 Quick Start

```bash
# Make script executable
chmod +x create-bastion.sh

# Create bastion host with default settings
./create-bastion.sh --cluster-name my-cluster

# Create with custom configuration
./create-bastion.sh \
  --cluster-name production-cluster \
  --instance-type t3.small \
  --openshift-version 4.15.0

# Connect to bastion host (after creation)
./connect-bastion.sh --copy-kubeconfig --setup-environment
```

## 📋 Features

- **Multi-OS Support**: Amazon Linux 2023 (recommended) and RHCOS
- **Pre-installed Tools**: OpenShift CLI, installer, AWS CLI v2
- **Enhanced Security**: Proper security group configuration
- **IAM Integration**: Automatic role assignment
- **Environment Setup**: Ready-to-use OpenShift environment

## 🔧 Command Line Options

| Option | Description | Default | Required |
|--------|-------------|---------|----------|
| `--cluster-name` | Cluster name for tagging | `my-cluster` | Yes |
| `--vpc-output-dir` | Directory containing VPC output | `./vpc-output` | No |
| `--instance-type` | Bastion instance type | `t3.large` | No |
| `--ssh-key-name` | SSH key pair name | `{cluster-name}-bastion-key` | No |
| `--openshift-version` | OpenShift version to install | `latest` | No |
| `--use-rhcos` | Use RHCOS instead of Amazon Linux | `no` | No |
| `--output-dir` | Directory to save bastion info | `./bastion-output` | No |
| `--region` | AWS region | `us-east-1` | No |
| `--help` | Display help message | N/A | No |

## 📊 Example Output

```
🏗️  Bastion Host Creation Script
================================

📋 Configuration:
   Cluster Name: my-cluster
   VPC Output Dir: ./vpc-output
   Instance Type: t3.large
   SSH Key Name: my-cluster-bastion-key
   OpenShift Version: latest
   Use RHCOS: no
   Output Dir: ./bastion-output
   Region: us-east-1

🔑 Creating SSH Key Pair
-------------------------
ℹ️  Creating SSH key pair: my-cluster-bastion-key
✅ SSH key pair created successfully

🛡️  Creating Security Group
-----------------------------
ℹ️  Creating security group: my-cluster-bastion-sg
✅ Security group created successfully

🖥️  Launching Bastion Instance
-------------------------------
ℹ️  Launching bastion instance...
ℹ️  Instance ID: i-1234567890abcdef0
ℹ️  Public IP: 52.23.45.67
ℹ️  Waiting for instance to be running...
✅ Bastion instance launched successfully

🛠️  Installing Tools
---------------------
ℹ️  Installing AWS CLI v2...
ℹ️  Installing OpenShift CLI...
ℹ️  Installing additional tools...
✅ Tools installation completed

📁 Saving Output Files
-----------------------
✅ Bastion instance ID saved to: ./bastion-output/bastion-instance-id
✅ Bastion public IP saved to: ./bastion-output/bastion-public-ip
✅ SSH key saved to: ./bastion-output/my-cluster-bastion-key.pem
✅ Summary saved to: ./bastion-output/bastion-summary.txt

🎉 Bastion host creation completed successfully!

📋 Summary:
   Instance ID: i-1234567890abcdef0
   Public IP: 52.23.45.67
   SSH Key: ./bastion-output/my-cluster-bastion-key.pem
   SSH Command: ssh -i ./bastion-output/my-cluster-bastion-key.pem ec2-user@52.23.45.67
```

## 🔐 Security Considerations

### Bastion Host Security
- Located in public subnet for access
- SSH access restricted by security group rules
- Pre-configured with necessary tools
- Temporary access solution

### SSH Access
```bash
# SSH to bastion host
ssh -i ./bastion-output/my-cluster-bastion-key.pem ec2-user@<bastion-public-ip>

# Default workspace
cd /home/ec2-user/openshift
```

## 🚀 Detailed Connection Guide

### Step 1: Set SSH Key Permissions
```bash
# Set proper permissions on the SSH key (required for SSH)
chmod 600 ./bastion-output/my-cluster-bastion-key.pem
```

### Step 2: Connect to Bastion Host
```bash
# SSH to the bastion host
ssh -i ./bastion-output/my-cluster-bastion-key.pem ec2-user@<bastion-public-ip>
```

### Step 3: Load OpenShift Environment
```bash
# Once connected to the bastion host, load the environment
source /home/ec2-user/openshift/env.sh
```

### Step 4: Copy OpenShift Configuration
```bash
# From your local machine, copy the kubeconfig to the bastion
scp -i ./bastion-output/my-cluster-bastion-key.pem \
  openshift-install/auth/kubeconfig \
  ec2-user@<bastion-public-ip>:~/openshift/
```

### Step 5: Access Your OpenShift Cluster
```bash
# On the bastion host, set up cluster access
export KUBECONFIG=~/openshift/kubeconfig

# Verify connection
oc get nodes
oc get clusteroperators
```

## 🛠️ Bastion Host Usage

### Initial Setup
```bash
# 1. Connect to bastion host
ssh -i ./bastion-output/my-cluster-bastion-key.pem ec2-user@<bastion-public-ip>

# 2. Load environment
source /home/ec2-user/openshift/env.sh

# 3. Check available tools
which oc
which kubectl
which openshift-install
which aws

# 4. View welcome message
cat /home/ec2-user/welcome.txt
```

### Cluster Management Commands
```bash
# Check cluster status
oc get nodes
oc get clusteroperators
oc get clusterversion

# View cluster information
oc cluster-info
oc whoami --show-console

# List projects and resources
oc get projects
oc get pods --all-namespaces

# Check AWS resources
aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/*,Values=owned"
```

### Troubleshooting Commands
```bash
# Check cluster events
oc get events --all-namespaces

# View node logs
oc adm node-logs --help
oc adm node-logs <node-name>

# Check cluster operators
oc get clusteroperators -o yaml

# Monitor cluster health
oc get clusterversion -o yaml
```

### File Transfer
```bash
# Copy files from local machine to bastion
scp -i ./bastion-output/my-cluster-bastion-key.pem \
  <local-file> \
  ec2-user@<bastion-public-ip>:~/openshift/

# Copy files from bastion to local machine
scp -i ./bastion-output/my-cluster-bastion-key.pem \
  ec2-user@<bastion-public-ip>:~/openshift/<file> \
  ./
```

## 🔧 Maintenance

### System Updates
```bash
sudo yum update -y
```

### Tool Updates
```bash
# Update OpenShift CLI
sudo curl -O https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz
sudo tar xvf openshift-client-linux.tar.gz -C /usr/local/bin
```

### Monitoring
```bash
# Check system resources
top
df -h

# Check OpenShift status
oc get clusterversion
oc get clusteroperators
```

## 🆘 Troubleshooting

### Common Issues

1. **Instance Launch Fails**
   ```bash
   # Check VPC and subnet configuration
   aws ec2 describe-vpcs --vpc-ids vpc-0123456789abcdef0
   aws ec2 describe-subnets --subnet-ids subnet-0123456789abcdef0
   ```

2. **SSH Connection Fails**
   ```bash
   # Check security group rules
   aws ec2 describe-security-groups --group-ids sg-0123456789abcdef0
   
   # Check instance status
   aws ec2 describe-instances --instance-ids i-1234567890abcdef0
   ```

3. **Tool Installation Fails**
   ```bash
   # SSH to instance and check logs
   ssh -i ./bastion-output/my-cluster-bastion-key.pem ec2-user@<bastion-public-ip>
   sudo journalctl -u cloud-init
   ```

## 💰 Cost Optimization

- Use `t3.large` for development environments (recommended)
- Use `t3.xlarge` for production workloads
- Consider using Spot instances for cost savings
- Terminate bastion when not in use

## 🔄 Cleanup

To delete the bastion host:

```bash
# Get instance ID
INSTANCE_ID=$(cat bastion-output/bastion-instance-id)

# Terminate instance
aws ec2 terminate-instances --instance-ids $INSTANCE_ID

# Delete SSH key pair
aws ec2 delete-key-pair --key-name my-cluster-bastion-key

# Clean up local files
rm -rf bastion-output
```

## 📚 Related Documentation

- [OpenShift Documentation](https://docs.openshift.com/)
- [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)
- [Amazon Linux 2023](https://docs.aws.amazon.com/linux/al2023/ug/)
- [RHCOS Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-customizations.html)

## 🔗 Automated Connection

For easy bastion host connection, use the `connect-bastion.sh` script:

```bash
# Basic connection
./connect-bastion.sh

# Connect and copy kubeconfig automatically
./connect-bastion.sh --copy-kubeconfig

# Connect and setup OpenShift environment
./connect-bastion.sh --setup-environment

# Full automation
./connect-bastion.sh --copy-kubeconfig --setup-environment
```

See [Bastion Connection Guide](README-connect-bastion.md) for detailed usage.

## 💡 Performance Recommendations

### Instance Type Selection
- Use `t3.large` for development environments (recommended)
- Use `t3.xlarge` for production workloads
- Use `t3.2xlarge` for heavy cluster management tasks 