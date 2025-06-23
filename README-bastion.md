# Bastion Host Creation Script

The `create-bastion.sh` script creates a bastion host for accessing private OpenShift clusters with pre-installed OpenShift tools.

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
| `--instance-type` | Bastion instance type | `t3.micro` | No |
| `--ssh-key-name` | SSH key pair name | `{cluster-name}-bastion-key` | No |
| `--openshift-version` | OpenShift version to install | `4.15.0` | No |
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
   Instance Type: t3.micro
   SSH Key Name: my-cluster-bastion-key
   OpenShift Version: 4.15.0
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

## 🛠️ Bastion Host Usage

### 1. Initial Access
```bash
# Copy install-config.yaml to bastion
scp -i ./bastion-output/my-cluster-bastion-key.pem \
  install-config.yaml \
  ec2-user@<bastion-public-ip>:~/openshift/
```

### 2. Cluster Installation
```bash
# On bastion host
cd ~/openshift
openshift-install create cluster --dir=./
```

### 3. Cluster Management
```bash
# On bastion host
export KUBECONFIG=~/openshift/auth/kubeconfig
oc get nodes
oc get co
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

- Use `t3.micro` for development environments
- Use `t3.small` or `t3.medium` for production
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