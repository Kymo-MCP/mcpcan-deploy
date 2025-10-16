# MCP Platform Helm 部署方案

## 概述

本文档介绍基于 Helm 的 MCP 平台 Kubernetes 部署方案。该方案替代了原有的 `envsubst` 变量替换方式，提供了更加标准化、可维护的部署解决方案。

## 目录结构

```
deploy/
├── helm/
│       ├── Chart.yaml                    # Helm Chart 元数据
│       ├── values.yaml                   # 默认配置值
│       ├── values-dev.yaml              # 开发环境配置
│       ├── values-prod.yaml             # 生产环境配置
│       └── templates/
│           ├── _helpers.tpl             # 模板辅助函数
│           ├── namespace.yaml           # 命名空间模板
│           ├── configmap.yaml           # 配置映射模板
│           ├── gateway-deployment.yaml  # Gateway 部署模板
│           ├── gateway-service.yaml     # Gateway 服务模板
│           └── gateway-ingress.yaml     # Gateway Ingress 模板
├── helm-deploy.sh                       # 部署脚本
└── HELM_DEPLOYMENT_GUIDE.md            # 本文档
```

## 技术方案优势

### 相比原有 envsubst 方案的改进

| 特性 | 原有方案 (envsubst) | 新方案 (Helm) |
|------|-------------------|---------------|
| 变量管理 | 分散在多个文件 | 集中在 values.yaml |
| 环境隔离 | 手动管理环境变量 | 独立的环境配置文件 |
| 模板功能 | 简单字符串替换 | 丰富的模板语法和函数 |
| 版本控制 | 难以追踪配置变更 | Chart 版本化管理 |
| 依赖管理 | 无依赖管理 | 支持 Chart 依赖 |
| 回滚能力 | 无内置回滚 | 一键回滚到任意版本 |
| 配置验证 | 无验证机制 | Schema 验证和 lint 检查 |
| 部署状态 | 无状态跟踪 | 完整的部署状态管理 |

## 前置条件

### 1. 安装 Helm

```bash
# macOS
brew install helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 验证安装
helm version
```

### 2. 配置 Kubernetes 集群

确保 `kubectl` 已正确配置并能连接到目标集群：

```bash
kubectl cluster-info
kubectl get nodes
```

### 3. 安装 Ingress Controller（可选）

如果集群中没有 Ingress Controller，需要先安装：

```bash
# 安装 NGINX Ingress Controller
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace
```

## 配置说明

### 1. 全局配置 (values.yaml)

```yaml
global:
  namespace: mcp-default          # 部署命名空间
  domain: example.com            # 域名
  version: latest                # 应用版本
  registry: registry.example.com # 镜像仓库
  imagePullPolicy: IfNotPresent  # 镜像拉取策略
```

### 2. 基础设施配置

```yaml
infrastructure:
  mysql:
    enabled: true                # 是否启用 MySQL
    image:
      repository: mysql
      tag: "8.0"
    auth:
      rootPassword: "password"   # 根密码
      database: "mcp"           # 数据库名
      username: "mcp_user"      # 用户名
      password: "password"      # 密码
    persistence:
      enabled: true             # 是否启用持久化
      size: 10Gi               # 存储大小
    resources:                  # 资源限制
      requests:
        memory: "512Mi"
        cpu: "250m"
      limits:
        memory: "1Gi"
        cpu: "500m"

  redis:
    enabled: true               # 是否启用 Redis
    # ... 类似 MySQL 配置
```

### 3. 应用服务配置

```yaml
services:
  gateway:
    enabled: true               # 是否启用服务
    name: mcp-gateway          # 服务名称
    replicas: 1                # 副本数
    image:
      repository: mcp/gateway  # 镜像仓库
      tag: latest             # 镜像标签
    service:
      port: 8080              # 服务端口
      type: ClusterIP         # 服务类型
    ingress:
      enabled: true           # 是否启用 Ingress
      host: gateway.example.com # 域名
      path: /                 # 路径
      pathType: Prefix        # 路径类型
    resources:                # 资源配置
      requests:
        memory: "256Mi"
        cpu: "100m"
      limits:
        memory: "512Mi"
        cpu: "500m"
    config:                   # 配置文件
      mountPath: /app/config  # 挂载路径
```

