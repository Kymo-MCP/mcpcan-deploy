#!/bin/bash
set -euo pipefail

# k3s Installation Script (Ubuntu Environment, Auto Node Type Detection)
# Auto-detect node type: First IP is master, others are workers
# Configuration priority: Command line args > Environment variables > Default values
# Dependencies: curl, sudo (if not root)

# Load common function library
source "$(dirname "$0")/bash.sh"

# --- Default values (read from bash.sh default configuration) ---
k3s_version="${K3S_VERSION}"                             # k3s version
k3s_token="${K3S_TOKEN:-}"                               # Auto-generated if empty
k3s_data_dir="${K3S_DATA_DIR}"                           # k3s data directory
k3s_kubeconfig_mode="${K3S_KUBECONFIG_MODE}"             # kubeconfig permissions
k3s_disable_components="${K3S_DISABLE_COMPONENTS}"       # Disabled components
k3s_mirror="${K3S_MIRROR}"                               # Mirror source
k3s_install_url="${K3S_INSTALL_URL}"                     # Installation script URL
tls_sans="${TLS_SANS:-}"                                 # Optional, comma-separated: my.domain.com,10.0.0.10
extra_args="${K3S_EXTRA_ARGS:-}"                         # Extra args passed to k3s

# Function to get all node IPs
get_all_node_ips() {
  if [ -n "${K3S_INSTALL_NODE_IP_LIST:-}" ]; then
    echo "$K3S_INSTALL_NODE_IP_LIST" | tr ' ' '\n'
  else
    # If no node list configured, return current server IP
    auto_detect_node_ips
  fi
}

# Check if Kubernetes environment is already installed (k3s or other k8s distributions)
check_existing_k8s() {
  local k8s_type=""
  
  # Check k3s
  if command -v k3s >/dev/null 2>&1; then
    k8s_type="k3s"
    info "Detected k3s, version: $(k3s --version | head -n1)"
    return 0
  fi
  
  # Check kubectl
  if command -v kubectl >/dev/null 2>&1; then
    if kubectl version --client >/dev/null 2>&1; then
      k8s_type="kubectl"
      info "Detected kubectl, version: $(kubectl version --client --short 2>/dev/null || echo "Unable to get version")"
    fi
  fi
  
  # Check systemd services
  if systemctl is-active --quiet k3s 2>/dev/null; then
    k8s_type="k3s"
    info "Detected k3s service running"
    return 0
  fi
  
  if systemctl is-active --quiet k3s-agent 2>/dev/null; then
    k8s_type="k3s"
    info "Detected k3s-agent service running"
    return 0
  fi
  
  if systemctl is-active --quiet kubelet 2>/dev/null; then
    k8s_type="kubelet"
    info "Detected kubelet service running"
  fi
  
  if [ -n "$k8s_type" ]; then
    echo "$k8s_type"
    return 0
  fi
  
  return 1
}

# Uninstall existing Kubernetes environment
uninstall_kubernetes() {
  local k8s_type="$1"
  
  log "Uninstalling existing $k8s_type environment..."
  
  if [ "$k8s_type" = "k3s" ]; then
    # Uninstall k3s server
    if command -v /usr/local/bin/k3s-uninstall.sh >/dev/null 2>&1; then
      sudo /usr/local/bin/k3s-uninstall.sh || true
      info "k3s server uninstalled"
    fi
    
    # Uninstall k3s agent
    if command -v /usr/local/bin/k3s-agent-uninstall.sh >/dev/null 2>&1; then
      sudo /usr/local/bin/k3s-agent-uninstall.sh || true
      info "k3s agent uninstalled"
    fi
  else
    warn "Detected other Kubernetes environment, please uninstall manually and re-run the script"
    error "Or use --force parameter to force installation"
    return 1
  fi
}

# Check if helm is installed
check_helm_installed() {
  if command -v helm >/dev/null 2>&1; then
    info "helm is installed, version: $(helm version --short 2>/dev/null || echo "Unable to get version")"
    return 0
  else
    return 1
  fi
}

# Install helm
install_helm() {
  log "Starting helm installation..."
  
  # Download and install helm
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  else
    error "curl command is required to install helm"
    return 1
  fi
  
  # Verify installation
  if check_helm_installed; then
    info "helm installed successfully"
  else
    error "helm installation failed"
    return 1
  fi
}

