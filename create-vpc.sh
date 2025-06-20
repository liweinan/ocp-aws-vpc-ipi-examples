#!/bin/bash

# Enhanced VPC Creation Script for AWS
# Combines features from CI operator and automation scripts
# Supports multiple AZs, shared VPC, and comprehensive output

set -euo pipefail

# Default values
DEFAULT_REGION="us-east-1"
DEFAULT_VPC_CIDR="10.0.0.0/16"
DEFAULT_CLUSTER_NAME="my-cluster"
DEFAULT_AVAILABILITY_ZONE_COUNT=3
DEFAULT_SUBNET_BITS=12
DEFAULT_INSTANCE_TYPE="t3.micro"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --region                    AWS region (default: $DEFAULT_REGION)"
    echo "  --vpc-cidr                 VPC CIDR block (default: $DEFAULT_VPC_CIDR)"
    echo "  --cluster-name             Cluster name for tagging (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --availability-zone-count  Number of AZs (1-3, default: $DEFAULT_AVAILABILITY_ZONE_COUNT)"
    echo "  --subnet-bits              Subnet size bits (5-13, default: $DEFAULT_SUBNET_BITS)"
    echo "  --zones-list               Comma-separated list of specific AZs (e.g., us-east-1a,us-east-1b)"
    echo "  --public-only              Create only public subnets (no private subnets)"
    echo "  --shared-vpc               Enable shared VPC with resource sharing"
    echo "  --resource-share-principals AWS account IDs for resource sharing"
    echo "  --additional-subnets       Create additional subnets in same AZ (0-1, default: 0)"
    echo "  --dhcp-options             Create custom DHCP options with domain name"
    echo "  --output-dir               Directory to save outputs (default: ./vpc-output)"
    echo "  --help                     Display this help message"
    exit 1
}

# Function to validate CIDR format
validate_cidr() {
    local cidr="$1"
    if [[ ! "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([1-9]|[12][0-9]|3[0-2])$ ]]; then
        echo "Error: Invalid CIDR format: $cidr"
        exit 1
    fi
}

# Function to validate AWS credentials
validate_aws_credentials() {
    if ! command -v aws &> /dev/null; then
        echo "Error: AWS CLI is not installed"
        exit 1
    fi

    # Build AWS CLI command with profile if set
    local aws_cmd="aws"
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        aws_cmd="aws --profile ${AWS_PROFILE}"
    fi

    if ! $aws_cmd sts get-caller-identity &> /dev/null; then
        echo "Error: AWS credentials not configured"
        exit 1
    fi
}

# Function to get available AZs
get_available_azs() {
    local region="$1"
    local max_count="$2"
    
    # Build AWS CLI command with profile if set
    local aws_cmd="aws"
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        aws_cmd="aws --profile ${AWS_PROFILE}"
    fi
    
    $aws_cmd --region "$region" ec2 describe-availability-zones \
        --filter Name=state,Values=available Name=zone-type,Values=availability-zone \
        --query "AvailabilityZones[0:${max_count}].ZoneName" \
        --output text | tr '\t' '\n'
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
        --availability-zone-count)
            AVAILABILITY_ZONE_COUNT="$2"
            shift 2
            ;;
        --subnet-bits)
            SUBNET_BITS="$2"
            shift 2
            ;;
        --zones-list)
            ZONES_LIST="$2"
            shift 2
            ;;
        --public-only)
            PUBLIC_ONLY="yes"
            shift
            ;;
        --shared-vpc)
            SHARED_VPC="yes"
            shift
            ;;
        --resource-share-principals)
            RESOURCE_SHARE_PRINCIPALS="$2"
            shift 2
            ;;
        --additional-subnets)
            ADDITIONAL_SUBNETS_COUNT="$2"
            shift 2
            ;;
        --dhcp-options)
            DHCP_OPTIONS="yes"
            shift
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
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
AVAILABILITY_ZONE_COUNT=${AVAILABILITY_ZONE_COUNT:-$DEFAULT_AVAILABILITY_ZONE_COUNT}
SUBNET_BITS=${SUBNET_BITS:-$DEFAULT_SUBNET_BITS}
ADDITIONAL_SUBNETS_COUNT=${ADDITIONAL_SUBNETS_COUNT:-0}
OUTPUT_DIR=${OUTPUT_DIR:-./vpc-output}

