#!/bin/bash

# Disconnected Cluster Infrastructure Creation Script
# Creates VPC, subnets, security groups, and bastion host for disconnected OpenShift cluster

set -euo pipefail

# Default values
DEFAULT_CLUSTER_NAME="disconnected-cluster"
DEFAULT_REGION="us-east-1"
DEFAULT_VPC_CIDR="172.16.0.0/16"
DEFAULT_PRIVATE_SUBNETS=3
DEFAULT_PUBLIC_SUBNETS=1
DEFAULT_INSTANCE_TYPE="t3.medium"
DEFAULT_AMI_OWNER="amazon"
DEFAULT_AMI_NAME="amzn2-ami-hvm-*-x86_64-gp2"
DEFAULT_OUTPUT_DIR="./infra-output"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --cluster-name        Cluster name (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --region              AWS region (default: $DEFAULT_REGION)"
    echo "  --vpc-cidr            VPC CIDR block (default: $DEFAULT_VPC_CIDR)"
    echo "  --private-subnets     Number of private subnets (default: $DEFAULT_PRIVATE_SUBNETS)"
    echo "  --public-subnets      Number of public subnets (default: $DEFAULT_PUBLIC_SUBNETS)"
    echo "  --instance-type       Bastion instance type (default: $DEFAULT_INSTANCE_TYPE)"
    echo "  --output-dir          Output directory (default: $DEFAULT_OUTPUT_DIR)"
    echo "  --dry-run             Show what would be created without actually creating"
    echo "  --help                Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --cluster-name my-disconnected-cluster --region us-east-1"
    echo "  $0 --dry-run --cluster-name test-cluster"
    exit 1
}

# Function to check if required tools are available
check_prerequisites() {
    local missing_tools=()
    
    for tool in aws jq yq; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo "❌ Missing required tools: ${missing_tools[*]}"
        echo "Please install the missing tools and try again"
        exit 1
    fi
    
    echo "✅ All required tools are available"
}

# Function to validate AWS credentials
validate_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "❌ AWS credentials not configured or invalid"
        echo "Please run 'aws configure' or set appropriate environment variables"
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query 'Account' --output text)
    local user_arn=$(aws sts get-caller-identity --query 'Arn' --output text)
    
    echo "✅ AWS credentials validated"
    echo "   Account ID: $account_id"
    echo "   User ARN: $user_arn"
}

