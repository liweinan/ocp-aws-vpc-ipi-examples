#!/bin/bash

# Disconnected Cluster Infrastructure Creation Script
# Creates VPC, subnets, security groups, and bastion host for disconnected OpenShift cluster

set -eo pipefail

# Default values
DEFAULT_CLUSTER_NAME="disconnected-cluster"
DEFAULT_REGION="us-east-1"
DEFAULT_VPC_CIDR="10.0.0.0/16"
DEFAULT_PRIVATE_SUBNETS=1
DEFAULT_PUBLIC_SUBNETS=1
DEFAULT_INSTANCE_TYPE="t3.medium"
DEFAULT_AMI_OWNER="amazon"
DEFAULT_AMI_NAME="amzn2-ami-hvm-*-x86_64-gp2"
DEFAULT_OUTPUT_DIR="./infra-output"
DEFAULT_SNO_MODE="yes"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --cluster-name        Cluster name (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --region              AWS region (default: $DEFAULT_REGION)"
    echo "  --vpc-cidr            VPC CIDR block (default: $DEFAULT_VPC_CIDR)"
    echo "  --private-subnets     Number of private subnets (default: $DEFAULT_PRIVATE_SUBNETS for SNO)"
    echo "  --public-subnets      Number of public subnets (default: $DEFAULT_PUBLIC_SUBNETS)"
    echo "  --instance-type       Bastion instance type (default: $DEFAULT_INSTANCE_TYPE)"
    echo "  --output-dir          Output directory (default: $DEFAULT_OUTPUT_DIR)"
    echo "  --sno                 Enable Single Node OpenShift (SNO) mode (default: enabled)"
    echo "  --no-sno              Disable SNO mode for multi-node deployment"
    echo "  --dry-run             Show what would be created without actually creating"
    echo "  --help                Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --cluster-name my-disconnected-cluster --region us-east-1"
    echo "  $0 --sno --cluster-name my-sno-cluster"
    echo "  $0 --no-sno --private-subnets 3 --cluster-name multi-node-cluster"
    echo "  $0 --dry-run --cluster-name test-cluster"
    echo ""
    echo "Note: SNO mode is enabled by default for cost-effective disconnected deployments"
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

# Function to check CIDR conflicts across all VPCs in the region
check_cidr_conflicts() {
    local test_cidr="$1"
    local region="$2"
    
    # Check across all VPCs in the region, not just current VPC
    local conflict_count=$(aws ec2 describe-subnets \
        --filters "Name=cidr-block,Values=$test_cidr" \
        --region "$region" \
        --query 'length(Subnets)' \
        --output text 2>/dev/null || echo "0")
    
    echo "$conflict_count"
}

# Function to find available CIDR in a range
find_available_cidr() {
    local vpc_cidr="$1"
    local region="$2"
    local start_base="$3"
    local subnet_type="$4"  # "public" or "private"
    
    local base_ip=$(echo "$vpc_cidr" | cut -d'.' -f1-2)  # e.g., "10.3"
    local cidr_base=$start_base
    local max_attempts=100
    local attempts=0
    
    while [ $attempts -lt $max_attempts ]; do
        local test_cidr="${base_ip}.${cidr_base}.0/24"
        local conflict_count=$(check_cidr_conflicts "$test_cidr" "$region")
        
        if [ "$conflict_count" = "0" ]; then
            echo "$test_cidr"
            return 0
        else
            echo "   ❌ CIDR $test_cidr conflicts with $conflict_count existing subnet(s)" >&2
            cidr_base=$((cidr_base + 1))  # Try next /24 block
            attempts=$((attempts + 1))
        fi
    done
    
    echo ""  # Return empty if no CIDR found
    return 1
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
    
    # Create public subnets
    echo "   Creating public subnets..."
    local public_subnet_ids=""
    local az_array=($azs)
    
    for i in $(seq 1 $public_subnets); do
        local az="${az_array[$((i-1))]}"
        # Find available CIDR block for public subnet
        echo "   Finding available CIDR for public subnet $i..."
        local subnet_cidr=$(find_available_cidr "$vpc_cidr" "$region" "$((10 + (i-1) * 10))" "public")
        
        if [ -z "$subnet_cidr" ]; then
            echo "❌ Error: Could not find available CIDR block for public subnet $i"
            exit 1
        fi
        
        echo "   ✅ Selected CIDR $subnet_cidr for public subnet $i"
        
        echo "   Creating public subnet $i with CIDR $subnet_cidr in AZ $az"
        
        local subnet_id=$(aws ec2 create-subnet \
            --vpc-id "$vpc_id" \
            --cidr-block "$subnet_cidr" \
            --availability-zone "$az" \
            --region "$region" \
            --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${cluster_name}-public-${i}},{Key=kubernetes.io/role/elb,Value=1}]" \
            --query 'Subnet.SubnetId' \
            --output text)
        
        if [[ ! "$subnet_id" =~ ^subnet-[a-zA-Z0-9]+ ]]; then
            echo "❌ Error: Failed to create public subnet $i: $subnet_id"
            exit 1
        fi
        
        echo "   ✅ Successfully created public subnet: $subnet_id"
        
        # Enable auto-assign public IP for public subnets
        aws ec2 modify-subnet-attribute \
            --subnet-id "$subnet_id" \
            --map-public-ip-on-launch \
            --region "$region"
        
        # Add kubernetes.io/cluster/unmanaged tag to public subnet
        # This prevents OpenShift from managing this subnet during installation
        aws ec2 create-tags \
            --resources "$subnet_id" \
            --tags Key=kubernetes.io/cluster/unmanaged,Value=true \
            --region "$region"
        
        echo "   ✅ Added kubernetes.io/cluster/unmanaged tag to public subnet"
        
        # Add to subnet list
        if [[ -n "$public_subnet_ids" ]]; then
            public_subnet_ids="${public_subnet_ids},${subnet_id}"
        else
            public_subnet_ids="$subnet_id"
        fi
    done
    
    # Create private subnets
    echo "   Creating private subnets..."
    local private_subnet_ids=""
    
    for i in $(seq 1 $private_subnets); do
        local az="${az_array[$((i-1))]}"
        # Find available CIDR block for private subnet
        echo "   Finding available CIDR for private subnet $i..."
        local subnet_cidr=$(find_available_cidr "$vpc_cidr" "$region" "$((100 + (i-1) * 10))" "private")
        
        if [ -z "$subnet_cidr" ]; then
            echo "❌ Error: Could not find available CIDR block for private subnet $i"
            exit 1
        fi
        
        echo "   ✅ Selected CIDR $subnet_cidr for private subnet $i"
        
        echo "   Creating private subnet $i with CIDR $subnet_cidr in AZ $az"
        
        local subnet_id=$(aws ec2 create-subnet \
            --vpc-id "$vpc_id" \
            --cidr-block "$subnet_cidr" \
            --availability-zone "$az" \
            --region "$region" \
            --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${cluster_name}-private-${i}},{Key=kubernetes.io/role/internal-elb,Value=1}]" \
            --query 'Subnet.SubnetId' \
            --output text)
        
        if [[ ! "$subnet_id" =~ ^subnet-[a-zA-Z0-9]+ ]]; then
            echo "❌ Error: Failed to create private subnet $i: $subnet_id"
            exit 1
        fi
        
        echo "   ✅ Successfully created private subnet: $subnet_id"
        
        # Add to subnet list
        if [[ -n "$private_subnet_ids" ]]; then
            private_subnet_ids="${private_subnet_ids},${subnet_id}"
        else
            private_subnet_ids="$subnet_id"
        fi
    done
    
    # Note: Disconnected cluster does not need NAT Gateway
    # Private subnets will be completely isolated from internet
    echo "   Skipping NAT Gateway creation for disconnected cluster..."
    echo "   Private subnets will be completely isolated from internet"
    
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
    if [[ -n "$public_subnet_ids" ]]; then
        for subnet_id in $(echo "$public_subnet_ids" | tr ',' ' '); do
            if [[ -n "$subnet_id" && "$subnet_id" =~ ^subnet-[a-zA-Z0-9]+ ]]; then
                echo "   Associating public subnet $subnet_id with public route table"
                aws ec2 associate-route-table \
                    --subnet-id "$subnet_id" \
                    --route-table-id "$public_rt_id" \
                    --region "$region"
            fi
        done
    fi
    
    # Private route table
    local private_rt_id=$(aws ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --region "$region" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${cluster_name}-private-rt}]" \
        --query 'RouteTable.RouteTableId' \
        --output text)
    
    # Private subnets have no internet access - truly disconnected
    # No route to internet (0.0.0.0/0) is added to private route table
    echo "   Private subnets configured with no internet access"
    
    # Associate private subnets with private route table
    if [[ -n "$private_subnet_ids" ]]; then
        for subnet_id in $(echo "$private_subnet_ids" | tr ',' ' '); do
            if [[ -n "$subnet_id" && "$subnet_id" =~ ^subnet-[a-zA-Z0-9]+ ]]; then
                echo "   Associating private subnet $subnet_id with private route table"
                aws ec2 associate-route-table \
                    --subnet-id "$subnet_id" \
                    --route-table-id "$private_rt_id" \
                    --region "$region"
            fi
        done
    fi
    
    # Save infrastructure information
    mkdir -p "$output_dir"
    echo "$vpc_id" > "$output_dir/vpc-id"
    echo "$public_subnet_ids" > "$output_dir/public-subnet-ids"
    echo "$private_subnet_ids" > "$output_dir/private-subnet-ids"
    echo "$azs" > "$output_dir/availability-zones"
    echo "$region" > "$output_dir/region"
    echo "$vpc_cidr" > "$output_dir/vpc-cidr"
    # No NAT Gateway for disconnected cluster
    echo "none" > "$output_dir/nat-gateway-id"
    echo "none" > "$output_dir/eip-id"
    
    echo "✅ VPC infrastructure created successfully"
    echo "   VPC ID: $vpc_id"
    echo "   Public Subnets: $public_subnet_ids"
    echo "   Private Subnets: $private_subnet_ids"
    echo "   NAT Gateway: None (disconnected cluster)"
}