# Check if ingress-nginx is installed
check_ingress_nginx_installed() {
  if ! command -v kubectl >/dev/null 2>&1; then
    return 1
  fi
  
  # Check if ingress-nginx namespace exists
  if kubectl get namespace ingress-nginx >/dev/null 2>&1; then
    # Check if ingress-nginx controller is running
    if kubectl get deployment -n ingress-nginx ingress-nginx-controller >/dev/null 2>&1; then
      local ready_replicas
      ready_replicas=$(kubectl get deployment -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
      # Ensure ready_replicas is a valid integer
      ready_replicas=${ready_replicas:-0}
      if [[ "$ready_replicas" =~ ^[0-9]+$ ]] && [ "$ready_replicas" -gt 0 ]; then
        info "ingress-nginx controller is installed and running"
        return 0
      fi
    fi
  fi
  
  return 1
}

# Install ingress-nginx controller
install_ingress_nginx() {
  log "Starting ingress-nginx controller installation..."
  
  if ! command -v kubectl >/dev/null 2>&1; then
    error "kubectl command is required to install ingress-nginx"
    return 1
  fi
  
  # Create ingress-nginx namespace
  kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
  
  # Install ingress-nginx using official manifest
  log "Applying ingress-nginx manifest..."
  if ! kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml; then
    error "Failed to apply ingress-nginx manifest"
    return 1
  fi
  
  # Wait for ingress-nginx controller to be ready
  log "Waiting for ingress-nginx controller to be ready..."
  if ! kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=300s; then
    error "Timeout waiting for ingress-nginx controller to be ready"
    
    # Show pod status for debugging
    log "Checking ingress-nginx pod status..."
    kubectl get pods -n ingress-nginx
    kubectl describe pods -n ingress-nginx
    
    return 1
  fi
  
  # Verify installation
  if check_ingress_nginx_installed; then
    info "ingress-nginx controller installed successfully"
  else
    error "ingress-nginx controller installation failed"
    return 1
  fi
}

# --- Parse command line arguments ---
usage() {
  cat <<EOF
Usage: ./install-k3s.sh [options]

This script auto-detects node type based on node IP list:
- First IP is master node (initialize cluster)
- Other IPs are worker nodes (join cluster)
- Current server IP must be in the configured node list

Options:
  --token TOKEN                  Cluster token, auto-generated if not provided (master)
  --version VERSION              Specify k3s version, e.g. v1.32.1+k3s1
  --data-dir PATH                k3s data directory (default: /var/lib/rancher/k3s)
  --kubeconfig-mode MODE         kubeconfig permissions
  --mirror [cn|global]           Mirror source (default: cn)
  --disable COMPONENTS           Disable components, comma-separated (default: traefik,rancher)
  --tls-sans "a.com,1.2.3.4"     Append TLS SANs (optional)
  --extra-args "..."             Append extra args to k3s
  --force                        Force reinstall (uninstall existing environment)
  --uninstall                    Uninstall k3s
  -h, --help                     Show help

Features:
  - Auto-detect public IP address, use private IP if no public IP
  - Auto-detect and install Helm tool
  - Auto-detect and install Ingress-Nginx controller
  - Support single-node and multi-node cluster deployment
  - Built-in default configuration, no dependency on environment variable files

Examples:
  Auto install (auto-detect IP and node type)
    sudo ./install-k3s.sh

  Force reinstall
    sudo ./install-k3s.sh --force

  Use custom version
    sudo ./install-k3s.sh --version v1.30.4+k3s1

  Specify token (for worker nodes)
    sudo ./install-k3s.sh --token mytoken
EOF
}

uninstall=false
force_install=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token) k3s_token="$2"; shift 2 ;;
    --version) k3s_version="$2"; shift 2 ;;
    --data-dir) k3s_data_dir="$2"; shift 2 ;;
    --kubeconfig-mode) k3s_kubeconfig_mode="$2"; shift 2 ;;
    --mirror) k3s_mirror="$2"; shift 2 ;;
    --disable) k3s_disable_components="$2"; shift 2 ;;
    --tls-sans) tls_sans="$2"; shift 2 ;;
    --extra-args) extra_args="$2"; shift 2 ;;
    --force) force_install=true; shift ;;
    --uninstall) uninstall=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "未知参数: $1"; usage; exit 2 ;;
  esac
done

# --- Pre-checks ---
check_ubuntu || exit 1

# Handle uninstall request
if [ "$uninstall" = true ]; then
  log "Uninstalling k3s..."
  
  # Try to uninstall server
  if command -v /usr/local/bin/k3s-uninstall.sh >/dev/null 2>&1; then
    sudo /usr/local/bin/k3s-uninstall.sh || true
    info "k3s server uninstalled"
  # Try to uninstall agent
  elif command -v /usr/local/bin/k3s-agent-uninstall.sh >/dev/null 2>&1; then
    sudo /usr/local/bin/k3s-agent-uninstall.sh || true
    info "k3s agent uninstalled"
  else
    error "k3s uninstall script not found"
  fi
  exit 0
fi

