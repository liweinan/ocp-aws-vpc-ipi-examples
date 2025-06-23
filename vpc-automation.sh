#!/bin/bash

# VPC Automation Script for OpenShift IPI Installation
# This script automates the creation of VPC and generates install-config.yaml

set -euo pipefail

# Default values
DEFAULT_REGION="us-east-1"
DEFAULT_VPC_CIDR="10.0.0.0/16"
DEFAULT_CLUSTER_NAME="my-cluster"
DEFAULT_BASE_DOMAIN="example.com"
DEFAULT_PRIVATE_SUBNETS=3
DEFAULT_INSTANCE_TYPE="t3.large"
DEFAULT_AMI_OWNER="amazon"
DEFAULT_AMI_NAME="amzn2-ami-hvm-*-x86_64-gp2"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --region           AWS region (default: $DEFAULT_REGION)"
    echo "  --vpc-cidr        VPC CIDR block (default: $DEFAULT_VPC_CIDR)"
    echo "  --cluster-name    OpenShift cluster name (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --base-domain     Base domain for the cluster (default: $DEFAULT_BASE_DOMAIN)"
    echo "  --private-subnets Number of private subnets (default: $DEFAULT_PRIVATE_SUBNETS)"
    echo "  --pull-secret     Red Hat pull secret (as string)"
    echo "  --pull-secret-file Path to file containing Red Hat pull secret"
    echo "  --ssh-key         SSH public key (as string)"
    echo "  --ssh-key-file    Path to SSH public key file"
    echo "  --instance-type   Bastion instance type (default: $DEFAULT_INSTANCE_TYPE)"
    echo "  --help            Display this help message"
    exit 1
}

# Function to read file contents
read_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "Error: File not found: $file"
        exit 1
    fi
    cat "$file"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            REGION="$2"
            shift 2
            ;;
        --vpc-cidr)
            VPC_CIDR="$2"
            shift 2
            ;;
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --base-domain)
            BASE_DOMAIN="$2"
            shift 2
            ;;
        --private-subnets)
            PRIVATE_SUBNETS="$2"
            shift 2
            ;;
        --pull-secret)
            PULL_SECRET="$2"
            shift 2
            ;;
        --pull-secret-file)
            PULL_SECRET=$(read_file "$2")
            shift 2
            ;;
        --ssh-key)
            SSH_KEY="$2"
            shift 2
            ;;
        --ssh-key-file)
            SSH_KEY=$(read_file "$2")
            shift 2
            ;;
        --instance-type)
            INSTANCE_TYPE="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Set default values if not provided
REGION=${REGION:-$DEFAULT_REGION}
VPC_CIDR=${VPC_CIDR:-$DEFAULT_VPC_CIDR}
CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
BASE_DOMAIN=${BASE_DOMAIN:-$DEFAULT_BASE_DOMAIN}
PRIVATE_SUBNETS=${PRIVATE_SUBNETS:-$DEFAULT_PRIVATE_SUBNETS}
INSTANCE_TYPE=${INSTANCE_TYPE:-$DEFAULT_INSTANCE_TYPE}

# Validate required parameters
if [[ -z "${PULL_SECRET:-}" ]]; then
    echo "Error: Pull secret is required. Use --pull-secret or --pull-secret-file"
    exit 1
fi

if [[ -z "${SSH_KEY:-}" ]]; then
    echo "Error: SSH key is required. Use --ssh-key or --ssh-key-file"
    exit 1
fi

# Validate AWS CLI and credentials
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed"
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    echo "Error: AWS credentials not configured"
    exit 1
fi

# Create VPC stack
echo "Creating VPC stack..."
STACK_NAME="${CLUSTER_NAME}-vpc"

# Calculate subnet CIDRs
IFS='/' read -r VPC_BASE VPC_BITS <<< "$VPC_CIDR"
IFS='.' read -r A B C D <<< "$VPC_BASE"

# Create CloudFormation template
cat > vpc-template.yaml <<EOF
AWSTemplateFormatVersion: '2010-09-09'
Description: VPC for OpenShift IPI Installation

Parameters:
  VpcCidr:
    Type: String
    Default: ${VPC_CIDR}
  ClusterName:
    Type: String
    Default: ${CLUSTER_NAME}