# Validate inputs
validate_cidr "$VPC_CIDR"
validate_aws_credentials

# Validate AZ count
if [[ "$AVAILABILITY_ZONE_COUNT" -lt 1 || "$AVAILABILITY_ZONE_COUNT" -gt 3 ]]; then
    echo "Error: Availability zone count must be between 1 and 3"
    exit 1
fi

# Validate subnet bits
if [[ "$SUBNET_BITS" -lt 5 || "$SUBNET_BITS" -gt 13 ]]; then
    echo "Error: Subnet bits must be between 5 and 13"
    exit 1
fi

# Get available AZs if not specified
if [[ -z "${ZONES_LIST:-}" ]]; then
    ZONES_LIST=$(get_available_azs "$REGION" "$AVAILABILITY_ZONE_COUNT" | tr '\n' ',')
    ZONES_LIST=${ZONES_LIST%,}
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Generate unique stack name
STACK_NAME="${CLUSTER_NAME}-vpc-$(date +%s)"

echo "🚀 Starting VPC creation..."
echo "📋 Configuration:"
echo "   Region: ${REGION}"
echo "   VPC CIDR: ${VPC_CIDR}"
echo "   Cluster Name: ${CLUSTER_NAME}"
echo "   AZ Count: ${AVAILABILITY_ZONE_COUNT}"
echo "   Subnet Bits: ${SUBNET_BITS}"
echo "   Zones: ${ZONES_LIST}"
echo "   Public Only: ${PUBLIC_ONLY:-no}"
echo "   Shared VPC: ${SHARED_VPC:-no}"
echo "   Output Dir: ${OUTPUT_DIR}"
echo ""

# Create CloudFormation template
echo "📝 Creating CloudFormation template..."
cp vpc-template.yaml "$OUTPUT_DIR/vpc-template.yaml"

# Create parameters file
echo "📋 Creating parameters file..."
cat > "$OUTPUT_DIR/vpc-params.json" <<EOF
[
  {
    "ParameterKey": "VpcCidr",
    "ParameterValue": "${VPC_CIDR}"
  },
  {
    "ParameterKey": "AvailabilityZoneCount",
    "ParameterValue": "${AVAILABILITY_ZONE_COUNT}"
  },
  {
    "ParameterKey": "SubnetBits",
    "ParameterValue": "${SUBNET_BITS}"
  },
  {
    "ParameterKey": "DhcpOptionSet",
    "ParameterValue": "${DHCP_OPTIONS:-no}"
  },
  {
    "ParameterKey": "OnlyPublicSubnets",
    "ParameterValue": "${PUBLIC_ONLY:-no}"
  },
  {
    "ParameterKey": "AllowedAvailabilityZoneList",
    "ParameterValue": "${ZONES_LIST}"
  },
  {
    "ParameterKey": "ResourceSharePrincipals",
    "ParameterValue": "${RESOURCE_SHARE_PRINCIPALS:-}"
  },
  {
    "ParameterKey": "AdditionalSubnetsCount",
    "ParameterValue": "${ADDITIONAL_SUBNETS_COUNT}"
  }
]
EOF

# Create VPC stack
echo "🏗️  Creating VPC stack: ${STACK_NAME}"
echo "📍 Region: ${REGION}"
echo "🌐 VPC CIDR: ${VPC_CIDR}"
echo "🏢 Availability Zones: ${ZONES_LIST}"
echo "🌍 Public Only: ${PUBLIC_ONLY:-no}"
echo "🤝 Shared VPC: ${SHARED_VPC:-no}"
echo ""

# Build AWS CLI command with profile if set
AWS_CMD="aws"
if [[ -n "${AWS_PROFILE:-}" ]]; then
    AWS_CMD="aws --profile ${AWS_PROFILE}"
fi

