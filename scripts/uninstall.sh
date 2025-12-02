#!/usr/bin/env bash
set -euo pipefail

# ==============================================
# k3s Uninstall Script (Ubuntu Environment)
# Completely uninstall k3s cluster and clean related resources
# Support uninstallation of master and worker nodes
# ==============================================

# Load common function library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bash.sh"

# --- Parse command line arguments ---
usage() {
  cat <<EOF
Usage: ./uninstall-k3s.sh [options]

This script is used to completely uninstall k3s cluster:
- Auto-detect node type (master/worker)
- Stop and uninstall k3s service
- Clean data directories and configuration files
- Remove related network configurations

Options:
  --force                        Force uninstall, skip confirmation
  --keep-data                    Keep data directory
  --clean-all                    Clean all related files (including images)
  -h, --help                     Show help

Examples:
  Standard uninstall
    sudo ./uninstall-k3s.sh

  Force uninstall (skip confirmation)
    sudo ./uninstall-k3s.sh --force

  Complete cleanup
    sudo ./uninstall-k3s.sh --clean-all
EOF
}

force=false
keep_data=false
clean_all=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) force=true; shift ;;
    --keep-data) keep_data=true; shift ;;
    --clean-all) clean_all=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown parameter: $1"; usage; exit 2 ;;
  esac
done

# --- Pre-checks ---
check_ubuntu || exit 1

# Check if running as root user
if [[ $EUID -ne 0 ]]; then
  error "This script requires root privileges to run"
  exit 1
fi

# Check if k3s is installed
if ! check_k3s_installed; then
  warn "k3s is not installed or has been uninstalled"
  exit 0
fi

# Confirm uninstall (unless using --force)
if [ "$force" != true ]; then
  echo "${YELLOW}Warning: This operation will completely uninstall k3s cluster and delete all related data!"
  echo "This will affect:"
  echo "- Stop all k3s services"
  echo "- Delete all containers and images"
  echo "- Clean network configurations"
  echo "- Delete data directories (unless using --keep-data)"
  echo ""
  read -p "Are you sure you want to continue? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    info "Cancelled uninstall operation"
    exit 0
  fi
fi

log "Starting k3s uninstall..."

# Detect node type
node_type="unknown"
if systemctl is-active --quiet k3s 2>/dev/null; then
  node_type="master"
  info "Detected k3s server node"
elif systemctl is-active --quiet k3s-agent 2>/dev/null; then
  node_type="worker"
  info "Detected k3s agent node"
else
  # Check if service files exist
  if [ -f "/etc/systemd/system/k3s.service" ]; then
    node_type="master"
  elif [ -f "/etc/systemd/system/k3s-agent.service" ]; then
    node_type="worker"
  fi
fi

# Stop services
log "Stopping k3s services..."
if [ "$node_type" = "master" ]; then
  systemctl stop k3s 2>/dev/null || true
  systemctl disable k3s 2>/dev/null || true
elif [ "$node_type" = "worker" ]; then
  systemctl stop k3s-agent 2>/dev/null || true
  systemctl disable k3s-agent 2>/dev/null || true
else
  # Try to stop all possible services
  systemctl stop k3s 2>/dev/null || true
  systemctl stop k3s-agent 2>/dev/null || true
  systemctl disable k3s 2>/dev/null || true
  systemctl disable k3s-agent 2>/dev/null || true
fi

# Use official uninstall script
log "Executing official uninstall script..."
if [ "$node_type" = "master" ] || [ "$node_type" = "unknown" ]; then
  if command -v /usr/local/bin/k3s-uninstall.sh >/dev/null 2>&1; then
    /usr/local/bin/k3s-uninstall.sh || true
    info "k3s server uninstall script completed"
  fi
fi

if [ "$node_type" = "worker" ] || [ "$node_type" = "unknown" ]; then
  if command -v /usr/local/bin/k3s-agent-uninstall.sh >/dev/null 2>&1; then
    /usr/local/bin/k3s-agent-uninstall.sh || true
    info "k3s agent uninstall script completed"
  fi
fi

# Clean remaining processes
log "Cleaning remaining processes..."
pkill -f k3s 2>/dev/null || true
pkill -f containerd 2>/dev/null || true

# Clean network configuration
log "Cleaning network configuration..."
# Delete CNI network interfaces
for iface in $(ip link show | grep -E 'cni0|flannel|veth' | awk -F: '{print $2}' | tr -d ' '); do
  ip link delete "$iface" 2>/dev/null || true
done

# Clean iptables rules
iptables -t nat -F 2>/dev/null || true
iptables -t mangle -F 2>/dev/null || true
iptables -F 2>/dev/null || true
iptables -X 2>/dev/null || true

# Clean data directories (unless specified to keep)
if [ "$keep_data" != true ]; then
  log "Cleaning data directories..."
  rm -rf /var/lib/rancher/k3s 2>/dev/null || true
  rm -rf /etc/rancher/k3s 2>/dev/null || true
  rm -rf /var/lib/kubelet 2>/dev/null || true
  rm -rf /var/lib/cni 2>/dev/null || true
  rm -rf /opt/cni 2>/dev/null || true
else
  info "Keeping data directories (--keep-data option used)"
fi

# Clean configuration files
log "Cleaning configuration files..."
rm -f /usr/local/bin/k3s 2>/dev/null || true
rm -f /usr/local/bin/kubectl 2>/dev/null || true
rm -f /usr/local/bin/crictl 2>/dev/null || true
rm -f /usr/local/bin/ctr 2>/dev/null || true
rm -f /usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
rm -f /usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null || true

# Clean systemd service files
rm -f /etc/systemd/system/k3s.service 2>/dev/null || true
rm -f /etc/systemd/system/k3s-agent.service 2>/dev/null || true
systemctl daemon-reload

# Clean registry configuration
rm -f /etc/rancher/k3s/registries.yaml 2>/dev/null || true

# Complete cleanup (if specified)
if [ "$clean_all" = true ]; then
  log "Performing complete cleanup..."
  
  # Clean container runtime data
  rm -rf /var/lib/containerd 2>/dev/null || true
  rm -rf /run/containerd 2>/dev/null || true
  rm -rf /run/k3s 2>/dev/null || true
  
  # Clean logs
  rm -rf /var/log/pods 2>/dev/null || true
  rm -rf /var/log/containers 2>/dev/null || true
  
  # Clean temporary files
  rm -rf /tmp/k3s-* 2>/dev/null || true
  
  info "Complete cleanup finished"
fi

# Clean environment variables
unset KUBECONFIG 2>/dev/null || true

# Verify uninstall results
log "Verifying uninstall results..."
if command -v k3s >/dev/null 2>&1; then
  warn "k3s command still exists, may need manual cleanup"
else
  info "k3s command successfully removed"
fi

if systemctl is-active --quiet k3s 2>/dev/null || systemctl is-active --quiet k3s-agent 2>/dev/null; then
  warn "k3s service still running, may need manual stop"
else
  info "k3s service successfully stopped"
fi

info "k3s uninstall completed!"
info "To reinstall, run: ./install-fast.sh"


# Suggest reboot (optional)
if [ "$clean_all" = true ]; then
  echo ""
  echo "${YELLOW}Recommend rebooting system to ensure all network configurations are completely cleaned"
  if [ "$force" != true ]; then
    read -p "Reboot now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      info "Rebooting system..."
      reboot
    fi
  fi
fi