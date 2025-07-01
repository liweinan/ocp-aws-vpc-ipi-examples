# Certificate Improvements for Disconnected Cluster

## 概述

本文档说明了我们对镜像仓库证书的改进，解决了证书域名不匹配的问题。

## 问题分析

### ❌ **之前的问题**

1. **证书只对特定域名有效**：
   ```bash
   -subj "/C=US/ST=State/L=City/O=Organization/CN=registry.$cluster_name.local"
   ```

2. **AWS 实例的公共 DNS 格式**：
   - `ec2-xx-xx-xx-xx.compute-1.amazonaws.com`
   - `ip-xx-xx-xx-xx.ec2.internal`

3. **证书不匹配导致的问题**：
   - 集群节点无法验证镜像仓库证书
   - 需要跳过 TLS 验证（`--tls-verify=false`）
   - 安全风险增加

### ✅ **解决方案**

我们采用了 **Subject Alternative Names (SAN)** 证书，包含多个域名和 IP 地址：

## 证书配置

### 1. 证书包含的域名和 IP

```bash
[alt_names]
DNS.1 = registry.$cluster_name.local    # 集群特定域名
DNS.2 = *.local                         # 通配符本地域名
DNS.3 = localhost                       # 本地主机名
DNS.4 = registry                        # 简短域名
DNS.5 = registry.$INSTANCE_ID.local     # 实例特定域名
IP.1 = 127.0.0.1                       # 本地回环地址
IP.2 = $PUBLIC_IP                      # 公网 IP
IP.3 = $PRIVATE_IP                     # 私网 IP
```

### 2. 证书生成过程

```bash
# 创建 OpenSSL 配置文件
cat > /opt/registry/certs/openssl.conf <<EOF
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
DNS.5 = registry.$INSTANCE_ID.local
IP.1 = 127.0.0.1
IP.2 = $PUBLIC_IP
IP.3 = $PRIVATE_IP
EOF

# 生成私钥和证书签名请求
openssl req -newkey rsa:4096 -nodes -sha256 \
    -keyout /opt/registry/certs/domain.key \
    -out /opt/registry/certs/domain.csr \
    -config /opt/registry/certs/openssl.conf

# 生成自签名证书
openssl x509 -req -in /opt/registry/certs/domain.csr \
    -signkey /opt/registry/certs/domain.key \
    -out /opt/registry/certs/domain.crt \
    -days 365 \
    -extensions v3_req \
    -extfile /opt/registry/certs/openssl.conf
```

## 优势

### 1. **兼容性**
- ✅ 支持多种访问方式
- ✅ 支持 IP 地址访问
- ✅ 支持通配符域名

### 2. **安全性**
- ✅ 不再需要跳过 TLS 验证
- ✅ 证书验证正常工作
- ✅ 支持 HTTPS 加密通信

### 3. **灵活性**
- ✅ 自动获取实例元数据
- ✅ 动态生成证书
- ✅ 支持多种网络环境

## 支持的访问方式

### 1. **域名访问**
```bash
# 集群特定域名
registry.fedora-disconnected-cluster.local:5000

# 通配符域名
registry.local:5000

# 实例特定域名
registry.i-1234567890abcdef0.local:5000
```

### 2. **IP 地址访问**
```bash
# 公网 IP
54.157.138.135:5000

# 私网 IP
172.16.1.251:5000

# 本地访问
localhost:5000
127.0.0.1:5000
```

## 验证证书

### 1. **查看证书信息**
```bash
openssl x509 -in /opt/registry/certs/domain.crt -text -noout
```

### 2. **测试证书有效性**
```bash
# 测试域名访问
curl -k -u admin:admin123 https://registry.local:5000/v2/_catalog

# 测试 IP 访问
curl -k -u admin:admin123 https://54.157.138.135:5000/v2/_catalog

# 测试本地访问
curl -k -u admin:admin123 https://localhost:5000/v2/_catalog
```

## 配置示例

### 1. **OpenShift 配置**
```yaml
imageContentSources:
- mirrors:
  - registry.fedora-disconnected-cluster.local:5000/openshift/release
  source: quay.io/openshift-release-dev/ocp-release
```

### 2. **Podman 登录**
```bash
# 使用域名
podman login --username admin --password admin123 registry.local:5000

# 使用 IP 地址
podman login --username admin --password admin123 54.157.138.135:5000
```

### 3. **Docker 登录**
```bash
# 使用域名
docker login registry.local:5000

# 使用 IP 地址
docker login 54.157.138.135:5000
```

## 注意事项

### 1. **证书有效期**
- 证书有效期为 365 天
- 需要定期更新证书
- 建议设置证书更新脚本

### 2. **安全考虑**
- 证书是自签名的，在生产环境中可能需要使用 CA 签名的证书
- 私钥文件需要妥善保护
- 建议定期轮换证书

### 3. **网络配置**
- 确保防火墙允许 5000 端口
- 确保安全组配置正确
- 确保 DNS 解析正确

## 故障排除

### 1. **证书验证失败**
```bash
# 检查证书文件是否存在
ls -la /opt/registry/certs/

# 检查证书内容
openssl x509 -in /opt/registry/certs/domain.crt -text -noout

# 检查证书有效期
openssl x509 -in /opt/registry/certs/domain.crt -noout -dates
```

### 2. **连接被拒绝**
```bash
# 检查镜像仓库是否运行
podman ps | grep mirror-registry

# 检查端口是否监听
netstat -tlnp | grep 5000

# 检查防火墙
sudo ufw status
```

### 3. **DNS 解析问题**
```bash
# 测试 DNS 解析
nslookup registry.local

# 添加 hosts 条目
echo "54.157.138.135 registry.local" >> /etc/hosts
```

## 总结

通过这些改进，我们解决了证书域名不匹配的问题：

- ✅ **多域名支持**：证书支持多种域名格式
- ✅ **IP 地址支持**：证书支持 IP 地址访问
- ✅ **自动配置**：自动获取实例元数据并生成证书
- ✅ **安全通信**：支持 HTTPS 加密通信
- ✅ **兼容性好**：支持各种访问方式和网络环境

这确保了 disconnected cluster 中的镜像仓库可以正常工作，同时保持安全性。 