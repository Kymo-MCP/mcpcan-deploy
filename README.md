# MCPCan Deployment Guide

## [Environment Dependencies](#dependencies)

Before starting deployment, please ensure your environment meets the following requirements:

- **Kubernetes**: 1.20 or higher
- **Helm**: 3.0 or higher
- **NGINX Ingress Controller**: Required if ingress is enabled (for domain access)
- **Persistent Storage**: For data persistence
- **Resource Requirements**: At least 4GB RAM and 2 CPU cores

## Quick Start ([View Helm Chart Repository:https://kymo-mcp.github.io/mcpcan-deploy/](https://kymo-mcp.github.io/mcpcan-deploy/))

This document provides two installation paths to help you deploy the MCPCAN management platform in different scenarios.

- **Fast Install Script**: Suitable for clean Linux servers, automatically installs dependencies and the platform. Recommended for quick experience via IP access.
- **Custom Install (Helm)**: Suitable for scenarios requiring custom domains, enabling HTTPS, modifying default accounts/passwords, or platform configurations.

### 1. Get Deployment Repository

Select the repository source based on your network environment:

```bash
# GitHub (International)
git clone https://github.com/Kymo-MCP/mcpcan-deploy.git
cd mcpcan-deploy

# Gitee (Recommended for China)
git clone https://gitee.com/kymomcp/mcpcan-deploy.git
cd mcpcan-deploy
```

### 2. Installation Paths

#### Path A: Fast Install (Recommended for IP Access)

This path automatically installs k3s, ingress-nginx, Helm, and deploys the MCPCAN platform. Suitable for fresh environments without pre-installed Kubernetes components.

```bash
# Standard Fast Install (International Mirrors)
./scripts/install-fast.sh

# Fast Install (Accelerated with China Mirrors)
./scripts/install-fast.sh --cn
```

Upon success, the script verifies the Helm release status and prints the access URL:
- Public IP: `http://<public-ip>` (Automatically detected)
- Local Fallback: `http://localhost`

#### Path B: Custom Install (Domain/HTTPS/Configuration)

Follow these steps when you need to use a custom domain, enable HTTPS, or adjust default configurations.

**Step 1: Install Dependencies (k3s, ingress-nginx, Helm)**

Suitable for clean environments. If you already have k3s/ingress-nginx/Helm, skip this section.

```bash
# Install k3s, ingress-nginx, and Helm
./scripts/install-run-environment.sh

# Install k3s, ingress-nginx, and Helm (China Mirrors)
./scripts/install-run-environment.sh --cn
```

**Step 2: Configure and Install**

```bash
# 1. Copy default configuration file
cp helm/values.yaml helm/values-custom.yaml

# 2. Edit custom configuration file (Set domain, TLS, etc.)
# vi helm/values-custom.yaml

# 3. Install
helm install mcpcan ./helm -f helm/values-custom.yaml \
  --namespace mcpcan --create-namespace --timeout 600s --wait
```

## Core Scripts Guide

The project provides multiple utility scripts to simplify deployment and management. Here is a guide for the three core scripts:

### 1. Fast Install Script (`install-fast.sh`)
**Purpose**: One-click installation and deployment of all components in a clean Linux environment.
**Features**:
- Automatically detects and installs K3s, Helm, Ingress-Nginx.
- Automatically deploys the MCPCAN platform.
- Supports `--cn` parameter for accelerated installation using domestic mirrors.
**Usage**:
```bash
./scripts/install-fast.sh [--cn]
```

### 2. Runtime Environment Install Script (`install-run-environment.sh`)
**Purpose**: Installs only the Kubernetes base runtime environment without deploying MCPCAN business applications.
**Features**:
- Installs K3s cluster.
- Installs Helm package manager.
- Installs Ingress-Nginx controller.
- Suitable for scenarios requiring custom configuration for MCPCAN installation.
**Usage**:
```bash
./scripts/install-run-environment.sh [--cn]
```

### 3. Uninstall Script (`uninstall.sh`)
**Purpose**: Completely uninstalls MCPCAN and its runtime environment.
**Warning**: This operation will delete the K3s cluster and all data. Please use with caution.
**Usage**:
```bash
./scripts/uninstall.sh
```

## Detailed Helm Usage Guide

This section details common Helm commands for managing MCPCAN deployments.

### 1. Install
Deploy the Chart into the Kubernetes cluster.

```bash
# Basic installation
helm install mcpcan ./helm --namespace mcpcan --create-namespace

# Install using custom configuration file
helm install mcpcan ./helm -f helm/values-custom.yaml --namespace mcpcan --create-namespace

# Common parameters:
# --namespace: Specify namespace
# --create-namespace: Create namespace if it doesn't exist
# --wait: Wait for all Pods to be ready before returning
# --timeout: Set timeout for waiting
```

### 2. Upgrade
Update the existing Release after modifying configuration or upgrading versions.

```bash
# Update configuration
helm upgrade mcpcan ./helm -f helm/values-custom.yaml --namespace mcpcan

# Dynamically modify a single configuration item
helm upgrade mcpcan ./helm --set global.domain=new.example.com --namespace mcpcan
```

### 3. View Status (Status & List)
View deployment status and version history.

```bash
# View deployment status (including Pod, Service, etc.)
helm status mcpcan --namespace mcpcan

# List all Releases in a specific namespace
helm list --namespace mcpcan

# View release history
helm history mcpcan --namespace mcpcan
```

### 4. Uninstall
Delete the deployed Release.

```bash
# Uninstall application
helm uninstall mcpcan --namespace mcpcan

# Note: By default, PVCs (Persistent Volume Claims) might not be deleted to protect data.
# To completely clean up data, manually delete the corresponding PVCs or data directories.
```

## Deployment Management & Operations

### Common Kubectl Commands

```bash
# View Pod status
kubectl get pods -n mcpcan

# View Service
kubectl get svc -n mcpcan

# View Ingress
kubectl get ingress -n mcpcan

# View Pod logs
kubectl logs -n mcpcan -l app=mcp-gateway -f

# View Pod details (for troubleshooting)
kubectl describe pod <pod-name> -n mcpcan
```

## More Utility Scripts

In addition to the core scripts, the `scripts/` directory provides auxiliary tools:
- `install-k3s.sh`: Installs K3s separately.
- `install-helm.sh`: Installs Helm separately.
- `install-ingress-nginx.sh`: Installs Ingress-Nginx separately.
- `generate-simple-cert.sh`: Generates self-signed SSL certificates.
- `load-images.sh`: Loads offline images.

## Advanced Configuration

### Multi-Environment Deployment

```bash
# Development Environment
helm install mcpcan-dev ./helm -f helm/values-dev.yaml \
  --namespace mcpcan-dev --create-namespace

# Production Environment
helm install mcpcan-prod ./helm -f helm/values-prod.yaml \
  --namespace mcpcan-prod --create-namespace
```

## Frequently Asked Questions

### Q: Pod stuck in Pending state?
A: Check if node resources are sufficient, view event information with `kubectl describe pod <pod-name> -n mcpcan`.

### Q: Cannot access services?
A: Check Ingress configuration and domain resolution, ensure firewall rules are correct.

### Q: Database connection failed?
A: Check MySQL service status and connection configuration, confirm password and database name are correct.

### Q: How to update configuration?
A: After modifying values.yaml file, use `helm upgrade` command to update deployment.

## Technical Support

If you encounter issues, please:
1. View logs: `kubectl logs -n mcpcan <pod-name>`
2. Check events: `kubectl get events -n mcpcan`
3. Submit Issue to project repository
4. Contact technical support team: opensource@kymo.cn