# Function to check for existing resources with same name
check_existing_resources() {
    local cluster_name="$1"
    local region="$2"
    
    echo "   Checking for existing resources with name: $cluster_name"
    
    # Check for existing VPCs with same name
    local existing_vpcs=$(aws ec2 describe-vpcs \
        --region "$region" \
        --filters "Name=tag:Name,Values=${cluster_name}-vpc" \
        --query 'Vpcs[?State==`available`].[VpcId]' \
        --output text)
    
    if [[ -n "$existing_vpcs" ]]; then
        echo "❌ Found existing VPC with name ${cluster_name}-vpc: $existing_vpcs"
        echo "   Please use a different cluster name or delete the existing VPC"
        return 1
    fi
    
    # Check for existing key pairs with same name
    local existing_keys=$(aws ec2 describe-key-pairs \
        --region "$region" \
        --key-names "${cluster_name}-bastion-key" \
        --query 'KeyPairs[].KeyName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$existing_keys" ]]; then
        echo "❌ Found existing key pair with name ${cluster_name}-bastion-key"
        echo "   Please use a different cluster name or delete the existing key pair"
        return 1
    fi
    
    # Check for existing security groups with same name
    local existing_sgs=$(aws ec2 describe-security-groups \
        --region "$region" \
        --filters "Name=group-name,Values=${cluster_name}-*" \
        --query 'SecurityGroups[].GroupName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$existing_sgs" ]]; then
        echo "❌ Found existing security groups with name pattern ${cluster_name}-*:"
        echo "   $existing_sgs"
        echo "   Please use a different cluster name or delete the existing security groups"
        return 1
    fi
    
    echo "   ✅ No existing resources found with name: $cluster_name"
}

# Function to suggest alternative VPC CIDRs
suggest_alternative_cidrs() {
    local region="$1"
    
    echo "💡 Alternative VPC CIDR suggestions:"
    echo "   - 172.16.0.0/16 (default)"
    echo "   - 172.17.0.0/16"
    echo "   - 172.18.0.0/16"
    echo "   - 172.19.0.0/16"
    echo "   - 192.168.0.0/16"
    echo "   - 192.168.1.0/16"
    echo ""
    echo "You can specify a different CIDR using: --vpc-cidr <CIDR>"
    echo "Example: $0 --vpc-cidr 172.17.0.0/16"
}

# Function to check for CIDR conflicts
check_cidr_conflicts() {
    local vpc_cidr="$1"
    local region="$2"
    
    echo "   Checking for existing CIDR conflicts..."
    
    # Get all VPCs in the region
    local existing_vpcs=$(aws ec2 describe-vpcs \
        --region "$region" \
        --query 'Vpcs[?State==`available`].[VpcId,CidrBlock]' \
        --output text)
    
    if [[ -n "$existing_vpcs" ]]; then
        echo "   Found existing VPCs:"
        echo "$existing_vpcs" | while read vpc_id cidr; do
            echo "     VPC $vpc_id: $cidr"
        done
    fi
    
    # Check if VPC CIDR overlaps with existing VPCs
    while read vpc_id cidr; do
        if [[ "$cidr" == "$vpc_cidr" ]]; then
            echo "❌ VPC CIDR $vpc_cidr conflicts with existing VPC $vpc_id"
            echo ""
            suggest_alternative_cidrs "$region"
            return 1
        fi
    done <<< "$existing_vpcs"
    
    echo "   ✅ No VPC CIDR conflicts found"
}

# Function to calculate non-overlapping subnet CIDRs
calculate_subnet_cidrs() {
    local vpc_cidr="$1"
    local subnet_count="$2"
    local start_offset="$3"
    local subnet_size="$4"
    
    local base_network=$(echo "$vpc_cidr" | cut -d'/' -f1)
    local vpc_prefix=$(echo "$vpc_cidr" | cut -d'/' -f2)
    
    # Convert base network to decimal for calculation
    local base_octets=($(echo "$base_network" | tr '.' ' '))
    local base_decimal=$((base_octets[0] * 16777216 + base_octets[1] * 65536 + base_octets[2] * 256 + base_octets[3]))
    
    local subnet_cidrs=""
    for i in $(seq 1 $subnet_count); do
        # Calculate subnet offset - each /24 subnet is 256 addresses apart
        local subnet_offset=$((start_offset + (i-1) * 256))
        local subnet_decimal=$((base_decimal + subnet_offset))
        
        # Convert back to IP address
        local octet1=$((subnet_decimal / 16777216))
        local octet2=$(((subnet_decimal % 16777216) / 65536))
        local octet3=$(((subnet_decimal % 65536) / 256))
        local octet4=$((subnet_decimal % 256))
        
        local subnet_cidr="${octet1}.${octet2}.${octet3}.${octet4}/${subnet_size}"
        subnet_cidrs="${subnet_cidrs}${subnet_cidr},"
    done
    
    echo "${subnet_cidrs%,}"
}

# Function to create VPC and subnets
create_vpc_infrastructure() {
    local cluster_name="$1"
    local region="$2"
    local vpc_cidr="$3"
    local private_subnets="$4"
    local public_subnets="$5"
    local output_dir="$6"
    
    echo "🏗️  Creating VPC infrastructure..."
    
    # Check for CIDR conflicts
    check_cidr_conflicts "$vpc_cidr" "$region"
    
    # Create VPC
    echo "   Creating VPC..."
    local vpc_id=$(aws ec2 create-vpc \
        --cidr-block "$vpc_cidr" \
        --region "$region" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${cluster_name}-vpc},{Key=kubernetes.io/cluster/${cluster_name},Value=shared}]" \
        --query 'Vpc.VpcId' \
        --output text)
    
    # Enable DNS hostnames
    aws ec2 modify-vpc-attribute \
        --vpc-id "$vpc_id" \
        --enable-dns-hostnames \
        --region "$region"
    
    # Create Internet Gateway
    echo "   Creating Internet Gateway..."
    local igw_id=$(aws ec2 create-internet-gateway \
        --region "$region" \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${cluster_name}-igw}]" \
        --query 'InternetGateway.InternetGatewayId' \
        --output text)
    
    aws ec2 attach-internet-gateway \
        --vpc-id "$vpc_id" \
        --internet-gateway-id "$igw_id" \
        --region "$region"
    
    # Get availability zones
    local azs=$(aws ec2 describe-availability-zones \
        --region "$region" \
        --query 'AvailabilityZones[0:3].ZoneName' \
        --output text)
    
    # Calculate subnet CIDRs - using non-overlapping ranges
    # Public subnets: 172.16.1.0/24, 172.16.2.0/24, 172.16.3.0/24, etc.
    # Private subnets: 172.16.11.0/24, 172.16.12.0/24, 172.16.13.0/24, etc.
    local public_subnet_cidrs=$(calculate_subnet_cidrs "$vpc_cidr" "$public_subnets" 256 24)
    local private_subnet_cidrs=$(calculate_subnet_cidrs "$vpc_cidr" "$private_subnets" 2816 24)
    
    echo "   Public subnet CIDRs: $public_subnet_cidrs"
    echo "   Private subnet CIDRs: $private_subnet_cidrs"
    
    # Create public subnets
    echo "   Creating public subnets..."
    local public_subnet_ids=""
    local az_array=($azs)
    local public_cidr_array=($(echo "$public_subnet_cidrs" | tr ',' ' '))
    
    for i in $(seq 1 $public_subnets); do
        local az="${az_array[$((i-1))]}"
        local subnet_cidr="${public_cidr_array[$((i-1))]}"
        
        local subnet_id=$(aws ec2 create-subnet \
            --vpc-id "$vpc_id" \
            --cidr-block "$subnet_cidr" \
            --availability-zone "$az" \
            --region "$region" \
            --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${cluster_name}-public-${i}},{Key=kubernetes.io/role/elb,Value=1}]" \
            --query 'Subnet.SubnetId' \
            --output text)
        
        aws ec2 modify-subnet-attribute \
            --subnet-id "$subnet_id" \
            --map-public-ip-on-launch \
            --region "$region"
        
        public_subnet_ids="${public_subnet_ids}${subnet_id},"
    done
    public_subnet_ids=${public_subnet_ids%,}
    
    # Create private subnets
    echo "   Creating private subnets..."
    local private_subnet_ids=""
    local private_cidr_array=($(echo "$private_subnet_cidrs" | tr ',' ' '))
    
    for i in $(seq 1 $private_subnets); do
        local az="${az_array[$((i-1))]}"
        local subnet_cidr="${private_cidr_array[$((i-1))]}"
        
        local subnet_id=$(aws ec2 create-subnet \
            --vpc-id "$vpc_id" \
            --cidr-block "$subnet_cidr" \
            --availability-zone "$az" \
            --region "$region" \
            --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${cluster_name}-private-${i}},{Key=kubernetes.io/role/internal-elb,Value=1}]" \
            --query 'Subnet.SubnetId' \
            --output text)
        
        private_subnet_ids="${private_subnet_ids}${subnet_id},"
    done
    private_subnet_ids=${private_subnet_ids%,}
    
    # Create NAT Gateway
    echo "   Creating NAT Gateway..."
    local first_public_subnet=$(echo "$public_subnet_ids" | cut -d',' -f1)
    
    local eip_id=$(aws ec2 allocate-address \
        --domain vpc \
        --region "$region" \
        --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${cluster_name}-nat-eip}]" \
        --query 'AllocationId' \
        --output text)
    
    local nat_gateway_id=$(aws ec2 create-nat-gateway \
        --subnet-id "$first_public_subnet" \
        --allocation-id "$eip_id" \
        --region "$region" \
        --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=${cluster_name}-nat}]" \
        --query 'NatGateway.NatGatewayId' \
        --output text)
    
    # Wait for NAT Gateway to be available
    echo "   Waiting for NAT Gateway to be available..."
    aws ec2 wait nat-gateway-available \
        --nat-gateway-ids "$nat_gateway_id" \
        --region "$region"
    
    # Create route tables
    echo "   Creating route tables..."
    
    # Public route table
    local public_rt_id=$(aws ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --region "$region" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${cluster_name}-public-rt}]" \
        --query 'RouteTable.RouteTableId' \
        --output text)
    
    aws ec2 create-route \
        --route-table-id "$public_rt_id" \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id "$igw_id" \
        --region "$region"
    
    # Associate public subnets with public route table
    for subnet_id in $(echo "$public_subnet_ids" | tr ',' ' '); do
        aws ec2 associate-route-table \
            --subnet-id "$subnet_id" \
            --route-table-id "$public_rt_id" \
            --region "$region"
    done
    
    # Private route table
    local private_rt_id=$(aws ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --region "$region" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${cluster_name}-private-rt}]" \
        --query 'RouteTable.RouteTableId' \
        --output text)
    
    aws ec2 create-route \
        --route-table-id "$private_rt_id" \
        --destination-cidr-block 0.0.0.0/0 \
        --nat-gateway-id "$nat_gateway_id" \
        --region "$region"
    
    # Associate private subnets with private route table
    for subnet_id in $(echo "$private_subnet_ids" | tr ',' ' '); do
        aws ec2 associate-route-table \
            --subnet-id "$subnet_id" \
            --route-table-id "$private_rt_id" \
            --region "$region"
    done
    
    # Save infrastructure information
    mkdir -p "$output_dir"
    echo "$vpc_id" > "$output_dir/vpc-id"
    echo "$public_subnet_ids" > "$output_dir/public-subnet-ids"
    echo "$private_subnet_ids" > "$output_dir/private-subnet-ids"
    echo "$azs" > "$output_dir/availability-zones"
    echo "$region" > "$output_dir/region"
    echo "$vpc_cidr" > "$output_dir/vpc-cidr"
    echo "$nat_gateway_id" > "$output_dir/nat-gateway-id"
    echo "$eip_id" > "$output_dir/eip-id"
    
    echo "✅ VPC infrastructure created successfully"
    echo "   VPC ID: $vpc_id"
    echo "   Public Subnets: $public_subnet_ids"
    echo "   Private Subnets: $private_subnet_ids"
    echo "   NAT Gateway: $nat_gateway_id"
}

