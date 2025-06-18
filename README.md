# AWS VPC IPI Configuration for OpenShift

This directory contains the configuration files needed to set up a custom VPC environment for OpenShift installation using the IPI (Installer Provisioned Infrastructure) method.

## Configuration Files

1. `aws-provision-vpc-shared.yaml`
   - Creates a shared VPC with public and private subnets
   - Configures DNS settings and necessary tags
   - Customizable CIDR blocks for VPC and subnets

2. `aws-provision-security-group.yaml`
   - Defines security groups for control plane and worker nodes
   - Sets up internal cluster communication rules
   - Configures necessary inbound/outbound rules

3. `aws-provision-bastionhost.yaml`
   - Provisions a bastion host in the public subnet
   - Installs necessary tools (aws-cli, openshift-client)
   - Configures SSH access

4. `ipi-conf-aws.yaml`
   - Main IPI installation configuration
   - Defines cluster architecture and networking
   - Configures AWS-specific settings

5. `aws-provision-iam-user-minimal-permission.yaml`
   - Creates IAM user with minimal required permissions
   - Sets up region-specific access
   - Implements resource tagging restrictions

## Usage

1. VPC Provisioning:
   ```bash
   oc process -f aws-provision-vpc-shared.yaml \
     -p vpc_name=my-vpc \
     -p region=us-east-1 | oc apply -f -
   ```

2. Security Group Setup:
   ```bash
   oc process -f aws-provision-security-group.yaml \
     -p vpc_name=my-vpc \
     -p cluster_name=my-cluster | oc apply -f -
   ```

3. Bastion Host Creation:
   ```bash
   oc process -f aws-provision-bastionhost.yaml \
     -p vpc_name=my-vpc \
     -p key_name=my-key | oc apply -f -
   ```

4. IPI Configuration:
   ```bash
   oc process -f ipi-conf-aws.yaml \
     -p cluster_name=my-cluster \
     -p base_domain=example.com \
     -p vpc_id=vpc-xxx \
     -p private_subnet_id=subnet-xxx \
     -p public_subnet_id=subnet-yyy | oc apply -f -
   ```

5. IAM User Setup:
   ```bash
   oc process -f aws-provision-iam-user-minimal-permission.yaml \
     -p cluster_name=my-cluster \
     -p region=us-east-1 | oc apply -f -
   ```

## Prerequisites

- AWS CLI configured with appropriate credentials
- OpenShift CLI (oc) installed
- Necessary AWS permissions to create resources
- Valid AWS key pair for bastion host access

## Notes

- All resources will be tagged with appropriate OpenShift cluster tags
- Security groups are configured with minimal required access
- The VPC is set up with both public and private subnets for proper cluster operation
- IAM permissions are scoped to specific regions and resources for security 