Resources:
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: !Ref VpcCidr
      EnableDnsHostnames: true
      EnableDnsSupport: true
      Tags:
        - Key: Name
          Value: !Sub \${ClusterName}-vpc

  InternetGateway:
    Type: AWS::EC2::InternetGateway
    Properties:
      Tags:
        - Key: Name
          Value: !Sub \${ClusterName}-igw

  AttachGateway:
    Type: AWS::EC2::VPCGatewayAttachment
    Properties:
      VpcId: !Ref VPC
      InternetGatewayId: !Ref InternetGateway

  PublicRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub \${ClusterName}-public-rt

  PublicRoute:
    Type: AWS::EC2::Route
    DependsOn: AttachGateway
    Properties:
      RouteTableId: !Ref PublicRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      GatewayId: !Ref InternetGateway

  NatGatewayEIP:
    Type: AWS::EC2::EIP
    DependsOn: AttachGateway
    Properties:
      Domain: vpc

  PublicSubnet:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: ${A}.${B}.0.0/24
      AvailabilityZone: !Select [0, !GetAZs ""]
      Tags:
        - Key: Name
          Value: !Sub \${ClusterName}-public-subnet

  NatGateway:
    Type: AWS::EC2::NatGateway
    Properties:
      AllocationId: !GetAtt NatGatewayEIP.AllocationId
      SubnetId: !Ref PublicSubnet

  PrivateRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub \${ClusterName}-private-rt

  PrivateRoute:
    Type: AWS::EC2::Route
    Properties:
      RouteTableId: !Ref PrivateRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      NatGatewayId: !Ref NatGateway
EOF

# Add private subnets dynamically
for i in $(seq 1 $PRIVATE_SUBNETS); do
    cat >> vpc-template.yaml <<EOF

  PrivateSubnet${i}:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: ${A}.${B}.${i}.0/24
      AvailabilityZone: !Select [$(($i-1)), !GetAZs ""]
      Tags:
        - Key: Name
          Value: !Sub \${ClusterName}-private-subnet-${i}

  PrivateSubnet${i}RouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PrivateSubnet${i}
      RouteTableId: !Ref PrivateRouteTable
EOF
done

# Add outputs section
cat >> vpc-template.yaml <<EOF

Outputs:
  VpcId:
    Description: VPC ID
    Value: !Ref VPC
  PublicSubnetId:
    Description: Public Subnet ID
    Value: !Ref PublicSubnet
EOF

# Add private subnet outputs
for i in $(seq 1 $PRIVATE_SUBNETS); do
    cat >> vpc-template.yaml <<EOF
  PrivateSubnet${i}Id:
    Description: Private Subnet ${i} ID
    Value: !Ref PrivateSubnet${i}
EOF
done

# Create VPC stack
echo "Creating VPC stack..."
aws cloudformation create-stack \
    --region "${REGION}" \
    --stack-name "${STACK_NAME}" \
    --template-body "file://vpc-template.yaml" \
    --parameters \
        ParameterKey=VpcCidr,ParameterValue="${VPC_CIDR}" \
        ParameterKey=ClusterName,ParameterValue="${CLUSTER_NAME}" \
    --capabilities CAPABILITY_IAM

echo "Waiting for stack creation to complete..."
aws cloudformation wait stack-create-complete \
    --region "${REGION}" \
    --stack-name "${STACK_NAME}"