# Check existing Kubernetes environment
if existing_k8s=$(check_existing_k8s); then
  if [ "$force_install" = true ]; then
    log "Detected existing $existing_k8s environment, forcing reinstall..."
    uninstall_kubernetes "$existing_k8s" || exit 1
  else
    warn "$existing_k8s is already installed, use --force parameter to reinstall"
    
    # If it's k3s environment, continue checking other components
    if [ "$existing_k8s" = "k3s" ]; then
      log "Checking other components..."
      
      # Check and install helm
      if ! check_helm_installed; then
        log "helm not installed, starting installation..."
        install_helm || exit 1
      fi
      
      # Check and install ingress-nginx
      if ! check_ingress_nginx_installed; then
        log "ingress-nginx controller not installed, starting installation..."
        install_ingress_nginx || exit 1
      fi
      
      info "All components check completed"
    fi
    
    exit 0
  fi
fi

# Install dependencies
install_dependencies curl

# Configure mirror repository
if [ "$k3s_mirror" = "cn" ]; then
  setup_k3s_registry
fi

# --- Auto node type detection ---
if ! node_info=$(check_node_in_list); then
  error "Node IP check failed"
  exit 1
fi

# Parse node info: type:IP:index
IFS=':' read -r node_type node_ip node_index <<< "$node_info"

# Validate parsing result
if [ -z "$node_type" ] || [ -z "$node_ip" ]; then
  error "Node info parsing failed: $node_info"
  exit 1
fi

info "Detected node type: $node_type, IP: $node_ip, index: $node_index"

# Function to build common installation arguments
build_install_args() {
  local role="$1"
  local args=()
  
  if [ "$role" = "master" ]; then
    args=(server --cluster-init)
  else
    args=(agent)
  fi
  
  # Disable components
  if [ -n "$k3s_disable_components" ]; then
    IFS=',' read -ra components <<< "$k3s_disable_components"
    for comp in "${components[@]}"; do
      args+=("--disable" "$comp")
    done
  fi
  
  # TLS SANs (master node only)
  if [ "$role" = "master" ]; then
    # Add SANs specified via --tls-sans parameter
    if [ -n "$tls_sans" ]; then
      IFS=',' read -ra sans <<< "$tls_sans"
      for s in "${sans[@]}"; do 
        args+=("--tls-san" "$s")
      done
      log "Adding TLS SANs: $tls_sans"
    fi

    # Add all node IPs to TLS SANs
    local node_ips
    node_ips=$(get_all_node_ips)
    while IFS= read -r ip; do
      [ -n "$ip" ] && args+=("--tls-san" "$ip")
    done <<< "$node_ips"
    
    # Add common k8s internal service IPs to TLS SANs
    args+=("--tls-san" "10.43.0.1") # kubernetes service IP
    args+=("--tls-san" "127.0.0.1") # localhost

    # Add K3S_API_URL to TLS SANs
    if [ -n "$K3S_API_URL" ]; then
      args+=("--tls-san" "$K3S_API_URL")
    fi
  fi
  
  # Extra arguments
  if [ -n "$extra_args" ]; then
    # shellcheck disable=SC2206
    local extra_array=( $extra_args )
    args+=("${extra_array[@]}")
    log "Extra arguments: $extra_args"
  fi
  
  printf '%s\n' "${args[@]}"
}

# Function to execute k3s installation
install_k3s() {
  local install_env="$1"
  shift
  local args=("$@")
  
  if [ -n "$k3s_version" ]; then
    log "Installing specified version: $k3s_version"
    curl -ksfL "$k3s_install_url" | INSTALL_K3S_VERSION="$k3s_version" sudo env $install_env sh -s - "${args[@]}"
  else
    log "Installing latest version"
    curl -ksfL "$k3s_install_url" | sudo env $install_env sh -s - "${args[@]}"
  fi
}

# Install based on node type
if [ "$node_type" = "master" ]; then
  log "Starting k3s master node installation..."
  
  # Generate token (if not provided)
  if [ -z "$k3s_token" ]; then
    k3s_token="$(random_token)"
    log "No token provided, auto-generated: $k3s_token"
  fi

  # Build environment variables
  install_env="K3S_TOKEN=$k3s_token K3S_KUBECONFIG_MODE=$k3s_kubeconfig_mode K3S_DATA_DIR=$k3s_data_dir K3S_NODE_IP=$node_ip"
  if [ -n "${K3S_INSTALL_NODE_IP_LIST:-}" ]; then
    install_env+=" K3S_INSTALL_NODE_IP_LIST=$K3S_INSTALL_NODE_IP_LIST"
  fi
  [ "$k3s_mirror" = "cn" ] && install_env+=" INSTALL_K3S_MIRROR=cn"

  # Build installation arguments and execute installation
  log "Initializing cluster, node IP: $node_ip"
  readarray -t args < <(build_install_args "master")
  install_k3s "$install_env" "${args[@]}"

  # Wait for service to start
  wait_for_service k3s
  
  info "k3s master node installation completed!"
  info "Token: $k3s_token"
  info "Node IP: $node_ip"
  info "Command for other nodes to join: sudo ./install-k3s.sh --token $k3s_token"

