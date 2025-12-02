# mcpcan 部署指南

## [环境依赖安装说明](#环境依赖安装说明)

在开始部署之前，请确保您的环境满足以下要求：

- **Kubernetes**: 1.20 或更高版本
- **Helm**: 3.0 或更高版本  
- **NGINX Ingress Controller**: 如果启用 Ingress（域名访问）
- **持久化存储**: 用于数据持久化
- **资源要求**: 至少 4GB 内存和 2 CPU 核心

## 快速开始 （[查看 Helm Chart 仓库:https://kymo-mcp.github.io/mcpcan-deploy/](https://kymo-mcp.github.io/mcpcan-deploy/)）

本文档提供两条安装路径，帮助你在不同场景下部署 MCPCAN 管理平台。

- **极速安装脚本**：适用于纯净的 Linux 服务器，自动安装依赖与平台，推荐使用 IP 访问快速体验。
- **自定义安装（Helm）**：适用于自定义域名、开启 HTTPS、修改默认账户/密码或平台配置的场景。

### 1. 获取部署仓库

根据网络环境选择拉取源：

```bash
# GitHub（国际网络）
git clone https://github.com/Kymo-MCP/mcpcan-deploy.git
cd mcpcan-deploy

# Gitee（中国网络推荐）
git clone https://gitee.com/kymomcp/mcpcan-deploy.git
cd mcpcan-deploy
```

### 2. 安装路径

#### 路径 A: 极速安装（推荐 IP 访问）

此路径会自动安装 k3s、ingress‑nginx、Helm，并部署 MCPCAN 平台；适合没有预装 Kubernetes 组件的全新环境。

```bash
# 标准极速安装（国际镜像源）
./scripts/install-fast.sh

# 极速安装（中国镜像源加速）
./scripts/install-fast.sh --cn
```

成功后脚本会校验 Helm 发布状态并打印访问地址：
- 公网 IP：`http://<public-ip>`（自动检测）
- 本地回退：`http://localhost`

#### 路径 B: 自定义安装（域名/HTTPS/配置）

当你需要使用自定义域名、开启 HTTPS、或调整默认配置时，按下面步骤进行安装。

**步骤 1: 安装依赖（k3s、ingress‑nginx、Helm）**

适用干净环境；如果你已有 k3s/ingress‑nginx/Helm，可跳过本小节。

```bash
# 安装 k3s、ingress‑nginx 与 Helm
./scripts/install-run-environment.sh

# 安装 k3s、ingress‑nginx 与 Helm（中国镜像源）
./scripts/install-run-environment.sh --cn
```

**步骤 2: 配置与安装**

```bash
# 1. 复制默认配置文件
cp helm/values.yaml helm/values-custom.yaml

# 2. 编辑自定义配置文件 (设置域名、TLS 等)
# vi helm/values-custom.yaml

# 3. 安装
helm install mcpcan ./helm -f helm/values-custom.yaml \
  --namespace mcpcan --create-namespace --timeout 600s --wait
```

## 核心脚本说明

项目提供了多个实用脚本来简化部署和管理，以下是三个核心脚本的用法说明：

### 1. 极速安装脚本 (`install-fast.sh`)
**用途**：在纯净的 Linux 环境中一键完成所有组件的安装和部署。
**功能**：
- 自动检测并安装 K3s、Helm、Ingress-Nginx。
- 自动部署 MCPCAN 平台。
- 支持 `--cn` 参数使用国内镜像源加速。
**用法**：
```bash
./scripts/install-fast.sh [--cn]
```

### 2. 运行环境安装脚本 (`install-run-environment.sh`)
**用途**：仅安装 Kubernetes 基础运行环境，不部署 MCPCAN 业务应用。
**功能**：
- 安装 K3s 集群。
- 安装 Helm 包管理器。
- 安装 Ingress-Nginx 控制器。
- 适合需要自定义配置安装 MCPCAN 的场景。
**用法**：
```bash
./scripts/install-run-environment.sh [--cn]
```

### 3. 卸载脚本 (`uninstall.sh`)
**用途**：彻底卸载 MCPCAN 及其运行环境。
**警告**：此操作会删除 K3s 集群和所有数据，请谨慎使用。
**用法**：
```bash
./scripts/uninstall.sh
```

## Helm 详细使用说明

本节详细介绍管理 MCPCAN 部署常用的 Helm 命令。

### 1. 安装 (Install)
将 Chart 部署到 Kubernetes 集群中。

```bash
# 基本安装
helm install mcpcan ./helm --namespace mcpcan --create-namespace

# 使用自定义配置文件安装
helm install mcpcan ./helm -f helm/values-custom.yaml --namespace mcpcan --create-namespace

# 常用参数说明：
# --namespace: 指定命名空间
# --create-namespace: 如果命名空间不存在则创建
# --wait: 等待所有 Pod 就绪后再返回
# --timeout: 设置等待超时时间
```

### 2. 升级 (Upgrade)
修改配置或升级版本后，更新现有的 Release。

```bash
# 更新配置
helm upgrade mcpcan ./helm -f helm/values-custom.yaml --namespace mcpcan

# 动态修改单个配置项
helm upgrade mcpcan ./helm --set global.domain=new.example.com --namespace mcpcan
```

### 3. 查看状态 (Status & List)
查看部署的状态和历史版本。

```bash
# 查看部署状态（包含 Pod、Service 等资源状态）
helm status mcpcan --namespace mcpcan

# 列出指定命名空间下的所有 Release
helm list --namespace mcpcan

# 查看发布历史版本
helm history mcpcan --namespace mcpcan
```

### 4. 卸载 (Uninstall)
删除部署的 Release。

```bash
# 卸载应用
helm uninstall mcpcan --namespace mcpcan

# 注意：默认情况下，PVC（持久卷声明）可能不会被删除，以保护数据。
# 如需彻底清理数据，需要手动删除对应的 PVC 或数据目录。
```

## 部署管理与运维

### 常用 Kubectl 命令

```bash
# 查看 Pod 状态
kubectl get pods -n mcpcan

# 查看服务 (Service)
kubectl get svc -n mcpcan

# 查看 Ingress
kubectl get ingress -n mcpcan

# 查看 Pod 日志
kubectl logs -n mcpcan -l app=mcp-gateway -f

# 查看 Pod 详细信息（用于排错）
kubectl describe pod <pod-name> -n mcpcan
```

## 更多脚本工具

除了核心脚本外，`scripts/` 目录下还提供了辅助工具：
- `install-k3s.sh`: 单独安装 K3s。
- `install-helm.sh`: 单独安装 Helm。
- `install-ingress-nginx.sh`: 单独安装 Ingress-Nginx。
- `generate-simple-cert.sh`: 生成自签名 SSL 证书。
- `load-images.sh`: 加载离线镜像。

## 高级配置

### 多环境部署

```bash
# 开发环境
helm install mcpcan-dev ./helm -f helm/values-dev.yaml \
  --namespace mcpcan-dev --create-namespace

# 生产环境
helm install mcpcan-prod ./helm -f helm/values-prod.yaml \
  --namespace mcpcan-prod --create-namespace
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
