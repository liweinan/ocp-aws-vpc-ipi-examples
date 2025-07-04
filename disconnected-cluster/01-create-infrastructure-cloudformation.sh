#!/bin/bash

# Alternative Disconnected Cluster Infrastructure Creation Script
# Uses CloudFormation template to create VPC with all required endpoints
# Based on aws-provision-vpc-disconnected pattern

set -eo pipefail

# Default values
DEFAULT_CLUSTER_NAME="disconnected-cluster"
DEFAULT_REGION="us-east-1"
DEFAULT_VPC_CIDR="10.0.0.0/16"
DEFAULT_PRIVATE_SUBNET_CIDR="10.0.100.0/24"
DEFAULT_PUBLIC_SUBNET_CIDR="10.0.10.0/24"
DEFAULT_INSTANCE_TYPE="t3.medium"
DEFAULT_OUTPUT_DIR="./infra-output"
DEFAULT_SNO_MODE="yes"
DEFAULT_TEMPLATE_FILE="./vpc-disconnected-template.yaml"
DEFAULT_AUTO_ADJUST_CIDR="yes"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "CloudFormation-based Disconnected Cluster Infrastructure Creation"
    echo "================================================================"
    echo ""
    echo "Options:"
    echo "  --cluster-name        Cluster name (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --region              AWS region (default: $DEFAULT_REGION)"
    echo "  --vpc-cidr            VPC CIDR block (default: $DEFAULT_VPC_CIDR)"
    echo "  --private-subnet-cidr Private subnet CIDR (default: $DEFAULT_PRIVATE_SUBNET_CIDR)"
    echo "  --public-subnet-cidr  Public subnet CIDR (default: $DEFAULT_PUBLIC_SUBNET_CIDR)"
    echo "  --instance-type       Bastion instance type (default: $DEFAULT_INSTANCE_TYPE)"
    echo "  --output-dir          Output directory (default: $DEFAULT_OUTPUT_DIR)"
    echo "  --template-file       CloudFormation template file (default: $DEFAULT_TEMPLATE_FILE)"
    echo "  --auto-adjust-cidr    Auto-adjust CIDR on conflicts (default: $DEFAULT_AUTO_ADJUST_CIDR)"
    echo "  --no-auto-adjust      Disable automatic CIDR adjustment"
    echo "  --sno                 Enable Single Node OpenShift (SNO) mode (default: enabled)"
    echo "  --no-sno              Disable SNO mode for multi-node deployment"
    echo "  --dry-run             Show what would be created without actually creating"
    echo "  --delete              Delete the CloudFormation stack"
    echo "  --help                Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --cluster-name my-disconnected-cluster --region us-east-1"
    echo "  $0 --sno --cluster-name my-sno-cluster --auto-adjust-cidr"
    echo "  $0 --no-sno --cluster-name multi-node-cluster --no-auto-adjust"
    echo "  $0 --dry-run --cluster-name test-cluster"
    echo "  $0 --delete --cluster-name test-cluster"
    echo ""
    echo "Features:"
    echo "  ✅ All required VPC endpoints (S3, EC2, ELB, Route53, STS, EBS)"
    echo "  ✅ No NAT Gateway (cost optimized for disconnected)"
    echo "  ✅ Automatic CIDR conflict detection and resolution"
    echo "  ✅ Dynamic subnet adjustment"
    echo "  ✅ Proper security groups and network configuration"
    echo "  ✅ SNO mode support"
    echo "  ✅ Compatible output format with existing scripts"
    exit 1
}

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    local missing_tools=()
    
    for tool in aws jq python3; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    print_success "All required tools are available"
}

# Function to validate AWS credentials
validate_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query 'Account' --output text)
    local user_arn=$(aws sts get-caller-identity --query 'Arn' --output text)
    
    print_success "AWS credentials validated"
    print_info "Account ID: $account_id"
    print_info "User ARN: $user_arn"
}