elif [ "$node_type" = "worker" ]; then
  log "Starting k3s worker node installation..."
  
  # Check required parameters
  if [ -z "$k3s_token" ]; then
    error "Worker node requires --token parameter"
    exit 2
  fi
  
  # Get master node IP (first one in node list)
  if [ -n "${K3S_INSTALL_NODE_IP_LIST:-}" ]; then
    node_list="${K3S_INSTALL_NODE_IP_LIST//\"/}"
    master_ip=$(echo "$node_list" | awk '{print $1}')
  else
    # If no node list configured, try to get from environment or use default
    master_ip="${K3S_MASTER_IP:-}"
    if [ -z "$master_ip" ]; then
      error "Unable to get master node IP. Please set K3S_INSTALL_NODE_IP_LIST or K3S_MASTER_IP environment variable"
      exit 2
    fi
  fi
  
  if [ -z "$master_ip" ]; then
    error "Unable to get master node IP"
    exit 2
  fi
  
  k3s_url="https://$master_ip:6443"

  # Build environment variables
  install_env="K3S_URL=$k3s_url K3S_TOKEN=$k3s_token K3S_DATA_DIR=$k3s_data_dir K3S_NODE_IP=$node_ip"
  [ "$k3s_mirror" = "cn" ] && install_env+=" INSTALL_K3S_MIRROR=cn"

  # Build installation arguments and execute installation
  log "Connecting to cluster: $k3s_url, node IP: $node_ip"
  readarray -t args < <(build_install_args "worker")
  install_k3s "$install_env" "${args[@]}"

  # Wait for service to start
  wait_for_service k3s-agent
  
  info "k3s worker node installation completed!"
  info "Connected to cluster: $k3s_url"
  info "Node IP: $node_ip"

else
  error "Unknown node type: $node_type"
  exit 2
fi

# Post-installation tips
if [ "$node_type" = "master" ]; then
  info "kubeconfig path: /etc/rancher/k3s/k3s.yaml"
  info "Use kubectl: sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes"
  info "Or: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
  info "Check service status: systemctl status k3s"
  
  # Wait for k3s to fully start
  log "Waiting for k3s to fully start..."
  sleep 10
  
  # Set KUBECONFIG environment variable
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  
  # Install helm (if not installed)
  if ! check_helm_installed; then
    log "helm not installed, starting installation..."
    install_helm || error "helm installation failed"
  fi
  
  # Install ingress-nginx controller (if not installed)
  if ! check_ingress_nginx_installed; then
    log "ingress-nginx controller not installed, starting installation..."
    install_ingress_nginx || error "ingress-nginx controller installation failed"
  fi
  
  # Generate external access kubeconfig
  log "Generating external access kubeconfig configuration file"
  if [ -f /etc/rancher/k3s/k3s.yaml ]; then

    # If K3S_API_URL is configured, also replace with domain name
    if [ -n "${K3S_API_URL:-}" ]; then
      # Create external access configuration directory
      sudo mkdir -p /etc/rancher/k3s/external
      sudo cp /etc/rancher/k3s/k3s.yaml /etc/rancher/k3s/$K3S_API_URL.yaml
      sudo sed -i "s|https://127.0.0.1:6443|https://$K3S_API_URL:6443|g" /etc/rancher/k3s/$K3S_API_URL.yaml
      sudo sed -i "s|https://localhost:6443|https://$K3S_API_URL:6443|g" /etc/rancher/k3s/$K3S_API_URL.yaml
      info "External access kubeconfig generated: /etc/rancher/k3s/$K3S_API_URL.yaml"
    fi

    # Generate container internal https://kubernetes.default.svc:443 configuration file, kubernetes-internal.yaml
    sudo cp /etc/rancher/k3s/k3s.yaml /etc/rancher/k3s/kubernetes-internal.yaml
    sudo sed -i "s|https://127.0.0.1:6443|https://kubernetes.default.svc:443|g" /etc/rancher/k3s/kubernetes-internal.yaml
    sudo sed -i "s|https://localhost:6443|https://kubernetes.default.svc:443|g" /etc/rancher/k3s/kubernetes-internal.yaml
    info "Container internal kubeconfig generated: /etc/rancher/k3s/kubernetes-internal.yaml"

  else
    error "Cannot find default kubeconfig file, external access configuration generation failed"
  fi

else
  info "Check service status: systemctl status k3s-agent"
fi

info "k3s installation completed! Node type: $node_type, IP: $node_ip"