# Function to create bastion host
create_bastion_host() {
    local cluster_name="$1"
    local region="$2"
    local vpc_id="$3"
    local public_subnet_ids="$4"
    local instance_type="$5"
    local output_dir="$6"
    
    echo "🏗️  Creating bastion host..."
    
    # Create bastion security group
    echo "   Creating bastion security group..."
    local bastion_sg_id=$(aws ec2 create-security-group \
        --group-name "${cluster_name}-bastion-sg" \
        --description "Security group for bastion host" \
        --vpc-id "$vpc_id" \
        --region "$region" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${cluster_name}-bastion-sg}]" \
        --query 'GroupId' \
        --output text)
    
    # Configure security group rules
    aws ec2 authorize-security-group-ingress \
        --group-id "$bastion_sg_id" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 \
        --region "$region"
    
    # Allow HTTP/HTTPS for registry access
    aws ec2 authorize-security-group-ingress \
        --group-id "$bastion_sg_id" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 \
        --region "$region"
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$bastion_sg_id" \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 \
        --region "$region"
    
    # Allow registry port
    aws ec2 authorize-security-group-ingress \
        --group-id "$bastion_sg_id" \
        --protocol tcp \
        --port 5000 \
        --cidr 0.0.0.0/0 \
        --region "$region"
    
    # Create SSH key pair
    echo "   Creating SSH key pair..."
    aws ec2 create-key-pair \
        --key-name "${cluster_name}-bastion-key" \
        --region "$region" \
        --query 'KeyMaterial' \
        --output text > "$output_dir/bastion-key.pem"
    
    chmod 600 "$output_dir/bastion-key.pem"
    
    # Get latest Amazon Linux 2023 AMI
    local ami_id=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --region "$region" \
        --output text)
    
    # Create user data script
    cat > "$output_dir/bastion-userdata.sh" <<'EOF'
