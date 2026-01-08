# MCPCan Deployment Guide

This document provides detailed instructions for deploying the MCPCan system using Docker Compose, which is the currently recommended deployment method. If you need Kubernetes deployment, please refer to [Helm Quick Start](#helm-quick-start).

## Table of Contents

1. [Docker Compose Deployment](#docker-compose-deployment)
   - [Prerequisites](#prerequisites)
   - [Quick Start](#quick-start)
   - [Custom Configuration](#custom-configuration)
   - [Common Maintenance Commands](#common-maintenance-commands)
   - [Service Architecture](#service-architecture)
   - [Advanced Configuration](#advanced-configuration)
   - [FAQ](#faq)
2. [Helm Quick Start](#helm-quick-start)

## Docker Compose Deployment

This deployment scheme supports dual protocol access via HTTP/HTTPS, suitable for local development, testing, or lightweight production environment deployments.

### Prerequisites

Before starting, please ensure your environment meets the following requirements:

- **Operating System**: Linux (Ubuntu/CentOS recommended) or macOS
- **Docker Engine**: 20.10.0+
- **Docker Compose**: v2.0.0+ (Docker Compose V2 plugin command `docker compose` is recommended)
- **Hardware Resources**:
  - CPU: 2 Core+
  - Memory: 4GB+
  - Disk: 10GB+

### Quick Start

#### 1. Get Code

```bash
# GitHub (International Network)
git clone https://github.com/Kymo-MCP/mcpcan-deploy.git
cd mcpcan-deploy/docker-compose

# Gitee (Recommended for China Network)
git clone https://gitee.com/kymomcp/mcpcan-deploy.git
cd mcpcan-deploy/docker-compose
```

#### 2. Preparation

1.  **Initialize Environment Configuration**:
    Copy the example environment file `example.env` to `.env`. This file contains all core configurations (such as ports, database passwords, version numbers, etc.).
    ```bash
    cp example.env .env
    ```
    *(Optional) Use a text editor (such as `vim` or `nano`) to modify the configuration in the `.env` file, for example, modifying the default port `MCP_ENTRY_SERVICE_PORT`.*

2.  **Generate Service Configuration**:
    Run the configuration generation script. This script will read variables from `.env` and generate the final configuration files into the `config/` directory based on templates in `config-template/`.
    ```bash
    chmod +x replace.sh
    ./replace.sh
    ```
    *Note: If you modify `.env` later, you must re-run this script to apply changes.*

#### 3. Start Services

Use Docker Compose to start all services. The first startup will automatically pull images and initialize the database.

```bash
docker compose up -d
```

**Startup Process Description**:
1.  **Base Service Startup**: MySQL and Redis start first.
2.  **Health Check**: Wait for MySQL and Redis status to become `healthy`.
3.  **Initialization**: The `mcp-init` container starts, executing database migration and seed data writing.
4.  **Core Service Startup**: After `mcp-init` **exits successfully**, core services such as `mcp-authz`, `mcp-market`, and `mcp-gateway` start.
5.  **Access Layer Startup**: Finally, `mcp-web` and `traefik` gateway start, providing services externally.

#### 4. Verify Installation

After the services start (usually takes 1-2 minutes), you can access via browser:

-   **Web Frontend**: [http://localhost](http://localhost) (or your configured HTTP port)
-   **HTTPS Access**: [https://localhost](https://localhost) (or your configured HTTPS port)
    -   *Note: Default uses a self-signed certificate; the browser will prompt it as insecure, please click "Proceed" to continue.*

Check running status:
```bash
docker compose ps
```
Ensure all service statuses are `Up` (or `Up (healthy)`), and `mcp-init` status is `Exited (0)`.

### Custom Configuration

#### Environment Variable Configuration

Main configurations are managed in the `.env` file. After modification, run `./replace.sh` to take effect.

| Variable Name | Default Value | Description |
| :--- | :--- | :--- |
| `VERSION` | latest | Image version tag |
| `MCP_ENTRY_SERVICE_PORT` | 80 | HTTP access port |
| `MCP_ENTRY_SERVICE_HTTPS_PORT` | 443 | HTTPS access port |
| `MYSQL_PASSWORD` | (see file) | Database password |
| `RUN_MODE` | prod | Running mode (demo/prod) |

#### Configuration Hot Update

Generated configuration files are located in the `config/` directory.
-   **Temporary Modification**: Directly modify files under `config/`, restart relevant containers to take effect (running `./replace.sh` will overwrite this modification).
-   **Permanent Modification**: Modify template files under `config-template/`, then run `./replace.sh`.

### Common Maintenance Commands

The following commands need to be executed in the `docker-compose/` directory.

#### Update Image and Restart
Use when a new version image is released (modified `VERSION` in `.env`):
```bash
# 1. Pull latest images
docker compose pull

# 2. Recreate and start containers (only recreate changed containers)
docker compose up -d
```

#### Force Recreate Containers
If configuration files are modified or you want to completely reset container running status:
```bash
# --force-recreate Force destroy old containers and create new ones
docker compose up -d --force-recreate
```

#### Restart All Services
Only restart containers, do not delete containers, do not update images:
```bash
docker compose restart
```

#### Stop Services
```bash
# Stop and remove containers, networks (retain data volumes)
docker compose down
```

#### View Service Logs
```bash
# View all logs (Ctrl+C to exit)
docker compose logs -f

# View specific service logs (e.g., mcp-gateway)
docker compose logs -f mcp-gateway

# View initialization task logs (troubleshoot startup failures)
docker compose logs mcp-init
```

#### Clean Unused Images
Clean up old images no longer in use to free up disk space:
```bash
docker image prune -f
```

#### Completely Clean Environment (Use with Caution)
**Warning**: This operation will delete all containers, networks, and **persistent data** (database, uploaded files, etc.).
```bash
docker compose down
rm -rf ./data
```

### Service Architecture

| Service Name | Description | Dependencies |
| :--- | :--- | :--- |
| **traefik** | Unified ingress gateway, handling HTTP/HTTPS routing | - |
| **mcp-init** | Initialization task (DB Migration/Seed), exits after completion | Depends on MySQL/Redis health |
| **mcp-authz** | Authentication and authorization service | Waits for mcp-init to complete |
| **mcp-market** | Plugin market core service | Waits for mcp-init to complete |
| **mcp-gateway** | API gateway service | Waits for mcp-init to complete |
| **mcp-web** | Frontend static resource service | Depends on backend service startup |

### Advanced Configuration

#### Certificate Replacement and Hot Loading

MCPCan supports TLS certificate dynamic hot loading without restarting services.

1.  Prepare certificate files (`.crt`, `.key`).
2.  Place certificates into the `certs/` directory.
3.  Modify certificate path configuration in `config/dynamic.yaml`.
4.  Traefik will automatically detect and apply new certificates.

### FAQ

**Q: Why do services like `mcp-market` stay in `Created` status and not start?**
A: This is a normal dependency waiting mechanism. They are configured with `condition: service_completed_successfully`, and must wait for the `mcp-init` container to successfully run and finish (Exit 0) before starting. Please check `mcp-init` logs to confirm if initialization was successful:
```bash
docker compose logs mcp-init
```

**Q: How to modify the database password?**
A: Modify `MYSQL_PASSWORD` in `.env`, then **must** delete old database data (`rm -rf data/mysql`), and re-run `./replace.sh && docker compose up -d`. Because MySQL only sets the password when initializing the data directory for the first time.

---

## Helm Quick Start

Suitable for Kubernetes environment deployment.

### Fast Install Script

This path automatically installs k3s, ingress-nginx, Helm, and deploys the MCPCAN platform; suitable for fresh environments without pre-installed Kubernetes components.

```bash
# 1. Switch to root directory
cd ..

# 2. Execute installation script
# Standard Fast Install (International Mirrors)
./scripts/install-fast.sh

# Fast Install (Accelerated with China Mirrors)
./scripts/install-fast.sh --cn
```

Upon success, the script verifies the Helm release status and prints the access URL.

For more Helm custom configurations and detailed instructions, please view the [Helm Chart Repository](https://kymo-mcp.github.io/mcpcan-deploy/).
