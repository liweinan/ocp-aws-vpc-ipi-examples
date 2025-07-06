#!/bin/bash

# 创建bootstrap到bastion的路由脚本
# 这个脚本会为private subnet添加一条路由，将流量导向bastion主机

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印函数
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 从infra-output目录读取配置
INFRA_OUTPUT_DIR="ci-operator/disconnected-cluster/infra-output"

if [[ ! -d "$INFRA_OUTPUT_DIR" ]]; then
    print_error "Infra output directory not found: $INFRA_OUTPUT_DIR"
    exit 1
fi

# 读取配置
VPC_ID=$(cat "$INFRA_OUTPUT_DIR/vpc-id" | tr -d '\n')
VPC_CIDR=$(cat "$INFRA_OUTPUT_DIR/vpc-cidr" | tr -d '\n')
PRIVATE_SUBNET_ID=$(cat "$INFRA_OUTPUT_DIR/private-subnet-ids" | tr -d '\n')
PUBLIC_SUBNET_ID=$(cat "$INFRA_OUTPUT_DIR/public-subnet-ids" | tr -d '\n')
BASTION_INSTANCE_ID=$(cat "$INFRA_OUTPUT_DIR/bastion-instance-id" | tr -d '\n')
REGION=$(cat "$INFRA_OUTPUT_DIR/region" | tr -d '\n')

print_info "📋 当前配置:"
echo "   VPC ID: $VPC_ID"
echo "   VPC CIDR: $VPC_CIDR"
echo "   Private Subnet ID: $PRIVATE_SUBNET_ID"
echo "   Public Subnet ID: $PUBLIC_SUBNET_ID"
echo "   Bastion Instance ID: $BASTION_INSTANCE_ID"
echo "   Region: $REGION"
echo ""

# 获取public subnet的CIDR
print_info "🔍 获取public subnet的CIDR..."
PUBLIC_SUBNET_CIDR=$(aws ec2 describe-subnets \
    --subnet-ids "$PUBLIC_SUBNET_ID" \
    --region "$REGION" \
    --query 'Subnets[0].CidrBlock' \
    --output text)

print_info "Public Subnet CIDR: $PUBLIC_SUBNET_CIDR"

# 获取private subnet的路由表
print_info "🔍 获取private subnet的路由表..."
PRIVATE_ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
    --filters "Name=association.subnet-id,Values=$PRIVATE_SUBNET_ID" \
    --region "$REGION" \
    --query 'RouteTables[0].RouteTableId' \
    --output text)

if [[ "$PRIVATE_ROUTE_TABLE_ID" == "None" || -z "$PRIVATE_ROUTE_TABLE_ID" ]]; then
    print_error "无法找到private subnet的路由表"
    exit 1
fi

print_info "Private Route Table ID: $PRIVATE_ROUTE_TABLE_ID"

# 检查是否已经存在到bastion的路由
print_info "🔍 检查是否已存在到bastion的路由..."
EXISTING_ROUTE=$(aws ec2 describe-route-tables \
    --route-table-ids "$PRIVATE_ROUTE_TABLE_ID" \
    --region "$REGION" \
    --query "RouteTables[0].Routes[?DestinationCidrBlock=='$PUBLIC_SUBNET_CIDR']" \
    --output text)

if [[ -n "$EXISTING_ROUTE" ]]; then
    print_warning "已存在到public subnet ($PUBLIC_SUBNET_CIDR) 的路由"
    print_info "当前路由配置:"
    aws ec2 describe-route-tables \
        --route-table-ids "$PRIVATE_ROUTE_TABLE_ID" \
        --region "$REGION" \
        --query "RouteTables[0].Routes[?DestinationCidrBlock=='$PUBLIC_SUBNET_CIDR']" \
        --output table
    
    read -p "是否要替换现有路由? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "取消操作"
        exit 0
    fi
    
    # 删除现有路由
    print_info "🗑️  删除现有路由..."
    aws ec2 delete-route \
        --route-table-id "$PRIVATE_ROUTE_TABLE_ID" \
        --destination-cidr-block "$PUBLIC_SUBNET_CIDR" \
        --region "$REGION"
    print_success "已删除现有路由"
fi

# 创建到bastion的路由
print_info "🛣️  创建到bastion的路由..."
aws ec2 create-route \
    --route-table-id "$PRIVATE_ROUTE_TABLE_ID" \
    --destination-cidr-block "$PUBLIC_SUBNET_CIDR" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$REGION"

if [[ $? -eq 0 ]]; then
    print_success "成功创建到bastion的路由"
else
    print_error "创建路由失败"
    exit 1
fi

# 验证路由创建
print_info "🔍 验证路由创建..."
sleep 5

ROUTE_STATUS=$(aws ec2 describe-route-tables \
    --route-table-ids "$PRIVATE_ROUTE_TABLE_ID" \
    --region "$REGION" \
    --query "RouteTables[0].Routes[?DestinationCidrBlock=='$PUBLIC_SUBNET_CIDR'].State" \
    --output text)

if [[ "$ROUTE_STATUS" == "active" ]]; then
    print_success "路由状态: $ROUTE_STATUS"
else
    print_warning "路由状态: $ROUTE_STATUS (可能需要一些时间来激活)"
fi

# 显示最终的路由表
print_info "📋 最终路由表配置:"
aws ec2 describe-route-tables \
    --route-table-ids "$PRIVATE_ROUTE_TABLE_ID" \
    --region "$REGION" \
    --query 'RouteTables[0].Routes' \
    --output table

# 保存路由信息
ROUTE_INFO_FILE="$INFRA_OUTPUT_DIR/bootstrap-bastion-route-info"
cat > "$ROUTE_INFO_FILE" << EOF
# Bootstrap to Bastion Route Information
# Created: $(date)
RouteTableId: $PRIVATE_ROUTE_TABLE_ID
DestinationCidrBlock: $PUBLIC_SUBNET_CIDR
InstanceId: $BASTION_INSTANCE_ID
Region: $REGION
Status: $ROUTE_STATUS
EOF

print_success "路由信息已保存到: $ROUTE_INFO_FILE"

echo ""
print_success "🎉 Bootstrap到Bastion的路由创建完成！"
echo ""
print_info "📝 路由配置摘要:"
echo "   • 源: Private Subnet ($PRIVATE_SUBNET_ID)"
echo "   • 目标: Public Subnet ($PUBLIC_SUBNET_CIDR)"
echo "   • 下一跳: Bastion Instance ($BASTION_INSTANCE_ID)"
echo "   • 路由表: $PRIVATE_ROUTE_TABLE_ID"
echo ""
print_info "🔗 现在bootstrap节点可以通过bastion访问registry了" 