#!/bin/bash
# Bastion host setup script for disconnected OpenShift cluster

# Update system
dnf update -y
dnf install -y jq wget tar gzip unzip git curl docker

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Create workspace directory
mkdir -p /home/ec2-user/disconnected-cluster
chown ec2-user:ec2-user /home/ec2-user/disconnected-cluster

# Add ec2-user to docker group
usermod -aG docker ec2-user

# Create helpful scripts
cat > /home/ec2-user/setup-registry.sh <<'SCRIPT_EOF'
#!/bin/bash
echo "🔧 Mirror Registry Setup"
echo "========================"
echo ""
echo "This script will help you set up a mirror registry for disconnected OpenShift installation."
echo ""
echo "Prerequisites:"
echo "1. Docker must be running"
echo "2. Sufficient disk space (at least 100GB recommended)"
echo ""
echo "Next steps:"
echo "1. Run: docker run -d --name mirror-registry -p 5000:5000 -v /opt/registry:/var/lib/registry:z registry:2"
echo "2. Create authentication: htpasswd -Bc /opt/registry/auth/htpasswd admin"
echo "3. Restart registry with authentication"
SCRIPT_EOF

chmod +x /home/ec2-user/setup-registry.sh
chown ec2-user:ec2-user /home/ec2-user/setup-registry.sh

