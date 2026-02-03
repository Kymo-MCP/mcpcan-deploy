#!/bin/bash

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
log "Chart Path: ./helm"
log "=================================================="

# 3. Check if Chart Path exists
log "Step 3: Checking Chart Path..."
if [ ! -d "./helm" ]; then
    log "Error: Helm chart directory not found at ./helm"
    exit 1
fi

# 4. Helm Template Check
log "Step 4: Verifying Helm Template..."
if helm template "$NAMESPACE" ./helm \
    --set global.cn=$GlobalCN \
    --set global.runMode=$GlobalRunMode \
    --set global.domain=$GlobalDomain \
    --set global.hostStorage.rootPath=$GlobalHostStorageRootPath \
    --set global.hostStorage.staticPath=$GlobalHostStorageStaticPath \
    --set global.hostStorage.codePackagePath=$GlobalHostStorageCodePackagePath \
    --set global.hostStorage.mysqlPath=$GlobalHostStorageMysqlPath \
    --set global.hostStorage.redisPath=$GlobalHostStorageRedisPath \
    --set ingress.tls.enabled=$IngressTlsEnabled \
    --set-file ingress.tls.crt=./tls.cert \
    --set-file ingress.tls.key=./tls.key \
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
helm $ACTION "$NAMESPACE" ./helm \
    --set global.cn=$GlobalCN \
    --set global.runMode=$GlobalRunMode \
    --set global.domain=$GlobalDomain \
    --set global.hostStorage.rootPath=$GlobalHostStorageRootPath \
    --set global.hostStorage.staticPath=$GlobalHostStorageStaticPath \
    --set global.hostStorage.codePackagePath=$GlobalHostStorageCodePackagePath \
    --set global.hostStorage.mysqlPath=$GlobalHostStorageMysqlPath \
    --set global.hostStorage.redisPath=$GlobalHostStorageRedisPath \
    --set ingress.tls.enabled=$IngressTlsEnabled \
    --set-file ingress.tls.crt=./tls.cert \
    --set-file ingress.tls.key=./tls.key \
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
