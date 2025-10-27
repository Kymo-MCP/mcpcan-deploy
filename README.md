# MCP-Box Deployment Guide

## Software Architecture Design

Based on Kubernetes microservice architecture, including the following core components:

1. **Gateway Service** - MCP gateway service, responsible for request routing and authentication
2. **Authz Service** - Authentication and authorization service
3. **Market Service** - Market service
4. **Web Service** - Frontend service
5. **MySQL** - Database service
6. **Redis** - Cache service

## Environment Dependencies

### Required Environment

Before starting deployment, please ensure your environment meets the following requirements:

#### 1. Kubernetes Cluster

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

#### 2. Required Tools

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

#### 3. NGINX Ingress Controller

MCP-Box depends on NGINX Ingress Controller to handle external traffic routing. Please ensure it's installed:

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

## Quick Start

### 1. Clone Repository

```bash
# Clone project repository
git clone https://github.com/your-org/mcp-box-deploy.git
cd mcp-box-deploy
```

### 2. Basic Configuration Deployment

Deploy using default configuration for quick setup:

```bash
# Basic deployment (using IP access, modify publicIP in ./helm/values.yaml)
helm install mcp-box ./helm --namespace mcp-box --create-namespace --timeout 600s --wait

# Check deployment status
kubectl get pods -n mcp-box
kubectl get svc -n mcp-box
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
  # Set your domain, e.g.: demo.mcp-box.com, publicIP configuration will be ignored when domain exists
  domain: "demo.mcp-box.com"
  
# Ingress configuration
ingress:
  tls:
    enabled: true
    # If using self-signed certificate (e.g.: demo.mcp-box.com), please configure certificate content
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
helm install mcp-box ./helm -f helm/values-custom.yaml \
  --namespace mcp-box --create-namespace --timeout 600s --wait

# Or upgrade existing deployment
helm upgrade mcp-box ./helm -f helm/values-custom.yaml \
  --namespace mcp-box --timeout 600s --wait
```

## Deployment Management

### Upgrade Deployment

```bash
# Upgrade to new version
helm upgrade mcp-box ./helm -f helm/values-custom.yaml \
  --set global.version=v1.1.0 \
  --namespace mcp-box --timeout 600s --wait

# View upgrade history
helm history mcp-box --namespace mcp-box
```

### Uninstall Deployment

```bash
# Uninstall Helm Release
helm uninstall mcp-box --namespace mcp-box

# Clean up namespace
kubectl delete namespace mcp-box

# Clean up persistent data (use with caution)
sudo rm -rf /data/mcp-box
```

### Common Management Commands

#### View Status

```bash
# View Helm Release status
helm status mcp-box --namespace mcp-box

# View Pod status
kubectl get pods -n mcp-box

# View service status
kubectl get svc -n mcp-box

# View Ingress status
kubectl get ingress -n mcp-box
```

#### View Logs

```bash
# View specific service logs
kubectl logs -n mcp-box -l app=mcp-gateway
kubectl logs -n mcp-box -l app=mcp-authz
kubectl logs -n mcp-box -l app=mcp-market
kubectl logs -n mcp-box -l app=mcp-web

# View logs in real-time
kubectl logs -n mcp-box -l app=mcp-gateway -f
```

#### Troubleshooting

```bash
# View Pod detailed information
kubectl describe pod <pod-name> -n mcp-box

# View events
kubectl get events -n mcp-box --sort-by='.lastTimestamp'

# Enter Pod for debugging
kubectl exec -it <pod-name> -n mcp-box -- /bin/sh

# Port forwarding (local debugging)
kubectl port-forward svc/mcp-gateway-svc 8080:8080 -n mcp-box
kubectl port-forward svc/mcp-web-svc 3000:3000 -n mcp-box
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
./scripts/generate-simple-cert.sh demo.mcp-box.com 365

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
helm upgrade --install mcp-box ./helm \
  --set global.version=v1.2.3 \
  --namespace mcp-box

# Custom domain
helm upgrade --install mcp-box ./helm \
  --set global.domain=my-custom-domain.com \
  --namespace mcp-box

# Custom resource limits
helm upgrade --install mcp-box ./helm \
  --set services.gateway.resources.limits.memory=512Mi \
  --set services.gateway.resources.limits.cpu=500m \
  --namespace mcp-box

# Disable a service
helm upgrade --install mcp-box ./helm \
  --set services.market.enabled=false \
  --namespace mcp-box
```

### Multi-Environment Deployment

```bash
# Development environment
helm install mcp-box-dev ./helm -f helm/values-dev.yaml \
  --namespace mcp-box-dev --create-namespace

# Staging environment
helm install mcp-box-staging ./helm -f helm/values-staging.yaml \
  --namespace mcp-box-staging --create-namespace

# Production environment
helm install mcp-box-prod ./helm -f helm/values-prod.yaml \
  --namespace mcp-box-prod --create-namespace
```

## Important Notes

1. **Resource Requirements**: Ensure the cluster has sufficient resources
2. **Security Configuration**: Change default passwords and keys in production environments
3. **Network Configuration**: Ensure firewall allows access to corresponding ports
4. **Backup Strategy**: Regularly backup databases and important configuration files
5. **Monitoring and Alerting**: Recommend configuring monitoring and alerting systems
6. **Version Management**: Recommend using specific version tags instead of `latest`

## Frequently Asked Questions

### Q: Pod stuck in Pending state?
A: Check if node resources are sufficient, view event information with `kubectl describe pod <pod-name> -n mcp-box`.

### Q: Cannot access services?
A: Check Ingress configuration and domain resolution, ensure firewall rules are correct.

### Q: Database connection failed?
A: Check MySQL service status and connection configuration, confirm password and database name are correct.

### Q: How to update configuration?
A: After modifying values.yaml file, use `helm upgrade` command to update deployment.

## Technical Support

If you encounter issues, please:
1. View logs: `kubectl logs -n mcp-box <pod-name>`
2. Check events: `kubectl get events -n mcp-box`
3. Submit Issue to project repository
4. Contact technical support team