### 4. 环境特定配置

#### 开发环境 (values-dev.yaml)
- 使用 `latest` 镜像标签
- 较小的资源配置
- 禁用持久化存储
- 简化的安全配置

#### 生产环境 (values-prod.yaml)
- 使用固定版本标签
- 高可用配置（多副本）
- 启用持久化存储
- 完整的安全和监控配置

## 部署操作

### 1. 使用部署脚本（推荐）

```bash
# 进入部署目录
cd backend/deploy

# 部署到开发环境
./helm-deploy.sh -e dev

# 部署到生产环境
./helm-deploy.sh -e prod

# 升级现有部署
./helm-deploy.sh -e prod -u

# 干运行（不实际部署）
./helm-deploy.sh -e dev -d

# 指定版本部署
./helm-deploy.sh -e prod -v v1.2.3

# 自定义命名空间和发布名
./helm-deploy.sh -e dev -n my-namespace -r my-release
```

### 2. 直接使用 Helm 命令

```bash
# 安装新部署
helm install mcp-box ./helm \
  -f ./helm/values-dev.yaml \
  --namespace mcp-dev \
  --create-namespace

# 升级部署
helm upgrade mcp-box ./helm \
  -f ./helm/values-prod.yaml \
  --namespace mcp-prod

# 回滚到上一版本
helm rollback mcp-box 1 --namespace mcp-prod

# 卸载部署
helm uninstall mcp-box --namespace mcp-prod
```

## 部署脚本选项

| 选项 | 简写 | 描述 | 默认值 |
|------|------|------|--------|
| `--environment` | `-e` | 部署环境 (dev/prod/staging) | dev |
| `--namespace` | `-n` | Kubernetes 命名空间 | 从配置文件读取 |
| `--version` | `-v` | 应用版本 | 从配置文件读取 |
| `--dry-run` | `-d` | 干运行模式 | false |
| `--upgrade` | `-u` | 升级现有部署 | false |
| `--release-name` | `-r` | Helm 发布名 | mcp-box |
| `--timeout` | `-t` | 部署超时时间 | 600s |
| `--no-wait` | | 不等待部署完成 | false |
| `--help` | `-h` | 显示帮助信息 | |

## 常用操作

### 1. 查看部署状态

```bash
# 查看 Helm 发布状态
helm status mcp-box -n mcp-dev

# 查看 Pod 状态
kubectl get pods -n mcp-dev

# 查看服务状态
kubectl get svc -n mcp-dev

# 查看 Ingress 状态
kubectl get ingress -n mcp-dev
```

### 2. 查看日志

```bash
# 查看特定服务日志
kubectl logs -f deployment/mcp-gateway -n mcp-dev

# 查看所有 Pod 日志
kubectl logs -f -l app.kubernetes.io/instance=mcp-box -n mcp-dev
```

### 3. 配置更新

```bash
# 更新配置后重新部署
./helm-deploy.sh -e dev -u

# 仅更新特定配置
helm upgrade mcp-box ./helm \
  --set services.gateway.replicas=3 \
  --namespace mcp-dev
```

### 4. 扩缩容操作

```bash
# 扩展 Gateway 服务到 3 个副本
kubectl scale deployment mcp-gateway --replicas=3 -n mcp-dev

# 或通过 Helm 更新
helm upgrade mcp-box ./helm \
  --set services.gateway.replicas=3 \
  -f ./helm/values-dev.yaml \
  --namespace mcp-dev
```

## 故障排查

### 1. 部署失败

