#!/bin/bash

# Bastion Host Creation Script for Disconnected Cluster
# Creates bastion host and cluster security group

set -eo pipefail

# Default values
DEFAULT_CLUSTER_NAME="disconnected-cluster"
DEFAULT_REGION="us-east-1"
DEFAULT_INSTANCE_TYPE="t3.large"
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
    echo "  --instance-type       Bastion instance type (default: $DEFAULT_INSTANCE_TYPE)"
    echo "  --output-dir          Output directory (default: $DEFAULT_OUTPUT_DIR)"
    echo "  --sno                 Enable Single Node OpenShift (SNO) mode (default: enabled)"
    echo "  --no-sno              Disable SNO mode for multi-node deployment"
    echo "  --dry-run             Show what would be created without actually creating"
    echo "  --delete              Delete bastion host and related resources"
    echo "  --help                Display this help message"
    echo ""
    echo "Prerequisites:"
    echo "  - VPC infrastructure must already exist (run 01-create-infrastructure.sh first)"
    echo "  - Output directory must contain vpc-id, public-subnet-ids, and vpc-cidr files"
    echo ""
    echo "Examples:"
    echo "  $0 --cluster-name my-disconnected-cluster"
    echo "  $0 --sno --instance-type t3.large"
    echo "  $0 --dry-run"
    exit 1
}

