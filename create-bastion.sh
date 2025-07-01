#!/bin/bash

# Bastion Host Creation Script
# Creates a bastion host in the VPC for OpenShift cluster access

set -euo pipefail

# Default values
DEFAULT_VPC_OUTPUT_DIR="./vpc-output"
DEFAULT_CLUSTER_NAME="my-cluster"
DEFAULT_INSTANCE_TYPE="t3.large"
DEFAULT_AMI_OWNER="amazon"
DEFAULT_AMI_NAME="amzn2-ami-hvm-*-x86_64-gp2"
DEFAULT_SSH_KEY_NAME=""
DEFAULT_OPENSHIFT_VERSION="latest"
DEFAULT_USE_RHCOS="no"
DEFAULT_CREATE_IAM_ROLE="no"
DEFAULT_ENHANCED_SECURITY="no"
DEFAULT_INTEGRATE_CONTROL_PLANE_SG="no"
DEFAULT_OUTPUT_DIR="./bastion-output"
DEFAULT_REGION="us-east-1"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --vpc-output-dir              Directory containing VPC output files (default: $DEFAULT_VPC_OUTPUT_DIR)"
    echo "  --cluster-name                Cluster name for tagging (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --instance-type               Bastion instance type (default: $DEFAULT_INSTANCE_TYPE)"
    echo "  --ssh-key-name                Name of existing SSH key pair (will create if not exists)"
    echo "  --openshift-version           OpenShift version to install on bastion (default: $DEFAULT_OPENSHIFT_VERSION)"
    echo "  --output-dir                  Directory to save bastion info (default: ./bastion-output)"
    echo "  --use-rhcos                   Use RHCOS AMI instead of Amazon Linux 2 (default: $DEFAULT_USE_RHCOS)"
    echo "  --create-iam-role             Create IAM role for bastion (default: $DEFAULT_CREATE_IAM_ROLE)"
    echo "  --enhanced-security           Enable enhanced security group with proxy ports (default: $DEFAULT_ENHANCED_SECURITY)"
    echo "  --integrate-control-plane-sg  Integrate with existing control plane security group"
    echo "  --help                        Display this help message"
    exit 1
}

# Function to validate VPC output
validate_vpc_output() {
    local vpc_dir="$1"
    
    required_files=("vpc-id" "public-subnet-ids" "availability-zones" "vpc-summary.txt")
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$vpc_dir/$file" ]]; then
            echo "Error: Required VPC output file not found: $vpc_dir/$file"
            echo "Please run create-vpc.sh first to generate VPC output"
            exit 1
        fi
    done
}

# Function to get AWS region from VPC output
get_region_from_vpc() {
    local vpc_dir="$1"
    local summary_file="$vpc_dir/vpc-summary.txt"
    
    if [[ -f "$summary_file" ]]; then
        grep "^Region:" "$summary_file" | awk '{print $2}'
    else
        echo "us-east-1"  # fallback
    fi
}

# Function to create SSH key pair
create_ssh_key_pair() {
    local key_name="$1"
    local region="$2"
    local output_dir="$3"
    
    echo "🔑 Creating SSH key pair: $key_name"
    
    # Check if key already exists
    if $AWS_CMD ec2 describe-key-pairs --key-names "$key_name" --region "$region" &> /dev/null; then
        echo "❌ Error: SSH key pair '$key_name' already exists in AWS"
        echo ""
        echo "This prevents the script from creating a usable bastion host because:"
        echo "1. The private key (.pem file) cannot be downloaded again from AWS"
        echo "2. Without the private key, you cannot SSH to the bastion host"
        echo ""
        echo "To fix this, you have two options:"
        echo ""
        echo "Option 1: Delete the existing key pair from AWS"
        echo "   $AWS_CMD ec2 delete-key-pair --key-name '$key_name' --region '$region'"
        echo ""
        echo "Option 2: Use a different key name"
        echo "   ./create-bastion.sh --cluster-name $CLUSTER_NAME --ssh-key-name '${key_name}-new'"
        echo ""
        echo "After fixing, run this script again."
        exit 1
    fi
    
    # Create new key pair
    $AWS_CMD ec2 create-key-pair \
        --key-name "$key_name" \
        --query 'KeyMaterial' \
        --output text \
        --region "$region" > "$output_dir/$key_name.pem"
    
    chmod 400 "$output_dir/$key_name.pem"
    echo "✅ SSH key pair created: $output_dir/$key_name.pem"
}