```bash
# 查看 Helm 发布历史
helm history mcp-box -n mcp-dev

# 查看失败的资源
kubectl describe pod <pod-name> -n mcp-dev

# 查看事件
kubectl get events -n mcp-dev --sort-by='.lastTimestamp'
```

### 2. 配置问题

```bash
# 验证 Chart 语法
helm lint ./helm

# 渲染模板查看最终配置
helm template mcp-box ./helm \
  -f ./helm/values-dev.yaml

# 干运行查看将要部署的资源
helm install mcp-box ./helm \
  -f ./helm/values-dev.yaml \
  --dry-run --debug
```

### 3. 网络问题

```bash
# 检查服务端点
kubectl get endpoints -n mcp-dev

# 测试服务连通性
kubectl run test-pod --image=busybox -it --rm -- /bin/sh
# 在 Pod 内执行: wget -qO- http://mcp-gateway:8080/health
```

## 安全最佳实践

### 1. 密码管理

```bash
# 使用 Kubernetes Secret 管理敏感信息
kubectl create secret generic mysql-secret \
  --from-literal=root-password=<strong-password> \
  --from-literal=password=<user-password> \
  -n mcp-prod

# 在 values.yaml 中引用 Secret
mysql:
  auth:
    existingSecret: mysql-secret
```

### 2. 镜像安全

```yaml
# 使用特定版本标签，避免使用 latest
image:
  repository: mcp/gateway
  tag: v1.2.3  # 不要使用 latest

# 配置镜像拉取策略
imagePullPolicy: IfNotPresent
```

### 3. 资源限制

```yaml
# 为所有容器设置资源限制
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

## 监控和日志

### 1. 集成 Prometheus

```yaml
# 在 values.yaml 中启用监控
monitoring:
  enabled: true
  prometheus:
    enabled: true
    serviceMonitor:
      enabled: true
```

### 2. 日志收集

```yaml
# 配置日志收集
logging:
  enabled: true
  fluentd:
    enabled: true
  elasticsearch:
    enabled: true
```

## 迁移指南

### 从原有 envsubst 方案迁移

1. **备份现有配置**
   ```bash
   cp -r deploy deploy.backup
   ```

2. **更新配置文件**
   - 将 `def.env` 中的变量迁移到 `values.yaml`
   - 根据环境创建对应的 `values-{env}.yaml` 文件

3. **测试新部署**
   ```bash
   # 先在开发环境测试
   ./helm-deploy.sh -e dev -d  # 干运行
   ./helm-deploy.sh -e dev     # 实际部署
   ```

4. **生产环境迁移**
   ```bash
   # 备份生产数据
   kubectl create backup...
   
   # 部署新版本
   ./helm-deploy.sh -e prod
   ```

## 常见问题

### Q: 如何添加新的服务？

A: 在 `values.yaml` 中添加新服务配置，并创建对应的模板文件：

```yaml
services:
  newservice:
    enabled: true
    name: mcp-newservice
    # ... 其他配置
```

### Q: 如何修改数据库连接配置？

A: 更新 `configs` 部分的配置模板：

```yaml
configs:
  gateway: |
    database:
      host: {{ .Values.infrastructure.mysql.service.name }}
      port: {{ .Values.infrastructure.mysql.service.port }}
      # ...
```

### Q: 如何处理配置文件中的敏感信息？

A: 使用 Kubernetes Secret 和 Helm 的 `lookup` 函数：

```yaml
# 创建 Secret
kubectl create secret generic app-secret --from-literal=api-key=xxx

# 在模板中引用
apiKey: {{ (lookup "v1" "Secret" .Values.global.namespace "app-secret").data.apiKey | b64dec }}
```

## 支持和贡献

如有问题或建议，请：

1. 查看本文档的故障排查部分
2. 检查 Helm Chart 的 lint 输出
3. 提交 Issue 或 Pull Request

---

**注意**: 在生产环境部署前，请务必：
- 仔细检查所有配置参数
- 在测试环境充分验证
- 准备回滚计划
- 备份重要数据