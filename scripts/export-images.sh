#!/bin/bash

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE_DIR="$PROJECT_DIR/template/k3s"

# 创建临时目录
TEMP_DIR="/tmp/k3s-images"
mkdir -p "$TEMP_DIR"

# 镜像列表文件
IMAGES_LIST="$TEMP_DIR/images.txt"

# 提取所有镜像
echo "提取模板中的镜像..."

# 从casdoor-backend.yaml提取镜像
grep "image:" "$TEMPLATE_DIR/casdoor-backend.yaml" | awk '{print $2}' >> "$IMAGES_LIST"

# 从casdoor-frontend.yaml提取镜像
grep "image:" "$TEMPLATE_DIR/casdoor-frontend.yaml" | awk '{print $2}' >> "$IMAGES_LIST"

# 从postgresql.yaml提取镜像
grep "image:" "$TEMPLATE_DIR/postgresql.yaml" | awk '{print $2}' >> "$IMAGES_LIST"

# 从helm-chart-store.yaml提取镜像
grep "image:" "$TEMPLATE_DIR/helm-chart-store.yaml" | awk '{print $2}' >> "$IMAGES_LIST"

# 去重
sort -u "$IMAGES_LIST" -o "$IMAGES_LIST"

echo "找到以下镜像:"
cat "$IMAGES_LIST"

# 拉取镜像并保存为tar包
echo "开始拉取镜像并导出为tar包..."

IMAGES_TAR="$PROJECT_DIR/images.tar"
> "$IMAGES_TAR"  # 清空已存在的tar文件

while IFS= read -r image; do
    if [ -n "$image" ]; then
        echo "处理镜像: $image"
        # 拉取镜像
        docker pull "$image"
        # 保存镜像到tar文件
        docker save "$image" | tar -xf - -C "$TEMP_DIR"
    fi
done < "$IMAGES_LIST"

# 将所有镜像打包成一个tar文件
echo "创建最终的镜像tar包: $IMAGES_TAR"
cd "$TEMP_DIR"
tar -cf "$IMAGES_TAR" .

# 清理临时目录
rm -rf "$TEMP_DIR"

echo "镜像导出完成: $IMAGES_TAR"