# Function to check if required tools are available
check_prerequisites() {
    local missing_tools=()
    
    for tool in aws jq openssl; do
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

# Function to validate infrastructure prerequisites
validate_infrastructure() {
    local output_dir="$1"
    
    if [[ ! -d "$output_dir" ]]; then
        echo "❌ Output directory does not exist: $output_dir"
        echo "Please run 01-create-infrastructure.sh first to create VPC infrastructure"
        exit 1
    fi
    
    local required_files=("vpc-id" "public-subnet-ids" "vpc-cidr")
    for file in "${required_files[@]}"; do
        if [[ ! -f "$output_dir/$file" ]]; then
            echo "❌ Required file missing: $output_dir/$file"
            echo "Please run 01-create-infrastructure.sh first to create VPC infrastructure"
            exit 1
        fi
    done
    
    echo "✅ Infrastructure prerequisites validated"
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
    
    # Check if bastion security group already exists
    echo "   Checking for existing bastion security group..."
    local bastion_sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${cluster_name}-bastion-sg" "Name=vpc-id,Values=$vpc_id" \
        --region "$region" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null)
    
    if [[ "$bastion_sg_id" == "None" || -z "$bastion_sg_id" ]]; then
        echo "   Creating bastion security group..."
        bastion_sg_id=$(aws ec2 create-security-group \
            --group-name "${cluster_name}-bastion-sg" \
            --description "Security group for bastion host" \
            --vpc-id "$vpc_id" \
            --region "$region" \
            --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${cluster_name}-bastion-sg}]" \
            --query 'GroupId' \
            --output text)
        echo "   ✅ Created bastion security group: $bastion_sg_id"
        
        # Configure security group rules for new security group
        echo "   Configuring security group rules..."
        aws ec2 authorize-security-group-ingress \
            --group-id "$bastion_sg_id" \
            --protocol tcp \
            --port 22 \
            --cidr 0.0.0.0/0 \
            --region "$region" \
            --output json
        
        # Allow HTTP/HTTPS for registry access
        aws ec2 authorize-security-group-ingress \
            --group-id "$bastion_sg_id" \
            --protocol tcp \
            --port 80 \
            --cidr 0.0.0.0/0 \
            --region "$region" \
            --output json
        
        aws ec2 authorize-security-group-ingress \
            --group-id "$bastion_sg_id" \
            --protocol tcp \
            --port 443 \
            --cidr 0.0.0.0/0 \
            --region "$region" \
            --output json
        
        # Allow registry port from VPC only (not from internet)
        aws ec2 authorize-security-group-ingress \
            --group-id "$bastion_sg_id" \
            --protocol tcp \
            --port 5000 \
            --cidr "$vpc_cidr" \
            --region "$region" \
            --output json
    else
        echo "   ✅ Using existing bastion security group: $bastion_sg_id"
        echo "   Skipping security group rule configuration (already exists)"
    fi
    
    # Check if SSH key pair already exists
    echo "   Checking for existing SSH key pair..."
    local key_exists=$(aws ec2 describe-key-pairs \
        --key-names "${cluster_name}-bastion-key" \
        --region "$region" \
        --query 'KeyPairs[0].KeyName' \
        --output text 2>/dev/null)
    
    if [[ "$key_exists" == "None" || -z "$key_exists" ]] && [[ ! -f "$output_dir/bastion-key.pem" ]]; then
        echo "   Creating SSH key pair..."
        aws ec2 create-key-pair \
            --key-name "${cluster_name}-bastion-key" \
            --region "$region" \
            --query 'KeyMaterial' \
            --output text > "$output_dir/bastion-key.pem"
        
        chmod 600 "$output_dir/bastion-key.pem"
        echo "   ✅ Created SSH key pair"
    else
        echo "   ✅ SSH key pair already exists"
        if [[ -f "$output_dir/bastion-key.pem" ]]; then
            chmod 600 "$output_dir/bastion-key.pem"
        fi
    fi
    
    # Get latest Ubuntu 22.04 AMI
    echo "   Getting latest Ubuntu 22.04 AMI..."
    local ami_id=$(aws ec2 describe-images \
        --owners 099720109477 \
        --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text \
        --region "$region" 2>/dev/null)
    
    if [[ -z "$ami_id" || "$ami_id" == "None" ]]; then
        echo "   Failed to get Ubuntu AMI, trying Amazon Linux 2..."
        ami_id=$(aws ec2 describe-images \
            --owners amazon \
            --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
            --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
            --output text \
            --region "$region" 2>/dev/null)
        
        if [[ -z "$ami_id" || "$ami_id" == "None" ]]; then
            echo "   Using fallback AMI..."
            ami_id="ami-0c7217cdde317cfec"  # Amazon Linux 2 fallback
        fi
    fi
    
    echo "   Using AMI: $ami_id"
    
    # Create user data script for bastion host
    cat > "$output_dir/bastion-userdata.sh" << 'EOF'
#!/bin/bash
apt-get update -y
apt-get install -y docker.io git wget curl jq

# Install oc client
wget -O /tmp/openshift-client-linux.tar.gz https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz
tar -xzf /tmp/openshift-client-linux.tar.gz -C /usr/local/bin/
chmod +x /usr/local/bin/oc /usr/local/bin/kubectl

# Start and enable Docker
systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu

# Create directories for registry
mkdir -p /opt/registry/{auth,certs,data}
chown -R ubuntu:ubuntu /opt/registry

# Create self-signed certificate directory structure
mkdir -p /opt/registry/certs
chown -R ubuntu:ubuntu /opt/registry/certs

# Install docker-compose
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

echo "Bastion host setup completed" > /var/log/bastion-setup.log
EOF
    
    # Get first public subnet
    local first_public_subnet=$(echo "$public_subnet_ids" | cut -d',' -f1)
    
    # Check if bastion instance already exists
    echo "   Checking for existing bastion instance..."
    local existing_instance=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=${cluster_name}-bastion" "Name=instance-state-name,Values=running,pending" \
        --region "$region" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null)
    
    local instance_id=""
    local public_ip=""
    
    if [[ "$existing_instance" == "None" || -z "$existing_instance" ]]; then
        echo "   Launching bastion instance..."
        instance_id=$(aws ec2 run-instances \
            --image-id "$ami_id" \
            --count 1 \
            --instance-type "$instance_type" \
            --key-name "${cluster_name}-bastion-key" \
            --security-group-ids "$bastion_sg_id" \
            --subnet-id "$first_public_subnet" \
            --user-data "file://$output_dir/bastion-userdata.sh" \
            --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":50,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${cluster_name}-bastion}]" \
            --region "$region" \
            --query 'Instances[0].InstanceId' \
            --output text)
        
        echo "   Waiting for instance to be running..."
        aws ec2 wait instance-running \
            --instance-ids "$instance_id" \
            --region "$region"
        
        echo "   ✅ Created bastion instance: $instance_id"
    else
        instance_id="$existing_instance"
        echo "   ✅ Using existing bastion instance: $instance_id"
    fi
    
    # Get public IP
    public_ip=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$region" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    # Save bastion information
    echo "$instance_id" > "$output_dir/bastion-instance-id"
    echo "$public_ip" > "$output_dir/bastion-public-ip"
    echo "$bastion_sg_id" > "$output_dir/bastion-security-group-id"
    
    echo "✅ Bastion host created successfully"
    echo "   Instance ID: $instance_id"
    echo "   Public IP: $public_ip"
    echo "   Security Group: $bastion_sg_id"
}

