#!/bin/bash
set -euo pipefail

# Ingress-nginx Installation Script
# Supports both global and China mirror sources
# Uses wget + kubectl deployment method (no Helm required)

# Load common function library
source "$(dirname "$0")/bash.sh"

# Default values
use_china_mirror=false
namespace="ingress-nginx"
service_type="LoadBalancer"
ingress_version="v1.13.3"  # Latest stable version

# URLs for deployment manifests
GITHUB_BASE_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-${ingress_version}/deploy/static/provider"
TEMP_DIR="/tmp/ingress-nginx-install"

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

# Function to download deployment manifest with progress
download_manifest() {
  local manifest_url="$1"
  local output_file="$2"
  
  log "Downloading manifest from: $manifest_url"
  
  # Use curl with progress bar as fallback if wget fails
  if command -v wget >/dev/null 2>&1; then
    if ! wget --progress=bar:force --timeout=30 --tries=3 -O "$output_file" "$manifest_url" 2>&1; then
      log "wget failed, trying curl..."
      if ! curl -L --connect-timeout 30 --max-time 60 --progress-bar -o "$output_file" "$manifest_url"; then
        error "Failed to download manifest from $manifest_url"
        return 1
      fi
    fi
  else
    if ! curl -L --connect-timeout 30 --max-time 60 --progress-bar -o "$output_file" "$manifest_url"; then
      error "Failed to download manifest from $manifest_url"
      return 1
    fi
  fi
  
  if [ ! -s "$output_file" ]; then
    error "Downloaded manifest is empty: $output_file"
    return 1
  fi
  
  log "Successfully downloaded manifest to: $output_file"
  return 0
}

# Function to test mirror availability
test_mirror_availability() {
  local mirror="$1"
  local timeout=5
  
  if curl -s --connect-timeout "$timeout" --max-time "$timeout" -I "https://$mirror" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Function to get the best available mirror
get_best_mirror() {
  local mirrors=("k8s.nju.edu.cn" "registry.cn-hangzhou.aliyuncs.com" "k8s.dockerproxy.com")
  
  log "🔍 Searching for the best available mirror..." >&2
  
  for mirror in "${mirrors[@]}"; do
    log "Testing mirror availability: $mirror" >&2
    if test_mirror_availability "$mirror" >/dev/null 2>&1; then
      log "✅ Mirror $mirror is accessible" >&2
      echo "$mirror"
      return 0
    else
      log "❌ Mirror $mirror is not accessible" >&2
    fi
  done
  
  log "⚠️ No mirrors are accessible, using default: k8s.dockerproxy.com" >&2
  echo "k8s.dockerproxy.com"
  return 1
}

# Function to replace images with China mirror
replace_images_with_china_mirror() {
  local manifest_file="$1"
  
  # Get the best available mirror
  local best_mirror
  best_mirror=$(get_best_mirror | tail -1)
  
  log "🔄 Replacing images with China mirror: $best_mirror"
  
  # Handle different mirror formats
  if [[ "$best_mirror" == "registry.cn-hangzhou.aliyuncs.com" ]]; then
    log "Using Aliyun mirror format..."
    # Aliyun uses a different path structure
    sed -i.bak "s|registry\.k8s\.io/|$best_mirror/google_containers/|g" "$manifest_file"
    sed -i.bak2 "s|k8s\.gcr\.io/|$best_mirror/google_containers/|g" "$manifest_file"
  else
    log "Using standard mirror format..."
    # Standard format for other mirrors
    sed -i.bak "s|registry\.k8s\.io/|$best_mirror/|g" "$manifest_file"
    sed -i.bak2 "s|k8s\.gcr\.io/|$best_mirror/|g" "$manifest_file"
  fi
  
  log "✅ Image replacement completed using mirror: $best_mirror"
  
  # Show what images will be used
  log "📋 Images that will be used:"
  grep -E "image: " "$manifest_file" | grep -v "registry\.k8s\.io\|k8s\.gcr\.io" | sort | uniq | while read -r line; do
    log "  $line"
  done
}

# Function to modify service type
modify_service_type() {
  local manifest_file="$1"
  local target_type="$2"
  
  if [ "$target_type" != "LoadBalancer" ]; then
    log "Modifying service type to: $target_type"
    sed -i.svc "s/type: LoadBalancer/type: $target_type/g" "$manifest_file"
  fi
}

# Function to install ingress-nginx using kubectl
install_ingress_nginx() {
  log "Starting ingress-nginx installation using kubectl..."
  
  # Check if kubectl is available
  if ! command -v kubectl >/dev/null 2>&1; then
    error "kubectl command is required to install ingress-nginx"
    return 1
  fi
  
  # Check if wget is available
  if ! command -v wget >/dev/null 2>&1; then
    error "wget command is required to download manifests"
    return 1
  fi
  
  # Create temporary directory
  mkdir -p "$TEMP_DIR"
  
  # Determine manifest URL based on service type
  local manifest_url
  case "$service_type" in
    "LoadBalancer")
      manifest_url="${GITHUB_BASE_URL}/cloud/deploy.yaml"
      ;;
    "NodePort")
      manifest_url="${GITHUB_BASE_URL}/baremetal/deploy.yaml"
      ;;
    "ClusterIP")
      manifest_url="${GITHUB_BASE_URL}/baremetal/deploy.yaml"
      ;;
    *)
      error "Unsupported service type: $service_type"
      return 1
      ;;
  esac
  
  local manifest_file="${TEMP_DIR}/ingress-nginx-deploy.yaml"
  
  # Download the manifest
  if ! download_manifest "$manifest_url" "$manifest_file"; then
    return 1
  fi
  
  # Replace images with China mirror if needed
  if [ "$use_china_mirror" = true ]; then
    replace_images_with_china_mirror "$manifest_file"
  fi
  
  # Modify service type if needed
  modify_service_type "$manifest_file" "$service_type"
  
  # Apply the manifest
  log "Applying ingress-nginx manifest..."
  log "This may take a few minutes, please wait..."
  
  # Check if kubectl can connect to cluster first
  if ! kubectl cluster-info >/dev/null 2>&1; then
    error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    return 1
  fi
  
  # Apply with timeout
  if ! timeout 300 kubectl apply -f "$manifest_file"; then
    error "Failed to apply ingress-nginx manifest (timeout after 5 minutes)"
    log "You can try applying manually: kubectl apply -f $manifest_file"
    return 1
  fi
  
  log "Manifest applied successfully"
  
  # Wait for deployment to be ready (optional, with shorter timeout)
  log "Checking if deployment is ready (this may take a few minutes)..."
  if kubectl wait --namespace "$namespace" \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=180s 2>/dev/null; then
    log "✅ Ingress-nginx deployment is ready"
  else
    warn "⚠️ Deployment may still be starting. Check status with: kubectl get pods -n $namespace"
  fi
  
  # Clean up temporary files
  rm -rf "$TEMP_DIR"
  
  info "ingress-nginx installed successfully"
  
  # Show service information
  log "Ingress-nginx service information:"
  kubectl get svc -n "$namespace" ingress-nginx-controller
}

