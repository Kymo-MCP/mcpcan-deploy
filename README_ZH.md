# MCPCan 部署指南

本文档提供了使用 Docker Compose 部署 MCPCan 系统的详细说明，这是目前推荐的部署方式。如果需要 Kubernetes 部署，请参考 [Helm 快速开始](#helm-快速开始)。

## 项目链接

- 🌐 [官网 (Official Site)](https://www.mcpcan.com)
- 📚 [文档 (Documentation)](https://www.mcpcan.com/docs/en/guide/welcome)
- 🎮 [在线演示 (Live Demo)](http://demo.mcpcan.com)
- 📦 [主仓库 (Main Repository)](https://github.com/Kymo-MCP/mcpcan)
- 🚀 [部署仓库 (Deployment Repository)](https://github.com/Kymo-MCP/mcpcan-deploy)

## 目录

1. [Docker Compose 部署](#docker-compose-部署)
   - [前置要求](#前置要求)
   - [快速开始](#快速开始)
   - [自定义配置](#自定义配置)
   - [常用维护命令](#常用维护命令)
   - [服务架构](#服务架构)
   - [高级配置](#高级配置)
   - [常见问题](#常见问题)
2. [Helm 快速开始](#helm-快速开始)

## Docker Compose 部署

该部署方案支持 HTTP/HTTPS 双协议访问，适合本地开发、测试或轻量级生产环境部署。

### 前置要求

在开始之前，请确保您的环境满足以下要求：

- **操作系统**: Linux (推荐 Ubuntu/CentOS) 或 macOS
- **Docker Engine**: 20.10.0+
- **Docker Compose**: v2.0.0+ (推荐使用 Docker Compose V2 插件命令 `docker compose`)
- **硬件资源**: 
  - CPU: 2 Core+
  - Memory: 4GB+
  - Disk: 10GB+

### 快速开始

#### 1. 获取代码

```bash
# GitHub (国际网络)
git clone https://github.com/Kymo-MCP/mcpcan-deploy.git
cd mcpcan-deploy/docker-compose

# Gitee (中国网络推荐)
git clone https://gitee.com/kymomcp/mcpcan-deploy.git
cd mcpcan-deploy/docker-compose
```

#### 2. 准备工作

1. **初始化环境配置**：
   复制示例环境文件 `example.env` 为 `.env`。该文件包含了所有核心配置（如端口、数据库密码、版本号等）。
   ```bash
   cp example.env .env
   ```
   *(可选) 使用文本编辑器（如 `vim` 或 `nano`）修改 `.env` 文件中的配置，例如修改默认端口 `MCP_ENTRY_SERVICE_PORT`。*

2. **生成服务配置**：
   运行配置生成脚本。该脚本会读取 `.env` 中的变量，并根据 `config-template/` 中的模板生成最终的配置文件到 `config/` 目录。
   ```bash
   chmod +x replace.sh
   ./replace.sh
   ```
   *注意：如果后续修改了 `.env`，必须重新运行此脚本以应用变更。*

#### 3. 启动服务

使用 Docker Compose 启动所有服务。首次启动会自动拉取镜像并进行数据库初始化。

```bash
docker compose up -d

# 默认登录凭证
登录: admin/admin123
```

**启动流程说明**：
1. **基础服务启动**: MySQL 和 Redis 率先启动。
2. **健康检查**: 等待 MySQL 和 Redis 状态变为 `healthy`。
3. **初始化**: `mcp-init` 容器启动，执行数据库迁移和种子数据写入。
4. **核心服务启动**: `mcp-init` **成功退出**后，`mcp-authz`, `mcp-market`, `mcp-gateway` 等核心服务启动。
5. **接入层启动**: 最后启动 `mcp-web` 和 `traefik` 网关，对外提供服务。

#### 4. 验证安装

服务启动完成后（通常需等待 1-2 分钟），可以通过浏览器访问：

- **Web 前端**: [http://localhost](http://localhost) (或您配置的 HTTP 端口)
- **HTTPS 访问**: [https://localhost](https://localhost) (或您配置的 HTTPS 端口)
  - *注意：默认使用自签名证书，浏览器会提示不安全，请点击“继续前往”即可。*

查看运行状态：
```bash
docker compose ps
```
确保所有服务状态为 `Up` (或 `Up (healthy)`)，且 `mcp-init` 状态为 `Exited (0)`。

### 自定义配置

#### 环境变量配置

主要配置均在 `.env` 文件中管理。修改后需运行 `./replace.sh` 生效。

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `VERSION` | latest | 镜像版本标签 |
| `MCP_ENTRY_SERVICE_PORT` | 80 | HTTP 访问端口 |
| `MCP_ENTRY_SERVICE_HTTPS_PORT` | 443 | HTTPS 访问端口 |
| `MYSQL_PASSWORD` | (见文件) | 数据库密码 |
| `RUN_MODE` | prod | 运行模式 (demo/prod) |

#### 配置热更新

生成的配置文件位于 `config/` 目录。
- **临时修改**: 直接修改 `config/` 下的文件，重启相关容器生效（运行 `./replace.sh` 会覆盖此修改）。
- **永久修改**: 修改 `config-template/` 下的模板文件，然后运行 `./replace.sh`。

### 常用维护命令

以下命令均需在 `docker-compose/` 目录下执行。

#### 更新镜像并重启
当发布了新版本镜像（修改了 `.env` 中的 `VERSION`）时使用：
```bash
# 1. 拉取最新镜像
docker compose pull

# 2. 重新创建并启动容器（仅重建有变更的容器）
docker compose up -d
```

#### 强制重建容器
如果修改了配置文件或想彻底重置容器运行状态：
```bash
# --force-recreate 强制销毁旧容器并创建新容器
docker compose up -d --force-recreate
```

#### 重启所有服务
仅重启容器，不删除容器，不更新镜像：
```bash
docker compose restart
```

#### 停止服务
```bash
# 停止并移除容器、网络（保留数据卷）
docker compose down
```

#### 查看服务日志
```bash
# 查看所有日志 (Ctrl+C 退出)
docker compose logs -f

# 查看特定服务日志 (如 mcp-gateway)
docker compose logs -f mcp-gateway

# 查看初始化任务日志 (排查启动失败问题)
docker compose logs mcp-init
```

#### 清理未使用的镜像
清理不再使用的旧镜像以释放磁盘空间：
```bash
docker image prune -f
```

#### 彻底清理环境 (慎用)
**警告**: 此操作将删除所有容器、网络以及**持久化的数据**（数据库、上传文件等）。
```bash
docker compose down
rm -rf ./data
```

### 服务架构

| 服务名称 | 描述 | 依赖关系 |
|---------|------|----------|
| **traefik** | 统一入口网关，处理 HTTP/HTTPS 路由 | - |
| **mcp-init** | 初始化任务 (DB Migration/Seed)，运行完即退出 | 依赖 MySQL/Redis 健康 |
| **mcp-authz** | 认证与授权服务 | 等待 mcp-init 完成 |
| **mcp-market** | 插件市场核心服务 | 等待 mcp-init 完成 |
| **mcp-gateway** | API 网关服务 | 等待 mcp-init 完成 |
| **mcp-web** | 前端静态资源服务 | 依赖后端服务启动 |

### 高级配置

#### 证书替换与热加载

MCPCan 支持 TLS 证书动态热加载，无需重启服务。

1. 准备证书文件（`.crt`, `.key`）。
2. 将证书放入 `certs/` 目录。
3. 修改 `config/dynamic.yaml` 中的证书路径配置。
4. Traefik 会自动检测并应用新证书。

### 常见问题

**Q: `mcp-market` 等服务一直处于 `Created` 状态不启动？**
A: 这是正常的依赖等待机制。它们配置了 `condition: service_completed_successfully`，必须等待 `mcp-init` 容器成功运行结束（Exit 0）后才会启动。请检查 `mcp-init` 的日志确认初始化是否成功：
```bash
docker compose logs mcp-init
```

**Q: 如何修改数据库密码？**
A: 修改 `.env` 中的 `MYSQL_PASSWORD`，然后**必须**删除旧的数据库数据（`rm -rf data/mysql`），再重新运行 `./replace.sh && docker compose up -d`。因为 MySQL 仅在首次初始化数据目录时设置密码。

---

## Helm 快速开始

适用于 Kubernetes 环境部署。

### 极速安装脚本

此路径会自动安装 k3s、ingress‑nginx、Helm，并部署 MCPCAN 平台；适合没有预装 Kubernetes 组件的全新环境。

```bash
# 1. 切换到根目录
cd ..

# 2. 执行安装脚本
# 标准极速安装（国际镜像源）
./scripts/install-fast.sh

# 极速安装（中国镜像源加速）
./scripts/install-fast.sh --cn
```

成功后脚本会校验 Helm 发布状态并打印访问地址。

更多 Helm 自定义配置和详细说明，请查看 [Helm Chart 仓库](https://kymo-mcp.github.io/mcpcan-deploy/)。
