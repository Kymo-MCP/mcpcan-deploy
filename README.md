# MCPCan Deployment Guide

## [Environment Dependencies](#dependencies) 

Before starting deployment, please ensure your environment meets the following requirements:

- **Kubernetes**: 1.20 or higher
- **Helm**: 3.0 or higher
- **NGINX Ingress Controller**: Required if ingress is enabled (for domain access)
- **Persistent Storage**: For data persistence
- **Resource Requirements**: At least 2GB RAM and 2 CPU cores

## Quick Start

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

### 1. Kubernetes Cluster

**Option A: Using K3s (Recommended for development and testing)**
```bash
# Install K3s
curl -sfL https://get.k3s.io | sh -

# Or use the script provided by the project (Recommended: installs K3s, ingress-nginx, helm by default)
./scripts/install-k3s.sh

# Verify installation
kubectl get nodes
```

**Option B: Using Standard Kubernetes**
- Kubernetes version >= 1.20
- At least 2GB available memory
- At least 2 CPU cores

### 2. Required Tools

Ensure the following tools are installed:

```bash
# Helm 3.x
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Verify installation
helm version
kubectl version --client
```

### 3. NGINX Ingress Controller

MCPCan depends on NGINX Ingress Controller to handle external traffic routing. Please ensure it's installed:

**Option A: Install using Helm (Recommended)**
```bash
# Add NGINX Ingress Helm repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install NGINX Ingress Controller
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443

# Verify installation
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

**Option B: Use project-provided configuration file**
```bash
# Use project-provided NGINX Ingress configuration
kubectl apply -f scripts/nginx-ingress-controller.yaml

# Verify installation
kubectl get pods -n ingress-nginx
```

**Verify Ingress Controller Status**
```bash
# Check if Ingress Controller is running normally
kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# Check service ports
kubectl get svc -n ingress-nginx
```

## Software Architecture Design

Based on Kubernetes microservice architecture, including the following core components:

1. **Gateway Service** - MCP gateway service, responsible for request routing and authentication
2. **Authz Service** - Authentication and authorization service
3. **Market Service** - Market service
4. **Web Service** - Frontend service
5. **MySQL** - Database service
6. **Redis** - Cache service

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
