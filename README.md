# AWS VPC IPI Configuration for OpenShift

This directory contains configuration files and automation scripts for setting up a custom VPC environment for OpenShift installation using the IPI (Installer Provisioned Infrastructure) method.

## 🚀 Quick Start

### Prerequisites
- AWS CLI installed and configured
- Red Hat pull secret (get from [Red Hat Console](https://console.redhat.com/openshift/install/pull-secret))
- SSH public key
- `jq` command-line tool

### Basic Workflow

```bash
# 1. Create VPC infrastructure
./create-vpc.sh --cluster-name my-cluster --region us-east-1

# 2. Create bastion host (for private clusters)
./create-bastion.sh --cluster-name my-cluster

# 3. Deploy OpenShift cluster
./deploy-openshift.sh \
  --cluster-name my-cluster \
  --base-domain example.com \
  --pull-secret "$(cat pull-secret.json)" \
  --ssh-key "$(cat ~/.ssh/id_rsa.pub)"
```

### Private Cluster Installation

For private cluster installation (Internal publish strategy), see the detailed guide:
**[Private Cluster Installation Guide](README-private-cluster-installation.md)**

This guide covers:
- Local `install-config.yaml` generation
- Bastion host setup and connection
- Cluster installation from bastion host
- Post-installation access and verification

**Note**: For private clusters, the installation process is:
1. Create VPC
2. Create bastion host
3. Generate `install-config.yaml` locally
4. Upload configuration to bastion host
5. Install cluster from bastion host

## 📋 Script Overview

| Script | Purpose | Documentation |
|--------|---------|---------------|
| `create-vpc.sh` | Creates production-ready VPC with multi-AZ support | [VPC Creation Guide](README-create-vpc.md) |
| `deploy-openshift.sh` | Deploys OpenShift cluster using VPC infrastructure | [OpenShift Deployment Guide](README-openshift-deployment.md) |
| `create-bastion.sh` | Creates bastion host for private cluster access | [Bastion Host Guide](README-bastion.md) |
| `connect-bastion.sh` | Automates bastion host connection and setup | [Bastion Connection Guide](README-connect-bastion.md) |
| `delete-cluster.sh` | Safely deletes OpenShift clusters with resource scanning | [Cluster Deletion Guide](README-delete-cluster.md) |
| `delete-vpc.sh` | Complete VPC deletion with OpenShift cluster | [Complete Deletion Guide](README-delete-vpc.md) |
| `delete-vpc-by-name.sh` | Delete VPC by name (when output directory is lost) | [Delete by Name Guide](README-delete-by-name.md) |
| `delete-vpc-cloudformation.sh` | Delete VPC using CloudFormation stack | [CloudFormation Deletion Guide](README-delete-cloudformation.md) |
| `delete-vpc-by-owner.sh` | Batch delete multiple VPCs by AWS account | [Delete by Owner Guide](README-delete-by-owner.md) |
| `cleanup.sh` | Clean up local files and optional AWS resources | [Cleanup Guide](README-cleanup.md) |
| `backup.sh` | Create compressed backups of project files | [Backup Guide](README-backup.md) |

## 🗑️ Deletion Options

When you need to delete VPCs and related resources, we provide multiple deletion scripts for different scenarios:

### Quick Deletion Guide
For the most common deletion scenarios, see [Quick Delete Guide](QUICK-DELETE.md).

### Deletion Script Selection

| Scenario | Recommended Script | When to Use |
|----------|-------------------|-------------|
| Delete OpenShift cluster only | `delete-cluster.sh` | Safe cluster deletion with resource scanning |
| Complete output directory available | `delete-vpc.sh` | Most comprehensive deletion process |
| Lost vpc-output directory | `delete-vpc-by-name.sh` | Only need VPC name |
| Know CloudFormation stack name | `delete-vpc-cloudformation.sh` | Most secure, ensures complete deletion |
| Batch delete multiple VPCs | `delete-vpc-by-owner.sh` | Bulk operations, high efficiency |

### Complete Cleanup Workflow

```bash
# 1. Delete OpenShift cluster (recommended first step)
./delete-cluster.sh --dry-run                    # Preview what will be deleted
./delete-cluster.sh                              # Delete the cluster

# 2. Delete VPC infrastructure
./delete-vpc.sh                                  # Delete VPC and remaining resources

# 3. Clean up local files
./cleanup.sh                                     # Remove local files and directories
```

## 🧹 Maintenance Tools

- **`cleanup.sh`** - Clean local files and optional AWS resources
- **`backup.sh`** - Create compressed backups with various options

## 📁 Directory Structure

After running the scripts, you'll have:

```
.
├── vpc-output/                 # VPC creation output
│   ├── vpc-id
│   ├── private-subnet-ids
│   ├── public-subnet-ids
│   └── ...
├── openshift-install/          # OpenShift installation
│   ├── install-config.yaml
│   ├── auth/
│   └── ...
└── bastion-output/             # Bastion host output
    ├── bastion-instance-id
    ├── bastion-public-ip
    └── ...
```

## ⚠️ Important Notes

- **Amazon Linux 2023**: Recommended for bastion hosts with OpenShift 4.18+ due to glibc compatibility
- **Private Clusters**: Default configuration creates private clusters accessible only through bastion host
- **Multi-AZ**: Enhanced VPC creation supports multi-AZ deployment for high availability
- **Security**: All resources are tagged with appropriate OpenShift cluster tags
- **Backup**: Always back up the generated `install-config.yaml` as it will be consumed by the installer

## 🔗 Related Documentation

- [OpenShift Documentation](https://docs.openshift.com/)
- [AWS VPC Documentation](https://docs.aws.amazon.com/vpc/)
- [OpenShift IPI Installation](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-default.html)
- [Red Hat Pull Secret](https://console.redhat.com/openshift/install/pull-secret)

## 🤝 Contributing

This project is designed to be modular and extensible. Key areas for enhancement:
- Additional network configurations
- Custom security group rules
- Integration with other AWS services
- Support for different OpenShift versions
- Enhanced monitoring and logging

## 📄 License

This project is provided as-is for educational and operational purposes. Please ensure compliance with your organization's policies and AWS best practices. 