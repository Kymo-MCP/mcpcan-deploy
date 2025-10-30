# MCPCan Deployment Guide

## [Environment Dependencies](#dependencies) 

Before starting deployment, please ensure your environment meets the following requirements:

- **Kubernetes**: 1.20 or higher
- **Helm**: 3.0 or higher
- **NGINX Ingress Controller**: Required if ingress is enabled (for domain access)
- **Persistent Storage**: For data persistence
- **Resource Requirements**: At least 4GB RAM and 2 CPU cores

## Quick Start ([View Helm Chart Repository:https://kymo-mcp.github.io/mcpcan-deploy/](https://kymo-mcp.github.io/mcpcan-deploy/))

### 1. Clone Repository

```bash
# Clone project repository
git clone https://github.com/Kymo-MCP/mcpcan-deploy.git
cd mcpcan-deploy
```

### 2. Basic Configuration Deployment

Deploy using default configuration for quick setup:

```bash
# Basic deployment (using IP access, modify publicIP in ./helm/values.yaml)
helm install mcpcan ./helm --namespace mcpcan --create-namespace --timeout 600s --wait

# Check deployment status
kubectl get pods -n mcpcan
kubectl get svc -n mcpcan
```

After deployment is complete, you can access through:
- Web Service: `http://<node-ip>`

### 3. Custom Domain Deployment

If you have your own domain, you can configure it following these steps:

#### Step 1: Copy and modify configuration file

```bash
# Copy default configuration
cp helm/values.yaml helm/values-custom.yaml
```

#### Step 2: Modify domain configuration

Edit `helm/values-custom.yaml`:

```yaml
# Global configuration
global:
  # Set your domain, e.g.: demo.mcpcan.com, publicIP configuration will be ignored when domain exists
  domain: "demo.mcpcan.com"
  
# Ingress configuration
ingress:
  tls:
    enabled: true
    # If using self-signed certificate (e.g.: demo.mcpcan.com), please configure certificate content
    # Note: Self-signed certificates will show security warnings in browsers
    # Installing with self-signed certificates may cause MCP access configurations to fail, 
    # in which case you can manually change the protocol to http in the configuration
    # Production environments should use official certificates
    crt: |
      -----BEGIN CERTIFICATE-----
      # Your certificate content
      -----END CERTIFICATE-----
    key: |
      -----BEGIN PRIVATE KEY-----
      # Your private key content
      -----END PRIVATE KEY-----
```

#### Step 3: Generate TLS Certificate (Optional)

```bash
# Generate self-signed certificate
./scripts/generate-simple-cert.sh your-domain.com 365

# Certificate files will be generated in certs/ directory
ls certs/
```

#### Step 4: Deploy with custom configuration

```bash
# Deploy with custom configuration
helm install mcpcan ./helm -f helm/values-custom.yaml \
  --namespace mcpcan --create-namespace --timeout 600s --wait

# Or upgrade existing deployment
helm upgrade mcpcan ./helm -f helm/values-custom.yaml \
  --namespace mcpcan --timeout 600s --wait
```

## Deployment Management

### Upgrade Deployment

```bash
# Upgrade to new version
helm upgrade mcpcan ./helm -f helm/values-custom.yaml \
  --set global.version=v1.1.0 \
  --namespace mcpcan --timeout 600s --wait

# View upgrade history
helm history mcpcan --namespace mcpcan
```

### Uninstall Deployment

```bash
# Uninstall Helm Release
helm uninstall mcpcan --namespace mcpcan

# Clean up namespace
kubectl delete namespace mcpcan

# Clean up persistent data (use with caution)
sudo rm -rf /data/mcpcan
```

### Common Management Commands

#### View Status

```bash
# View Helm Release status
helm status mcpcan --namespace mcpcan

# View Pod status
kubectl get pods -n mcpcan

# View service status
kubectl get svc -n mcpcan

# View Ingress status
kubectl get ingress -n mcpcan
```

#### View Logs

```bash
# View specific service logs
kubectl logs -n mcpcan -l app=mcp-gateway
kubectl logs -n mcpcan -l app=mcp-authz
kubectl logs -n mcpcan -l app=mcp-market
kubectl logs -n mcpcan -l app=mcp-web

# View logs in real-time
kubectl logs -n mcpcan -l app=mcp-gateway -f
```

#### Troubleshooting

```bash
# View Pod detailed information
kubectl describe pod <pod-name> -n mcpcan

# View events
kubectl get events -n mcpcan --sort-by='.lastTimestamp'

# Enter Pod for debugging
kubectl exec -it <pod-name> -n mcpcan -- /bin/sh

# Port forwarding (local debugging)
kubectl port-forward svc/mcp-gateway-svc 8080:8080 -n mcpcan
kubectl port-forward svc/mcp-web-svc 3000:3000 -n mcpcan
```