echo "✅ Bastion host setup completed"
EOF
    
    # Launch bastion instance
    echo "   Launching bastion instance..."
    local first_public_subnet=$(echo "$public_subnet_ids" | cut -d',' -f1)
    
    local instance_id=$(aws ec2 run-instances \
        --image-id "$ami_id" \
        --instance-type "$instance_type" \
        --key-name "${cluster_name}-bastion-key" \
        --security-group-ids "$bastion_sg_id" \
        --subnet-id "$first_public_subnet" \
        --associate-public-ip-address \
        --user-data file://"$output_dir/bastion-userdata.sh" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${cluster_name}-bastion}]" \
        --region "$region" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    # Wait for instance to be running
    echo "   Waiting for bastion instance to be ready..."
    aws ec2 wait instance-running \
        --instance-ids "$instance_id" \
        --region "$region"
    
    # Get bastion public IP
    local bastion_public_ip=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$region" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    # Save bastion information
    echo "$instance_id" > "$output_dir/bastion-instance-id"
    echo "$bastion_public_ip" > "$output_dir/bastion-public-ip"
    echo "$bastion_sg_id" > "$output_dir/bastion-security-group-id"
    
    echo "✅ Bastion host created successfully"
    echo "   Instance ID: $instance_id"
    echo "   Public IP: $bastion_public_ip"
    echo "   SSH Key: $output_dir/bastion-key.pem"
}

