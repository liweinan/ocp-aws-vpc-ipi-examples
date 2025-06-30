#!/bin/bash

AMI_ID="ami-0c7217cdde317cfec"
REGION="us-east-1"

echo "Testing Fedora AMI: $AMI_ID in region: $REGION"
echo "=============================================="

# Test if AMI exists and is available
echo "Checking AMI availability..."
RESULT=$(AWS_PROFILE=static aws ec2 describe-images --image-ids "$AMI_ID" --region "$REGION" --query 'Images[0].State' --output text 2>/dev/null)

if [[ "$RESULT" == "available" ]]; then
    echo "✅ AMI is available!"
    
    # Get more details
    echo ""
    echo "AMI Details:"
    AWS_PROFILE=static aws ec2 describe-images --image-ids "$AMI_ID" --region "$REGION" --query 'Images[0].[ImageId,Name,Architecture,OwnerId,State]' --output table
else
    echo "❌ AMI is not available or doesn't exist"
    echo "Result: $RESULT"
    
    # Try to find alternative Fedora AMIs
    echo ""
    echo "Searching for alternative Fedora AMIs..."
    echo "请手动在 AWS 控制台查找 Fedora 官方 AMI 或参考 Fedora 官方文档。"
fi 