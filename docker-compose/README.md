# MCPCan Docker Compose Deployment Guide

This document provides detailed instructions for deploying the MCPCan system using Docker Compose. This deployment scheme supports dual HTTP/HTTPS access and is suitable for local development, testing, or lightweight production environments.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
   - [Preparation](#21-preparation)
   - [Start Services](#22-start-services)
   - [Verify Installation](#23-verify-installation)
3. [Custom Configuration](#custom-configuration)
   - [Environment Variables](#31-environment-variables)
   - [Configuration Hot Reload](#32-configuration-hot-reload)
4. [Common Maintenance Commands](#common-maintenance-commands)
5. [Service Architecture](#service-architecture)
6. [Advanced Configuration](#advanced-configuration)
   - [Certificate Replacement & Hot Reloading](#61-certificate-replacement--hot-reloading)
7. [FAQ](#faq)

## Prerequisites

Before starting, please ensure your environment meets the following requirements:

- **OS**: Linux (Ubuntu/CentOS recommended) or macOS
- **Docker Engine**: 20.10.0+
- **Docker Compose**: v2.0.0+ (Docker Compose V2 plugin command `docker compose` is recommended)
- **Hardware Resources**:
  - CPU: 2 Core+
  - Memory: 4GB+
  - Disk: 10GB+

## Quick Start

### 2.1 Preparation

1. **Enter the deployment directory**:
   ```bash
   cd mcpcan-deploy/docker-compose/
   ```

2. **Initialize Environment Configuration**:
   Copy the example environment file `example.env` to `.env`. This file contains all core configurations (such as ports, database passwords, version numbers, etc.).
   ```bash
   cp example.env .env
   ```
   *(Optional) Use a text editor (such as `vim` or `nano`) to modify configurations in the `.env` file, for example, modifying the default port `MCP_ENTRY_SERVICE_PORT`.*

3. **Generate Service Configuration**:
   Run the configuration generation script. This script reads variables from `.env` and generates the final configuration files into the `config/` directory based on templates in `config-template/`.
   ```bash
   chmod +x replace.sh
   ./replace.sh
   ```
   *Note: If you modify `.env` later, you must re-run this script to apply the changes.*

### 2.2 Start Services

Use Docker Compose to start all services. The first startup will automatically pull images and perform database initialization.

```bash
docker compose up -d
```

**Startup Process Explanation**:
1. **Basic Services Start**: MySQL and Redis start first.
2. **Health Check**: Wait for MySQL and Redis status to become `healthy`.
3. **Initialization**: The `mcp-init` container starts, executing database migrations and seed data writing.
4. **Core Services Start**: After `mcp-init` **successfully exits**, core services like `mcp-authz`, `mcp-market`, and `mcp-gateway` start.
5. **Access Layer Start**: Finally, `mcp-web` and the `traefik` gateway start to provide external services.

### 2.3 Verify Installation

After the service startup is complete (usually wait 1-2 minutes), you can access via browser:

- **Web Frontend**: [http://localhost](http://localhost) (or your configured HTTP port)
- **HTTPS Access**: [https://localhost](https://localhost) (or your configured HTTPS port)
  - *Note: A self-signed certificate is used by default. The browser will prompt that it is insecure; please click "Proceed" to continue.*

Check running status:
```bash
docker compose ps
```
Ensure all service statuses are `Up` (or `Up (healthy)`), and the `mcp-init` status is `Exited (0)`.

## Custom Configuration

### 3.1 Environment Variables

Main configurations are managed in the `.env` file. After modification, run `./replace.sh` to take effect.

| Variable Name | Default Value | Description |
|--------|--------|------|
| `VERSION` | latest | Image version tag |
| `MCP_ENTRY_SERVICE_PORT` | 80 | HTTP access port |
| `MCP_ENTRY_SERVICE_HTTPS_PORT` | 443 | HTTPS access port |
| `MYSQL_PASSWORD` | (see file) | Database password |
| `RUN_MODE` | prod | Run mode (demo/prod) |

### 3.2 Configuration Hot Reload

Generated configuration files are located in the `config/` directory.
- **Temporary Modification**: Directly modify files under `config/`, restart related containers to take effect (running `./replace.sh` will overwrite this modification).
- **Permanent Modification**: Modify template files under `config-template/`, then run `./replace.sh`.

## Common Maintenance Commands

The following commands need to be executed in the `docker-compose/` directory.

### Update Image and Restart
Use when a new version of the image is released (modified `VERSION` in `.env`):
```bash
# 1. Pull the latest image
docker compose pull

# 2. Recreate and start containers (only recreate changed containers)
docker compose up -d
```

### Force Recreate Containers
If you modified configuration files or want to completely reset container running status:
```bash
# --force-recreate forces destruction of old containers and creation of new ones
docker compose up -d --force-recreate
```

### Restart All Services
Only restart containers, do not delete containers, do not update images:
```bash
docker compose restart
```

### Stop Services
```bash
# Stop and remove containers, networks (preserve data volumes)
docker compose down
```

### View Service Logs
```bash
# View all logs (Ctrl+C to exit)
docker compose logs -f

# View specific service logs (e.g., mcp-gateway)
docker compose logs -f mcp-gateway

# View initialization task logs (troubleshoot startup failures)
docker compose logs mcp-init
```

### Clean Unused Images
Clean up old images no longer in use to free up disk space:
```bash
docker image prune -f
```

### Completely Clean Environment (Use with Caution)
**Warning**: This operation will delete all containers, networks, and **persistent data** (database, uploaded files, etc.).
```bash
docker compose down
rm -rf ./data
```

## Service Architecture

| Service Name | Description | Dependencies |
|---------|------|----------|
| **traefik** | Unified Ingress Gateway, handles HTTP/HTTPS routing | - |
| **mcp-init** | Initialization Task (DB Migration/Seed), exits after completion | Depends on MySQL/Redis health |
| **mcp-authz** | Authentication & Authorization Service | Waits for mcp-init to complete |
| **mcp-market** | Plugin Market Core Service | Waits for mcp-init to complete |
| **mcp-gateway** | API Gateway Service | Waits for mcp-init to complete |
| **mcp-web** | Frontend Static Resource Service | Depends on backend services start |

## Advanced Configuration

### 6.1 Certificate Replacement & Hot Reloading

MCPCan supports dynamic hot reloading of TLS certificates without restarting services.

1. Prepare certificate files (`.crt`, `.key`).
2. Place certificates into the `certs/` directory.
3. Modify the certificate path configuration in `config/dynamic.yaml`.
4. Traefik will automatically detect and apply the new certificate.

## FAQ

**Q: `mcp-market` and other services stay in `Created` status and don't start?**
A: This is a normal dependency waiting mechanism. They are configured with `condition: service_completed_successfully` and must wait for the `mcp-init` container to successfully finish running (Exit 0) before starting. Please check the `mcp-init` logs to confirm if initialization was successful:
```bash
docker compose logs mcp-init
```

**Q: How to modify the database password?**
A: Modify `MYSQL_PASSWORD` in `.env`, then you **MUST** delete the old database data (`rm -rf data/mysql`), and re-run `./replace.sh && docker compose up -d`. Because MySQL only sets the password when initializing the data directory for the first time.