# Function to create cluster security group
create_cluster_security_group() {
    local cluster_name="$1"
    local region="$2"
    local vpc_id="$3"
    local output_dir="$4"
    
    echo "🏗️  Creating cluster security group..."
    
    local cluster_sg_id=$(aws ec2 create-security-group \
        --group-name "${cluster_name}-cluster-sg" \
        --description "Security group for OpenShift cluster" \
        --vpc-id "$vpc_id" \
        --region "$region" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${cluster_name}-cluster-sg}]" \
        --query 'GroupId' \
        --output text)
    
    # Allow all traffic within the security group
    aws ec2 authorize-security-group-ingress \
        --group-id "$cluster_sg_id" \
        --protocol all \
        --source-group "$cluster_sg_id" \
        --region "$region"
    
    # Allow SSH from bastion
    local bastion_sg_id=$(cat "$output_dir/bastion-security-group-id")
    aws ec2 authorize-security-group-ingress \
        --group-id "$cluster_sg_id" \
        --protocol tcp \
        --port 22 \
        --source-group "$bastion_sg_id" \
        --region "$region"
    
    # Allow registry access from cluster
    aws ec2 authorize-security-group-ingress \
        --group-id "$cluster_sg_id" \
        --protocol tcp \
        --port 5000 \
        --source-group "$cluster_sg_id" \
        --region "$region"
    
    echo "$cluster_sg_id" > "$output_dir/cluster-security-group-id"
    
    echo "✅ Cluster security group created"
    echo "   Security Group ID: $cluster_sg_id"
}

# Function to cleanup on failure
cleanup_on_failure() {
    local output_dir="$1"
    local region="$2"
    
    echo ""
    echo "🧹 Cleaning up partially created resources..."
    
    if [[ -f "$output_dir/vpc-id" ]]; then
        local vpc_id=$(cat "$output_dir/vpc-id")
        echo "   Deleting VPC: $vpc_id"
        aws ec2 delete-vpc --vpc-id "$vpc_id" --region "$region" 2>/dev/null || true
    fi
    
    if [[ -f "$output_dir/bastion-instance-id" ]]; then
        local instance_id=$(cat "$output_dir/bastion-instance-id")
        echo "   Terminating bastion instance: $instance_id"
        aws ec2 terminate-instances --instance-ids "$instance_id" --region "$region" 2>/dev/null || true
    fi
    
    if [[ -f "$output_dir/nat-gateway-id" ]]; then
        local nat_id=$(cat "$output_dir/nat-gateway-id")
        echo "   Deleting NAT Gateway: $nat_id"
        aws ec2 delete-nat-gateway --nat-gateway-id "$nat_id" --region "$region" 2>/dev/null || true
    fi
    
    if [[ -f "$output_dir/eip-id" ]]; then
        local eip_id=$(cat "$output_dir/eip-id")
        echo "   Releasing Elastic IP: $eip_id"
        aws ec2 release-address --allocation-id "$eip_id" --region "$region" 2>/dev/null || true
    fi
    
    echo "   Removing output directory: $output_dir"
    rm -rf "$output_dir" 2>/dev/null || true
    
    echo "✅ Cleanup completed"
}

