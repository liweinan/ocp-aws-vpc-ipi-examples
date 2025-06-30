#!/bin/bash

# Force Delete VPC Script
# Deletes a VPC and all its dependencies

set -euo pipefail

VPC_ID="${1:-}"
REGION="${2:-us-east-1}"

if [[ -z "$VPC_ID" ]]; then
    echo "Usage: $0 <vpc-id> [region]"
    echo "Example: $0 vpc-03dbff9ea3d256485 us-east-1"
    exit 1
fi

echo "🗑️  Force Deleting VPC: $VPC_ID in region: $REGION"
echo "=================================================="

# Function to delete resources
delete_vpc_resources() {
    local vpc_id="$1"
    local region="$2"
    
    echo "🔍 Checking VPC dependencies..."
    
    # Delete NAT Gateways
    echo "   Deleting NAT Gateways..."
    local nat_gateways=$(aws ec2 describe-nat-gateways \
        --region "$region" \
        --filter "Name=vpc-id,Values=$vpc_id" \
        --query 'NatGateways[?State!=`deleted`].[NatGatewayId]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$nat_gateways" ]]; then
        for nat_id in $nat_gateways; do
            echo "     Deleting NAT Gateway: $nat_id"
            aws ec2 delete-nat-gateway --nat-gateway-id "$nat_id" --region "$region" 2>/dev/null || true
        done
        
        # Wait for NAT Gateways to be deleted
        echo "     Waiting for NAT Gateways to be deleted..."
        for nat_id in $nat_gateways; do
            aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$nat_id" --region "$region" 2>/dev/null || true
        done
    fi
    
    # Delete Elastic IPs
    echo "   Deleting Elastic IPs..."
    local eips=$(aws ec2 describe-addresses \
        --region "$region" \
        --filter "Name=domain,Values=vpc" \
        --query 'Addresses[?AssociationId==null].[AllocationId]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$eips" ]]; then
        for eip_id in $eips; do
            echo "     Releasing Elastic IP: $eip_id"
            aws ec2 release-address --allocation-id "$eip_id" --region "$region" 2>/dev/null || true
        done
    fi
    
    # Delete Network ACLs (except default)
    echo "   Deleting Network ACLs..."
    local nacls=$(aws ec2 describe-network-acls \
        --region "$region" \
        --filter "Name=vpc-id,Values=$vpc_id" \
        --query 'NetworkAcls[?IsDefault==`false`].[NetworkAclId]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$nacls" ]]; then
        for nacl_id in $nacls; do
            echo "     Deleting Network ACL: $nacl_id"
            aws ec2 delete-network-acl --network-acl-id "$nacl_id" --region "$region" 2>/dev/null || true
        done
    fi
    
    # Delete Route Tables (except default)
    echo "   Deleting Route Tables..."
    local route_tables=$(aws ec2 describe-route-tables \
        --region "$region" \
        --filter "Name=vpc-id,Values=$vpc_id" \
        --query 'RouteTables[?Associations[0].Main!=`true`].[RouteTableId]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$route_tables" ]]; then
        for rt_id in $route_tables; do
            echo "     Deleting Route Table: $rt_id"
            aws ec2 delete-route-table --route-table-id "$rt_id" --region "$region" 2>/dev/null || true
        done
    fi
    
    # Delete Security Groups (except default)
    echo "   Deleting Security Groups..."
    local security_groups=$(aws ec2 describe-security-groups \
        --region "$region" \
        --filter "Name=vpc-id,Values=$vpc_id" \
        --query 'SecurityGroups[?GroupName!=`default`].[GroupId]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$security_groups" ]]; then
        for sg_id in $security_groups; do
            echo "     Deleting Security Group: $sg_id"
            aws ec2 delete-security-group --group-id "$sg_id" --region "$region" 2>/dev/null || true
        done
    fi
    
    # Delete Subnets
    echo "   Deleting Subnets..."
    local subnets=$(aws ec2 describe-subnets \
        --region "$region" \
        --filter "Name=vpc-id,Values=$vpc_id" \
        --query 'Subnets[].SubnetId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$subnets" ]]; then
        for subnet_id in $subnets; do
            echo "     Deleting Subnet: $subnet_id"
            aws ec2 delete-subnet --subnet-id "$subnet_id" --region "$region" 2>/dev/null || true
        done
    fi
    
    # Delete Internet Gateway
    echo "   Deleting Internet Gateway..."
    local igw_id=$(aws ec2 describe-internet-gateways \
        --region "$region" \
        --filter "Name=attachment.vpc-id,Values=$vpc_id" \
        --query 'InternetGateways[0].InternetGatewayId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$igw_id" && "$igw_id" != "None" ]]; then
        echo "     Detaching Internet Gateway: $igw_id"
        aws ec2 detach-internet-gateway --vpc-id "$vpc_id" --internet-gateway-id "$igw_id" --region "$region" 2>/dev/null || true
        
        echo "     Deleting Internet Gateway: $igw_id"
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" --region "$region" 2>/dev/null || true
    fi
    
    # Delete VPC
    echo "   Deleting VPC: $vpc_id"
    aws ec2 delete-vpc --vpc-id "$vpc_id" --region "$region" 2>/dev/null || true
    
    echo "✅ VPC deletion completed"
}

# Main execution
if [[ "${AWS_PROFILE:-}" ]]; then
    export AWS_PROFILE
fi

delete_vpc_resources "$VPC_ID" "$REGION"

echo ""
echo "🔍 Verifying VPC deletion..."
if aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --region "$REGION" 2>/dev/null; then
    echo "❌ VPC still exists"
    exit 1
else
    echo "✅ VPC successfully deleted"
fi 