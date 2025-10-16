#!/bin/bash
set -euo pipefail

# Helm Installation Script
# Supports both global and China mirror sources

# Load common function library
source "$(dirname "$0")/bash.sh"

# Default values
use_china_mirror=false

# Function to check if helm is installed
check_helm_installed() {
  if command -v helm >/dev/null 2>&1; then
    info "helm is installed, version: $(helm version --short 2>/dev/null || echo "Unable to get version")"
    return 0
  else
    return 1
  fi
}

# Function to install helm
install_helm() {
  log "Starting helm installation..."
  
  # Check if curl is available
  if ! command -v curl >/dev/null 2>&1; then
    error "curl command is required to install helm"
    return 1
  fi
  
  # Download and install helm
  if [ "$use_china_mirror" = true ]; then
    log "Using China mirror for helm installation..."
    # Use China mirror for faster download
    curl -fsSL https://get.helm.sh/helm-v3.12.3-linux-amd64.tar.gz | tar -xzO linux-amd64/helm | sudo tee /usr/local/bin/helm > /dev/null
    sudo chmod +x /usr/local/bin/helm
  else
    log "Using global source for helm installation..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi
  
  # Verify installation
  if check_helm_installed; then
    info "helm installed successfully"
  else
    error "helm installation failed"
    return 1
  fi
}

# Parse command line arguments
usage() {
  cat <<EOF
Usage: ./install-helm.sh [options]

Options:
  --cn                   Use China mirror sources
  --force                Force reinstall even if helm is already installed
  -h, --help             Show help

Examples:
  Install helm with global source:
    ./install-helm.sh

  Install helm with China mirror:
    ./install-helm.sh --cn

  Force reinstall:
    ./install-helm.sh --force
EOF
}

force_install=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cn) use_china_mirror=true; shift ;;
    --force) force_install=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown parameter: $1"; usage; exit 2 ;;
  esac
done

# Validate parameters (no validation needed for boolean flag)

# Main installation logic
log "Helm installation script started"
log "Use China mirror: $use_china_mirror"

# Check if helm is already installed
if check_helm_installed; then
  if [ "$force_install" = true ]; then
    log "Helm is already installed, forcing reinstall..."
    install_helm || exit 1
  else
    info "Helm is already installed, use --force to reinstall"
    exit 0
  fi
else
  log "Helm not found, starting installation..."
  install_helm || exit 1
fi

info "Helm installation completed successfully!"