$AWS_CMD cloudformation create-stack \
    --region "${REGION}" \
    --stack-name "${STACK_NAME}" \
    --template-body "file://${OUTPUT_DIR}/vpc-template.yaml" \
    --parameters "file://${OUTPUT_DIR}/vpc-params.json" \
    --capabilities CAPABILITY_IAM \
    --tags Key=Name,Value="${STACK_NAME}" Key=CreatedBy,Value="Enhanced-VPC-Script" Key=ClusterName,Value="${CLUSTER_NAME}"

echo "⏳ Waiting for stack creation to complete..."
$AWS_CMD cloudformation wait stack-create-complete \
    --region "${REGION}" \
    --stack-name "${STACK_NAME}"

# Get stack outputs
echo "📊 Getting stack outputs..."
$AWS_CMD cloudformation describe-stacks \
    --region "${REGION}" \
    --stack-name "${STACK_NAME}" > "$OUTPUT_DIR/stack-output.json"

# Extract key information
VPC_ID=$(jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="VpcId") | .OutputValue' "$OUTPUT_DIR/stack-output.json")
PUBLIC_SUBNET_IDS=$(jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="PublicSubnetIds") | .OutputValue' "$OUTPUT_DIR/stack-output.json")
PRIVATE_SUBNET_IDS=$(jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="PrivateSubnetIds") | .OutputValue' "$OUTPUT_DIR/stack-output.json")
AVAILABILITY_ZONES=$(jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="AvailabilityZones") | .OutputValue' "$OUTPUT_DIR/stack-output.json")

# Save individual files for easy access
echo "$VPC_ID" > "$OUTPUT_DIR/vpc-id"
echo "$PUBLIC_SUBNET_IDS" > "$OUTPUT_DIR/public-subnet-ids"
echo "$PRIVATE_SUBNET_IDS" > "$OUTPUT_DIR/private-subnet-ids"
echo "$AVAILABILITY_ZONES" > "$OUTPUT_DIR/availability-zones"
echo "$STACK_NAME" > "$OUTPUT_DIR/stack-name"

# Create summary file
cat > "$OUTPUT_DIR/vpc-summary.txt" <<EOF
VPC Creation Summary
===================

Stack Name: ${STACK_NAME}
Region: ${REGION}
VPC ID: ${VPC_ID}
VPC CIDR: ${VPC_CIDR}

Availability Zones: ${AVAILABILITY_ZONES}

Public Subnets: ${PUBLIC_SUBNET_IDS}
Private Subnets: ${PRIVATE_SUBNET_IDS}

Configuration:
- Availability Zone Count: ${AVAILABILITY_ZONE_COUNT}
- Subnet Bits: ${SUBNET_BITS}
- Public Only: ${PUBLIC_ONLY:-no}
- Shared VPC: ${SHARED_VPC:-no}
- DHCP Options: ${DHCP_OPTIONS:-no}
- Additional Subnets: ${ADDITIONAL_SUBNETS_COUNT}

Files Created:
- vpc-template.yaml: CloudFormation template
- vpc-params.json: Parameters used
- stack-output.json: Full stack output
- vpc-id: VPC ID
- public-subnet-ids: Public subnet IDs
- private-subnet-ids: Private subnet IDs
- availability-zones: Availability zones used
- stack-name: Stack name
- vpc-summary.txt: This summary

Next Steps:
1. Use the VPC ID and subnet IDs for your OpenShift installation
2. The VPC includes S3 VPC endpoints for better performance
3. NAT gateways are configured for private subnet internet access
4. All resources are properly tagged for identification
EOF

echo ""
echo "✅ VPC creation completed successfully!"
echo ""
echo "📁 Output directory: ${OUTPUT_DIR}"
echo "🆔 VPC ID: ${VPC_ID}"
echo "🌐 Public Subnets: ${PUBLIC_SUBNET_IDS}"
echo "🔒 Private Subnets: ${PRIVATE_SUBNET_IDS}"
echo "📍 Availability Zones: ${AVAILABILITY_ZONES}"
echo ""
echo "📋 Summary saved to: ${OUTPUT_DIR}/vpc-summary.txt"
echo ""
echo "To delete the VPC stack:"
echo "$AWS_CMD cloudformation delete-stack --region ${REGION} --stack-name ${STACK_NAME}" 