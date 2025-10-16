#!/bin/bash

# MCP-Box Helm Chart 发布到 GitHub Pages 脚本
# Usage: ./publish-to-github-pages.sh [chart-version] [github-repo-url]

set -e

# 配置参数
CHART_NAME="mcp-box"
CHART_VERSION=${1:-"1.0.0"}
GITHUB_REPO=${2:-"https://github.com/YOUR_USERNAME/mcp-box-helm-charts.git"}
TEMP_DIR="/tmp/helm-publish-$$"
CHART_DIR="$(dirname "$0")/.."

echo "🚀 开始发布 Helm Chart 到 GitHub Pages..."

# 验证 Helm Chart
echo "📋 验证 Helm Chart..."
cd "$CHART_DIR"
helm lint .
helm template . --debug > /dev/null

# 更新 Chart 版本
echo "📝 更新 Chart 版本到 $CHART_VERSION..."
sed -i.bak "s/^version:.*/version: $CHART_VERSION/" Chart.yaml
sed -i.bak "s/^appVersion:.*/appVersion: $CHART_VERSION/" Chart.yaml

# 打包 Chart
echo "📦 打包 Helm Chart..."
helm package . --destination /tmp/

# 克隆 GitHub Pages 仓库
echo "📥 克隆 GitHub Pages 仓库..."
rm -rf "$TEMP_DIR"
git clone "$GITHUB_REPO" "$TEMP_DIR"
cd "$TEMP_DIR"

# 创建或切换到 gh-pages 分支
if git show-ref --verify --quiet refs/remotes/origin/gh-pages; then
    git checkout gh-pages
else
    git checkout --orphan gh-pages
    git rm -rf .
fi

# 复制打包的 Chart
echo "📋 复制 Chart 包..."
cp "/tmp/${CHART_NAME}-${CHART_VERSION}.tgz" ./

# 生成或更新 index.yaml
echo "🔄 更新 Helm 仓库索引..."
if [ -f index.yaml ]; then
    helm repo index . --merge index.yaml --url "https://$(echo $GITHUB_REPO | sed 's|https://github.com/||' | sed 's|\.git||')/github.io/"
else
    helm repo index . --url "https://$(echo $GITHUB_REPO | sed 's|https://github.com/||' | sed 's|\.git||')/github.io/"
fi

# 创建 README.md
cat > README.md << EOF
# MCP-Box Helm Charts

这是 MCP-Box 项目的官方 Helm Charts 仓库。

## 使用方法

### 添加 Helm 仓库

\`\`\`bash
helm repo add mcp-box https://$(echo $GITHUB_REPO | sed 's|https://github.com/||' | sed 's|\.git||').github.io/
helm repo update
\`\`\`

### 安装 MCP-Box

\`\`\`bash
# 使用默认配置安装
helm install mcp-box mcp-box/mcp-box

# 使用自定义配置安装
helm install mcp-box mcp-box/mcp-box -f values-custom.yaml
\`\`\`

### 升级 MCP-Box

\`\`\`bash
helm upgrade mcp-box mcp-box/mcp-box
\`\`\`

## 可用版本

- 当前版本: $CHART_VERSION
- 更新时间: $(date)

## 支持

如有问题，请访问 [GitHub Issues](https://github.com/YOUR_USERNAME/qm-mcp/issues)
EOF

# 提交更改
echo "💾 提交更改到 GitHub..."
git add .
git config user.name "GitHub Actions"
git config user.email "actions@github.com"
git commit -m "发布 $CHART_NAME v$CHART_VERSION"
git push origin gh-pages

# 清理
echo "🧹 清理临时文件..."
rm -rf "$TEMP_DIR"
rm "/tmp/${CHART_NAME}-${CHART_VERSION}.tgz"

echo "✅ Helm Chart 已成功发布到 GitHub Pages!"
echo "🌐 仓库地址: https://$(echo $GITHUB_REPO | sed 's|https://github.com/||' | sed 's|\.git||').github.io/"
echo "📦 Chart 版本: $CHART_VERSION"