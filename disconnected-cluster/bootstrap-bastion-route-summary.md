# Bootstrap到Bastion路由配置总结

## 概述

已成功为disconnected OpenShift集群创建了bootstrap节点到bastion主机的路由，使bootstrap节点能够通过bastion访问registry。

## 网络架构

```
┌─────────────────────────────────────────────────────────────┐
│                        VPC (10.0.0.0/16)                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │ Private Subnet  │    │ Public Subnet   │                │
│  │ 10.0.100.0/24   │    │ 10.0.10.0/24    │                │
│  │                 │    │                 │                │
│  │ ┌─────────────┐ │    │ ┌─────────────┐ │                │
│  │ │ Bootstrap   │ │    │ │ Bastion     │ │                │
│  │ │ Node        │ │    │ │ Host        │ │                │
│  │ │             │ │    │ │             │ │                │
│  │ │ Registry    │ │────┼─│ Registry    │ │                │
│  │ │ Client      │ │    │ │ Server      │ │                │
│  │ │             │ │    │ │ (localhost: │ │                │
│  │ └─────────────┘ │    │ │  5000)      │ │                │
│  └─────────────────┘    │ └─────────────┘ │                │
│                         └─────────────────┘                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 路由配置详情

### 路由表信息
- **路由表ID**: `rtb-07a2f54bf701220ec`
- **关联子网**: Private Subnet (`subnet-0c20cd6726093521c`)
- **VPC**: `vpc-0437dc12208551157`
- **区域**: `us-east-1`

### 路由规则
| 目标CIDR | 下一跳 | 状态 | 描述 |
|----------|--------|------|------|
| `10.0.10.0/24` | `i-0ec1c936ca9d0953a` | active | 到bastion主机的路由 |

### 网络接口信息
- **实例ID**: `i-0ec1c936ca9d0953a` (Bastion)
- **网络接口ID**: `eni-0cda3c3f5436c0ebb`
- **实例所有者**: `301721915996`

## 配置步骤回顾

1. **读取基础设施配置**
   - 从 `infra-output/` 目录读取VPC、子网、实例信息
   - 验证所有必要资源的存在

2. **获取网络信息**
   - Public Subnet CIDR: `10.0.10.0/24`
   - Private Subnet ID: `subnet-0c20cd6726093521c`
   - Bastion Instance ID: `i-0ec1c936ca9d0953a`

3. **创建路由**
   - 在private subnet的路由表中添加路由
   - 目标: `10.0.10.0/24` (public subnet)
   - 下一跳: bastion实例

4. **验证配置**
   - 确认路由状态为 `active`
   - 保存配置信息到 `bootstrap-bastion-route-info`

## 工作原理

### 流量路径
1. **Bootstrap节点** 尝试访问 `localhost:5000`
2. **DNS解析** 将 `registry.ci.openshift.org` 解析到 `10.0.10.10`
3. **路由查找** 匹配到 `10.0.10.0/24` 路由规则
4. **流量转发** 通过bastion实例转发
5. **Registry访问** 最终到达bastion上的registry服务

### 关键配置
- **Bootstrap节点** `/etc/hosts`:
  ```
  10.0.10.10 registry.ci.openshift.org
  10.0.10.10 quay.io
  ```

- **Registry配置** `/etc/containers/registries.conf`:
  ```toml
  [[registry.mirror]]
  location = "localhost:5000/openshift/ocp/release"
  insecure = true
  ```

## 验证方法

### 1. 检查路由状态
```bash
AWS_PROFILE=static aws ec2 describe-route-tables \
  --route-table-ids rtb-07a2f54bf701220ec \
  --region us-east-1 \
  --query 'RouteTables[0].Routes[?DestinationCidrBlock==`10.0.10.0/24`]'
```

### 2. 测试网络连通性
```bash
# 从bootstrap节点测试
ping 10.0.10.10
curl http://10.0.10.10:5000/v2/_catalog
```

### 3. 验证镜像拉取
```bash
# 在bootstrap节点上测试
podman pull localhost:5000/openshift/ocp/release:4.19
```

## 故障排除

### 常见问题

1. **路由状态不是active**
   - 检查bastion实例是否运行
   - 验证网络接口配置

2. **无法访问registry**
   - 确认bastion上的registry服务正在运行
   - 检查防火墙规则

3. **DNS解析失败**
   - 验证 `/etc/hosts` 配置
   - 检查网络连通性

### 调试命令
```bash
# 检查路由表
ip route show

# 检查网络连通性
traceroute 10.0.10.10

# 检查registry服务
curl -v http://localhost:5000/v2/_catalog
```

## 下一步

1. **配置bootstrap节点**
   - 应用之前创建的修复配置
   - 更新 `/etc/hosts` 和 registry配置

2. **测试镜像拉取**
   - 验证bootstrap节点能够从bastion拉取镜像
   - 确认所有必要的镜像都可以访问

3. **继续集群安装**
   - 使用修复后的配置重新启动集群安装
   - 监控安装进度和日志

## 文件位置

- **路由信息**: `ci-operator/disconnected-cluster/infra-output/bootstrap-bastion-route-info`
- **创建脚本**: `ci-operator/disconnected-cluster/create-bootstrap-bastion-route.sh`
- **基础设施配置**: `ci-operator/disconnected-cluster/infra-output/`

---

**创建时间**: 2025-07-05 14:37:13 CST  
**状态**: ✅ 成功配置  
**路由状态**: active 