# Function to create bastion host
create_bastion_host() {
    local cluster_name="$1"
    local region="$2"
    local vpc_id="$3"
    local public_subnet_ids="$4"
    local instance_type="$5"
    local output_dir="$6"
    local vpc_cidr="$7"
    
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
    
    # Allow registry port from VPC only (not from internet)
    aws ec2 authorize-security-group-ingress \
        --group-id "$bastion_sg_id" \
        --protocol tcp \
        --port 5000 \
        --cidr "$vpc_cidr" \
        --region "$region"
    
    # Create SSH key pair
    echo "   Creating SSH key pair..."
    aws ec2 create-key-pair \
        --key-name "${cluster_name}-bastion-key" \
        --region "$region" \
        --query 'KeyMaterial' \
        --output text > "$output_dir/bastion-key.pem"
    
    chmod 600 "$output_dir/bastion-key.pem"
    
    # Get latest Ubuntu 22.04 AMI
    echo "   Getting latest Ubuntu 22.04 AMI..."
    local ami_id=$(aws ec2 describe-images \
        --owners self \
        --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-22.04-*-amd64-server-*" "Name=state,Values=available" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --region "$region" \
        --output text 2>/dev/null)
    
    if [ "$ami_id" = "None" ] || [ -z "$ami_id" ]; then
        echo "   Failed to get AMI ID, using fallback AMI..."
        # Fallback to a known Ubuntu 22.04 AMI for us-east-1
        if [ "$region" = "us-east-1" ]; then
            ami_id="ami-0c7217cdde317cfec"  # Ubuntu 22.04 LTS in us-east-1
        else
            echo "❌ Error: Could not determine AMI ID for region $region"
            return 1
        fi
    fi
    
    echo "   Using AMI: $ami_id"
    
    # Create user data script
    cat > "$output_dir/bastion-userdata.sh" <<'EOF'
#!/bin/bash
# Bastion host setup script for disconnected OpenShift cluster

# Update system
apt update -y
apt upgrade -y

# Install required packages
apt install -y jq wget tar gzip unzip git curl apache2-utils podman

# Start and enable podman socket
systemctl enable podman.socket
systemctl start podman.socket

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Create workspace directory
mkdir -p /home/ubuntu/disconnected-cluster
chown ubuntu:ubuntu /home/ubuntu/disconnected-cluster

# Create registry directories
mkdir -p /opt/registry/auth
mkdir -p /opt/registry/data
mkdir -p /opt/registry/certs

# Create registry authentication
htpasswd -Bbn admin admin123 > /opt/registry/auth/htpasswd

# Get instance metadata for certificate
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

# Create self-signed certificate with multiple SANs
cat > /opt/registry/certs/openssl.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = Organization
CN = registry.local

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = registry.local
DNS.2 = *.local
DNS.3 = localhost
DNS.4 = registry
DNS.5 = registry.${INSTANCE_ID}.local
IP.1 = 127.0.0.1
IP.2 = ${PUBLIC_IP}
IP.3 = ${PRIVATE_IP}
EOF

openssl req -newkey rsa:4096 -nodes -sha256 \
    -keyout /opt/registry/certs/domain.key \
    -out /opt/registry/certs/domain.csr \
    -config /opt/registry/certs/openssl.conf

openssl x509 -req -in /opt/registry/certs/domain.csr \
    -signkey /opt/registry/certs/domain.key \
    -out /opt/registry/certs/domain.crt \
    -days 365 \
    -extensions v3_req \
    -extfile /opt/registry/certs/openssl.conf

# Clean up CSR file
rm -f /opt/registry/certs/domain.csr

# Start registry with podman and TLS
podman run -d --name mirror-registry \
    -p 5000:5000 \
    -v /opt/registry/data:/var/lib/registry:z \
    -v /opt/registry/auth:/auth:z \
    -v /opt/registry/certs:/certs:z \
    -e REGISTRY_AUTH=htpasswd \
    -e REGISTRY_AUTH_HTPASSWD_REALM=Registry \
    -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
    -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
    -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
    --restart=always \
    registry:2

# Create helpful scripts
cat > /home/ubuntu/setup-registry.sh <<'SCRIPT_EOF'
#!/bin/bash
echo "🔧 Mirror Registry Setup"
echo "========================"
echo ""
echo "Registry is already running with podman!"
echo ""
echo "Registry URL: https://localhost:5000"
echo "Username: admin"
echo "Password: admin123"
echo ""
echo "To test registry access:"
echo "curl -k -u admin:admin123 https://localhost:5000/v2/_catalog"
SCRIPT_EOF

chmod +x /home/ubuntu/setup-registry.sh
chown ubuntu:ubuntu /home/ubuntu/setup-registry.sh

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
        --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":50,"VolumeType":"gp3"}}]' \
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
    local sno_mode="$5"
    
    echo "🏗️  Creating cluster security group..."
    
    local sg_name="${cluster_name}-cluster-sg"
    local sg_description="Security group for OpenShift cluster"
    
    if [[ "$sno_mode" == "yes" ]]; then
        sg_name="${cluster_name}-sno-sg"
        sg_description="Security group for Single Node OpenShift (SNO) cluster"
        echo "   Configuring for Single Node OpenShift (SNO) deployment..."
    fi
    
    local cluster_sg_id=$(aws ec2 create-security-group \
        --group-name "$sg_name" \
        --description "$sg_description" \
        --vpc-id "$vpc_id" \
        --region "$region" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$sg_name}]" \
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
    if [[ "$sno_mode" == "yes" ]]; then
        echo "   Configured for SNO deployment"
    fi
}

