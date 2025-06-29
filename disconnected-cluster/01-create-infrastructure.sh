# Create user data script for Ubuntu with podman
cat > "$output_dir/bastion-userdata.sh" <<'EOF'
#!/bin/bash
# Bastion host setup script for disconnected OpenShift cluster

# Update system
apt update -y
apt upgrade -y

# Install required packages
apt install -y jq wget tar gzip unzip git curl apache2-utils

# Install podman
apt install -y podman

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

# Create registry authentication
htpasswd -Bbn admin admin123 > /opt/registry/auth/htpasswd

# Start registry with podman
podman run -d --name mirror-registry \
    -p 5000:5000 \
    -v /opt/registry/data:/var/lib/registry:z \
    -v /opt/registry/auth:/auth:z \
    -e REGISTRY_AUTH=htpasswd \
    -e REGISTRY_AUTH_HTPASSWD_REALM=Registry \
    -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
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
echo "Registry URL: http://localhost:5000"
echo "Username: admin"
echo "Password: admin123"
echo ""
echo "To test registry access:"
echo "curl -u admin:admin123 http://localhost:5000/v2/_catalog"
SCRIPT_EOF

chmod +x /home/ubuntu/setup-registry.sh
chown ubuntu:ubuntu /home/ubuntu/setup-registry.sh

echo "✅ Bastion host setup completed"
EOF