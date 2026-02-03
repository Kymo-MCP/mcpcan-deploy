# MCPCan 部署指南 (mcpcan.itqm.com)

本文档描述了如何为 `mcpcan.itqm.com` 部署 MCPCan 环境。

## 先决条件

- Kubernetes 集群 (v1.20+)
- 本地安装 Helm 3
- 配置了集群访问权限的 `kubectl`

## 环境信息

- **环境**: `mcpcan.itqm.com`
- **命名空间**: `mcpcan`
- **配置文件 (Values)**: `env/mcpcan-itqm-com/values-mcpcan-itqm-com.yaml`
- **域名**: `mcpcan.itqm.com`

## 部署命令

请在项目根目录 (`mcpcan-mainsite`) 下运行以下命令。

### 1. 首次安装 (Fresh Installation)

首次安装发布版本：

```bash
helm install mcpcan ./helm \
  -f ./helm/values-mcpcan-itqm-com.yaml \
  --namespace mcpcan \
  --create-namespace \
  --timeout 600s \
  --wait
```

### 2. 升级 (Upgrade)

升级现有发布版本：

```bash
helm upgrade mcpcan ./helm \
  -f ./helm/values-mcpcan-itqm-com.yaml \
  --namespace mcpcan \
  --timeout 600s \
  --wait
```

### 3. 卸载 (Uninstall)

移除部署：

```bash
helm uninstall mcpcan --namespace mcpcan
```

## 验证

检查 Pod 状态：

```bash
kubectl get pods -n mcpcan
```

## 访问信息

- **URL**: [https://mcpcan.itqm.com](https://mcpcan.itqm.com)
- **默认管理员用户**: `admin`
- **默认密码**: `S5fy3du88OQT9B`

> **注意**: 请在首次登录后修改默认密码。