# Function to delete bastion host and related resources
delete_bastion_host() {
    local cluster_name="$1"
    local region="$2"
    local output_dir="$3"
    
    echo "🗑️  Deleting bastion host and related resources..."
    
    # Check if output directory exists
    if [[ ! -d "$output_dir" ]]; then
        echo "❌ Output directory does not exist: $output_dir"
        echo "Nothing to delete"
        return 0
    fi
    
    # Delete bastion instance if exists
    if [[ -f "$output_dir/bastion-instance-id" ]]; then
        local instance_id=$(cat "$output_dir/bastion-instance-id")
        echo "   Terminating bastion instance: $instance_id"
        
        # Check if instance exists and is not already terminated
        local instance_state=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --region "$region" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || echo "not-found")
        
        if [[ "$instance_state" != "not-found" && "$instance_state" != "terminated" && "$instance_state" != "terminating" ]]; then
            aws ec2 terminate-instances \
                --instance-ids "$instance_id" \
                --region "$region" \
                --output table
            echo "   ✅ Instance termination initiated"
            
            # Wait for instance to be terminated
            echo "   Waiting for instance to terminate..."
            aws ec2 wait instance-terminated \
                --instance-ids "$instance_id" \
                --region "$region"
            echo "   ✅ Instance terminated"
        else
            echo "   ℹ️  Instance is already terminated or not found"
        fi
        
        rm -f "$output_dir/bastion-instance-id"
        rm -f "$output_dir/bastion-public-ip"
    else
        echo "   ℹ️  No bastion instance ID found"
    fi
    
    # Delete cluster security group first (it may reference bastion security group)
    if [[ -f "$output_dir/cluster-security-group-id" ]]; then
        local cluster_sg_id=$(cat "$output_dir/cluster-security-group-id")
        echo "   Deleting cluster security group: $cluster_sg_id"
        
        # Check if security group exists
        local cluster_sg_exists=$(aws ec2 describe-security-groups \
            --group-ids "$cluster_sg_id" \
            --region "$region" \
            --query 'SecurityGroups[0].GroupId' \
            --output text 2>/dev/null || echo "not-found")
        
        if [[ "$cluster_sg_exists" != "not-found" ]]; then
            # Remove all rules from cluster security group first
            echo "   Removing all ingress rules from cluster security group..."
            local cluster_rules=$(aws ec2 describe-security-groups \
                --group-ids "$cluster_sg_id" \
                --region "$region" \
                --query 'SecurityGroups[0].IpPermissions' \
                --output json)
            
            if [[ "$cluster_rules" != "[]" && "$cluster_rules" != "null" ]]; then
                aws ec2 revoke-security-group-ingress \
                    --group-id "$cluster_sg_id" \
                    --ip-permissions "$cluster_rules" \
                    --region "$region" 2>/dev/null || true
                echo "   ✅ Removed all ingress rules from cluster security group"
            fi
            
            # Remove all egress rules (except default)
            local cluster_egress=$(aws ec2 describe-security-groups \
                --group-ids "$cluster_sg_id" \
                --region "$region" \
                --query 'SecurityGroups[0].IpPermissionsEgress[?!(IpProtocol==`-1` && IpRanges[0].CidrIp==`0.0.0.0/0`)]' \
                --output json)
            
            if [[ "$cluster_egress" != "[]" && "$cluster_egress" != "null" ]]; then
                aws ec2 revoke-security-group-egress \
                    --group-id "$cluster_sg_id" \
                    --ip-permissions "$cluster_egress" \
                    --region "$region" 2>/dev/null || true
                echo "   ✅ Removed custom egress rules from cluster security group"
            fi
            
            # Now try to delete the cluster security group
            if aws ec2 delete-security-group \
                --group-id "$cluster_sg_id" \
                --region "$region" 2>/dev/null; then
                echo "   ✅ Cluster security group deleted"
            else
                echo "   ⚠️  Could not delete cluster security group (may have remaining dependencies)"
                echo "   You may need to manually clean up security group: $cluster_sg_id"
            fi
        else
            echo "   ℹ️  Cluster security group not found"
        fi
        
        rm -f "$output_dir/cluster-security-group-id"
    else
        echo "   ℹ️  No cluster security group ID found"
    fi
    
    # Delete bastion security group if exists
    if [[ -f "$output_dir/bastion-security-group-id" ]]; then
        local sg_id=$(cat "$output_dir/bastion-security-group-id")
        echo "   Deleting bastion security group: $sg_id"
        
        # Check if security group exists
        local sg_exists=$(aws ec2 describe-security-groups \
            --group-ids "$sg_id" \
            --region "$region" \
            --query 'SecurityGroups[0].GroupId' \
            --output text 2>/dev/null || echo "not-found")
        
        if [[ "$sg_exists" != "not-found" ]]; then
            # Remove all rules from bastion security group first
            echo "   Removing all ingress rules from bastion security group..."
            local bastion_rules=$(aws ec2 describe-security-groups \
                --group-ids "$sg_id" \
                --region "$region" \
                --query 'SecurityGroups[0].IpPermissions' \
                --output json)
            
            if [[ "$bastion_rules" != "[]" && "$bastion_rules" != "null" ]]; then
                aws ec2 revoke-security-group-ingress \
                    --group-id "$sg_id" \
                    --ip-permissions "$bastion_rules" \
                    --region "$region" 2>/dev/null || true
                echo "   ✅ Removed all ingress rules from bastion security group"
            fi
            
            # Remove all egress rules (except default)
            local bastion_egress=$(aws ec2 describe-security-groups \
                --group-ids "$sg_id" \
                --region "$region" \
                --query 'SecurityGroups[0].IpPermissionsEgress[?!(IpProtocol==`-1` && IpRanges[0].CidrIp==`0.0.0.0/0`)]' \
                --output json)
            
            if [[ "$bastion_egress" != "[]" && "$bastion_egress" != "null" ]]; then
                aws ec2 revoke-security-group-egress \
                    --group-id "$sg_id" \
                    --ip-permissions "$bastion_egress" \
                    --region "$region" 2>/dev/null || true
                echo "   ✅ Removed custom egress rules from bastion security group"
            fi
            
            # Also remove any rules from other security groups that reference this bastion security group
            echo "   Removing security group rule dependencies..."
            
            # Find all security groups that reference this bastion security group
            local referencing_sgs=$(aws ec2 describe-security-groups \
                --region "$region" \
                --query "SecurityGroups[?IpPermissions[?UserIdGroupPairs[?GroupId=='$sg_id']]].GroupId" \
                --output text)
            
            if [[ -n "$referencing_sgs" && "$referencing_sgs" != "None" ]]; then
                for ref_sg in $referencing_sgs; do
                    echo "   Removing rules from security group $ref_sg that reference $sg_id"
                    
                    # Get the rules that reference our security group
                    local rules=$(aws ec2 describe-security-groups \
                        --group-ids "$ref_sg" \
                        --region "$region" \
                        --query "SecurityGroups[0].IpPermissions[?UserIdGroupPairs[?GroupId=='$sg_id']]" \
                        --output json)
                    
                    if [[ "$rules" != "[]" && "$rules" != "null" ]]; then
                        # Remove the rules
                        aws ec2 revoke-security-group-ingress \
                            --group-id "$ref_sg" \
                            --ip-permissions "$rules" \
                            --region "$region" 2>/dev/null || true
                        echo "   ✅ Removed ingress rules from $ref_sg"
                    fi
                done
            fi
            
            # Now try to delete the bastion security group
            if aws ec2 delete-security-group \
                --group-id "$sg_id" \
                --region "$region" 2>/dev/null; then
                echo "   ✅ Bastion security group deleted"
            else
                echo "   ⚠️  Could not delete bastion security group (may have remaining dependencies)"
                echo "   You may need to manually clean up security group: $sg_id"
            fi
        else
            echo "   ℹ️  Bastion security group not found"
        fi
        
        rm -f "$output_dir/bastion-security-group-id"
    else
        echo "   ℹ️  No bastion security group ID found"
    fi
    
    # Delete SSH key pair if exists
    local key_name="${cluster_name}-bastion-key"
    echo "   Deleting SSH key pair: $key_name"
    
    local key_exists=$(aws ec2 describe-key-pairs \
        --key-names "$key_name" \
        --region "$region" \
        --query 'KeyPairs[0].KeyName' \
        --output text 2>/dev/null || echo "not-found")
    
    if [[ "$key_exists" != "not-found" ]]; then
        aws ec2 delete-key-pair \
            --key-name "$key_name" \
            --region "$region"
        echo "   ✅ SSH key pair deleted from AWS"
    else
        echo "   ℹ️  SSH key pair not found in AWS"
    fi
    
    # Remove local SSH key file
    if [[ -f "$output_dir/bastion-key.pem" ]]; then
        rm -f "$output_dir/bastion-key.pem"
        echo "   ✅ Local SSH key file removed"
    else
        echo "   ℹ️  No local SSH key file found"
    fi
    
    echo ""
    echo "✅ Bastion host deletion completed!"
    echo ""
    echo "🧹 Cleaned up resources:"
    echo "   - Bastion EC2 instance"
    echo "   - Bastion security group"
    echo "   - Cluster security group"
    echo "   - SSH key pair (AWS and local file)"
    echo ""
    echo "ℹ️  VPC infrastructure remains intact"
    echo "   To recreate bastion host, run: $0 --cluster-name $cluster_name"
}

