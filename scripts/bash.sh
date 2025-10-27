#!/usr/bin/env bash

# ==============================================
# Common Bash Script Library
# Contains environment variable loading, color definitions, logging functions, and other common logic
# ==============================================

# --- k3s installation default parameters ---
# K3S installation default parameters
K3S_VERSION=${K3S_VERSION:-"v1.32.1+k3s1"}
K3S_MIRROR=${K3S_MIRROR:-"cn"}
K3S_INSTALL_URL=${K3S_INSTALL_URL:-"https://rancher-mirror.rancher.cn/k3s/k3s-install.sh"}
K3S_DATA_DIR=${K3S_DATA_DIR:-"/var/lib/rancher/k3s"}
K3S_KUBECONFIG_MODE=${K3S_KUBECONFIG_MODE:-"644"}
K3S_DISABLE_COMPONENTS=${K3S_DISABLE_COMPONENTS:-"traefik,rancher"}

# --- Color definitions ---
GREEN="✅ "
YELLOW="💡️ "
RED="❌"
GRAY="️🕒 "
NOTICE="⚠️ "

# --- Utility functions ---
# Get absolute path of script directory
script_dir() { cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P; }

# Logging functions
log() { echo "[$(basename "$0")] $*"; }
err() { echo "[$(basename "$0")][ERROR] $*" >&2; }
info() { echo "${GREEN}$*"; }
warn() { echo "${YELLOW}$*"; }
error() { echo "${RED}$*" >&2; }

# Generate random token (when not provided)
random_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  else
    head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

# Check if command exists
check_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "Command not found: $cmd"
    return 1
  fi
  return 0
}

# Check if running as root user
check_root() {
  if [[ $EUID -eq 0 ]]; then
    return 0
  else
    return 1
  fi
}

# Check if running on Ubuntu system
check_ubuntu() {
  if [[ "${OSTYPE:-linux}" != linux* ]]; then
    error "This script is designed for Linux/Ubuntu environment. Current system: ${OSTYPE:-unknown}"
    return 1
  fi
  
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
      warn "Detected non-Ubuntu system: $ID, compatibility issues may occur"
    fi
  fi
  
  return 0
}