# Main execution
main() {
    # Set up trap for cleanup on script exit
    trap 'echo ""; echo "❌ Script interrupted. Cleaning up..."; cleanup_on_failure "$OUTPUT_DIR" "$REGION"; exit 1' INT TERM
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --vpc-cidr)
                VPC_CIDR="$2"
                shift 2
                ;;
            --private-subnets)
                PRIVATE_SUBNETS="$2"
                shift 2
                ;;
            --public-subnets)
                PUBLIC_SUBNETS="$2"
                shift 2
                ;;
            --instance-type)
                INSTANCE_TYPE="$2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="yes"
                shift
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
    
    # Set default values
    CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
    REGION=${REGION:-$DEFAULT_REGION}
    VPC_CIDR=${VPC_CIDR:-$DEFAULT_VPC_CIDR}
    PRIVATE_SUBNETS=${PRIVATE_SUBNETS:-$DEFAULT_PRIVATE_SUBNETS}
    PUBLIC_SUBNETS=${PUBLIC_SUBNETS:-$DEFAULT_PUBLIC_SUBNETS}
    INSTANCE_TYPE=${INSTANCE_TYPE:-$DEFAULT_INSTANCE_TYPE}
    OUTPUT_DIR=${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}
    DRY_RUN=${DRY_RUN:-no}
    
    # Display script header
    echo "🚀 Disconnected Cluster Infrastructure Creation"
    echo "==============================================="
    echo ""
    echo "📋 Configuration:"
    echo "   Cluster Name: $CLUSTER_NAME"
    echo "   Region: $REGION"
    echo "   VPC CIDR: $VPC_CIDR"
    echo "   Private Subnets: $PRIVATE_SUBNETS"
    echo "   Public Subnets: $PUBLIC_SUBNETS"
    echo "   Bastion Instance Type: $INSTANCE_TYPE"
    echo "   Output Directory: $OUTPUT_DIR"
    echo "   Dry Run: $DRY_RUN"
    echo ""
    
    if [[ "$DRY_RUN" == "yes" ]]; then
        echo "🔍 DRY RUN MODE - No resources will be created"
        echo ""
        echo "Would create:"
        echo "  - VPC with CIDR $VPC_CIDR"
        echo "  - $PUBLIC_SUBNETS public subnet(s)"
        echo "  - $PRIVATE_SUBNETS private subnet(s)"
        echo "  - NAT Gateway"
        echo "  - Bastion host ($INSTANCE_TYPE)"
        echo "  - Security groups"
        echo "  - SSH key pair"
        echo ""
        echo "To actually create resources, run without --dry-run"
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Validate AWS credentials
    validate_aws_credentials
    
    # Check for existing resources with same name
    if ! check_existing_resources "$CLUSTER_NAME" "$REGION"; then
        exit 1
    fi
    
    # Create VPC infrastructure
    if ! create_vpc_infrastructure "$CLUSTER_NAME" "$REGION" "$VPC_CIDR" "$PRIVATE_SUBNETS" "$PUBLIC_SUBNETS" "$OUTPUT_DIR"; then
        echo "❌ Failed to create VPC infrastructure"
        cleanup_on_failure "$OUTPUT_DIR" "$REGION"
        exit 1
    fi
    
    # Create bastion host
    local vpc_id=$(cat "$OUTPUT_DIR/vpc-id")
    local public_subnet_ids=$(cat "$OUTPUT_DIR/public-subnet-ids")
    if ! create_bastion_host "$CLUSTER_NAME" "$REGION" "$vpc_id" "$public_subnet_ids" "$INSTANCE_TYPE" "$OUTPUT_DIR"; then
        echo "❌ Failed to create bastion host"
        cleanup_on_failure "$OUTPUT_DIR" "$REGION"
        exit 1
    fi
    
    # Create cluster security group
    if ! create_cluster_security_group "$CLUSTER_NAME" "$REGION" "$vpc_id" "$OUTPUT_DIR"; then
        echo "❌ Failed to create cluster security group"
        cleanup_on_failure "$OUTPUT_DIR" "$REGION"
        exit 1
    fi
    
    # Remove trap since we succeeded
    trap - INT TERM
    
    echo ""
    echo "✅ Infrastructure creation completed successfully!"
    echo ""
    echo "📁 Output files saved to: $OUTPUT_DIR"
    echo "   vpc-id: VPC identifier"
    echo "   public-subnet-ids: Public subnet identifiers"
    echo "   private-subnet-ids: Private subnet identifiers"
    echo "   bastion-public-ip: Bastion host public IP"
    echo "   bastion-key.pem: SSH private key for bastion access"
    echo ""
    echo "🔗 Next steps:"
    echo "1. Connect to bastion host: ssh -i $OUTPUT_DIR/bastion-key.pem ec2-user@$(cat $OUTPUT_DIR/bastion-public-ip)"
    echo "2. Run: ./02-setup-mirror-registry.sh --cluster-name $CLUSTER_NAME"
    echo ""
    echo "⚠️  Important:"
    echo "   - Keep the SSH key file secure: $OUTPUT_DIR/bastion-key.pem"
    echo "   - The bastion host is accessible from the internet"
    echo "   - Private subnets are isolated and require NAT Gateway for outbound access"
}

# Run main function with all arguments
main "$@" 