## Shell Script Usage Guide

The project provides multiple utility scripts to simplify deployment and management:

### 1. K3s Management Scripts

```bash
# Install K3s
./scripts/install-k3s.sh

# Uninstall K3s
./scripts/uninstall-k3s.sh
```

### 2. Certificate Generation Script

```bash
# Generate self-signed certificate
# Usage: ./scripts/generate-simple-cert.sh <domain> <validity-days>
./scripts/generate-simple-cert.sh demo.mcpcan.com 365

# Generated certificate files
ls certs/
# tls.crt - Certificate file
# tls.key - Private key file
```

### 3. Helm Package Management

```bash
# Push Helm package to GitHub Pages
./scripts/push-helm-pkg-to-github-pages.sh
```

## Advanced Configuration

### Custom Deployment Parameters

You can override default configurations using `--set` parameters:

```bash
# Custom image version
helm upgrade --install mcpcan ./helm \
  --set global.version=v1.2.3 \
  --namespace mcpcan

# Custom domain
helm upgrade --install mcpcan ./helm \
  --set global.domain=my-custom-domain.com \
  --namespace mcpcan

# Custom resource limits
helm upgrade --install mcpcan ./helm \
  --set services.gateway.resources.limits.memory=512Mi \
  --set services.gateway.resources.limits.cpu=500m \
  --namespace mcpcan

# Disable a service
helm upgrade --install mcpcan ./helm \
  --set services.market.enabled=false \
  --namespace mcpcan
```

### Multi-Environment Deployment

```bash
# Development environment
helm install mcpcan-dev ./helm -f helm/values-dev.yaml \
  --namespace mcpcan-dev --create-namespace

# Staging environment
helm install mcpcan-staging ./helm -f helm/values-staging.yaml \
  --namespace mcpcan-staging --create-namespace

# Production environment
helm install mcpcan-prod ./helm -f helm/values-prod.yaml \
  --namespace mcpcan-prod --create-namespace
```

## Environment Dependencies Installation Guide

### One-Click Runtime Environment Installation (Recommended)

For clean environments, we recommend using the provided one-click installation script:

```bash
# Install complete runtime environment (K3s + Helm + Ingress-Nginx)
./scripts/install-run-environment.sh

# Use China mirror sources for faster installation
./scripts/install-run-environment.sh --cn

# View all available options
./scripts/install-run-environment.sh --help
```

**This script automatically installs the following components:**
- **K3s**: Lightweight Kubernetes distribution
- **Helm**: Kubernetes package manager
- **Ingress-Nginx**: Ingress controller for handling external traffic routing

### Manual Installation (Optional)

If you need custom installation or already have some components, you can choose manual installation:

#### 1. Kubernetes Cluster
- Kubernetes version >= 1.20
- At least 2GB available memory and 2 CPU cores

#### 2. Helm Package Manager
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

#### 3. NGINX Ingress Controller
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=NodePort
```

## Software Architecture Design

MCPCan is built on a modern Kubernetes microservice architecture, providing comprehensive MCP service lifecycle management capabilities. The platform consists of the following core components:

### Core Services

1. **MCPCan-Web** - Vue.js-based frontend service providing modern web interface for MCP service management
2. **MCPCan-Gateway** - MCP gateway service responsible for request routing, protocol conversion, and authentication
3. **MCPCan-Authz** - Authentication and authorization service handling user management and access control
4. **MCPCan-Market** - MCP service marketplace for discovering, publishing, and managing MCP services
5. **MCPCan-Init** - Initialization service for system setup and configuration

### Data Storage

6. **MySQL** - Primary database service for persistent data storage
7. **Redis** - Cache service for session management and performance optimization

### Technology Stack

**Frontend:**
- Framework: Vue.js 3.5+ (Composition API)
- Language: TypeScript
- Styling: UnoCSS, SCSS
- UI Components: Element Plus
- State Management: Pinia
- Build Tool: Vite

**Backend:**
- Language: Go 1.24.2+
- Framework: Gin, gRPC
- Database: MySQL, Redis
- Containerization: Docker, Kubernetes

## Important Notes

1. **Resource Requirements**: Ensure the cluster has sufficient resources
2. **Security Configuration**: Change default passwords and keys in production environments
3. **Network Configuration**: Ensure firewall allows access to corresponding ports
4. **Backup Strategy**: Regularly backup databases and important configuration files
5. **Monitoring and Alerting**: Recommend configuring monitoring and alerting systems
6. **Version Management**: Recommend using specific version tags instead of `latest`

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
