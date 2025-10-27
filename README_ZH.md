# MCP-Box 部署指南

## 软件架构设计

基于 Kubernetes 的微服务架构，包含以下核心组件：

1. **Gateway 服务** - MCP 网关服务，负责请求路由和认证
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

# 或使用项目提供的脚本（推荐:默认安装 K3s，ingress-nginx, helm）
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

#### 3. NGINX Ingress Controller

MCP-Box 依赖 NGINX Ingress Controller 来处理外部流量路由，请确保已安装：

**选项 A: 使用 Helm 安装（推荐）**
```bash
# 添加 NGINX Ingress Helm 仓库
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# 安装 NGINX Ingress Controller
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443

# 验证安装
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

**选项 B: 使用项目提供的配置文件**
```bash
# 使用项目提供的 NGINX Ingress 配置
kubectl apply -f scripts/nginx-ingress-controller.yaml

# 验证安装
kubectl get pods -n ingress-nginx
```

**验证 Ingress Controller 状态**
```bash
# 检查 Ingress Controller 是否正常运行
kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# 检查服务端口
kubectl get svc -n ingress-nginx
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
# 基本部署（使用 IP 访问, 修改 ./helm/values.yaml 中的 publicIP）
helm install mcp-box ./helm --namespace mcp-box --create-namespace --timeout 600s --wait

# 查看部署状态
kubectl get pods -n mcp-box
kubectl get svc -n mcp-box
```

部署完成后，可通过以下方式访问：
- Web 服务：`http://<node-ip>`

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
  # 设置您的域名, 例如: demo.mcp-box.com, 存在 domain 时 publicIP 配置将被忽略
  domain: "demo.mcp-box.com"
  
# Ingress configuration
ingress:
  tls:
    enabled: true
    # 如果使用自签名证书（例如：demo.mcp-box.com），请配置证书内容
    # 注意：自签名证书在浏览器中会显示安全警告
    # 使用自签名证书安装，系统生成的MCP访问配置可能会导致无法正常访问，此时可以手动将配置中协议改为 http
    #　生产环境建议使用正式证书
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


### 3. Helm 包管理

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

1. **资源要求**：确保集群有足够的资源
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
