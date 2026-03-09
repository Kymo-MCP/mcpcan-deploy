# HTTPS / TLS 部署方案指南 (BYOC)

本指南面向需要使用自有商业证书或自签名证书为 MCPCan 开启 HTTPS 访问的用户。

## 方案协议

为了保持主部署文件的精简，我们采用了 **Docker Compose Override** 机制。默认情况下，系统仅开启 HTTP (80 端口)。

## 快速配置步骤

### 1. 准备证书文件

在 `docker-compose.yml` 同级目录下创建 `certs` 文件夹，并将您的证书和私钥放入其中：

- `certs/server.crt`
- `certs/server.key`

> [!TIP]
> 如果您的文件名不同，请在下一步中修改配置文件中的路径。

### 2. 配置 Traefik TLS 声明

编辑 `https-setup/tls-config.yaml` 文件，确保路径指向镜像内的挂载位置：

```yaml
tls:
  certificates:
    - certFile: /etc/traefik/certs/server.crt # 对应外部的 ./certs/server.crt
      keyFile: /etc/traefik/certs/server.key # 对应外部的 ./certs/server.key
```

### 3. 启动服务 (关键)

使用双文件模式启动 Docker Compose，这会自动合并主配置与 HTTPS 扩展配置：

```bash
docker-compose -f docker-compose.yml -f docker-compose.tls.yml up -d
```

## 验证

- 访问 `https://YOUR_DOMAIN`。
- 检查 `mcp-entry` (Traefik) 的日志以确认证书是否加载成功：
  ```bash
  docker logs -f mcp-entry
  ```

## 常见问题

- **端口冲突**：如果 443 端口被占用，请在 `.env` 中修改 `MCP_ENTRY_SERVICE_HTTPS_PORT`。
- **证书链不完整**：如果浏览器提示证书不可信，请确保 `server.crt` 包含了完整的证书链（Full Chain）。
