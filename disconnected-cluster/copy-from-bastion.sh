#!/bin/bash
# Copy sync results from bastion host

BASTION_IP="54.156.74.113"
CLUSTER_NAME="weli-disconnected-cluster-1751362952"
BASTION_KEY="./infra-output/bastion-key.pem"

echo "📋 Copying files from bastion host..."
mkdir -p ./bastion-output

scp -i "./infra-output/bastion-key.pem" -o StrictHostKeyChecking=no -r ubuntu@$BASTION_IP:/home/ubuntu/openshift-sync/install-config-template.yaml ./bastion-output/
scp -i "./infra-output/bastion-key.pem" -o StrictHostKeyChecking=no -r ubuntu@$BASTION_IP:/home/ubuntu/openshift-sync/imageContentSources.yaml ./bastion-output/

echo "✅ Files copied to ./bastion-output/"
echo "   - install-config-template.yaml"
echo "   - imageContentSources.yaml"
