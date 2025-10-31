#!/bin/bash
set -euo pipefail

# Ingress-nginx Installation Script
# Supports both global and China mirror sources

# Load common function library
source "$(dirname "$0")/bash.sh"

# Default values
use_china_mirror=false
namespace="ingress-nginx"
service_type="LoadBalancer"

# Function to check if ingress-nginx is installed
check_ingress_installed() {
  if kubectl get namespace "$namespace" >/dev/null 2>&1; then
    if kubectl get deployment -n "$namespace" ingress-nginx-controller >/dev/null 2>&1; then
      info "ingress-nginx is already installed in namespace: $namespace"
      return 0
    fi
  fi
  return 1
}

# Function to install ingress-nginx
install_ingress_nginx() {
  log "Starting ingress-nginx installation..."
  
  # Check if helm is available
  if ! command -v helm >/dev/null 2>&1; then
    error "helm command is required to install ingress-nginx"
    return 1
  fi
  
  # Check if kubectl is available
  if ! command -v kubectl >/dev/null 2>&1; then
    error "kubectl command is required to install ingress-nginx"
    return 1
  fi
  
  # Add ingress-nginx helm repository
  log "Adding ingress-nginx helm repository..."
  if [ "$use_china_mirror" = true ]; then
    # Use Aliyun mirror for China users - try the official ingress-nginx chart with mirror images
    # First try to add the official repo but with timeout, fallback to mirror if fails
    if ! timeout 10 helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null; then
      log "Official repository failed, using Aliyun mirror repository..."
      helm repo add ingress-nginx https://kubernetes.oss-cn-hangzhou.aliyuncs.com/charts
    fi
  else
    # Use official repository
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
  fi
  helm repo update
  
  # Prepare helm install command
  local helm_cmd="helm install ingress-nginx ingress-nginx/ingress-nginx"
  helm_cmd="$helm_cmd --namespace $namespace"
  helm_cmd="$helm_cmd --create-namespace"
  
  if [ "$use_china_mirror" = true ]; then
    log "Using China mirror configuration for ingress-nginx..."
    # Configure China mirror images directly in helm command
    # Use the correct Aliyun mirror registry and image names
    helm_cmd="$helm_cmd --set controller.image.registry=registry.cn-hangzhou.aliyuncs.com"
    helm_cmd="$helm_cmd --set controller.image.image=google_containers/nginx-ingress-controller"
    helm_cmd="$helm_cmd --set controller.image.tag=v1.9.4"
    helm_cmd="$helm_cmd --set controller.admissionWebhooks.patch.image.registry=registry.cn-hangzhou.aliyuncs.com"
    helm_cmd="$helm_cmd --set controller.admissionWebhooks.patch.image.image=google_containers/kube-webhook-certgen"
    helm_cmd="$helm_cmd --set controller.admissionWebhooks.patch.image.tag=v20231011-8b53cabe0"
    helm_cmd="$helm_cmd --set defaultBackend.image.registry=registry.cn-hangzhou.aliyuncs.com"
    helm_cmd="$helm_cmd --set defaultBackend.image.image=google_containers/defaultbackend-amd64"
    helm_cmd="$helm_cmd --set defaultBackend.image.tag=1.5"
  fi
  
  helm_cmd="$helm_cmd --set controller.service.type=$service_type"
  
  # Execute helm install
  log "Installing ingress-nginx with command: $helm_cmd"
  eval "$helm_cmd"
  
  # Wait for deployment to be ready
  log "Waiting for ingress-nginx deployment to be ready..."
  kubectl wait --namespace "$namespace" \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=300s
  
  info "ingress-nginx installed successfully"
}

# Parse command line arguments
usage() {
  cat <<EOF
Usage: ./install-ingress-nginx.sh [options]

Options:
  --cn                    Use China mirror sources
  --namespace NAME        Kubernetes namespace (default: ingress-nginx)
  --service-type TYPE     Service type (default: LoadBalancer)
  --force                 Force reinstall even if already installed
  -h, --help             Show help

Examples:
  Install with global sources:
    ./install-ingress-nginx.sh

  Install with China mirror:
    ./install-ingress-nginx.sh --cn

  Install to custom namespace:
    ./install-ingress-nginx.sh --namespace my-ingress

  Force reinstall:
    ./install-ingress-nginx.sh --force
EOF
}

force_install=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cn) use_china_mirror=true; shift ;;
    --namespace) namespace="$2"; shift 2 ;;
    --service-type) service_type="$2"; shift 2 ;;
    --force) force_install=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown parameter: $1"; usage; exit 2 ;;
  esac
done

# Main installation logic
log "Ingress-nginx installation script started"
log "Namespace: $namespace"
log "Service type: $service_type"
log "Use China mirror: $use_china_mirror"

# Check if ingress-nginx is already installed
if check_ingress_installed; then
  if [ "$force_install" = true ]; then
    log "Ingress-nginx is already installed, forcing reinstall..."
    # Uninstall first
    helm uninstall ingress-nginx -n "$namespace" || true
    kubectl delete namespace "$namespace" --ignore-not-found=true
    sleep 10
    install_ingress_nginx || exit 1
  else
    info "Ingress-nginx is already installed, use --force to reinstall"
    exit 0
  fi
else
  log "Ingress-nginx not found, starting installation..."
  install_ingress_nginx || exit 1
fi

info "Ingress-nginx installation completed successfully!"