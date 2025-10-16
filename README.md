# MCP-Box Helm Charts

这是 MCP-Box 项目的官方 Helm Charts 仓库。

## 使用方法

### 添加 Helm 仓库

```bash
helm repo add mcp-box https://kymo-mcp.github.io/mcp-box-deploy/
helm repo update
```

### 安装 MCP-Box

```bash
# 使用默认配置安装
helm install mcp-box mcp-box/mcp-box

# 使用自定义配置安装
helm install mcp-box mcp-box/mcp-box -f values-custom.yaml
```

### 升级 MCP-Box

```bash
helm upgrade mcp-box mcp-box/mcp-box
```

## 可用版本

- 当前版本: v1.0.0-dev
- 更新时间: 2025年10月16日 星期四 18时50分55秒 CST

## 支持

如有问题，请访问 [GitHub Issues](https://github.com/Kymo-MCP/mcp-box-deploy/issues)
