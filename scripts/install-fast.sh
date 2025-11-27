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
    sed -i 's/^\s*cn:\s*false/cn: true/' "$dst"
  fi
}

helm_install() {
  log "Running Helm install"
  local ns="mcpcan"
  helm install mcpcan ./helm -f helm/values-custom.yaml --namespace "$ns" --create-namespace --timeout 600s --wait || {
    err "Helm install failed"
    exit 1
  }
  log "Helm install finished"
}

verify_pods() {
  local ns="mcpcan"
  log "Verifying pods in namespace: $ns"
  local start_ts=$(date +%s)
  local timeout=$((start_ts + 600))
  while true; do
    local now=$(date +%s)
    if [ "$now" -ge "$timeout" ]; then
      err "Timeout waiting for all pods to become Ready"
      kubectl get pods -n "$ns" || true
      exit 1
    fi
    local not_ready=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | awk '{print $3}' | grep -Ev 'Running|Succeeded|Completed' | wc -l || echo 1)
    local in_error=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | awk '{print $3}' | grep -E 'Error|CrashLoopBackOff|ImagePullBackOff|Init:Error' | wc -l || echo 1)
    if [ "$not_ready" -eq 0 ] && [ "$in_error" -eq 0 ]; then
      log "All pods are Ready"
      break
    fi
    log "Waiting for pods... not_ready=$not_ready error=$in_error"
    sleep 5
  done
}

print_access_url() {
  local dst="helm/values-custom.yaml"
  local public_ip=$(grep -E '^\s*publicIP:' "$dst" | awk '{print $2}' | tr -d '"')
  if [ -z "$public_ip" ]; then
    warn "publicIP not found in $dst"
  else
    log "Access URL: http://$public_ip"
  fi
}

main() {
  log "Fast installation started"
  install_environment
  clone_repo_if_needed
  copy_and_adjust_values
  helm_install
  verify_pods
  print_access_url
  log "Fast installation finished"
}

main "$@"