# Main execution
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cluster-name)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --cluster-name requires a value"
                    usage
                fi
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --region)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --region requires a value"
                    usage
                fi
                REGION="$2"
                shift 2
                ;;
            --vpc-cidr)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --vpc-cidr requires a value"
                    usage
                fi
                VPC_CIDR="$2"
                shift 2
                ;;
            --private-subnets)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --private-subnets requires a value"
                    usage
                fi
                PRIVATE_SUBNETS="$2"
                shift 2
                ;;
            --public-subnets)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --public-subnets requires a value"
                    usage
                fi
                PUBLIC_SUBNETS="$2"
                shift 2
                ;;
            --instance-type)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --instance-type requires a value"
                    usage
                fi
                INSTANCE_TYPE="$2"
                shift 2
                ;;
            --output-dir)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --output-dir requires a value"
                    usage
                fi
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --sno)
                SNO_MODE="yes"
                shift
                ;;
            --no-sno)
                SNO_MODE="no"
                shift
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
    SNO_MODE=${SNO_MODE:-$DEFAULT_SNO_MODE}
    
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
    echo "   SNO Mode: $SNO_MODE"
    echo ""
    
    if [[ "$DRY_RUN" == "yes" ]]; then
        echo "🔍 DRY RUN MODE - No resources will be created"
        echo ""
        echo "Would create:"
        echo "  - VPC with CIDR $VPC_CIDR"
        echo "  - $PUBLIC_SUBNETS public subnet(s)"
        echo "  - $PRIVATE_SUBNETS private subnet(s)"
        if [[ "$SNO_MODE" == "yes" ]]; then
            echo "  - Optimized for Single Node OpenShift (SNO) deployment"
            echo "  - Estimated cost: $20-40/day"
        else
            echo "  - Multi-node deployment configuration"
            echo "  - Estimated cost: $50-100/day"
        fi
        echo "  - No NAT Gateway (disconnected cluster)"
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
    
    # Create VPC infrastructure
    create_vpc_infrastructure "$CLUSTER_NAME" "$REGION" "$VPC_CIDR" "$PRIVATE_SUBNETS" "$PUBLIC_SUBNETS" "$OUTPUT_DIR"
    
    # Note: Bastion host and cluster security group creation moved to separate script
    # Run ./02-create-bastion.sh to create bastion host and security groups
    
    echo ""
    echo "✅ VPC infrastructure creation completed successfully!"
    if [[ "$SNO_MODE" == "yes" ]]; then
        echo "🎯 Configured for Single Node OpenShift (SNO) deployment"
    fi
    echo ""
    echo "📁 Output files saved to: $OUTPUT_DIR"
    echo "   vpc-id: VPC identifier"
    echo "   public-subnet-ids: Public subnet identifiers"
    echo "   private-subnet-ids: Private subnet identifiers"
    echo "   availability-zones: Availability zones used"
    echo "   region: AWS region"
    echo "   vpc-cidr: VPC CIDR block"
    echo ""
    echo "🔗 Next steps:"
    echo "1. Create bastion host: ./02-create-bastion.sh --cluster-name $CLUSTER_NAME"
    if [[ "$SNO_MODE" == "yes" ]]; then
        echo "   Use --sno flag for SNO-optimized configuration"
    fi
    echo "2. Setup mirror registry: ./04-setup-mirror-registry.sh --cluster-name $CLUSTER_NAME"
    if [[ "$SNO_MODE" == "yes" ]]; then
        echo ""
        echo "🎯 SNO-specific notes:"
        echo "   - Single private subnet created for SNO node"
        echo "   - Use --sno flag in subsequent scripts for consistency"
        echo "   - Estimated cost: $20-40/day (vs $50-100/day for multi-node)"
    fi
    echo ""
    echo "⚠️  Important:"
    echo "   - Private subnets are completely isolated from internet (disconnected cluster)"
    echo "   - No NAT Gateway created for cost optimization"
}

# Run main function with all arguments
main "$@" 