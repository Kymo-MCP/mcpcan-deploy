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
git clone https://github.com/Kymo-MCP/mcp-box-deploy.git
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

## CI/CD Pipeline

This project uses GitHub Actions for comprehensive automated testing, security scanning, and Helm chart releases. The pipeline follows industry best practices and includes multiple validation stages.

### Workflows Overview

1. **Release Charts** (`release.yml`)
   - **Triggers**: Push to `main`/`develop` branches, version tags (`v*`), manual dispatch
   - **Features**:
     - Comprehensive chart testing with `chart-testing` (ct)
     - Multi-stage validation (lint → test → release)
     - Automatic version management from tags or VERSION file
     - Chart packaging and GitHub release creation
     - GitHub Pages deployment for chart repository
     - Support for development and production releases

2. **PR Validation** (`pr-validation.yml`)
   - **Triggers**: Pull requests to `main`/`develop` branches
   - **Features**:
     - Smart change detection (Helm charts, scripts, workflows)
     - Multi-Kubernetes version testing (v1.27, v1.28, v1.29)
     - Shell script validation with ShellCheck
     - GitHub Actions workflow validation with ActionLint
     - Chart version format validation
     - Comprehensive validation summary

3. **Security Scan** (`security.yml`)
   - **Triggers**: Push events, pull requests, daily schedule (2 AM UTC), manual dispatch
   - **Features**:
     - **Helm Security**: kube-linter and Checkov scanning
     - **Container Security**: Trivy vulnerability scanning for base images
     - **Dependency Security**: SBOM generation and Grype vulnerability scanning
     - **Integration**: Results uploaded to GitHub Security tab
     - **Reporting**: Detailed vulnerability summaries and recommendations

### Chart Repository

The Helm chart repository is automatically maintained and deployed to GitHub Pages:

```bash
# Add the repository
helm repo add mcp-box https://qm-mcp.github.io/mcp-box-deploy/
helm repo update

# Install the chart
helm install mcp-box mcp-box/mcp-box --namespace mcp-box --create-namespace
```

### Release Process

#### Automatic Releases

1. **Development Releases**: Automatically created on push to `develop` branch
   - Version format: `{base-version}-develop-{timestamp}`
   - Marked as pre-release

2. **Production Releases**: Created when pushing version tags
   ```bash
   git tag v1.2.3
   git push origin v1.2.3
   ```

#### Manual Releases

Use the GitHub Actions UI to trigger manual releases:
1. Go to Actions → Release Charts → Run workflow
2. Select branch and specify version
3. Choose whether to mark as pre-release

### Development Workflow

1. **Create Feature Branch**
   ```bash
   git checkout -b feature/new-feature
   ```

2. **Make Changes** - Modify Helm charts, scripts, or documentation

3. **Create Pull Request** - PR validation will automatically run:
   - Helm chart linting and testing
   - Security scanning
   - Script validation
   - Multi-Kubernetes version compatibility testing

4. **Review and Merge** - After approval and successful validation

5. **Automatic Release** - Charts are automatically released upon merge to main

### Security and Compliance

The pipeline includes comprehensive security measures:

- **Daily Security Scans**: Automated vulnerability detection
- **Container Image Scanning**: Base image security validation
- **Kubernetes Security**: Best practices enforcement with kube-linter
- **Dependency Tracking**: SBOM generation and vulnerability monitoring
- **SARIF Integration**: Security results in GitHub Security tab

### Monitoring and Troubleshooting

#### Workflow Status

Monitor workflow status in the GitHub Actions tab:
- ✅ Green: All checks passed
- ❌ Red: Issues found, check logs for details
- 🟡 Yellow: In progress or warnings

#### Common Issues

1. **Chart Validation Failures**
   ```bash
   # Test locally before pushing
   helm lint helm/
   helm template helm/ --debug
   ```

2. **Security Scan Failures**
   - Review security tab for vulnerability details
   - Update base images or dependencies as needed
   - Check uploaded artifacts for detailed reports

3. **Release Failures**
   - Ensure proper version format (semantic versioning)
   - Check Chart.yaml version consistency
   - Verify GitHub token permissions

### Configuration Files

- **`.github/workflows/`**: GitHub Actions workflow definitions
- **`cr.yaml`**: Chart Releaser configuration
- **`helm/Chart.yaml`**: Chart metadata and version information
- **`VERSION`**: Base version for development releases
```
https://<username>.github.io/mcp-box-deploy/
```

Add the repository:
```bash
helm repo add mcp-box https://<username>.github.io/mcp-box-deploy/
helm repo update
```

### Release Process

1. **Development**: Create feature branches and submit PRs
2. **Validation**: Automated PR validation ensures quality
3. **Release**: Merge to `main` triggers automatic release
4. **Versioning**: Use semantic versioning tags (e.g., `v1.2.3`)

### Manual Release

To trigger a manual release:
1. Go to Actions tab in GitHub repository
2. Select "Release Charts" workflow
3. Click "Run workflow"
4. Specify version and release options

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
