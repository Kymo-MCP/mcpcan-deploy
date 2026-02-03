#!/bin/bash

export NAMESPACE=bots-dev
export GlobalRunMode=kymo
export GlobalCN=true
export GlobalDomain=ai-dev.itqm.cn
export GlobalEnabledPreLoadImages=false
export GlobalHostStorageRootPath=/data/bots-dev
export GlobalHostStorageStaticPath=/data/bots-dev/static
export GlobalHostStorageCodePackagePath=/data/bots-dev/code-package
export GlobalHostStorageMysqlPath=/data/bots-dev/mysql
export GlobalHostStorageRedisPath=/data/bots-dev/redis
export GlobalWebPathRule=/mcpcan-web
export GlobalApiPathRule=/mcpcan-api
export IngressTlsCreateSecret=false
export IngressTlsEnabled=true
export IngressTlsSecretName=ai-dev-itqm-cn
export InfrastructureMysqlEnabled=false
export InfrastructureMysqlDBUsername=intelligent
export InfrastructureMysqlDBPassword="UHNwAa57&"
export InfrastructureMysqlDBDatabase=intelligent
export InfrastructureMysqlDBHost=mysql-svc.dev
export InfrastructureMysqlDBPort=3306
export InfrastructureRedisEnabled=false
export InfrastructureRedisHost=redis-svc
export InfrastructureRedisPort=6379
export InfrastructureRedisPassword=1W3yTRb80aBMY5kY
export InfrastructureRedisDB=2
# 注意：对于 bots-dev 环境，'mcp-entry-ingress' 必须在腾讯云上手动创建。
# 我们设置 IngressEnabled=false 以防止 Helm 管理它。
# 重要提示：如果此 Ingress 之前由 Helm 管理，在运行此脚本之前，
# 您必须将以下注解添加到现有的 Ingress 资源中，以防止 Helm 将其删除：
# metadata:
#   annotations:
#     helm.sh/resource-policy: keep
export IngressEnabled=false
export NodeSelector='{"kubernetes.io/hostname": "10.10.0.29"}'






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
    --set global.domain=$GlobalDomain \
    --set global.runMode=$GlobalRunMode \
    --set global.enabledPreLoadImages=$GlobalEnabledPreLoadImages \
    --set global.hostStorage.rootPath=$GlobalHostStorageRootPath \
    --set global.hostStorage.staticPath=$GlobalHostStorageStaticPath \
    --set global.hostStorage.codePackagePath=$GlobalHostStorageCodePackagePath \
    --set global.hostStorage.mysqlPath=$GlobalHostStorageMysqlPath \
    --set global.hostStorage.redisPath=$GlobalHostStorageRedisPath \
    --set global.webPathRule=$GlobalWebPathRule \
    --set global.apiPathRule=$GlobalApiPathRule \
    --set ingress.tls.createSecret=$IngressTlsCreateSecret \
    --set ingress.tls.enabled=$IngressTlsEnabled \
    --set ingress.tls.secretName=$IngressTlsSecretName \
    --set infrastructure.mysql.enabled=$InfrastructureMysqlEnabled \
    --set infrastructure.mysql.auth.username=$InfrastructureMysqlDBUsername \
    --set infrastructure.mysql.auth.password="$InfrastructureMysqlDBPassword" \
    --set infrastructure.mysql.auth.database=$InfrastructureMysqlDBDatabase \
    --set infrastructure.mysql.service.name=$InfrastructureMysqlDBHost \
    --set infrastructure.mysql.service.port=$InfrastructureMysqlDBPort \
    --set infrastructure.redis.enabled=$InfrastructureRedisEnabled \
    --set infrastructure.redis.service.name=$InfrastructureRedisHost \
    --set infrastructure.redis.service.port=$InfrastructureRedisPort \
    --set infrastructure.redis.auth.password="$InfrastructureRedisPassword" \
    --set infrastructure.redis.auth.db=$InfrastructureRedisDB \
    --set ingress.enabled=$IngressEnabled \
    --set-json nodeSelector="$NodeSelector" \
    --namespace "$NAMESPACE" > /dev/null; then
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
    --set global.domain=$GlobalDomain \
    --set global.enabledPreLoadImages=$GlobalEnabledPreLoadImages \
    --set global.runMode=$GlobalRunMode \
    --set global.hostStorage.rootPath=$GlobalHostStorageRootPath \
    --set global.hostStorage.staticPath=$GlobalHostStorageStaticPath \
    --set global.hostStorage.codePackagePath=$GlobalHostStorageCodePackagePath \
    --set global.hostStorage.mysqlPath=$GlobalHostStorageMysqlPath \
    --set global.hostStorage.redisPath=$GlobalHostStorageRedisPath \
    --set global.webPathRule=$GlobalWebPathRule \
    --set global.apiPathRule=$GlobalApiPathRule \
    --set ingress.tls.createSecret=$IngressTlsCreateSecret \
    --set ingress.tls.enabled=$IngressTlsEnabled \
    --set ingress.tls.secretName=$IngressTlsSecretName \
    --set infrastructure.mysql.enabled=$InfrastructureMysqlEnabled \
    --set infrastructure.mysql.auth.username=$InfrastructureMysqlDBUsername \
    --set infrastructure.mysql.auth.password="$InfrastructureMysqlDBPassword" \
    --set infrastructure.mysql.auth.database=$InfrastructureMysqlDBDatabase \
    --set infrastructure.mysql.service.name=$InfrastructureMysqlDBHost \
    --set infrastructure.mysql.service.port=$InfrastructureMysqlDBPort \
    --set infrastructure.redis.enabled=$InfrastructureRedisEnabled \
    --set infrastructure.redis.auth.enabled=$InfrastructureRedisEnabled \
    --set infrastructure.redis.service.name=$InfrastructureRedisHost \
    --set infrastructure.redis.service.port=$InfrastructureRedisPort \
    --set infrastructure.redis.auth.password="$InfrastructureRedisPassword" \
    --set infrastructure.redis.auth.db=$InfrastructureRedisDB \
    --set ingress.enabled=$IngressEnabled \
    --set-json nodeSelector="$NodeSelector" \
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
