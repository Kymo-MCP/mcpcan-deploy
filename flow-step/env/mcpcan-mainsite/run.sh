#!/bin/bash
# 敏感信息从流水线环境变量获取
# 对应变量组: tencent-image-registry
IMAGE_REGISTRY_USERNAME="${username}"
IMAGE_REPOSITORY_PASWORD="${password}"

# 对应变量组: 腾讯云OSS-bucket-itqm-1315102570
# 注意：流水线中使用 OSS 前缀变量存储了 COS 密钥
COS_SECRET_ID="${OSS_ACCESS_KEY_ID}"
COS_SECRET_KEY="${OSS_ACCESS_KEY_SECRET}"

# RUN PATH
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/../.."
HELM_CHART="$PROJECT_ROOT/helm"


helm upgrade mcpcan-mainsite "$HELM_CHART" \
  --set image.registry.username="$IMAGE_REGISTRY_USERNAME" \
  --set image.registry.password="$IMAGE_REPOSITORY_PASWORD" \
  --set backup.cos.secretId="$COS_SECRET_ID" \
  --set backup.cos.secretKey="$COS_SECRET_KEY" \
  --namespace mcpcan-mainsite --timeout 600s --wait