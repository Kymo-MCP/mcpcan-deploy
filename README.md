# MCP-Box 部署指南

## 软件架构设计

基于 Kubernetes 的微服务架构，包含以下核心组件：

1. **Gateway 服务** - API 网关，负责请求路由和认证
2. **Authz 服务** - 认证授权服务
3. **Market 服务** - 市场服务
4. **Web 服务** - 前端服务
5. **MySQL** - 数据库服务
6. **Redis** - 缓存服务

## 环境依赖

### 必需环境

在开始部署之前，请确保您的环境满足以下要求：

#### 1. Kubernetes 集群

**选项 A: 使用 K3s（推荐用于开发和测试）**
```bash
# 安装 K3s
curl -sfL https://get.k3s.io | sh -

# 或使用项目提供的脚本
./scripts/install-k3s.sh

# 验证安装
kubectl get nodes
```

**选项 B: 使用标准 Kubernetes**
- Kubernetes 版本 >= 1.20
- 至少 2GB 可用内存
- 至少 2 CPU 核心

#### 2. 必需工具

确保已安装以下工具：

```bash
# Helm 3.x
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# 验证安装
helm version
kubectl version --client
```

## 快速开始

### 1. 克隆仓库

```bash
# 克隆项目仓库
git clone https://github.com/your-org/mcp-box-deploy.git
cd mcp-box-deploy
```

### 2. 基本配置部署

使用默认配置进行快速部署：

```bash
# 基本部署（使用 IP 访问）
helm install mcp-box ./helm --namespace mcp-box --create-namespace --timeout 600s --wait

# 查看部署状态
kubectl get pods -n mcp-box
kubectl get svc -n mcp-box
```

部署完成后，可通过以下方式访问：
- Web 服务：`http://<node-ip>:30080`
- Gateway API：`http://<node-ip>:30081`

### 3. 自定义域名部署

如果您有自己的域名，可以按以下步骤配置：

#### 步骤 1: 复制并修改配置文件

```bash
# 复制默认配置
cp helm/values.yaml helm/values-custom.yaml
```

#### 步骤 2: 修改域名配置

编辑 `helm/values-custom.yaml`：

```yaml
# Global configuration
global:
  # 设置您的域名
  domain: "your-domain.com"
  publicIP: "your-server-ip"
  
# Ingress configuration
ingress:
  tls:
    enabled: true
    # 如果使用自签名证书，设置证书内容
    crt: |
      -----BEGIN CERTIFICATE-----
      # 您的证书内容
      -----END CERTIFICATE-----
    key: |
      -----BEGIN PRIVATE KEY-----
      # 您的私钥内容
      -----END PRIVATE KEY-----
```

#### 步骤 3: 生成 TLS 证书（可选）

```bash
# 生成自签名证书
./scripts/generate-simple-cert.sh your-domain.com 365

# 证书文件将生成在 certs/ 目录下
ls certs/
```

#### 步骤 4: 使用自定义配置部署

```bash
# 使用自定义配置部署
helm install mcp-box ./helm -f helm/values-custom.yaml \
  --namespace mcp-box --create-namespace --timeout 600s --wait

# 或升级现有部署
helm upgrade mcp-box ./helm -f helm/values-custom.yaml \
  --namespace mcp-box --timeout 600s --wait
```

## Values.yaml 配置说明

### 全局配置 (global)

```yaml
global:
  # 域名配置（可选，不设置则使用 publicIP）
  domain: ""
  
  # 公网 IP 地址（domain 为空时使用）
  publicIP: "192.168.1.100"
  
  # 应用版本
  version: v1.0.0
  
  # 镜像仓库地址
  registry: ccr.ccs.tencentyun.com/itqm-private
  
  # 镜像拉取策略
  imagePullPolicy: Always
  
  # 应用密钥
  appSecret: dev-app-secret
  
  # 存储配置
  hostStorage:
    rootPath: /data/mcp-box          # 主机存储根路径
    staticPath: /data/mcp-box/static # 静态文件路径
    mysqlPath: /data/mcp-box/mysql   # MySQL 数据路径
    redisPath: /data/mcp-box/redis   # Redis 数据路径
```

### 基础设施配置 (infrastructure)

```yaml
infrastructure:
  mysql:
    enabled: true                    # 是否启用 MySQL
    auth:
      rootPassword: dev-root-password
      database: mcp_dev
      username: mcp_user
      password: dev-password
    resources:                       # 资源限制
      requests:
        memory: "256Mi"
        cpu: "100m"
      limits:
        memory: "512Mi"
        cpu: "500m"
  
  redis:
    enabled: true                    # 是否启用 Redis
    auth:
      password: dev-redis-password
      db: 0
```

### 服务配置 (services)

```yaml
services:
  web:
    enabled: true                    # 是否启用服务
    replicas: 1                      # 副本数量
    resources:                       # 资源配置
      requests:
        memory: "128Mi"
        cpu: "50m"
      limits:
        memory: "256Mi"
        cpu: "200m"
    ingress:
      enabled: true                  # 是否启用 Ingress
      path: /                        # 访问路径
```

### TLS 配置 (ingress.tls)

```yaml
ingress:
  tls:
    enabled: true                    # 是否启用 TLS
    secretName: domain-tls           # Secret 名称
    crt: |                          # 证书内容（Base64 编码）
      -----BEGIN CERTIFICATE-----
      # 证书内容
      -----END CERTIFICATE-----
    key: |                          # 私钥内容（Base64 编码）
      -----BEGIN PRIVATE KEY-----
      # 私钥内容
      -----END PRIVATE KEY-----
```

