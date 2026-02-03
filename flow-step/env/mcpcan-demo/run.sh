#!/bin/bash

# Resolve Project Root Directory
# Ensure we are in the mcpcan-deploy root directory regardless of where the script is called from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Navigate 3 levels up: dev -> env -> flow-step -> mcpcan-deploy
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [ ! -d "$PROJECT_ROOT/helm" ]; then
    echo "Error: Could not find project root (helm directory not found in $PROJECT_ROOT)"
    exit 1
fi

cd "$PROJECT_ROOT" || exit 1
echo "Working directory: $(pwd)"
HELM_CHART="$PROJECT_ROOT/helm"
TLS_CERT_PATH="$PROJECT_ROOT/flow-step/env/mcpcan-demo/tls.cert"
TLS_KEY_PATH="$PROJECT_ROOT/flow-step/env/mcpcan-demo/tls.key"

export NAMESPACE=mcp-demo
export GlobalCN=true
export GlobalRunMode=demo
export GlobalDomain=demo.mcpcan.com
export GlobalHostStorageRootPath=/data/mcpcan
export GlobalHostStorageStaticPath=/data/mcpcan/static
export GlobalHostStorageCodePackagePath=/data/mcpcan/code-package
export GlobalHostStorageMysqlPath=/data/mcpcan/mysql
export GlobalHostStorageRedisPath=/data/mcpcan/redis
export IngressTlsEnabled=true


# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}


# 1. Parse Arguments
log "Step 1: Parsing Arguments..."
ACTION=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --action)
            ACTION="$2"
            shift 2
            ;;
        *)
            log "Unknown parameter: $1"
            exit 1
            ;;
    esac
done

# 2. Validate Action
log "Step 2: Validating Action..."
if [[ "$ACTION" != "install" && "$ACTION" != "upgrade" ]]; then
    log "Error: run.sh --action parameter is required (install|upgrade)"
    exit 1
fi

log "=================================================="
log "Starting Helm Deployment"
log "Action: $ACTION"
log "Namespace: $NAMESPACE"
log "Chart Path: $HELM_CHART"
log "=================================================="

# 3. Check if Chart Path exists
log "Step 3: Checking Chart Path..."
if [ ! -d "$HELM_CHART" ]; then
    log "Error: Helm chart directory not found at $HELM_CHART"
    exit 1
fi

# 4. Helm Template Check
log "Step 4: Verifying Helm Template..."
if helm template "$NAMESPACE" "$HELM_CHART" \
    --set global.cn=$GlobalCN \
    --set global.runMode=$GlobalRunMode \
    --set global.domain=$GlobalDomain \
    --set global.hostStorage.rootPath=$GlobalHostStorageRootPath \
    --set global.hostStorage.staticPath=$GlobalHostStorageStaticPath \
    --set global.hostStorage.codePackagePath=$GlobalHostStorageCodePackagePath \
    --set global.hostStorage.mysqlPath=$GlobalHostStorageMysqlPath \
    --set global.hostStorage.redisPath=$GlobalHostStorageRedisPath \
    --set ingress.tls.enabled=$IngressTlsEnabled \
    --set-file ingress.tls.crt="$TLS_CERT_PATH" \
    --set-file ingress.tls.key="$TLS_KEY_PATH" \
    --namespace "$NAMESPACE" \
    --debug > /dev/null; then
    log "Helm template verification passed."
else
    log "Error: Helm template verification failed."
    exit 1
fi

# 5. Execute Helm Command
log "Step 5: Executing Helm $ACTION..."
# shellcheck disable=SC2086
helm $ACTION "$NAMESPACE" "$HELM_CHART" \
    --set global.cn=$GlobalCN \
    --set global.runMode=$GlobalRunMode \
    --set global.domain=$GlobalDomain \
    --set global.hostStorage.rootPath=$GlobalHostStorageRootPath \
    --set global.hostStorage.staticPath=$GlobalHostStorageStaticPath \
    --set global.hostStorage.codePackagePath=$GlobalHostStorageCodePackagePath \
    --set global.hostStorage.mysqlPath=$GlobalHostStorageMysqlPath \
    --set global.hostStorage.redisPath=$GlobalHostStorageRedisPath \
    --set ingress.tls.enabled=$IngressTlsEnabled \
    --set-file ingress.tls.crt="$TLS_CERT_PATH" \
    --set-file ingress.tls.key="$TLS_KEY_PATH" \
    --namespace "$NAMESPACE" \
    --timeout 600s \
    --wait \
    --debug

# shellcheck disable=SC2181
if [ $? -eq 0 ]; then
    log "=================================================="
    log "Deployment Completed Successfully!"
    log "=================================================="
else
    log "=================================================="
    log "Deployment Failed!"
    log "=================================================="
    exit 1
fi