# Function to get RHCOS AMI for the region
get_rhcos_ami() {
    local region="$1"
    local openshift_version="$2"
    
    # Extract major.minor version for RHCOS URL
    local major_minor=$(echo "$openshift_version" | cut -d'.' -f1,2)
    local rhcos_url="https://raw.githubusercontent.com/openshift/installer/release-${major_minor}/data/data/coreos/rhcos.json"
    
    # Download RHCOS image list
    if ! curl -sSLf --retry 3 --connect-timeout 30 --max-time 60 -o /tmp/bastion-image.json "$rhcos_url"; then
        echo "Failed to download RHCOS image list from $rhcos_url" >&2
        return 1
    fi
    
    # Validate JSON
    if ! jq empty /tmp/bastion-image.json &>/dev/null; then
        echo "Downloaded file is not valid JSON" >&2
        return 1
    fi
    
    # Extract AMI ID for the region
    local ami_id=$(jq -r --arg r "$region" '.architectures.x86_64.images.aws.regions[$r].image // ""' /tmp/bastion-image.json)
    
    if [[ "$ami_id" == "" ]]; then
        echo "RHCOS AMI not found for region $region" >&2
        return 1
    fi
    
    echo "$ami_id"
}

# Function to get region-appropriate instance type
get_instance_type() {
    local region="$1"
    local preferred_type="$2"
    
    # Handle region-specific instance type limitations
    case "$region" in
        "us-gov-east-1")
            if [[ "$preferred_type" == "t2.medium" ]]; then
                echo "t3a.medium"
                return
            fi
            ;;
        "us-gov-west-1")
            if [[ "$preferred_type" == "t2.medium" ]]; then
                echo "t3a.medium"
                return
            fi
            ;;
    esac
    
    echo "$preferred_type"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --vpc-output-dir)
            VPC_OUTPUT_DIR="$2"
            shift 2
            ;;
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --instance-type)
            INSTANCE_TYPE="$2"
            shift 2
            ;;
        --ssh-key-name)
            SSH_KEY_NAME="$2"
            shift 2
            ;;
        --openshift-version)
            OPENSHIFT_VERSION="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --use-rhcos)
            USE_RHCOS="$2"
            shift 2
            ;;
        --create-iam-role)
            CREATE_IAM_ROLE="$2"
            shift 2
            ;;
        --enhanced-security)
            ENHANCED_SECURITY="$2"
            shift 2
            ;;
        --integrate-control-plane-sg)
            INTEGRATE_CONTROL_PLANE_SG="$2"
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
VPC_OUTPUT_DIR=${VPC_OUTPUT_DIR:-$DEFAULT_VPC_OUTPUT_DIR}
CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
INSTANCE_TYPE=${INSTANCE_TYPE:-$DEFAULT_INSTANCE_TYPE}
SSH_KEY_NAME=${SSH_KEY_NAME:-"${CLUSTER_NAME}-bastion-key"}
OPENSHIFT_VERSION=${OPENSHIFT_VERSION:-$DEFAULT_OPENSHIFT_VERSION}
OUTPUT_DIR=${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}
USE_RHCOS=${USE_RHCOS:-$DEFAULT_USE_RHCOS}
CREATE_IAM_ROLE=${CREATE_IAM_ROLE:-$DEFAULT_CREATE_IAM_ROLE}
ENHANCED_SECURITY=${ENHANCED_SECURITY:-$DEFAULT_ENHANCED_SECURITY}
INTEGRATE_CONTROL_PLANE_SG=${INTEGRATE_CONTROL_PLANE_SG:-$DEFAULT_INTEGRATE_CONTROL_PLANE_SG}

