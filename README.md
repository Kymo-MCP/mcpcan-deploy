# 部署

## 软件架构设计

kubeadm 部署 k3s 集群

1. 核心服务 core
2. 认证服务 authz
3. 前端服务 web

## Helm 部署指南

### 前置条件

确保已安装以下工具：
- `helm` (Helm 3.x)
- `kubectl`
- 可访问的 Kubernetes 集群

### 环境配置

项目支持以下环境：
- `staging` - 测试环境

每个环境对应的配置文件：
- `helm/values-staging.yaml` - 测试环境配置

### 部署命令

#### 1. 测试环境部署

```bash
# 基本部署
helm install mcp-box ./helm --namespace mcp-box --create-namespace --timeout 600s --wait

# 升级部署
helm upgrade --install mcp-box ./helm --namespace mcp-box --timeout 600s --wait
```

### 卸载命令

#### 1. 卸载 Helm Release

```bash
# 卸载指定环境的部署
helm uninstall mcp-box --namespace mcp-box

# 卸载并等待完成
helm uninstall mcp-box --namespace mcp-box --wait

# 卸载并保留历史记录
helm uninstall mcp-box --namespace mcp-box --keep-history
```

#### 2. 清理资源

```bash
# 删除命名空间（会删除所有相关资源）
kubectl delete namespace mcp-box

# 删除持久化卷声明（如果需要）
kubectl delete pvc -n mcp-box --all

# 删除 ConfigMap 和 Secret
kubectl delete configmap -n mcp-box --all
kubectl delete secret -n mcp-box --all
```

### 常用管理命令

#### 查看部署状态

```bash
# 查看 Helm Release 状态
helm status mcp-box --namespace mcp-box

# 查看 Helm Release 历史
helm history mcp-box --namespace mcp-box

# 查看 Pod 状态
kubectl get pods -n mcp-box

# 查看服务状态
kubectl get svc -n mcp-box

# 查看 Ingress 状态
kubectl get ingress -n mcp-box
```

#### 日志查看

```bash
# 查看所有 Pod 日志
kubectl logs -n mcp-box -l app.kubernetes.io/instance=mcp-box

# 查看特定服务日志
kubectl logs -n mcp-box -l app=mcp-gateway
kubectl logs -n mcp-box -l app=mcp-authz
kubectl logs -n mcp-box -l app=mcp-market
kubectl logs -n mcp-box -l app=mcp-web

# 实时查看日志
kubectl logs -n mcp-box -l app=mcp-gateway -f
```

#### 配置管理

```bash
# 查看 ConfigMap
kubectl get configmap -n mcp-box
kubectl describe configmap mcp-config -n mcp-box

# 查看 Secret
kubectl get secret -n mcp-box
kubectl describe secret domain-tls -n mcp-box

# 更新配置后重启服务
kubectl rollout restart deployment/mcp-gateway -n mcp-box
kubectl rollout restart deployment/mcp-authz -n mcp-box
kubectl rollout restart deployment/mcp-market -n mcp-box
kubectl rollout restart deployment/mcp-web -n mcp-box
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
kubectl port-forward svc/mcp-web-svc 80:80 -n mcp-box
```

### 自定义部署参数

可以通过 `--set` 参数覆盖默认配置：

```bash
# 自定义镜像版本
helm upgrade --install mcp-box ./helm -f ./helm/values-staging.yaml \
  --set global.version=v1.2.3 \
  --namespace mcp-dev

# 自定义域名
helm upgrade --install mcp-box ./helm -f ./helm/values-staging.yaml \
  --set global.domain=my-custom-domain.com \
  --namespace mcp-dev

# 自定义资源限制
helm upgrade --install mcp-box ./helm -f ./helm/values-staging.yaml \
  --set services.gateway.resources.limits.memory=512Mi \
  --set services.gateway.resources.limits.cpu=500m \
  --namespace mcp-dev

# 禁用某个服务
helm upgrade --install mcp-box ./helm -f ./helm/values-staging.yaml \
  --set services.market.enabled=false \
  --namespace mcp-dev
```

### 注意事项

1. **命名空间管理**：建议为不同环境使用不同的命名空间
2. **资源监控**：部署后请监控资源使用情况，根据需要调整资源配置
3. **数据备份**：生产环境部署前请确保数据库和持久化数据已备份
4. **版本管理**：建议使用具体的版本标签而不是 `latest`
5. **安全配置**：生产环境请确保 TLS 证书和密钥配置正确


# shell 脚本

## 生成自签名证书

```bash
./scripts/generate-simple-cert.sh demo.mcp-box.com 3650
```