# Install dependency packages (Ubuntu)
install_dependencies() {
  local packages=("$@")
  
  if [ ${#packages[@]} -eq 0 ]; then
    return 0
  fi
  
  log "Checking and installing dependency packages: ${packages[*]}"
  
  local missing_packages=()
  for pkg in "${packages[@]}"; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
      missing_packages+=("$pkg")
    fi
  done
  
  if [ ${#missing_packages[@]} -gt 0 ]; then
    log "Installing missing dependency packages: ${missing_packages[*]}"
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -y
      sudo apt-get install -y "${missing_packages[@]}"
    else
      error "apt-get not found, please manually install dependency packages: ${missing_packages[*]}"
      return 1
    fi
  else
    info "All dependency packages are installed"
  fi
}

# Configure k3s domestic mirror repository
setup_k3s_registry() {
  log "Configuring k3s domestic mirror repository"
  sudo mkdir -p /etc/rancher/k3s
  sudo tee /etc/rancher/k3s/registries.yaml > /dev/null <<EOF
mirrors:
  docker.io:
    endpoint:
      - "https://registry.cn-hangzhou.aliyuncs.com"
      - "https://docker.mirrors.ustc.edu.cn"
      - "https://hub.docker.com"
  k8s.gcr.io:
    endpoint:
      - "https://registry.cn-hangzhou.aliyuncs.com"
      - "https://docker.mirrors.ustc.edu.cn"
      - "https://hub.docker.com"
  gcr.io:
    endpoint:
      - "https://gcr.mirrors.ustc.edu.cn"
  k8s.gcr.io:
    endpoint:
      - "https://k8s-gcr.mirrors.ustc.edu.cn"
  quay.io:
    endpoint:
      - "https://quay.mirrors.ustc.edu.cn"
  "ccr.ccs.tencentyun.com":
    endpoint:
      - "https://ccr.ccs.tencentyun.com"
  aliyun.com:
    endpoint:
      - "https://registry.cn-hangzhou.aliyuncs.com"
      - "https://registry.cn-guangzhou.aliyuncs.com"
EOF
  
  info "k3s mirror repository configuration completed"
}

# Check if k3s is installed
check_k3s_installed() {
  if command -v k3s >/dev/null 2>&1; then
    info "k3s is installed, version: $(k3s --version | head -n1)"
    return 0
  else
    return 1
  fi
}

# Get node IP address
get_node_ip() {

  if [ -n "${NODE_IP:-}" ]; then
    echo "$NODE_IP"
    return 0
  fi
  
  # Automatically get primary network interface IP
  local ip
  ip=$(hostname -I | awk '{print $1}')
  
  if [ -n "$ip" ]; then
    echo "$ip"
  else
    error "Unable to get node IP address"
    return 1
  fi
}

# Get all IP addresses of current server (including public IP)
get_server_ips() {
  local ips=()
  
  # Get local network interface IPs (compatible with Linux and macOS)
  local local_ips
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS uses ifconfig
    local_ips=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}')
  else
    # Linux uses hostname -I
    local_ips=$(hostname -I | tr ' ' '\n' | grep -v '^$')
  fi
  
  while IFS= read -r ip; do
    [ -n "$ip" ] && ips+=("$ip")
  done <<< "$local_ips"
  
  # Try to get public IP
  local public_ip
  if command -v curl >/dev/null 2>&1; then
    # Try multiple services to get public IP
    for service in "http://ipinfo.io/ip" "http://icanhazip.com" "http://ifconfig.me/ip" "http://checkip.amazonaws.com" "http://ip.42.pl/raw"; do
      public_ip=$(curl -s --connect-timeout 5 --max-time 10 "$service" 2>/dev/null | tr -d '\n\r\t ')
      if [[ "$public_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # Check if already exists in local IP list
        local found=false
        for local_ip in "${ips[@]}"; do
          if [ "$local_ip" = "$public_ip" ]; then
            found=true
            break
          fi
        done
        if [ "$found" = false ]; then
          ips+=("$public_ip")
          # Only output detailed information in debug mode
          [ "${DEBUG:-}" = "1" ] && info "Detected public IP: $public_ip"
        fi
        break
      fi
    done
  fi
  
  # If no public IP obtained, log it
  if [ -z "$public_ip" ] || ! [[ "$public_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    [ "${DEBUG:-}" = "1" ] && warn "Unable to get public IP, will use private IP"
  fi
  
  printf '%s\n' "${ips[@]}"
}

# Auto-detect node IP list (prioritize public IP, use private IP if not available)
auto_detect_node_ips() {
  local server_ips_str
  server_ips_str=$(get_server_ips)
  
  local primary_ip=""
  local public_ip=""
  local private_ip=""
  
  # Analyze obtained IP addresses
  while IFS= read -r ip; do
    [ -z "$ip" ] && continue
    
    # Determine if it's a public IP (exclude private network segments)
    if [[ "$ip" =~ ^10\. ]] || [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || [[ "$ip" =~ ^192\.168\. ]]; then
      # Private IP
      if [ -z "$private_ip" ]; then
        private_ip="$ip"
      fi
    else
      # Public IP
      if [ -z "$public_ip" ]; then
        public_ip="$ip"
      fi
    fi
  done <<< "$server_ips_str"
  
  # Prioritize public IP, use private IP if not available
  if [ -n "$public_ip" ]; then
    primary_ip="$public_ip"
    # Only output detailed information in debug mode
    [ "${DEBUG:-}" = "1" ] && info "Using public IP as node IP: $primary_ip"
  elif [ -n "$private_ip" ]; then
    primary_ip="$private_ip"
    # Only output detailed information in debug mode
    [ "${DEBUG:-}" = "1" ] && info "Using private IP as node IP: $primary_ip"
  else
    error "Unable to get valid IP address"
    return 1
  fi
  
  # Set K3S_API_URL to primary IP
  export K3S_API_URL="$primary_ip"
  
  # Return primary IP (for single node installation)
  echo "$primary_ip"
}

# Check if current server IP is in node list, return node type and position
check_node_in_list() {
  # If no node list configured, auto-detect and set as single node
  if [ -z "${K3S_INSTALL_NODE_IP_LIST:-}" ]; then
    local auto_ip
    auto_ip=$(auto_detect_node_ips)
    if [ $? -eq 0 ] && [ -n "$auto_ip" ]; then
      export K3S_INSTALL_NODE_IP_LIST="$auto_ip"
      # Only output information in debug mode to avoid interfering with node type parsing
      [ "${DEBUG:-}" = "true" ] && info "Auto-detected node IP list: $K3S_INSTALL_NODE_IP_LIST"
      # Directly return master node information without extra output
      echo "master:$auto_ip:0"
      return 0
    else
      error "Failed to auto-detect node IP"
      return 1
    fi
  fi
  
  local node_list="${K3S_INSTALL_NODE_IP_LIST}"
  
  if [ -z "$node_list" ]; then
    error "K3S_INSTALL_NODE_IP_LIST not configured"
    return 1
  fi
  
  # Convert node list to array (compatible with bash and zsh)
  local configured_nodes
  if [ -n "$ZSH_VERSION" ]; then
    # zsh environment, use word splitting
    setopt sh_word_split 2>/dev/null || true
    configured_nodes=($node_list)
  else
    # bash environment
    IFS=' ' read -ra configured_nodes <<< "$node_list"
  fi
  
  if [ ${#configured_nodes[@]} -eq 0 ]; then
    error "Node IP list is empty"
    return 1
  fi
  
  # Get all IPs of current server
  local server_ips_str
  server_ips_str=$(get_server_ips)
  
  # Check for matches
  local i=0
  for config_ip in "${configured_nodes[@]}"; do
    while IFS= read -r server_ip; do
      [ -z "$server_ip" ] && continue
      if [ "$server_ip" = "$config_ip" ]; then
        if [ $i -eq 0 ]; then
          echo "master:$config_ip:$i"
        else
          echo "worker:$config_ip:$i"
        fi
        return 0
      fi
    done <<< "$server_ips_str"
    i=$((i + 1))
  done
  
  # No match found
  error "Current server is not in the configured node IP list"
  error "Server IPs: $(echo "$server_ips_str" | tr '\n' ' ')"
  error "Node list: ${configured_nodes[*]}"
  return 1
}

# Wait for service to start
wait_for_service() {
  local service_name="$1"
  local max_wait="${2:-60}"
  local wait_time=0
  
  log "Waiting for service to start: $service_name"
  
  while [ $wait_time -lt $max_wait ]; do
    if systemctl is-active --quiet "$service_name"; then
      info "Service $service_name has started"
      return 0
    fi
    
    sleep 2
    wait_time=$((wait_time + 2))
    echo -n "."
  done
  
  echo
  error "Service $service_name startup timeout"
  return 1
}

# Show script usage help
show_usage() {
  cat <<EOF
Usage: $0 [options]

This script provides a common function library for k3s installation.

Environment Variables:
  K3S_VERSION              k3s version (default: v1.32.1+k3s1)
  K3S_MIRROR              Mirror source (default: cn)
  K3S_INSTALL_URL         Installation script URL
  K3S_DATA_DIR            Data directory (default: /var/lib/rancher/k3s)
  K3S_KUBECONFIG_MODE     kubeconfig permissions (default: 644)
  K3S_DISABLE_COMPONENTS  Disabled components (default: traefik,rancher)
Examples:
  source bash.sh          # Load common function library
EOF
}

# Handle command line arguments (when script is executed directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    -h|--help)
      show_usage
      exit 0
      ;;
    *)
      echo "This is a common function library, please use source command to load:"
      echo "  source bash.sh"
      echo ""
      echo "Or view help:"
      echo "  bash bash.sh --help"
      exit 1
      ;;
  esac
fi