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

# 敏感信息从流水线环境变量获取
# 对应变量组: tencent-image-registry
IMAGE_REGISTRY_USERNAME="${username}"
IMAGE_REPOSITORY_PASWORD="${password}"

# 对应变量组: 腾讯云OSS-bucket-itqm-1315102570
# 注意：流水线中使用 OSS 前缀变量存储了 COS 密钥
COS_SECRET_ID="${OSS_ACCESS_KEY_ID}"
COS_SECRET_KEY="${OSS_ACCESS_KEY_SECRET}"


helm upgrade mcpcan-mainsite "$HELM_CHART" \
  --set image.registry.username="$IMAGE_REGISTRY_USERNAME" \
  --set image.registry.password="$IMAGE_REPOSITORY_PASWORD" \
  --set backup.cos.secretId="$COS_SECRET_ID" \
  --set backup.cos.secretKey="$COS_SECRET_KEY" \
  --namespace mcpcan-mainsite --timeout 600s --wait