# Parse command line arguments
usage() {
  cat <<EOF
Usage: ./install-ingress-nginx.sh [options]

Ingress-nginx Installation Script (kubectl + wget method)
Supports both global and China mirror sources

Options:
  --cn                    Use China mirror sources (k8s.dockerproxy.com)
  --namespace NAME        Kubernetes namespace (default: ingress-nginx)
  --service-type TYPE     Service type: LoadBalancer|NodePort|ClusterIP (default: LoadBalancer)
  --version VERSION       Ingress-nginx version (default: v1.13.3)
  --force                 Force reinstall even if already installed
  -h, --help             Show help

Mirror Sources:
  Global:  https://github.com/kubernetes/ingress-nginx (registry.k8s.io)
  China:   https://dockerproxy.com/docs (k8s.dockerproxy.com)

Examples:
  Install with global sources:
    ./install-ingress-nginx.sh

  Install with China mirror:
    ./install-ingress-nginx.sh --cn

  Install to custom namespace with NodePort:
    ./install-ingress-nginx.sh --namespace my-ingress --service-type NodePort

  Install specific version:
    ./install-ingress-nginx.sh --version v1.12.0

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
    --version) ingress_version="$2"; GITHUB_BASE_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-${ingress_version}/deploy/static/provider"; shift 2 ;;
    --force) force_install=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown parameter: $1"; usage; exit 2 ;;
  esac
done

# Validate service type
case "$service_type" in
  "LoadBalancer"|"NodePort"|"ClusterIP") ;;
  *) error "Invalid service type: $service_type. Must be LoadBalancer, NodePort, or ClusterIP"; exit 1 ;;
esac

# Main installation logic
log "Ingress-nginx installation script started (kubectl + wget method)"
log "Version: $ingress_version"
log "Namespace: $namespace"
log "Service type: $service_type"
log "Use China mirror: $use_china_mirror"
if [ "$use_china_mirror" = true ]; then
  log "Mirror source: k8s.dockerproxy.com (https://dockerproxy.com/docs)"
else
  log "Mirror source: registry.k8s.io (https://github.com/kubernetes/ingress-nginx)"
fi

# Check if ingress-nginx is already installed
if check_ingress_installed; then
  if [ "$force_install" = true ]; then
    log "Ingress-nginx is already installed, forcing reinstall..."
    # Uninstall using kubectl
    kubectl delete -f "${GITHUB_BASE_URL}/cloud/deploy.yaml" --ignore-not-found=true || true
    kubectl delete -f "${GITHUB_BASE_URL}/baremetal/deploy.yaml" --ignore-not-found=true || true
    kubectl delete namespace "$namespace" --ignore-not-found=true || true
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