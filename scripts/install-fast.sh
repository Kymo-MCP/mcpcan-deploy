#!/bin/bash
set -euo pipefail

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*"; }
warn() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*"; }
err() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*"; }

usage() {
  cat <<EOF
Usage: install-fast.sh [--cn]

Options:
  --cn    Use China mirror sources and adjust template parameters

Steps performed:
  1) Install runtime environment (K3s + Helm + Ingress)
  2) Clone deployment repository if missing
  3) Enter repository directory
  4) Copy parameter template to values-custom.yaml
  5) Apply --cn adjustments to values-custom.yaml
  6) Run Helm install
  7) Verify all pods are running
  8) Output access URL http://publicIP
EOF
}

CN=false
for arg in "$@"; do
  case "$arg" in
    --cn) CN=true ; shift ;;
    -h|--help) usage; exit 0 ;;
    *) ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$(dirname "$0")/bash.sh"

install_environment() {
  log "Installing runtime environment (K3s + Helm + Ingress)"
  local env_script="$ROOT_DIR/scripts/install-run-environment.sh"
  if [ ! -x "$env_script" ]; then
    err "Environment installer not found: $env_script"
    exit 1
  fi
  if [ "$CN" = true ]; then
    bash "$env_script" --cn
  else
    bash "$env_script"
  fi
  log "Runtime environment installation completed"
}

clone_repo_if_needed() {
  local repo_url="https://github.com/Kymo-MCP/mcpcan-deploy.git"
  if [ -d "$ROOT_DIR/helm" ]; then
    log "Repository already present at $ROOT_DIR"
    REPO_DIR="$ROOT_DIR"
    return
  fi
  REPO_DIR="$PWD/mcpcan-deploy"
  log "Cloning repository $repo_url into $REPO_DIR"
  if command -v git >/dev/null 2>&1; then
    git clone "$repo_url" "$REPO_DIR"
  else
    err "git is required to clone repository"
    exit 1
  fi
}

copy_and_adjust_values() {
  cd "$REPO_DIR"
  log "Entering repository directory: $REPO_DIR"
  local src="helm/values.yaml"
  local dst="helm/values-custom.yaml"
  if [ ! -f "$src" ]; then
    err "Template file not found: $src"
    exit 1
  fi
  cp "$src" "$dst"
  log "Copied parameter template to $dst"
  if [ "$CN" = true ]; then
    log "Applying China mirror adjustments to $dst"
    sed -i -E 's/^([[:space:]]*)cn:[[:space:]]*false/\1cn: true/' "$dst"
  fi
}

helm_install() {
  local ns="mcpcan"
  log "Checking Helm release status"
  local status_out=""
  if status_out=$(helm status mcpcan --namespace "$ns" 2>/dev/null); then
    local status
    status=$(echo "$status_out" | awk -F': ' '/^STATUS:/{print $2}')
    if [ -n "$status" ]; then
      if [ "$status" = "deployed" ] || [ "$status" = "superseded" ]; then
        warn "Helm release 'mcpcan' already exists with status: $status"
        read -r -p "Force upgrade to latest chart? [y/N]: " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
          log "Running Helm upgrade mcpcan ./helm -f helm/values-custom.yaml --namespace \"$ns\" --timeout 600s --wait"
          helm upgrade mcpcan ./helm -f helm/values-custom.yaml --namespace "$ns" --timeout 600s --wait || {
            err "Helm upgrade mcpcan failed"
            exit 1
          }
          log "Helm upgrade mcpcan finished"
        else
          err "Release exists, skip upgrade. Fix or change values then run upgrade manually"
          exit 0
        fi
      else
        warn "Helm release 'mcpcan' status is abnormal: $status"
        read -r -p "Force upgrade anyway? [y/N]: " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
          log "Running Helm upgrade mcpcan ./helm -f helm/values-custom.yaml --namespace \"$ns\" --timeout 600s --wait"
          helm upgrade mcpcan ./helm -f helm/values-custom.yaml --namespace "$ns" --timeout 600s --wait || {
            err "Helm upgrade mcpcan failed"
            exit 1
          }
          log "Helm upgrade mcpcan finished"
        else
          err "Please repair the abnormal status first, then upgrade"
          exit 1
        fi
      fi
    else
      warn "Unable to read Helm release status"
      read -r -p "Proceed with upgrade? [y/N]: " ans
      if [[ "$ans" =~ ^[Yy]$ ]]; then
        log "Running Helm upgrade mcpcan ./helm -f helm/values-custom.yaml --namespace \"$ns\" --timeout 600s --wait"
        helm upgrade mcpcan ./helm -f helm/values-custom.yaml --namespace "$ns" --timeout 600s --wait || {
          err "Helm upgrade mcpcan failed"
          exit 1
        }
        log "Helm upgrade mcpcan finished"
      else
        err "Cancel upgrade"
        exit 1
      fi
    fi
  else
    log "Running Helm install mcpcan ./helm -f helm/values-custom.yaml --namespace \"$ns\" --create-namespace --timeout 600s (this step needs a few minutes)"
    helm install mcpcan ./helm -f helm/values-custom.yaml --namespace "$ns" --create-namespace --timeout 600s --wait || {
      err "Running Helm install mcpcan ./helm -f helm/values-custom.yaml --namespace \"$ns\" --create-namespace --timeout 600s --wait failed"
      exit 1
    }
    log "Running Helm install mcpcan finished"
  fi
}

verify_pods() {
  local ns="mcpcan"
  log "Verifying Helm release status"
  local start_ts=$(date +%s)
  local timeout=$((start_ts + 600))
  while true; do
    local now=$(date +%s)
    if [ "$now" -ge "$timeout" ]; then
      err "Timeout waiting for Helm release to be deployed"
      helm status mcpcan --namespace "$ns" || true
      exit 1
    fi
    local status_out
    status_out=$(helm status mcpcan --namespace "$ns" 2>/dev/null || true)
    if echo "$status_out" | grep -qE '^STATUS: (deployed|superseded)'; then
      log "Installation succeeded: Helm release is deployed"
      local public_ip=""
      if command -v auto_detect_node_ips >/dev/null 2>&1; then
        public_ip=$(auto_detect_node_ips 2>/dev/null || true)
      fi
      if ! echo "$public_ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
        public_ip=""
      fi
      if [ -n "$public_ip" ]; then
        log "Access URL: http://$public_ip"
      else
        log "Access URL: http://localhost"
      fi
      exit 0
    fi
    log "Waiting for Helm release..."
    sleep 5
  done
}

main() {
  log "Fast installation started"
  install_environment
  clone_repo_if_needed
  copy_and_adjust_values
  helm_install
  verify_pods
  log "Fast installation finished"
}

main "$@"
