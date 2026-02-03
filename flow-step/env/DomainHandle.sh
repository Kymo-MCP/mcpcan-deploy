#!/bin/bash

process_pem_with_spaces() {
    local content="$1"
    local tag_core="$2"
    # 构建标准标记（支持关键词含空格，如"RSA PRIVATE KEY"）
    local begin_pattern="-----BEGIN\s+${tag_core//\//\\/}\s+-----"
    local end_pattern="-----END\s+${tag_core//\//\\/}\s+-----"
    # 临时占位符（避免与内容冲突）
    local begin_placeholder="__BEGIN_${tag_core// /_}__"
    local end_placeholder="__END_${tag_core// /_}__"

    # 处理流程：
    # 1. 修复标记内的多余空格（将多个空格转为单个），并替换为占位符保护标记
    # 2. 将内容中所有剩余空格替换为换行（恢复多行结构）
    # 3. 恢复占位符为标准标记（确保标记完整）
    # 4. 去除空行（清理冗余）
    echo "$content" | sed -E \
        -e "s/${begin_pattern}/-----BEGIN ${tag_core}-----/g" \
        -e "s/${end_pattern}/-----END ${tag_core}-----/g" \
        -e "s/-----BEGIN ${tag_core}-----/${begin_placeholder}/g" \
        -e "s/-----END ${tag_core}-----/${end_placeholder}/g" \
        -e 's/ /\n/g' \
        -e "s/${begin_placeholder}/-----BEGIN ${tag_core}-----/g" \
        -e "s/${end_placeholder}/-----END ${tag_core}-----/g" \
        -e '/^$/d'
}

# 示例1：处理证书（标记为"CERTIFICATE"，无内部空格）
cert=$(process_pem_with_spaces "$cert" "CERTIFICATE")

# 示例2：处理RSA私钥（标记为"RSA PRIVATE KEY"，含内部空格）
key=$(process_pem_with_spaces "$key" "RSA PRIVATE KEY")


# helm install mcp-test ./helm \
#   --set global.cn=true \
#   --set global.domain="mcp-test.itqm.com" \
#   --set global.hostStorage.rootPath="/data/mcp-test" \
#   --set global.hostStorage.staticPath="/data/mcp-test/static" \
#   --set global.hostStorage.codePackagePath="/data/mcp-test/code-package" \
#   --set global.hostStorage.mysqlPath="/data/mcp-test/mysql" \
#   --set global.hostStorage.redisPath="/data/mcp-test/redis" \
#   --set infrastructure.mysql.service.nodePort=32306 \
#   --set infrastructure.redis.service.nodePort=32379 \
#   --set ingress.tls.enabled=true \
#   --set-file ingress.tls.crt=<(echo -e "$cert") \
#   --set-file ingress.tls.key=<(echo -e "$key") \
#   --namespace mcp-test --create-namespace --timeout 600s --wait

helm upgrade mcp-test ./helm \
  --set global.cn=true \
  --set global.domain="mcp-test.itqm.com" \
  --set global.hostStorage.rootPath="/data/mcp-test" \
  --set global.hostStorage.staticPath="/data/mcp-test/static" \
  --set global.hostStorage.codePackagePath="/data/mcp-test/code-package" \
  --set global.hostStorage.mysqlPath="/data/mcp-test/mysql" \
  --set global.hostStorage.redisPath="/data/mcp-test/redis" \
  --set infrastructure.mysql.service.nodePort=32306 \
  --set infrastructure.redis.service.nodePort=32379 \
  --set ingress.tls.enabled=true \
  --set-file ingress.tls.crt=<(echo -e "$cert") \
  --set-file ingress.tls.key=<(echo -e "$key") \
  --namespace mcp-test --timeout 600s --wait