# Avoid unbound variable errors
IAM_ROLE_ARN=""
IAM_ROLE_NAME=""

# Validate VPC output
echo "🔍 Validating VPC output..."
validate_vpc_output "$VPC_OUTPUT_DIR"

# Read VPC information
VPC_ID=$(cat "$VPC_OUTPUT_DIR/vpc-id" | tr -d '\n')
PUBLIC_SUBNET_IDS=$(cat "$VPC_OUTPUT_DIR/public-subnet-ids" | tr -d '\n')
AVAILABILITY_ZONES=$(cat "$VPC_OUTPUT_DIR/availability-zones" | tr -d '\n')
REGION=$(get_region_from_vpc "$VPC_OUTPUT_DIR")

# Get first public subnet for bastion
FIRST_PUBLIC_SUBNET=$(echo "$PUBLIC_SUBNET_IDS" | cut -d',' -f1)

echo "📋 VPC Configuration:"
echo "   VPC ID: $VPC_ID"
echo "   Region: $REGION"
echo "   Public Subnet: $FIRST_PUBLIC_SUBNET"
echo "   Availability Zone: $(echo "$AVAILABILITY_ZONES" | cut -d',' -f1)"
echo ""

# Validate AWS CLI and credentials
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed"
    exit 1
fi

# Build AWS CLI command with profile if set
AWS_CMD="aws"
if [[ -n "${AWS_PROFILE:-}" ]]; then
    AWS_CMD="aws --profile ${AWS_PROFILE}"
fi

if ! $AWS_CMD sts get-caller-identity &> /dev/null; then
    echo "Error: AWS credentials not configured"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Create SSH key pair
create_ssh_key_pair "$SSH_KEY_NAME" "$REGION" "$OUTPUT_DIR"

# Create bastion security group
echo "🛡️  Creating bastion security group..."
BASTION_SG_NAME="${CLUSTER_NAME}-bastion-sg"