## 部署管理

### 升级部署

```bash
# 升级到新版本
helm upgrade mcp-box ./helm -f helm/values-custom.yaml \
  --set global.version=v1.1.0 \
  --namespace mcp-box --timeout 600s --wait

# 查看升级历史
helm history mcp-box --namespace mcp-box
```

### 卸载部署

```bash
# 卸载 Helm Release
helm uninstall mcp-box --namespace mcp-box

# 清理命名空间
kubectl delete namespace mcp-box

# 清理持久化数据（谨慎操作）
sudo rm -rf /data/mcp-box
```

### 常用管理命令

#### 查看状态

```bash
# 查看 Helm Release 状态
helm status mcp-box --namespace mcp-box

# 查看 Pod 状态
kubectl get pods -n mcp-box

# 查看服务状态
kubectl get svc -n mcp-box

# 查看 Ingress 状态
kubectl get ingress -n mcp-box
```

#### 日志查看

```bash
# 查看特定服务日志
kubectl logs -n mcp-box -l app=mcp-gateway
kubectl logs -n mcp-box -l app=mcp-authz
kubectl logs -n mcp-box -l app=mcp-market
kubectl logs -n mcp-box -l app=mcp-web

# 实时查看日志
kubectl logs -n mcp-box -l app=mcp-gateway -f
```

#### 故障排查

```bash
# 查看 Pod 详细信息
kubectl describe pod <pod-name> -n mcp-box

# 查看事件
kubectl get events -n mcp-box --sort-by='.lastTimestamp'

# 进入 Pod 调试
kubectl exec -it <pod-name> -n mcp-box -- /bin/sh

# 端口转发（本地调试）
kubectl port-forward svc/mcp-gateway-svc 8080:8080 -n mcp-box
kubectl port-forward svc/mcp-web-svc 3000:3000 -n mcp-box
```

## Shell 脚本使用说明

项目提供了多个实用脚本来简化部署和管理：

### 1. K3s 管理脚本

```bash
# 安装 K3s
./scripts/install-k3s.sh

# 卸载 K3s
./scripts/uninstall-k3s.sh
```

### 2. 证书生成脚本

```bash
# 生成自签名证书
# 用法: ./scripts/generate-simple-cert.sh <域名> <有效期天数>
./scripts/generate-simple-cert.sh demo.mcp-box.com 365

# 生成的证书文件
ls certs/
# tls.crt - 证书文件
# tls.key - 私钥文件
```

### 3. 部署脚本

```bash
# 一键部署到 K8s
./scripts/deploy-to-k8s.sh

# 加载镜像到本地
./scripts/load-images.sh
```

### 4. Helm 包管理

```bash
# 推送 Helm 包到 GitHub Pages
./scripts/push-helm-pkg-to-github-pages.sh
```

## 高级配置

### 自定义部署参数

可以通过 `--set` 参数覆盖默认配置：

```bash
# 自定义镜像版本
helm upgrade --install mcp-box ./helm \
  --set global.version=v1.2.3 \
  --namespace mcp-box

# 自定义域名
helm upgrade --install mcp-box ./helm \
  --set global.domain=my-custom-domain.com \
  --namespace mcp-box

# 自定义资源限制
helm upgrade --install mcp-box ./helm \
  --set services.gateway.resources.limits.memory=512Mi \
  --set services.gateway.resources.limits.cpu=500m \
  --namespace mcp-box

# 禁用某个服务
helm upgrade --install mcp-box ./helm \
  --set services.market.enabled=false \
  --namespace mcp-box
```

### 多环境部署

```bash
# 开发环境
helm install mcp-box-dev ./helm -f helm/values-dev.yaml \
  --namespace mcp-box-dev --create-namespace

# 测试环境
helm install mcp-box-staging ./helm -f helm/values-staging.yaml \
  --namespace mcp-box-staging --create-namespace

# 生产环境
helm install mcp-box-prod ./helm -f helm/values-prod.yaml \
  --namespace mcp-box-prod --create-namespace
```

## 注意事项

1. **资源要求**：确保集群有足够的资源（至少 2GB 内存，2 CPU 核心）
2. **存储配置**：生产环境建议使用持久化存储而非 hostPath
3. **安全配置**：生产环境请修改默认密码和密钥
4. **网络配置**：确保防火墙允许相应端口访问
5. **备份策略**：定期备份数据库和重要配置文件
6. **监控告警**：建议配置监控和告警系统
7. **版本管理**：建议使用具体的版本标签而不是 `latest`

## 常见问题

### Q: Pod 一直处于 Pending 状态？
A: 检查节点资源是否充足，查看 `kubectl describe pod <pod-name> -n mcp-box` 的事件信息。

### Q: 无法访问服务？
A: 检查 Ingress 配置和域名解析，确保防火墙规则正确。

### Q: 数据库连接失败？
A: 检查 MySQL 服务状态和连接配置，确认密码和数据库名称正确。

### Q: 如何更新配置？
A: 修改 values.yaml 文件后，使用 `helm upgrade` 命令更新部署。

## 技术支持

如遇到问题，请：
1. 查看日志：`kubectl logs -n mcp-box <pod-name>`
2. 检查事件：`kubectl get events -n mcp-box`
3. 提交 Issue 到项目仓库
4. 联系技术支持团队
