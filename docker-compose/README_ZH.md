# MCPCan Docker Compose 部署指南

本文档提供了使用 Docker Compose 部署 MCPCan 系统的详细说明。该部署方案支持 HTTP/HTTPS 双协议访问，适合本地开发、测试或轻量级生产环境部署。

## 目录

1. [前置要求](#前置要求)
2. [快速开始](#快速开始)
   - [默认快速启动](#21-默认快速启动)
   - [自定义配置启动](#22-自定义配置启动)
3. [访问服务](#访问服务)
4. [高级配置](#高级配置)
   - [证书替换与热加载](#41-证书替换与热加载)
   - [自定义配置](#42-自定义配置)
5. [服务架构](#服务架构)
6. [数据持久化](#数据持久化)
7. [常见问题](#常见问题)

## 前置要求

- **Docker Engine**: 20.10.0+
- **Docker Compose**: v2.0.0+ (推荐使用 Docker Compose V2)

## 快速开始

进入部署目录：
```bash
cd docker-compose/
```

### 2.1 默认快速启动

如果你不需要修改任何端口或配置，直接运行以下命令即可启动（默认占用 80 和 443 端口）：

```bash
docker compose up -d
```
- **HTTP 访问**: [http://localhost](http://localhost) (默认端口 80)
- **HTTPS 访问**: [https://localhost](https://localhost) (默认端口 443)
此命令将使用仓库中预置的默认配置启动所有服务。

### 2.2 自定义配置启动

如果你需要修改数据库密码、端口、域名或镜像版本，请按以下步骤操作：

1. **创建配置文件**：
   复制示例环境文件：
   ```bash
   cp example.env .env
   ```
   使用编辑器修改 `.env` 中的变量（如 `MYSQL_PASSWORD`, `HOST_HTTP_PORT` 等）。

2. **生成配置并启动**：
   运行替换脚本，该脚本会根据 `.env` 生成新的服务配置文件（旧配置会自动备份），然后强制重新创建容器：
   ```bash
   ./replace.sh && docker compose up -d --force-recreate
   ```

   **启动流程说明**：
   1. 脚本根据模板和 `.env` 生成新的 yaml 配置文件到 `config/` 目录。
   2. 启动 MySQL 和 Redis，并等待健康检查通过。
   3. 运行 `mcp-init` 进行初始化（数据库迁移/种子数据）。
   4. 启动后端服务 (`mcp-authz`, `mcp-market`, `mcp-gateway`)。
   5. 启动网关代理 (`traefik`) 和前端服务 (`mcp-web`)。

## 访问服务

系统默认同时开启 HTTP 和 HTTPS 访问，且互不干扰（不会强制跳转）。

- **HTTP 访问**: [http://localhost](http://localhost) (默认端口 80)
- **HTTPS 访问**: [https://localhost](https://localhost) (默认端口 443)
  - *注意：默认使用自签名证书，浏览器可能会提示不安全，请点击“继续访问”或“高级 -> 继续”。*

| 服务 | URL (HTTP) | URL (HTTPS) |
|------|------------|-------------|
| **Web 前端** | http://localhost | https://localhost |
| **API 网关** | http://localhost/mcp-gateway | https://localhost/mcp-gateway |

*(端口取决于 `.env` 中的 `MCP_ENTRY_SERVICE_PORT` 和 `MCP_ENTRY_SERVICE_HTTPS_PORT`)*

## 高级配置

### 4.1 证书替换与热加载

MCPCan 使用 Traefik 作为入口网关，支持 TLS 证书的动态热加载，无需重启服务。

1. **准备证书**：
   准备好你的域名证书文件（例如 `my-domain.crt` 和 `my-domain.key`）。

2. **替换文件**：
   将证书文件放入 `certs/` 目录（或你挂载的目录）。

3. **修改配置**：
   编辑 `config/dynamic.yaml` 文件，更新 `tls` 部分的路径：
   ```yaml
   tls:
     certificates:
       - certFile: /etc/traefik/certs/my-domain.crt
         keyFile: /etc/traefik/certs/my-domain.key
   ```
   *注意：这里的路径是容器内的路径，默认挂载映射为宿主机 `./certs` -> 容器 `/etc/traefik/certs`。*

4. **自动生效**：
   保存 `dynamic.yaml` 后，Traefik 会自动检测文件变化并加载新证书，无需任何重启操作。

### 4.2 自定义配置

为了模拟 Kubernetes ConfigMap，我们在 `config/` 目录下生成了各服务的配置文件。

- **模板文件**：位于 `config-template/`，包含变量占位符。
- **生成文件**：位于 `config/`，由 `./replace.sh` 生成。
- **注意**：如果你修改了 `.env`，**必须**重新运行 `./replace.sh` 才能将变更应用到 `config/` 下的实际配置文件中。

## 服务架构

| 服务名称 | 描述 | 依赖 | 默认端口 |
|---------|------|------|---------|
| **traefik** | 入口网关 (Ingress) | - | 80, 443, 8080 |
| **mysql** | 数据存储 | - | 31306 -> 3306 |
| **redis** | 缓存与消息队列 | - | 31379 -> 6379 |
| **mcp-init** | 初始化任务 (运行完即止) | mysql, redis | - |
| **mcp-authz** | 认证与授权服务 | mysql, redis, mcp-init | 8081 |
| **mcp-market** | 插件/代码包市场服务 | mysql, redis, mcp-init, mcp-authz | 8080 |
| **mcp-gateway** | API 网关 | mysql, redis, mcp-market, mcp-authz | 8082 |
| **mcp-web** | 前端 UI | mcp-gateway | 3000 |

## 数据持久化

数据默认存储在当前目录下的 `data/` 目录（由 `.env` 中的 `HOST_DATA_PATH` 控制）：

- `data/mysql`: MySQL 数据库文件
- `data/redis`: Redis 数据文件
- `data/mcpcan`: 应用上传的文件、代码包等

**清理数据**（慎用）：
如果要彻底重置环境，停止容器并删除 data 目录：
```bash
docker compose down
rm -rf ./data
```

## 常见问题

**Q: HTTPS 访问时浏览器提示证书无效？**
A: 这是正常的，因为默认使用的是自签名证书。你可以按照 [4.1 证书替换与热加载](#41-证书替换与热加载) 章节替换为你自己的有效证书。

**Q: 修改了 config/ 下的文件，重启后被覆盖了？**
A: 如果你运行了 `./replace.sh`，它会根据模板重新生成配置文件。如果你想永久修改配置，请修改 `config-template/` 下的模板文件，或者直接修改 `config/` 下的文件但不要再运行 `replace.sh`。

**Q: 容器启动失败，报错 "Connection refused"？**
A: 检查 `docker compose logs mcp-init` 或其他服务日志。通常是因为数据库尚未就绪。Docker Compose 配置了 `healthcheck`，但如果机器性能较慢，可能需要增加超时时间。