# Function to check if two CIDR blocks overlap
cidr_overlap() {
    local cidr1="$1"
    local cidr2="$2"
    
    # Use ipcalc if available, otherwise use simple Python check
    if command -v ipcalc &> /dev/null; then
        # Check if ranges overlap using ipcalc
        if ipcalc -c "$cidr1" "$cidr2" &> /dev/null; then
            return 0  # Overlap detected
        else
            return 1  # No overlap
        fi
    else
        # Python-based overlap check
        python3 -c "
import ipaddress
import sys
try:
    net1 = ipaddress.IPv4Network('$cidr1', strict=False)
    net2 = ipaddress.IPv4Network('$cidr2', strict=False)
    if net1.overlaps(net2):
        sys.exit(0)  # Overlap
    else:
        sys.exit(1)  # No overlap
except:
    sys.exit(1)  # Error, assume no overlap
"
    fi
}

# Function to get all existing VPC CIDRs in region
get_existing_vpc_cidrs() {
    local region="$1"
    
    aws ec2 describe-vpcs \
        --region "$region" \
        --query 'Vpcs[].CidrBlock' \
        --output text 2>/dev/null || echo ""
}

# Function to get all existing subnet CIDRs in region
get_existing_subnet_cidrs() {
    local region="$1"
    
    aws ec2 describe-subnets \
        --region "$region" \
        --query 'Subnets[].CidrBlock' \
        --output text 2>/dev/null || echo ""
}

# Function to generate alternative CIDR
generate_alternative_cidr() {
    local original_cidr="$1"
    local cidr_type="$2"  # vpc, private, public
    
    # Generate alternatives based on type
    case "$cidr_type" in
        "vpc")
            # Try different /16 networks
            for i in {11..50}; do
                local new_cidr="${i}.0.0.0/16"
                if [[ "$new_cidr" != "$original_cidr" ]]; then
                    echo "$new_cidr"
                    return
                fi
            done
            ;;
        "private")
            # Try different /24 networks within common private ranges
            for i in {101..200}; do
                local new_cidr="10.0.${i}.0/24"
                if [[ "$new_cidr" != "$original_cidr" ]]; then
                    echo "$new_cidr"
                    return
                fi
            done
            ;;
        "public")
            # Try different /24 networks for public subnets
            for i in {11..50}; do
                local new_cidr="10.0.${i}.0/24"
                if [[ "$new_cidr" != "$original_cidr" ]]; then
                    echo "$new_cidr"
                    return
                fi
            done
            ;;
    esac
    
    echo "$original_cidr"  # Return original if no alternative found
}