# Get stack outputs
echo "Getting stack outputs..."
VPC_ID=$(aws cloudformation describe-stacks \
    --region "${REGION}" \
    --stack-name "${STACK_NAME}" \
    --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' \
    --output text)

PUBLIC_SUBNET=$(aws cloudformation describe-stacks \
    --region "${REGION}" \
    --stack-name "${STACK_NAME}" \
    --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnetId`].OutputValue' \
    --output text)

# Get private subnet IDs
PRIVATE_SUBNET_IDS=""
for i in $(seq 1 $PRIVATE_SUBNETS); do
    SUBNET_ID=$(aws cloudformation describe-stacks \
        --region "${REGION}" \
        --stack-name "${STACK_NAME}" \
        --query "Stacks[0].Outputs[?OutputKey==\`PrivateSubnet${i}Id\`].OutputValue" \
        --output text)
    PRIVATE_SUBNET_IDS="${PRIVATE_SUBNET_IDS}${SUBNET_ID},"
done
PRIVATE_SUBNET_IDS=${PRIVATE_SUBNET_IDS%,}

# Generate install-config.yaml
echo "Generating install-config.yaml..."
cat > install-config.yaml <<EOF
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform:
    aws:
      type: m5.xlarge
  replicas: 3
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      type: m5.xlarge
  replicas: 3
metadata:
  name: ${CLUSTER_NAME}
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: ${VPC_CIDR}
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: ${REGION}
    subnets:
EOF

# Add private subnet IDs to install-config.yaml
IFS=',' read -ra SUBNET_ARRAY <<< "$PRIVATE_SUBNET_IDS"
for subnet in "${SUBNET_ARRAY[@]}"; do
    echo "    - ${subnet}" >> install-config.yaml
done

echo "    vpc: ${VPC_ID}" >> install-config.yaml

cat >> install-config.yaml <<EOF
publish: Internal
pullSecret: '${PULL_SECRET}'
sshKey: |
  ${SSH_KEY}
EOF

echo "Setup complete!"
echo "VPC ID: ${VPC_ID}"
echo "Public Subnet: ${PUBLIC_SUBNET}"
echo "Private Subnets: ${PRIVATE_SUBNET_IDS}"
echo "install-config.yaml has been generated"
echo ""
echo "Next steps:"
echo "1. Review the generated install-config.yaml"
echo "2. Run 'openshift-install create cluster --dir=./' to start the cluster installation"

# After VPC and subnet creation, add bastion host creation

# Create bastion security group
echo "Creating bastion security group..."
BASTION_SG_NAME="${CLUSTER_NAME}-bastion-sg"

aws ec2 create-security-group \
    --group-name "${BASTION_SG_NAME}" \
    --description "Security group for bastion host" \
    --vpc-id "${VPC_ID}" \
    --region "${REGION}"

BASTION_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${BASTION_SG_NAME}" \
    --region "${REGION}" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

# Configure security group rules
aws ec2 authorize-security-group-ingress \
    --group-id "${BASTION_SG_ID}" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region "${REGION}"

# Get latest Amazon Linux 2 AMI
AMI_ID=$(aws ec2 describe-images \
    --owners "${DEFAULT_AMI_OWNER}" \
    --filters "Name=name,Values=${DEFAULT_AMI_NAME}" \
                "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --region "${REGION}" \
    --output text)

# Create bastion host user data script
cat > bastion-userdata.sh <<EOF
#!/bin/bash
# Update system
yum update -y

# Install required packages
yum install -y jq wget tar gzip

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Install OpenShift CLI (oc)
OC_VERSION="4.12.0"
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OC_VERSION}/openshift-client-linux.tar.gz
tar xvf openshift-client-linux.tar.gz -C /usr/local/bin
rm -f openshift-client-linux.tar.gz

# Install OpenShift Installer
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OC_VERSION}/openshift-install-linux.tar.gz
tar xvf openshift-install-linux.tar.gz -C /usr/local/bin
rm -f openshift-install-linux.tar.gz

# Set required permissions
chmod +x /usr/local/bin/oc
chmod +x /usr/local/bin/kubectl
chmod +x /usr/local/bin/openshift-install

# Create workspace directory
mkdir -p /home/ec2-user/openshift
chown ec2-user:ec2-user /home/ec2-user/openshift
EOF

# Launch bastion instance
echo "Launching bastion host..."
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "${AMI_ID}" \
    --instance-type "${INSTANCE_TYPE}" \
    --key-name "${CLUSTER_NAME}-key" \
    --security-group-ids "${BASTION_SG_ID}" \
    --subnet-id "${PUBLIC_SUBNET}" \
    --associate-public-ip-address \
    --user-data file://bastion-userdata.sh \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${CLUSTER_NAME}-bastion}]" \
    --region "${REGION}" \
    --query 'Instances[0].InstanceId' \
    --output text)

# Wait for instance to be running
echo "Waiting for bastion host to be ready..."
aws ec2 wait instance-running \
    --instance-ids "${INSTANCE_ID}" \
    --region "${REGION}"

# Get bastion public IP
BASTION_PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "${INSTANCE_ID}" \
    --region "${REGION}" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

# Create SSH key pair for bastion access
aws ec2 create-key-pair \
    --key-name "${CLUSTER_NAME}-key" \
    --query 'KeyMaterial' \
    --output text \
    --region "${REGION}" > "${CLUSTER_NAME}-key.pem"

chmod 400 "${CLUSTER_NAME}-key.pem"

echo "Bastion host is ready!"
echo "Bastion Public IP: ${BASTION_PUBLIC_IP}"
echo "SSH Key: ${CLUSTER_NAME}-key.pem"
echo ""
echo "To connect to the bastion host:"
echo "ssh -i ${CLUSTER_NAME}-key.pem ec2-user@${BASTION_PUBLIC_IP}" 