# Check if security group already exists
EXISTING_SG=$($AWS_CMD ec2 describe-security-groups \
    --filters "Name=group-name,Values=${BASTION_SG_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
    --region "${REGION}" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

if [[ "$EXISTING_SG" != "None" && "$EXISTING_SG" != "" ]]; then
    echo "⚠️  Security group '$BASTION_SG_NAME' already exists: $EXISTING_SG"
    BASTION_SG_ID="$EXISTING_SG"
else
    # Create new security group
    BASTION_SG_ID=$($AWS_CMD ec2 create-security-group \
        --group-name "${BASTION_SG_NAME}" \
        --description "Security group for bastion host" \
        --vpc-id "${VPC_ID}" \
        --region "${REGION}" \
        --query 'GroupId' \
        --output text)

    # Configure basic security group rules
    $AWS_CMD ec2 authorize-security-group-ingress \
        --group-id "${BASTION_SG_ID}" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 \
        --region "${REGION}"

    # Add enhanced security rules if requested
    if [[ "$ENHANCED_SECURITY" == "yes" ]]; then
        echo "🔒 Adding enhanced security group rules..."
        
        # ICMP for ping
        $AWS_CMD ec2 authorize-security-group-ingress \
            --group-id "${BASTION_SG_ID}" \
            --protocol icmp \
            --port -1 \
            --cidr 0.0.0.0/0 \
            --region "${REGION}"
        
        # Proxy ports
        $AWS_CMD ec2 authorize-security-group-ingress \
            --group-id "${BASTION_SG_ID}" \
            --protocol tcp \
            --port 873 \
            --cidr 0.0.0.0/0 \
            --region "${REGION}"
        
        $AWS_CMD ec2 authorize-security-group-ingress \
            --group-id "${BASTION_SG_ID}" \
            --protocol tcp \
            --port 3128 \
            --cidr 0.0.0.0/0 \
            --region "${REGION}"
        
        $AWS_CMD ec2 authorize-security-group-ingress \
            --group-id "${BASTION_SG_ID}" \
            --protocol tcp \
            --port 3129 \
            --cidr 0.0.0.0/0 \
            --region "${REGION}"
        
        # Registry ports
        $AWS_CMD ec2 authorize-security-group-ingress \
            --group-id "${BASTION_SG_ID}" \
            --protocol tcp \
            --port 5000 \
            --cidr 0.0.0.0/0 \
            --region "${REGION}"
        
        $AWS_CMD ec2 authorize-security-group-ingress \
            --group-id "${BASTION_SG_ID}" \
            --protocol tcp \
            --port 6001 \
            --cidr 0.0.0.0/0 \
            --region "${REGION}"
        
        $AWS_CMD ec2 authorize-security-group-ingress \
            --group-id "${BASTION_SG_ID}" \
            --protocol tcp \
            --port 6002 \
            --cidr 0.0.0.0/0 \
            --region "${REGION}"
        
        # Web ports
        $AWS_CMD ec2 authorize-security-group-ingress \
            --group-id "${BASTION_SG_ID}" \
            --protocol tcp \
            --port 80 \
            --cidr 0.0.0.0/0 \
            --region "${REGION}"
        
        $AWS_CMD ec2 authorize-security-group-ingress \
            --group-id "${BASTION_SG_ID}" \
            --protocol tcp \
            --port 8080 \
            --cidr 0.0.0.0/0 \
            --region "${REGION}"
        
        echo "✅ Enhanced security group rules added"
    fi

    echo "✅ Security group created: $BASTION_SG_ID"
fi

# Get control plane security group if integration is requested
CONTROL_PLANE_SG_ID=""
if [[ "$INTEGRATE_CONTROL_PLANE_SG" == "yes" ]]; then
    echo "🔗 Looking for control plane security group..."
    
    # Try to find control plane security group by common naming patterns
    CONTROL_PLANE_SG_ID=$($AWS_CMD ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=*controlplane*" \
        --region "${REGION}" \
        --query 'SecurityGroups[0].GroupId' \
        --output text)
    
    if [[ "$CONTROL_PLANE_SG_ID" != "None" && "$CONTROL_PLANE_SG_ID" != "" ]]; then
        echo "✅ Found control plane security group: $CONTROL_PLANE_SG_ID"
        echo "$CONTROL_PLANE_SG_ID" > "$OUTPUT_DIR/control-plane-security-group-id"
    else
        echo "⚠️  Control plane security group not found, continuing without integration"
    fi
fi

# Find latest Amazon Linux AMI
if [[ "$USE_RHCOS" == "yes" ]]; then
    echo "🔄 Using RHCOS AMI..."
    RHCOS_AMI=$(get_rhcos_ami "$REGION" "$OPENSHIFT_VERSION")
    if [[ $? -eq 0 ]]; then
        AMI_ID="$RHCOS_AMI"
        echo "✅ Using RHCOS AMI: $AMI_ID"
    else
        echo "⚠️  Failed to get RHCOS AMI, falling back to Amazon Linux 2023"
    fi
else
    SSH_USER="ec2-user"
    # Use Amazon Linux 2023 instead of Amazon Linux 2
    echo "🖼️  Getting latest Amazon Linux 2023 AMI..."
    AL2023_AMI=$(aws ec2 describe-images \
        --owners self \
        --region "$REGION" \
        --filters 'Name=name,Values=al2023-ami-*-x86_64' 'Name=architecture,Values=x86_64' 'Name=state,Values=available' \
        --query 'Images[*].[ImageId,CreationDate]' \
        --output text | sort -k2 -r | head -n1 | awk '{print $1}')
    if [[ -z "$AL2023_AMI" ]]; then
        echo "❌ Could not find Amazon Linux 2023 AMI in region $REGION" >&2
        exit 1
    fi
    AMI_ID="$AL2023_AMI"
    echo "✅ Using Amazon Linux 2023 AMI: $AMI_ID"
fi

# Get appropriate instance type for the region
INSTANCE_TYPE=$(get_instance_type "$REGION" "$INSTANCE_TYPE")
echo "✅ Using instance type: $INSTANCE_TYPE"

# Determine if using RHCOS
IS_RHCOS="no"
if [[ "$USE_RHCOS" == "yes" ]]; then
    IS_RHCOS="yes"
fi

# Prepare user-data
if [[ "$IS_RHCOS" == "yes" ]]; then
    SSH_USER="core"
    # For RHCOS, we'll rely on AWS's automatic key injection
    # and use a minimal Ignition config that just ensures the system is ready
    cat > "$OUTPUT_DIR/bastion-ignition.json" <<EOF
{
  "ignition": { "version": "3.2.0" },
  "storage": {
    "files": [
      {
        "path": "/etc/hostname",
        "mode": 420,
        "contents": {
          "source": "data:text/plain;charset=utf-8;base64,${CLUSTER_NAME}-bastion"
        }
      }
    ]
  }
}
EOF
    USERDATA_ARG="--user-data file://$OUTPUT_DIR/bastion-ignition.json"
else
    SSH_USER="ec2-user"
    # Amazon Linux 2023: use bash user-data script
    cat > "$OUTPUT_DIR/bastion-userdata.sh" <<EOF
#!/bin/bash
# Bastion host setup script for OpenShift cluster access

# Set SSH user for later use
SSH_USER="ec2-user"

# Update system based on OS type
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    if [[ "\$ID" == "amzn" && "\$VERSION_ID" == "2023"* ]]; then
        # Amazon Linux 2023
        echo "Amazon Linux 2023 detected - updating packages..."
        dnf update -y
        dnf install -y jq wget tar gzip unzip git curl
    elif [[ -f /etc/redhat-release ]]; then
        # RHEL/CentOS/Amazon Linux 2
        if command -v rpm-ostree &> /dev/null; then
            # RHCOS - no package manager updates needed
            echo "RHCOS detected - skipping package updates"
        else
            # RHEL/CentOS/Amazon Linux 2
            yum update -y
            yum install -y jq wget tar gzip unzip git curl
        fi
    fi
else
    # Fallback for older systems
    yum update -y
    yum install -y jq wget tar gzip unzip git curl
fi

# Install AWS CLI v2 (works on both RHCOS and Amazon Linux)
if ! command -v aws &> /dev/null; then
    echo "Installing AWS CLI v2..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
fi

# Install OpenShift CLI (oc) - only if not already present
if ! command -v oc &> /dev/null; then
    echo "📥 Installing OpenShift CLI version ${OPENSHIFT_VERSION}..."
    wget -q "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OPENSHIFT_VERSION}/openshift-client-linux.tar.gz"
    tar xf openshift-client-linux.tar.gz -C /usr/local/bin
    rm -f openshift-client-linux.tar.gz
    chmod +x /usr/local/bin/oc /usr/local/bin/kubectl
fi

# Install OpenShift Installer - only if not already present
if ! command -v openshift-install &> /dev/null; then
    echo "📥 Installing OpenShift Installer version ${OPENSHIFT_VERSION}..."
    wget -q "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OPENSHIFT_VERSION}/openshift-install-linux.tar.gz"
    tar xf openshift-install-linux.tar.gz -C /usr/local/bin
    rm -f openshift-install-linux.tar.gz
    chmod +x /usr/local/bin/openshift-install
fi

# Create workspace directory
mkdir -p /home/\${SSH_USER}/openshift
chown \${SSH_USER}:\${SSH_USER} /home/\${SSH_USER}/openshift

# Create helpful scripts
cat > /home/\${SSH_USER}/setup-openshift-access.sh <<'SCRIPT_EOF'
#!/bin/bash
# Script to setup OpenShift cluster access

echo "🔧 OpenShift Cluster Access Setup"
echo "=================================="
echo ""
echo "This script helps you access your OpenShift cluster from the bastion host."
echo ""
echo "Prerequisites:"
echo "1. OpenShift cluster must be installed and running"
echo "2. You need the kubeconfig file from the installation"
echo ""
echo "Steps:"
echo "1. Copy your kubeconfig file to this bastion host"
echo "2. Place it in /home/\${SSH_USER}/openshift/kubeconfig"
echo "3. Run: export KUBECONFIG=~/openshift/kubeconfig"
echo "4. Test access: oc get nodes"
echo ""
echo "Alternative: Use 'oc login' with cluster credentials"
echo "Example: oc login https://api.your-cluster.your-domain.com:6443"
SCRIPT_EOF

chmod +x /home/\${SSH_USER}/setup-openshift-access.sh
chown \${SSH_USER}:\${SSH_USER} /home/\${SSH_USER}/setup-openshift-access.sh

# Create environment file
cat > /home/\${SSH_USER}/openshift/env.sh <<'ENV_EOF'
#!/bin/bash
# OpenShift environment variables

export CLUSTER_NAME="${CLUSTER_NAME}"
export REGION="${REGION}"
export VPC_ID="${VPC_ID}"

# Add OpenShift tools to PATH
export PATH="/usr/local/bin:\$PATH"

# Set AWS region
export AWS_DEFAULT_REGION="${REGION}"

echo "✅ OpenShift environment loaded"
echo "   Cluster: \$CLUSTER_NAME"
echo "   Region: \$REGION"
echo "   VPC: \$VPC_ID"
ENV_EOF

chmod +x /home/\${SSH_USER}/openshift/env.sh
chown \${SSH_USER}:\${SSH_USER} /home/\${SSH_USER}/openshift/env.sh

# Create welcome message
cat > /home/\${SSH_USER}/welcome.txt <<'WELCOME_EOF'
🚀 OpenShift Bastion Host Ready!
================================

This bastion host is configured for OpenShift cluster management.

📋 Available Tools:
- oc (OpenShift CLI)
- kubectl (Kubernetes CLI)
- openshift-install (OpenShift Installer)
- aws (AWS CLI v2)

📁 Workspace Directory:
/home/\${SSH_USER}/openshift/

🔧 Setup Commands:
1. Load environment: source /home/\${SSH_USER}/openshift/env.sh
2. Setup cluster access: ./setup-openshift-access.sh

📖 Useful Commands:
- Check cluster status: oc get nodes
- View cluster info: oc cluster-info
- List projects: oc get projects
- Check AWS resources: aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/*,Values=owned"

🔐 Security Notes:
- This bastion host is in a public subnet
- SSH access is restricted to your IP
- Use the provided SSH key for access
- Consider using a VPN for additional security

Happy OpenShifting! 🎉
WELCOME_EOF

chown \${SSH_USER}:\${SSH_USER} /home/\${SSH_USER}/welcome.txt

# Display welcome message on login (but only for interactive sessions)
if [[ -t 0 ]]; then
    echo "cat /home/\${SSH_USER}/welcome.txt" >> /home/\${SSH_USER}/.bashrc
fi

echo "✅ Bastion host setup completed"
EOF
    USERDATA_ARG="--user-data file://$OUTPUT_DIR/bastion-userdata.sh"
fi

# Launch bastion instance
echo "🚀 Launching bastion host..."

# Prepare security group list
SECURITY_GROUP_IDS="${BASTION_SG_ID}"
if [[ -n "$CONTROL_PLANE_SG_ID" ]]; then
    SECURITY_GROUP_IDS="${BASTION_SG_ID} ${CONTROL_PLANE_SG_ID}"
fi

# Prepare IAM instance profile
IAM_INSTANCE_PROFILE=""
if [[ -n "$IAM_ROLE_ARN" ]]; then
    IAM_ROLE_NAME=$(echo "$IAM_ROLE_ARN" | cut -d'/' -f2)
    IAM_INSTANCE_PROFILE="--iam-instance-profile Name=${IAM_ROLE_NAME}"
fi

INSTANCE_ID=$($AWS_CMD ec2 run-instances \
    --image-id "${AMI_ID}" \
    --instance-type "${INSTANCE_TYPE}" \
    --key-name "${SSH_KEY_NAME}" \
    --security-group-ids ${SECURITY_GROUP_IDS} \
    --subnet-id "${FIRST_PUBLIC_SUBNET}" \
    --associate-public-ip-address \
    ${IAM_INSTANCE_PROFILE} \
    $USERDATA_ARG \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${CLUSTER_NAME}-bastion},{Key=ClusterName,Value=${CLUSTER_NAME}}]" \
    --region "${REGION}" \
    --query 'Instances[0].InstanceId' \
    --output text)

echo "✅ Bastion instance launched: $INSTANCE_ID"

# Wait for instance to be running
echo "⏳ Waiting for bastion host to be ready..."
$AWS_CMD ec2 wait instance-running \
    --instance-ids "${INSTANCE_ID}" \
    --region "${REGION}"

# Get bastion public IP
BASTION_PUBLIC_IP=$($AWS_CMD ec2 describe-instances \
    --instance-ids "${INSTANCE_ID}" \
    --region "${REGION}" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

# Save bastion information
echo "$INSTANCE_ID" > "$OUTPUT_DIR/bastion-instance-id"
echo "$BASTION_PUBLIC_IP" > "$OUTPUT_DIR/bastion-public-ip"
echo "$BASTION_SG_ID" > "$OUTPUT_DIR/bastion-security-group-id"
echo "$SSH_KEY_NAME" > "$OUTPUT_DIR/bastion-ssh-key-name"

# Create summary file
cat > "$OUTPUT_DIR/bastion-summary.txt" <<EOF
Bastion Host Summary
===================

Cluster Name: ${CLUSTER_NAME}
Region: ${REGION}
VPC ID: ${VPC_ID}

Bastion Host:
- Instance ID: ${INSTANCE_ID}
- Public IP: ${BASTION_PUBLIC_IP}
- Instance Type: ${INSTANCE_TYPE}
- Security Group: ${BASTION_SG_ID}
- SSH Key: ${SSH_KEY_NAME}
- SSH User: ${SSH_USER}

Network:
- Subnet: ${FIRST_PUBLIC_SUBNET}
- Availability Zone: $(echo "$AVAILABILITY_ZONES" | cut -d',' -f1)

Configuration:
- Use RHCOS: ${USE_RHCOS}
- Create IAM Role: ${CREATE_IAM_ROLE}
- Enhanced Security: ${ENHANCED_SECURITY}
- Integrate Control Plane SG: ${INTEGRATE_CONTROL_PLANE_SG}

${IAM_ROLE_ARN:+IAM Role: ${IAM_ROLE_ARN}
}${CONTROL_PLANE_SG_ID:+Control Plane Security Group: ${CONTROL_PLANE_SG_ID}
}Access Information:
- SSH Command: ssh -i ${OUTPUT_DIR}/${SSH_KEY_NAME}.pem ${SSH_USER}@${BASTION_PUBLIC_IP}
- SSH Key File: ${OUTPUT_DIR}/${SSH_KEY_NAME}.pem

Installed Tools:
- OpenShift CLI (oc) version ${OPENSHIFT_VERSION}
- Kubernetes CLI (kubectl)
- OpenShift Installer
- AWS CLI v2

Workspace Directory: /home/${SSH_USER}/openshift/

${ENHANCED_SECURITY:+Enhanced Security Features:
- Proxy ports: 3128, 3129, 873
- Registry ports: 5000, 6001-6002
- Web ports: 80, 8080
- ICMP for ping
}

Next Steps:
1. Set SSH key permissions: chmod 600 ${OUTPUT_DIR}/${SSH_KEY_NAME}.pem
2. SSH to the bastion host: ssh -i ${OUTPUT_DIR}/${SSH_KEY_NAME}.pem ${SSH_USER}@${BASTION_PUBLIC_IP}
3. Load the environment: source /home/${SSH_USER}/openshift/env.sh
4. Copy your OpenShift kubeconfig to the bastion (from your local machine):
   scp -i ${OUTPUT_DIR}/${SSH_KEY_NAME}.pem openshift-install/auth/kubeconfig ${SSH_USER}@${BASTION_PUBLIC_IP}:~/openshift/
5. Access your OpenShift cluster from the bastion:
   export KUBECONFIG=~/openshift/kubeconfig
   oc get nodes
   oc get clusteroperators

Useful Commands on Bastion Host:
- Check cluster status: oc get nodes, oc get clusteroperators, oc get clusterversion
- Access OpenShift console: oc whoami --show-console
- Troubleshooting: oc adm node-logs --help, oc get events --all-namespaces

Security Notes:
- The bastion host is in a public subnet
- SSH access is open to all IPs (0.0.0.0/0)
- Consider restricting SSH access to your IP range
- Use the provided SSH key for secure access
${IAM_ROLE_ARN:+${CONTROL_PLANE_SG_ID:+- IAM role provides S3 access for cluster operations
- Integrated with control plane security group for cluster access
}}
EOF

echo ""
echo "✅ Bastion host is ready!"
echo ""
echo "📁 Output directory: ${OUTPUT_DIR}"
echo "🆔 Instance ID: ${INSTANCE_ID}"
echo "🌐 Public IP: ${BASTION_PUBLIC_IP}"
echo "🔑 SSH Key: ${OUTPUT_DIR}/${SSH_KEY_NAME}.pem"
echo ""
echo "🔗 CONNECTING TO THE BASTION HOST"
echo "================================="
echo ""
echo "📋 Step 1: Set proper permissions on SSH key"
echo "chmod 600 ${OUTPUT_DIR}/${SSH_KEY_NAME}.pem"
echo ""
echo "📋 Step 2: SSH to the bastion host"
echo "ssh -i ${OUTPUT_DIR}/${SSH_KEY_NAME}.pem ${SSH_USER}@${BASTION_PUBLIC_IP}"
echo ""
echo "📋 Step 3: Once connected, load the OpenShift environment"
echo "source /home/${SSH_USER}/openshift/env.sh"
echo ""
echo "📋 Step 4: Copy your OpenShift kubeconfig to the bastion (from your local machine)"
echo "scp -i ${OUTPUT_DIR}/${SSH_KEY_NAME}.pem openshift-install/auth/kubeconfig ${SSH_USER}@${BASTION_PUBLIC_IP}:~/openshift/"
echo ""
echo "📋 Step 5: Access your OpenShift cluster from the bastion"
echo "export KUBECONFIG=~/openshift/kubeconfig"
echo "oc get nodes"
echo "oc get clusteroperators"
echo ""
echo "🔧 USEFUL COMMANDS ON THE BASTION HOST"
echo "======================================"
echo ""
echo "📊 Check cluster status:"
echo "oc get nodes"
echo "oc get clusteroperators"
echo "oc get clusterversion"
echo ""
echo "🌐 Access OpenShift console:"
echo "oc whoami --show-console"
echo ""
echo "🔍 Troubleshooting:"
echo "oc adm node-logs --help"
echo "oc get events --all-namespaces"
echo ""
echo "📋 Summary saved to: ${OUTPUT_DIR}/bastion-summary.txt"
echo ""
echo "🛑 To terminate the bastion host:"
echo "$AWS_CMD ec2 terminate-instances --instance-ids ${INSTANCE_ID} --region ${REGION}" 