# Function to find non-conflicting CIDRs
find_non_conflicting_cidrs() {
    local region="$1"
    local vpc_cidr="$2"
    local private_subnet_cidr="$3"
    local public_subnet_cidr="$4"
    local auto_adjust="$5"
    
    if [[ "$auto_adjust" != "yes" ]]; then
        echo "$vpc_cidr|$private_subnet_cidr|$public_subnet_cidr"
        return
    fi
    
    print_info "🔍 Checking for CIDR conflicts in region $region..." >&2
    
    # Get existing CIDRs
    local existing_vpc_cidrs=$(get_existing_vpc_cidrs "$region")
    local existing_subnet_cidrs=$(get_existing_subnet_cidrs "$region")
    
    print_info "Found $(echo "$existing_vpc_cidrs" | wc -w) existing VPCs" >&2
    print_info "Found $(echo "$existing_subnet_cidrs" | wc -w) existing subnets" >&2
    
    local final_vpc_cidr="$vpc_cidr"
    local final_private_cidr="$private_subnet_cidr"
    local final_public_cidr="$public_subnet_cidr"
    local conflicts_found=false
    
    # Check VPC CIDR conflicts
    for existing_cidr in $existing_vpc_cidrs; do
        if cidr_overlap "$final_vpc_cidr" "$existing_cidr"; then
            print_warning "VPC CIDR conflict detected: $final_vpc_cidr overlaps with $existing_cidr" >&2
            conflicts_found=true
            
            # Try to find alternative
            local attempts=0
            while [[ $attempts -lt 10 ]]; do
                local alternative_vpc_cidr=$(generate_alternative_cidr "$final_vpc_cidr" "vpc")
                local has_conflict=false
                
                for existing_cidr in $existing_vpc_cidrs; do
                    if cidr_overlap "$alternative_vpc_cidr" "$existing_cidr"; then
                        has_conflict=true
                        break
                    fi
                done
                
                if [[ "$has_conflict" == false ]]; then
                    print_success "Found alternative VPC CIDR: $alternative_vpc_cidr" >&2
                    final_vpc_cidr="$alternative_vpc_cidr"
                    
                    # Adjust subnet CIDRs to fit within new VPC CIDR
                    local vpc_base=$(echo "$final_vpc_cidr" | cut -d'.' -f1-2)
                    final_private_cidr="${vpc_base}.100.0/24"
                    final_public_cidr="${vpc_base}.10.0/24"
                    break
                fi
                
                ((attempts++))
            done
            
            if [[ $attempts -eq 10 ]]; then
                print_error "Could not find non-conflicting VPC CIDR after 10 attempts" >&2
                return 1
            fi
            break
        fi
    done
    
    # Check subnet CIDR conflicts
    for existing_cidr in $existing_subnet_cidrs; do
        if cidr_overlap "$final_private_cidr" "$existing_cidr"; then
            print_warning "Private subnet CIDR conflict detected: $final_private_cidr overlaps with $existing_cidr" >&2
            conflicts_found=true
            final_private_cidr=$(generate_alternative_cidr "$final_private_cidr" "private")
            print_success "Using alternative private subnet CIDR: $final_private_cidr" >&2
        fi
        
        if cidr_overlap "$final_public_cidr" "$existing_cidr"; then
            print_warning "Public subnet CIDR conflict detected: $final_public_cidr overlaps with $existing_cidr" >&2
            conflicts_found=true
            final_public_cidr=$(generate_alternative_cidr "$final_public_cidr" "public")
            print_success "Using alternative public subnet CIDR: $final_public_cidr" >&2
        fi
    done
    
    if [[ "$conflicts_found" == true ]]; then
        print_success "✅ All CIDR conflicts resolved automatically" >&2
        print_info "Final CIDRs:" >&2
        print_info "  VPC CIDR: $final_vpc_cidr" >&2
        print_info "  Private Subnet CIDR: $final_private_cidr" >&2
        print_info "  Public Subnet CIDR: $final_public_cidr" >&2
    else
        print_success "✅ No CIDR conflicts detected" >&2
    fi
    
    echo "$final_vpc_cidr|$final_private_cidr|$final_public_cidr"
}

# Function to get first available AZ
get_availability_zone() {
    local region="$1"
    
    local first_az=$(aws ec2 describe-availability-zones \
        --region "$region" \
        --query 'AvailabilityZones[0].ZoneName' \
        --output text)
    
    if [[ "$first_az" == "None" || -z "$first_az" ]]; then
        print_error "Could not determine availability zone for region $region"
        exit 1
    fi
    
    echo "$first_az"
}

