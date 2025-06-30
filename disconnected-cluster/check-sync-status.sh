#!/bin/bash
# Check sync status on bastion host

BASTION_IP="54.157.138.135"
CLUSTER_NAME="fedora-disconnected-cluster"
BASTION_KEY="infra-output/bastion-key.pem"

echo "🔍 Checking sync status on bastion host..."
ssh -i "infra-output/bastion-key.pem" -o StrictHostKeyChecking=no ubuntu@$BASTION_IP "ls -la /home/ubuntu/openshift-sync/"

echo ""
echo "📊 Registry catalog:"
ssh -i "infra-output/bastion-key.pem" -o StrictHostKeyChecking=no ubuntu@$BASTION_IP "curl -k -s -u admin:admin123 https://registry.$CLUSTER_NAME.local:5000/v2/_catalog | jq ."
