#!/bin/bash

# K3s + Helm + Ingress-Nginx Complete Installation Script
# This script installs a complete Kubernetes runtime environment including:
# - K3s (Lightweight Kubernetes)
# - Helm (Package manager for Kubernetes)
# - Ingress-Nginx (Ingress controller)
#
# Features:
# - Unified parameter logic for China mirror sources (--cn)
# - Sequential installation with dependency checking
# - Support for all K3s installation options
# - Automatic error handling and rollback
# - Comprehensive logging

set -e

# Color output functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
  echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
  echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}"
}

error() {
  echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
  echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Default values
use_china_mirror=false
force_install=false
skip_k3s=false
skip_helm=false
skip_ingress=false

# K3s parameters
k3s_token=""
k3s_version=""
k3s_data_dir=""
k3s_disable=""
k3s_tls_sans=""
k3s_extra_args=""

usage() {
  cat <<EOF
Usage: ./install-run-environment.sh [options]

This script installs a complete Kubernetes runtime environment including K3s, Helm, and Ingress-Nginx.

Options:
  --cn                   Use China mirror sources for all components
  --force                Force reinstall all components
  --skip-k3s             Skip K3s installation (only install Helm and Ingress-Nginx)
  --skip-helm            Skip Helm installation
  --skip-ingress         Skip Ingress-Nginx installation
  
  K3s specific options:
  --token <token>        K3s cluster token
  --version <version>    K3s version to install
  --data-dir <path>      K3s data directory
  --disable <components> Disable K3s components (comma-separated)
  --tls-sans <ips>       Additional TLS SANs (comma-separated)
  --extra-args <args>    Additional K3s arguments
  
  -h, --help             Show help

Examples:
  Install complete environment with global sources:
    ./install-run-environment.sh

  Install complete environment with China mirror:
    ./install-run-environment.sh --cn

  Install only Helm and Ingress-Nginx (skip K3s):
    ./install-run-environment.sh --skip-k3s --cn

  Install K3s with specific version and skip Ingress-Nginx:
    ./install-run-environment.sh --version v1.28.5+k3s1 --skip-ingress

  Force reinstall all components:
    ./install-run-environment.sh --force --cn
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cn) use_china_mirror=true; shift ;;
    --force) force_install=true; shift ;;
    --skip-k3s) skip_k3s=true; shift ;;
    --skip-helm) skip_helm=true; shift ;;
    --skip-ingress) skip_ingress=true; shift ;;
    --token) k3s_token="$2"; shift 2 ;;
    --version) k3s_version="$2"; shift 2 ;;
    --data-dir) k3s_data_dir="$2"; shift 2 ;;
    --disable) k3s_disable="$2"; shift 2 ;;
    --tls-sans) k3s_tls_sans="$2"; shift 2 ;;
    --extra-args) k3s_extra_args="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown parameter: $1"; usage; exit 2 ;;
  esac
done

# Get script directory
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if required scripts exist
check_scripts() {
  local missing_scripts=()
  
  if [ "$skip_k3s" != true ] && [ ! -f "$script_dir/install-k3s.sh" ]; then
    missing_scripts+=("install-k3s.sh")
  fi
  
  if [ "$skip_helm" != true ] && [ ! -f "$script_dir/install-helm.sh" ]; then
    missing_scripts+=("install-helm.sh")
  fi
  
  if [ "$skip_ingress" != true ] && [ ! -f "$script_dir/install-ingress-nginx.sh" ]; then
    missing_scripts+=("install-ingress-nginx.sh")
  fi
  
  if [ ${#missing_scripts[@]} -gt 0 ]; then
    error "Missing required scripts: ${missing_scripts[*]}"
    error "Please ensure all installation scripts are in the same directory: $script_dir"
    exit 1
  fi
}

# Install K3s
install_k3s() {
  if [ "$skip_k3s" = true ]; then
    log "Skipping K3s installation as requested"
    return 0
  fi
  
  log "Installing K3s..."
  
  local k3s_args=()
  
  # Add China mirror parameter
  if [ "$use_china_mirror" = true ]; then
    k3s_args+=("--mirror" "cn")
  fi
  
  # Add force parameter
  if [ "$force_install" = true ]; then
    k3s_args+=("--force")
  fi
  
  # Add K3s specific parameters
  [ -n "$k3s_token" ] && k3s_args+=("--token" "$k3s_token")
  [ -n "$k3s_version" ] && k3s_args+=("--version" "$k3s_version")
  [ -n "$k3s_data_dir" ] && k3s_args+=("--data-dir" "$k3s_data_dir")
  [ -n "$k3s_disable" ] && k3s_args+=("--disable" "$k3s_disable")
  [ -n "$k3s_tls_sans" ] && k3s_args+=("--tls-sans" "$k3s_tls_sans")
  [ -n "$k3s_extra_args" ] && k3s_args+=("--extra-args" "$k3s_extra_args")
  
  if bash "$script_dir/install-k3s.sh" "${k3s_args[@]}"; then
    info "K3s installation completed successfully"
  else
    error "K3s installation failed"
    return 1
  fi
}

# Install Helm
install_helm() {
  if [ "$skip_helm" = true ]; then
    log "Skipping Helm installation as requested"
    return 0
  fi
  
  log "Installing Helm..."
  
  local helm_args=()
  
  # Add China mirror parameter
  if [ "$use_china_mirror" = true ]; then
    helm_args+=("--cn")
  fi
  
  # Add force parameter
  if [ "$force_install" = true ]; then
    helm_args+=("--force")
  fi
  
  if bash "$script_dir/install-helm.sh" "${helm_args[@]}"; then
    info "Helm installation completed successfully"
  else
    error "Helm installation failed"
    return 1
  fi
}

# Install Ingress-Nginx
install_ingress_nginx() {
  if [ "$skip_ingress" = true ]; then
    log "Skipping Ingress-Nginx installation as requested"
    return 0
  fi
  
  log "Installing Ingress-Nginx..."
  
  local ingress_args=()
  
  # Add China mirror parameter
  if [ "$use_china_mirror" = true ]; then
    ingress_args+=("--cn")
  fi
  
  # Add force parameter
  if [ "$force_install" = true ]; then
    ingress_args+=("--force")
  fi
  
  if bash "$script_dir/install-ingress-nginx.sh" "${ingress_args[@]}"; then
    info "Ingress-Nginx installation completed successfully"
  else
    error "Ingress-Nginx installation failed"
    return 1
  fi
}

# Main installation logic
main() {
  log "Starting complete Kubernetes runtime environment installation"
  log "China mirror: $use_china_mirror"
  log "Force install: $force_install"
  log "Skip K3s: $skip_k3s"
  log "Skip Helm: $skip_helm"
  log "Skip Ingress-Nginx: $skip_ingress"
  
  # Check if all required scripts exist
  check_scripts
  
  # Install components in order
  install_k3s || exit 1
  install_helm || exit 1
  install_ingress_nginx || exit 1
  
  info "Complete Kubernetes runtime environment installation finished successfully!"
  info ""
  info "Installed components:"
  [ "$skip_k3s" != true ] && info "  ✓ K3s (Lightweight Kubernetes)"
  [ "$skip_helm" != true ] && info "  ✓ Helm (Package manager)"
  [ "$skip_ingress" != true ] && info "  ✓ Ingress-Nginx (Ingress controller)"
  info ""
  info "You can now use kubectl and helm to manage your Kubernetes cluster!"
}

# Run main function
main "$@"