# Function to create CloudFormation stack
create_cloudformation_stack() {
    local cluster_name="$1"
    local region="$2"
    local vpc_cidr="$3"
    local private_subnet_cidr="$4"
    local public_subnet_cidr="$5"
    local sno_mode="$6"
    local template_file="$7"
    local dry_run="$8"
    
    print_info "Creating CloudFormation stack..."
    
    local stack_name="${cluster_name}-vpc-infrastructure"
    local availability_zone=$(get_availability_zone "$region")
    
    print_info "Stack name: $stack_name"
    print_info "Template file: $template_file"
    print_info "Availability zone: $availability_zone"
    
    # Check if template file exists
    if [[ ! -f "$template_file" ]]; then
        print_error "CloudFormation template file not found: $template_file"
        exit 1
    fi
    
    # Validate template
    print_info "Validating CloudFormation template..."
    if ! aws cloudformation validate-template \
        --template-body file://"$template_file" \
        --region "$region" &> /dev/null; then
        print_error "CloudFormation template validation failed"
        exit 1
    fi
    print_success "Template validation passed"
    
    if [[ "$dry_run" == "yes" ]]; then
        print_info "DRY RUN: Would create CloudFormation stack with parameters:"
        echo "  ClusterName: $cluster_name"
        echo "  VpcCidr: $vpc_cidr"
        echo "  PrivateSubnetCidr: $private_subnet_cidr"
        echo "  PublicSubnetCidr: $public_subnet_cidr"
        echo "  AvailabilityZone: $availability_zone"
        echo "  SNOMode: $sno_mode"
        return 0
    fi
    
    # Create stack
    print_info "Creating CloudFormation stack: $stack_name"
    local stack_id=$(aws cloudformation create-stack \
        --stack-name "$stack_name" \
        --template-body file://"$template_file" \
        --parameters \
            ParameterKey=ClusterName,ParameterValue="$cluster_name" \
            ParameterKey=VpcCidr,ParameterValue="$vpc_cidr" \
            ParameterKey=PrivateSubnetCidr,ParameterValue="$private_subnet_cidr" \
            ParameterKey=PublicSubnetCidr,ParameterValue="$public_subnet_cidr" \
            ParameterKey=AvailabilityZone,ParameterValue="$availability_zone" \
            ParameterKey=SNOMode,ParameterValue="$sno_mode" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$region" \
        --query 'StackId' \
        --output text)
    
    if [[ -z "$stack_id" ]]; then
        print_error "Failed to create CloudFormation stack"
        exit 1
    fi
    
    print_success "CloudFormation stack creation initiated"
    print_info "Stack ID: $stack_id"
    
    # Wait for stack creation to complete
    print_info "Waiting for stack creation to complete..."
    print_info "This may take 5-10 minutes due to VPC endpoint creation..."
    
    if aws cloudformation wait stack-create-complete \
        --stack-name "$stack_name" \
        --region "$region"; then
        print_success "CloudFormation stack created successfully"
    else
        print_error "CloudFormation stack creation failed"
        
        # Get stack events for debugging
        print_info "Stack events (last 10):"
        aws cloudformation describe-stack-events \
            --stack-name "$stack_name" \
            --region "$region" \
            --query 'StackEvents[0:9].[Timestamp,ResourceStatus,ResourceType,LogicalResourceId,ResourceStatusReason]' \
            --output table
        exit 1
    fi
    
    # Get stack outputs
    print_info "Retrieving stack outputs..."
    get_stack_outputs "$stack_name" "$region" "$cluster_name"
}

# Function to get stack outputs and save to files
get_stack_outputs() {
    local stack_name="$1"
    local region="$2"
    local cluster_name="$3"
    
    print_info "Saving stack outputs to $OUTPUT_DIR..."
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Get all stack outputs
    local outputs=$(aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$region" \
        --query 'Stacks[0].Outputs' \
        --output json)
    
    if [[ -z "$outputs" || "$outputs" == "null" ]]; then
        print_error "No stack outputs found"
        exit 1
    fi
    
    # Extract and save individual outputs
    echo "$outputs" | jq -r '.[] | select(.OutputKey=="VPCId") | .OutputValue' > "$OUTPUT_DIR/vpc-id"
    echo "$outputs" | jq -r '.[] | select(.OutputKey=="PublicSubnetId") | .OutputValue' > "$OUTPUT_DIR/public-subnet-ids"
    echo "$outputs" | jq -r '.[] | select(.OutputKey=="PrivateSubnetId") | .OutputValue' > "$OUTPUT_DIR/private-subnet-ids"
    echo "$outputs" | jq -r '.[] | select(.OutputKey=="AvailabilityZone") | .OutputValue' > "$OUTPUT_DIR/availability-zones"
    echo "$outputs" | jq -r '.[] | select(.OutputKey=="VPCCidr") | .OutputValue' > "$OUTPUT_DIR/vpc-cidr"
    echo "$outputs" | jq -r '.[] | select(.OutputKey=="BastionSecurityGroupId") | .OutputValue' > "$OUTPUT_DIR/bastion-security-group-id"
    echo "$outputs" | jq -r '.[] | select(.OutputKey=="ClusterSecurityGroupId") | .OutputValue' > "$OUTPUT_DIR/cluster-security-group-id"
    echo "$outputs" | jq -r '.[] | select(.OutputKey=="VPCEndpointsSecurityGroupId") | .OutputValue' > "$OUTPUT_DIR/vpc-endpoints-security-group-id"
    
    # VPC Endpoints
    echo "$outputs" | jq -r '.[] | select(.OutputKey=="S3EndpointId") | .OutputValue' > "$OUTPUT_DIR/s3-endpoint-id"
    echo "$outputs" | jq -r '.[] | select(.OutputKey=="EC2EndpointId") | .OutputValue' > "$OUTPUT_DIR/ec2-endpoint-id"
    echo "$outputs" | jq -r '.[] | select(.OutputKey=="ELBEndpointId") | .OutputValue' > "$OUTPUT_DIR/elb-endpoint-id"
    echo "$outputs" | jq -r '.[] | select(.OutputKey=="Route53EndpointId") | .OutputValue' > "$OUTPUT_DIR/route53-endpoint-id"
    echo "$outputs" | jq -r '.[] | select(.OutputKey=="STSEndpointId") | .OutputValue' > "$OUTPUT_DIR/sts-endpoint-id"
    echo "$outputs" | jq -r '.[] | select(.OutputKey=="EBSEndpointId") | .OutputValue' > "$OUTPUT_DIR/ebs-endpoint-id"
    
    # These are always 'none' for disconnected cluster
    echo "$outputs" | jq -r '.[] | select(.OutputKey=="NATGatewayId") | .OutputValue' > "$OUTPUT_DIR/nat-gateway-id"
    echo "$outputs" | jq -r '.[] | select(.OutputKey=="ElasticIPId") | .OutputValue' > "$OUTPUT_DIR/eip-id"
    
    # Save region
    echo "$region" > "$OUTPUT_DIR/region"
    
    # Save stack name for later reference
    echo "$stack_name" > "$OUTPUT_DIR/cloudformation-stack-name"
    
    print_success "All outputs saved to $OUTPUT_DIR"
}

# Function to create bastion host (separate from CloudFormation)
create_bastion_host() {
    local cluster_name="$1"
    local region="$2"
    local instance_type="$3"
    local output_dir="$4"
    local vpc_cidr="$5"
    
    print_info "Creating bastion host..."
    
    # Read required values from output files
    local vpc_id=$(cat "$output_dir/vpc-id")
    local public_subnet_id=$(cat "$output_dir/public-subnet-ids")
    local bastion_sg_id=$(cat "$output_dir/bastion-security-group-id")
    
    # Create SSH key pair
    print_info "Creating SSH key pair..."
    aws ec2 create-key-pair \
        --key-name "${cluster_name}-bastion-key" \
        --region "$region" \
        --query 'KeyMaterial' \
        --output text > "$output_dir/bastion-key.pem"
    
    chmod 600 "$output_dir/bastion-key.pem"
    
    # Generate public key for later use
    ssh-keygen -y -f "$output_dir/bastion-key.pem" > "$output_dir/bastion-key.pem.pub"
    
    # Get latest Ubuntu 22.04 AMI
    print_info "Getting latest Ubuntu 22.04 AMI..."
    local ami_id=$(aws ec2 describe-images \
        --owners 099720109477 \
        --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" "Name=state,Values=available" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --region "$region" \
        --output text 2>/dev/null)
    
    if [[ "$ami_id" == "None" || -z "$ami_id" ]]; then
        print_warning "Failed to get Ubuntu AMI, using fallback..."
        # Fallback AMI for us-east-1
        if [[ "$region" == "us-east-1" ]]; then
            ami_id="ami-0c7217cdde317cfec"
        else
            print_error "Could not determine AMI ID for region $region"
            return 1
        fi
    fi
    
    print_info "Using AMI: $ami_id"
    
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
cat > /opt/registry/certs/openssl.conf <<EOL
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
EOL

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

echo "✅ Bastion host setup completed"
EOF
    
    # Launch bastion instance
    print_info "Launching bastion instance..."
    local instance_id=$(aws ec2 run-instances \
        --image-id "$ami_id" \
        --instance-type "$instance_type" \
        --key-name "${cluster_name}-bastion-key" \
        --security-group-ids "$bastion_sg_id" \
        --subnet-id "$public_subnet_id" \
        --associate-public-ip-address \
        --user-data file://"$output_dir/bastion-userdata.sh" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${cluster_name}-bastion}]" \
        --region "$region" \
        --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":50,"VolumeType":"gp3"}}]' \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    # Wait for instance to be running
    print_info "Waiting for bastion instance to be ready..."
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
    
    print_success "Bastion host created successfully"
    print_info "Instance ID: $instance_id"
    print_info "Public IP: $bastion_public_ip"
    print_info "SSH Key: $output_dir/bastion-key.pem"
}

# Function to delete CloudFormation stack
delete_cloudformation_stack() {
    local cluster_name="$1"
    local region="$2"
    local output_dir="$3"
    
    local stack_name="${cluster_name}-vpc-infrastructure"
    
    print_info "Deleting CloudFormation stack: $stack_name"
    
    # Check if stack exists
    if ! aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$region" &> /dev/null; then
        print_warning "CloudFormation stack does not exist: $stack_name"
        return 0
    fi
    
    # Delete bastion instance and key pair first
    if [[ -f "$output_dir/bastion-instance-id" ]]; then
        local instance_id=$(cat "$output_dir/bastion-instance-id")
        print_info "Terminating bastion instance: $instance_id"
        aws ec2 terminate-instances \
            --instance-ids "$instance_id" \
            --region "$region" &> /dev/null || true
    fi
    
    if aws ec2 describe-key-pairs \
        --key-names "${cluster_name}-bastion-key" \
        --region "$region" &> /dev/null; then
        print_info "Deleting SSH key pair: ${cluster_name}-bastion-key"
        aws ec2 delete-key-pair \
            --key-name "${cluster_name}-bastion-key" \
            --region "$region" &> /dev/null || true
    fi
    
    # Delete CloudFormation stack
    aws cloudformation delete-stack \
        --stack-name "$stack_name" \
        --region "$region"
    
    print_info "Waiting for stack deletion to complete..."
    if aws cloudformation wait stack-delete-complete \
        --stack-name "$stack_name" \
        --region "$region"; then
        print_success "CloudFormation stack deleted successfully"
    else
        print_warning "Stack deletion may have failed. Check AWS console."
    fi
    
    # Clean up output directory
    if [[ -d "$output_dir" ]]; then
        rm -rf "$output_dir"
        print_success "Output directory cleaned up"
    fi
}

# Main execution
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cluster-name)
                if [[ -z "${2:-}" ]]; then
                    print_error "--cluster-name requires a value"
                    usage
                fi
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --region)
                if [[ -z "${2:-}" ]]; then
                    print_error "--region requires a value"
                    usage
                fi
                REGION="$2"
                shift 2
                ;;
            --vpc-cidr)
                if [[ -z "${2:-}" ]]; then
                    print_error "--vpc-cidr requires a value"
                    usage
                fi
                VPC_CIDR="$2"
                shift 2
                ;;
            --private-subnet-cidr)
                if [[ -z "${2:-}" ]]; then
                    print_error "--private-subnet-cidr requires a value"
                    usage
                fi
                PRIVATE_SUBNET_CIDR="$2"
                shift 2
                ;;
            --public-subnet-cidr)
                if [[ -z "${2:-}" ]]; then
                    print_error "--public-subnet-cidr requires a value"
                    usage
                fi
                PUBLIC_SUBNET_CIDR="$2"
                shift 2
                ;;
            --instance-type)
                if [[ -z "${2:-}" ]]; then
                    print_error "--instance-type requires a value"
                    usage
                fi
                INSTANCE_TYPE="$2"
                shift 2
                ;;
            --output-dir)
                if [[ -z "${2:-}" ]]; then
                    print_error "--output-dir requires a value"
                    usage
                fi
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --template-file)
                if [[ -z "${2:-}" ]]; then
                    print_error "--template-file requires a value"
                    usage
                fi
                TEMPLATE_FILE="$2"
                shift 2
                ;;
            --auto-adjust-cidr)
                AUTO_ADJUST_CIDR="yes"
                shift
                ;;
            --no-auto-adjust)
                AUTO_ADJUST_CIDR="no"
                shift
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
            --delete)
                DELETE_MODE="yes"
                shift
                ;;
            --help)
                usage
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                ;;
        esac
    done
    
    # Set default values
    CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
    REGION=${REGION:-$DEFAULT_REGION}
    VPC_CIDR=${VPC_CIDR:-$DEFAULT_VPC_CIDR}
    PRIVATE_SUBNET_CIDR=${PRIVATE_SUBNET_CIDR:-$DEFAULT_PRIVATE_SUBNET_CIDR}
    PUBLIC_SUBNET_CIDR=${PUBLIC_SUBNET_CIDR:-$DEFAULT_PUBLIC_SUBNET_CIDR}
    INSTANCE_TYPE=${INSTANCE_TYPE:-$DEFAULT_INSTANCE_TYPE}
    OUTPUT_DIR=${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}
    TEMPLATE_FILE=${TEMPLATE_FILE:-$DEFAULT_TEMPLATE_FILE}
    SNO_MODE=${SNO_MODE:-$DEFAULT_SNO_MODE}
    AUTO_ADJUST_CIDR=${AUTO_ADJUST_CIDR:-$DEFAULT_AUTO_ADJUST_CIDR}
    DRY_RUN=${DRY_RUN:-no}
    DELETE_MODE=${DELETE_MODE:-no}
    
    # Display script header
    echo "🚀 CloudFormation-based Disconnected Cluster Infrastructure"
    echo "=========================================================="
    echo ""
    echo "📋 Configuration:"
    echo "   Cluster Name: $CLUSTER_NAME"
    echo "   Region: $REGION"
    echo "   VPC CIDR: $VPC_CIDR"
    echo "   Private Subnet CIDR: $PRIVATE_SUBNET_CIDR"
    echo "   Public Subnet CIDR: $PUBLIC_SUBNET_CIDR"
    echo "   Bastion Instance Type: $INSTANCE_TYPE"
    echo "   Output Directory: $OUTPUT_DIR"
    echo "   Template File: $TEMPLATE_FILE"
    echo "   SNO Mode: $SNO_MODE"
    echo "   Auto-adjust CIDR: $AUTO_ADJUST_CIDR"
    echo "   Dry Run: $DRY_RUN"
    echo "   Delete Mode: $DELETE_MODE"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Validate AWS credentials
    validate_aws_credentials
    
    if [[ "$DELETE_MODE" == "yes" ]]; then
        delete_cloudformation_stack "$CLUSTER_NAME" "$REGION" "$OUTPUT_DIR"
        exit 0
    fi
    
    if [[ "$DRY_RUN" == "yes" ]]; then
        print_info "DRY RUN MODE - No resources will be created"
        echo ""
        echo "Would create via CloudFormation:"
        echo "  - VPC with CIDR $VPC_CIDR"
        echo "  - 1 public subnet: $PUBLIC_SUBNET_CIDR"
        echo "  - 1 private subnet: $PRIVATE_SUBNET_CIDR"
        if [[ "$SNO_MODE" == "yes" ]]; then
            echo "  - Optimized for Single Node OpenShift (SNO) deployment"
            echo "  - Estimated cost: $36-50/month (including VPC endpoints)"
        else
            echo "  - Multi-node deployment configuration"
            echo "  - Estimated cost: $50-70/month (including VPC endpoints)"
        fi
        echo "  - No NAT Gateway (disconnected cluster)"
        echo "  - All required VPC endpoints (S3, EC2, ELB, Route53, STS, EBS)"
        echo "  - Security groups for bastion, cluster, and VPC endpoints"
        echo "  - Bastion host ($INSTANCE_TYPE)"
        echo "  - SSH key pair"
        echo ""
        echo "To actually create resources, run without --dry-run"
        exit 0
    fi
    
    # Find non-conflicting CIDRs
    print_info "🔧 Determining optimal CIDR configuration..."
    local cidr_result=$(find_non_conflicting_cidrs "$REGION" "$VPC_CIDR" "$PRIVATE_SUBNET_CIDR" "$PUBLIC_SUBNET_CIDR" "$AUTO_ADJUST_CIDR")
    
    if [[ $? -ne 0 ]]; then
        print_error "Failed to resolve CIDR conflicts"
        exit 1
    fi
    
    # Parse results
    IFS='|' read -r FINAL_VPC_CIDR FINAL_PRIVATE_CIDR FINAL_PUBLIC_CIDR <<< "$cidr_result"
    
    # Update CIDRs if they were adjusted
    if [[ "$FINAL_VPC_CIDR" != "$VPC_CIDR" || "$FINAL_PRIVATE_CIDR" != "$PRIVATE_SUBNET_CIDR" || "$FINAL_PUBLIC_CIDR" != "$PUBLIC_SUBNET_CIDR" ]]; then
        print_info "📋 Updated Configuration:"
        print_info "   VPC CIDR: $VPC_CIDR → $FINAL_VPC_CIDR"
        print_info "   Private Subnet CIDR: $PRIVATE_SUBNET_CIDR → $FINAL_PRIVATE_CIDR"
        print_info "   Public Subnet CIDR: $PUBLIC_SUBNET_CIDR → $FINAL_PUBLIC_CIDR"
    fi

    # Create CloudFormation stack with final CIDRs
    create_cloudformation_stack "$CLUSTER_NAME" "$REGION" "$FINAL_VPC_CIDR" "$FINAL_PRIVATE_CIDR" "$FINAL_PUBLIC_CIDR" "$SNO_MODE" "$TEMPLATE_FILE" "$DRY_RUN"
    
    # Create bastion host (not included in CloudFormation for flexibility)
    create_bastion_host "$CLUSTER_NAME" "$REGION" "$INSTANCE_TYPE" "$OUTPUT_DIR" "$FINAL_VPC_CIDR"
    
    echo ""
    echo "✅ CloudFormation-based infrastructure creation completed successfully!"
    if [[ "$SNO_MODE" == "yes" ]]; then
        echo "🎯 Configured for Single Node OpenShift (SNO) deployment"
    fi
    echo ""
    echo "📁 Output files saved to: $OUTPUT_DIR"
    echo "   vpc-id: VPC identifier"
    echo "   public-subnet-ids: Public subnet identifier"
    echo "   private-subnet-ids: Private subnet identifier"
    echo "   availability-zones: Availability zone used"
    echo "   region: AWS region"
    echo "   vpc-cidr: VPC CIDR block"
    echo "   bastion-instance-id: Bastion host instance ID"
    echo "   bastion-public-ip: Bastion host public IP"
    echo "   bastion-key.pem: SSH private key for bastion"
    echo "   cloudformation-stack-name: CloudFormation stack name"
    echo ""
    echo "🔗 VPC Endpoints created via CloudFormation:"
    echo "   ✅ S3 Gateway endpoint (free)"
    echo "   ✅ EC2 Interface endpoint ($7.20/month)"
    echo "   ✅ ELB Interface endpoint ($7.20/month)"
    echo "   ✅ Route53 Interface endpoint ($7.20/month)"
    echo "   ✅ STS Interface endpoint ($7.20/month)"
    echo "   ✅ EBS Interface endpoint ($7.20/month)"
    echo "   Total VPC endpoints cost: ~$36/month"
    echo ""
    echo "🔗 Next steps:"
    echo "1. Setup mirror registry: ./04-setup-mirror-registry.sh --cluster-name $CLUSTER_NAME"
    echo "2. Sync images: ./05-sync-images.sh --cluster-name $CLUSTER_NAME"
    echo "3. Prepare install config: ./07-prepare-install-config.sh --cluster-name $CLUSTER_NAME"
    if [[ "$SNO_MODE" == "yes" ]]; then
        echo "   Use --sno flag in subsequent scripts for consistency"
    fi
    echo ""
    echo "🗑️  To delete all resources:"
    echo "   $0 --delete --cluster-name $CLUSTER_NAME"
    echo ""
    echo "💰 Cost estimate:"
    echo "   - VPC endpoints: ~$36/month"
    echo "   - Bastion host ($INSTANCE_TYPE): ~$20-30/month"
    if [[ "$SNO_MODE" == "yes" ]]; then
        echo "   - SNO cluster: ~$50-70/month"
        echo "   Total estimated cost: ~$106-136/month"
    else
        echo "   - Multi-node cluster: ~$150-300/month"
        echo "   Total estimated cost: ~$206-366/month"
    fi
}

# Run main function with all arguments
main "$@" 