# Function to create cluster security group
create_cluster_security_group() {
    local cluster_name="$1"
    local region="$2"
    local vpc_id="$3"
    local output_dir="$4"
    local sno_mode="$5"
    
    echo "🏗️  Creating cluster security group..."
    
    # Create cluster security group
    local cluster_sg_id=$(aws ec2 create-security-group \
        --group-name "${cluster_name}-cluster-sg" \
        --description "Security group for OpenShift cluster nodes" \
        --vpc-id "$vpc_id" \
        --region "$region" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${cluster_name}-cluster-sg}]" \
        --query 'GroupId' \
        --output text)
    
    # Allow all traffic within the security group (cluster internal communication)
    aws ec2 authorize-security-group-ingress \
        --group-id "$cluster_sg_id" \
        --protocol all \
        --source-group "$cluster_sg_id" \
        --region "$region"
    
    # Get bastion security group ID (should be available from the create_bastion_host function)
    local bastion_sg_id_from_file=""
    if [[ -f "$output_dir/bastion-security-group-id" ]]; then
        bastion_sg_id_from_file=$(cat "$output_dir/bastion-security-group-id")
    fi
    
    # Use the bastion_sg_id from the function parameter or from file
    local bastion_sg_for_cluster="$bastion_sg_id_from_file"
    
    if [[ "$sno_mode" == "yes" ]]; then
        echo "   Configuring security group for SNO deployment..."
        # SNO-specific rules: Allow API server access from bastion
        
        # API server (6443) from bastion
        aws ec2 authorize-security-group-ingress \
            --group-id "$cluster_sg_id" \
            --protocol tcp \
            --port 6443 \
            --source-group "$bastion_sg_for_cluster" \
            --region "$region"
        
        # Machine config server (22623) from bastion
        aws ec2 authorize-security-group-ingress \
            --group-id "$cluster_sg_id" \
            --protocol tcp \
            --port 22623 \
            --source-group "$bastion_sg_for_cluster" \
            --region "$region"
    else
        echo "   Configuring security group for multi-node deployment..."
        # Multi-node specific rules
        
        # API server (6443) from bastion
        aws ec2 authorize-security-group-ingress \
            --group-id "$cluster_sg_id" \
            --protocol tcp \
            --port 6443 \
            --source-group "$bastion_sg_for_cluster" \
            --region "$region"
        
        # Machine config server (22623) from bastion
        aws ec2 authorize-security-group-ingress \
            --group-id "$cluster_sg_id" \
            --protocol tcp \
            --port 22623 \
            --source-group "$bastion_sg_for_cluster" \
            --region "$region"
    fi
    
    # Allow registry access from cluster nodes
    aws ec2 authorize-security-group-ingress \
        --group-id "$bastion_sg_for_cluster" \
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
            --delete)
                DELETE_MODE="yes"
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
    INSTANCE_TYPE=${INSTANCE_TYPE:-$DEFAULT_INSTANCE_TYPE}
    OUTPUT_DIR=${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}
    DRY_RUN=${DRY_RUN:-no}
    DELETE_MODE=${DELETE_MODE:-no}
    SNO_MODE=${SNO_MODE:-$DEFAULT_SNO_MODE}
    
    # Display script header
    echo "🚀 Disconnected Cluster Bastion Host Creation"
    echo "============================================="
    echo ""
    echo "📋 Configuration:"
    echo "   Cluster Name: $CLUSTER_NAME"
    echo "   Region: $REGION"
    echo "   Bastion Instance Type: $INSTANCE_TYPE"
    echo "   Output Directory: $OUTPUT_DIR"
    echo "   Dry Run: $DRY_RUN"
    echo "   Delete Mode: $DELETE_MODE"
    echo "   SNO Mode: $SNO_MODE"
    echo ""
    
    # Handle delete mode
    if [[ "$DELETE_MODE" == "yes" ]]; then
        echo "🗑️  DELETE MODE - Removing bastion host and related resources"
        echo ""
        
        # Check prerequisites for deletion
        check_prerequisites
        validate_aws_credentials
        
        # Delete bastion host
        delete_bastion_host "$CLUSTER_NAME" "$REGION" "$OUTPUT_DIR"
        exit 0
    fi
    
    if [[ "$DRY_RUN" == "yes" ]]; then
        echo "🔍 DRY RUN MODE - No resources will be created"
        echo ""
        echo "Would create:"
        echo "  - Bastion host ($INSTANCE_TYPE)"
        echo "  - Bastion security group"
        echo "  - Cluster security group"
        echo "  - SSH key pair"
        if [[ "$SNO_MODE" == "yes" ]]; then
            echo "  - SNO-optimized security group rules"
        else
            echo "  - Multi-node security group rules"
        fi
        echo ""
        echo "To actually create resources, run without --dry-run"
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Validate AWS credentials
    validate_aws_credentials
    
    # Validate infrastructure prerequisites
    validate_infrastructure "$OUTPUT_DIR"
    
    # Read infrastructure information
    local vpc_id=$(cat "$OUTPUT_DIR/vpc-id")
    local public_subnet_ids=$(cat "$OUTPUT_DIR/public-subnet-ids")
    local vpc_cidr=$(cat "$OUTPUT_DIR/vpc-cidr")
    
    echo "📖 Using existing infrastructure:"
    echo "   VPC ID: $vpc_id"
    echo "   Public Subnets: $public_subnet_ids"
    echo "   VPC CIDR: $vpc_cidr"
    echo ""
    
    # Create bastion host
    create_bastion_host "$CLUSTER_NAME" "$REGION" "$vpc_id" "$public_subnet_ids" "$INSTANCE_TYPE" "$OUTPUT_DIR" "$vpc_cidr"
    
    # Create cluster security group
    create_cluster_security_group "$CLUSTER_NAME" "$REGION" "$vpc_id" "$OUTPUT_DIR" "$SNO_MODE"
    
    echo ""
    echo "✅ Bastion host creation completed successfully!"
    if [[ "$SNO_MODE" == "yes" ]]; then
        echo "🎯 Configured for Single Node OpenShift (SNO) deployment"
    fi
    echo ""
    echo "📁 Output files saved to: $OUTPUT_DIR"
    echo "   bastion-instance-id: Bastion host instance ID"
    echo "   bastion-public-ip: Bastion host public IP"
    echo "   bastion-key.pem: SSH private key for bastion access"
    echo "   bastion-security-group-id: Bastion security group ID"
    echo "   cluster-security-group-id: Cluster security group ID"
    echo ""
    echo "🔗 Next steps:"
    echo "1. Connect to bastion host: ssh -i $OUTPUT_DIR/bastion-key.pem ubuntu@$(cat $OUTPUT_DIR/bastion-public-ip)"
    echo "2. Run: ./02-setup-mirror-registry.sh --cluster-name $CLUSTER_NAME"
    if [[ "$SNO_MODE" == "yes" ]]; then
        echo "   Use --sno flag for SNO-optimized configuration"
    fi
    echo ""
    echo "⚠️  Important:"
    echo "   - Keep the SSH key file secure: $OUTPUT_DIR/bastion-key.pem"
    echo "   - The bastion host is accessible from the internet"
    echo "   - Wait a few minutes for the bastion host to complete initialization"
}

# Run main function with all arguments
main "$@" 