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
cat > /opt/registry/certs/openssl.conf <<'CONFIG_EOF'
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
CONFIG_EOF

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
