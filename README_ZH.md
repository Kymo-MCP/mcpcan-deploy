# mcpcan 部署指南

## [环境依赖安装说明](#环境依赖安装说明)

在开始部署之前，请确保您的环境满足以下要求：

- **Kubernetes**: 1.20 或更高版本
- **Helm**: 3.0 或更高版本  
- **NGINX Ingress Controller**: 如果启用 Ingress（域名访问）
- **持久化存储**: 用于数据持久化
- **资源要求**: 至少 4GB 内存和 2 CPU 核心

## 快速开始 （[查看 Helm Chart 仓库:https://kymo-mcp.github.io/mcpcan-deploy/](https://kymo-mcp.github.io/mcpcan-deploy/)）

### 1. 克隆仓库

```bash
# 克隆项目仓库
git clone https://github.com/Kymo-MCP/mcpcan-deploy.git
cd mcpcan-deploy
```

### 2. 基本配置部署

使用默认配置进行快速部署：

```bash
# 基本部署（使用 IP 访问, 修改 ./helm/values.yaml 中的 publicIP）
helm install mcpcan ./helm --namespace mcpcan --create-namespace --timeout 600s --wait

# 查看部署状态
kubectl get pods -n mcpcan
kubectl get svc -n mcpcan
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
  # 设置您的域名, 例如: demo.mcpcan.com, 存在 domain 时 publicIP 配置将被忽略
  domain: "demo.mcpcan.com"
  
# Ingress configuration
ingress:
  tls:
    enabled: true
    # 如果使用自签名证书（例如：demo.mcpcan.com），请配置证书内容
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
helm install mcpcan ./helm -f helm/values-custom.yaml \
  --namespace mcpcan --create-namespace --timeout 600s --wait

# 或升级现有部署
helm upgrade mcpcan ./helm -f helm/values-custom.yaml \
  --namespace mcpcan --timeout 600s --wait
```

## 部署管理

### 升级部署

```bash
# 升级到新版本
helm upgrade mcpcan ./helm -f helm/values-custom.yaml \
  --set global.version=v1.1.0 \
  --namespace mcpcan --timeout 600s --wait

# 查看升级历史
helm history mcpcan --namespace mcpcan
```

### 卸载部署

```bash
# 卸载 Helm Release
helm uninstall mcpcan --namespace mcpcan

# 清理命名空间
kubectl delete namespace mcpcan

# 清理持久化数据（谨慎操作）
sudo rm -rf /data/mcpcan
```

### 常用管理命令

#### 查看状态

```bash
# 查看 Helm Release 状态
helm status mcpcan --namespace mcpcan

# 查看 Pod 状态
kubectl get pods -n mcpcan

# 查看服务状态
kubectl get svc -n mcpcan

# 查看 Ingress 状态
kubectl get ingress -n mcpcan
```

#### 日志查看

```bash
# 查看特定服务日志
kubectl logs -n mcpcan -l app=mcp-gateway
kubectl logs -n mcpcan -l app=mcp-authz
kubectl logs -n mcpcan -l app=mcp-market
kubectl logs -n mcpcan -l app=mcp-web

# 实时查看日志
kubectl logs -n mcpcan -l app=mcp-gateway -f
```

#### 故障排查

```bash
# 查看 Pod 详细信息
kubectl describe pod <pod-name> -n mcpcan

# 查看事件
kubectl get events -n mcpcan --sort-by='.lastTimestamp'

# 进入 Pod 调试
kubectl exec -it <pod-name> -n mcpcan -- /bin/sh
```

## Shell 脚本使用说明

项目提供了多个实用脚本来简化部署和管理：

### 1. 运行环境一键安装脚本

```bash
# 一键安装完整运行环境 (K3s + Helm + Ingress-Nginx)
./scripts/install-run-environment.sh

# 使用中国镜像源加速安装
./scripts/install-run-environment.sh --cn

# 查看所有可用选项
./scripts/install-run-environment.sh --help
```

### 2. K3s 管理脚本

```bash
# 安装 K3s
./scripts/install-k3s.sh

# 卸载 K3s
./scripts/uninstall-k3s.sh
```

### 3. Helm 安装脚本

```bash
# 安装 Helm 包管理器
./scripts/install-helm.sh
```

### 4. Ingress-Nginx 安装脚本

```bash
# 安装 Ingress-Nginx 控制器
./scripts/install-ingress-nginx.sh
```

### 5. 证书生成脚本

```bash
# 生成自签名证书
# 用法: ./scripts/generate-simple-cert.sh <域名> <有效期天数>
./scripts/generate-simple-cert.sh demo.mcpcan.com 365

# 生成的证书文件
ls certs/
# tls.crt - 证书文件
# tls.key - 私钥文件
```

### 6. 镜像管理脚本

```bash
# 加载离线镜像
./scripts/load-images.sh

# 交互式 Bash 环境
./scripts/bash.sh
```


## 高级配置

### 多环境部署

```bash
# 开发环境
helm install mcpcan-dev ./helm -f helm/values-dev.yaml \
  --namespace mcpcan-dev --create-namespace

# 测试环境
helm install mcpcan-staging ./helm -f helm/values-staging.yaml \
  --namespace mcpcan-staging --create-namespace

# 生产环境
helm install mcpcan-prod ./helm -f helm/values-prod.yaml \
  --namespace mcpcan-prod --create-namespace
```

## 注意事项

1. **资源要求**：确保集群有足够的资源
3. **安全配置**：生产环境请修改默认密码和密钥
4. **网络配置**：确保防火墙允许相应端口访问
5. **备份策略**：定期备份数据库和重要配置文件
6. **监控告警**：建议配置监控和告警系统
7. **版本管理**：建议使用具体的版本标签而不是 `latest`


## 环境依赖安装说明

### 一键安装运行环境（推荐）

对于纯净环境，推荐使用项目提供的一键安装脚本：

```bash
# 安装完整运行环境（K3s + Helm + Ingress-Nginx）
./scripts/install-run-environment.sh

# 使用国内镜像源加速安装
./scripts/install-run-environment.sh --cn

# 查看所有可用选项
./scripts/install-run-environment.sh --help
```

**该脚本会自动安装以下组件：**
- **K3s**: 轻量级 Kubernetes 发行版
- **Helm**: Kubernetes 包管理器
- **Ingress-Nginx**: Ingress 控制器，用于处理外部流量路由

### 手动安装（可选）

如果您需要自定义安装或已有部分组件，可以选择手动安装：

#### 1.  k3s 安装

```bash
# 使用官方安装脚本安装 K3s
curl -sfL https://get.k3s.io | sh -

# 或者指定版本安装
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.28.5+k3s1 sh -

# 验证安装
sudo k3s kubectl get nodes
```



#### 2. Helm 包管理器
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

#### 3. NGINX Ingress Controller
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=NodePort
```

## 常见问题

### Q: Pod 一直处于 Pending 状态？
A: 检查节点资源是否充足，查看 `kubectl describe pod <pod-name> -n mcpcan` 的事件信息。

### Q: 无法访问服务？
A: 检查 Ingress 配置和域名解析，确保防火墙规则正确。

### Q: 数据库连接失败？
A: 检查 MySQL 服务状态和连接配置，确认密码和数据库名称正确。

### Q: 如何更新配置？
A: 修改 values.yaml 文件后，使用 `helm upgrade` 命令更新部署。

## 技术支持

如遇到问题，请：
1. 查看日志：`kubectl logs -n mcpcan <pod-name>`
2. 检查事件：`kubectl get events -n mcpcan`
3. 提交 Issue 到项目仓库
4. 联系技术支持团队
