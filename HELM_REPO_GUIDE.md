# 使用 GitHub 仓库作为 Helm Repo 源完整指南

本指南将详细说明如何使用 GitHub 仓库作为 Helm Chart 源，并将打包好的 Chart 推送到 GitHub Pages 进行发布。

## 前置条件

1. **GitHub 仓库**: 确保你有一个 GitHub 仓库（如：`Kymo-MCP/mcp-box-deploy`）
2. **Helm 工具**: 安装 Helm 3.x 版本
3. **Git 工具**: 安装 Git 并配置好认证
4. **权限**: 对目标 GitHub 仓库有推送权限

## 步骤一：GitHub 仓库设置

### 1.1 创建或准备 GitHub 仓库

```bash
# 如果还没有仓库，创建一个新的
# 访问 https://github.com/new
# 仓库名称：mcp-box-deploy
# 设置为 Public（GitHub Pages 需要）
```

### 1.2 启用 GitHub Pages

1. 进入仓库设置页面：`https://github.com/Kymo-MCP/mcp-box-deploy/settings`
2. 滚动到 **Pages** 部分
3. 配置 Source：
   - **Source**: Deploy from a branch
   - **Branch**: `gh-pages`
   - **Folder**: `/ (root)`
4. 保存设置

## 步骤二：准备 Helm Chart

### 2.1 验证 Chart 结构

确保你的 Helm Chart 目录结构正确：

```
mcp-box-deploy/helm/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── mcp-web.yaml
│   ├── mcp-market.yaml
│   ├── mcp-authz.yaml
│   ├── mcp-gateway.yaml
│   ├── mcp-init.yaml
│   └── mcp-redis.yaml
└── scripts/
    └── publish-to-github-pages.sh
```

### 2.2 检查 Chart.yaml

确保 `Chart.yaml` 包含正确的信息：

```yaml
apiVersion: v2
name: mcp-box
description: A Helm chart for MCP-Box application
type: application
version: 0.1.0
appVersion: "v1.0.0"
```

## 步骤三：使用发布脚本

### 3.1 脚本功能说明

<mcfile name="publish-to-github-pages.sh" path="/Users/nolan/go/src/qm-mcp/mcp-box-deploy/helm/scripts/publish-to-github-pages.sh"></mcfile> 脚本会自动完成以下操作：

1. **验证 Chart**: 运行 `helm lint` 和 `helm template` 检查
2. **更新版本**: 自动更新 Chart.yaml 中的版本号
3. **打包 Chart**: 生成 `.tgz` 格式的 Chart 包
4. **克隆仓库**: 克隆 GitHub 仓库到临时目录
5. **切换分支**: 创建或切换到 `gh-pages` 分支
6. **更新索引**: 生成或更新 `index.yaml` 文件
7. **推送更改**: 提交并推送到 GitHub

### 3.2 运行发布脚本

```bash
# 进入 Helm Chart 目录
cd /Users/nolan/go/src/qm-mcp/mcp-box-deploy/helm

# 给脚本执行权限
chmod +x scripts/publish-to-github-pages.sh

# 方式一：使用默认版本（从 backend/VERSION 文件读取）
./scripts/publish-to-github-pages.sh

# 方式二：指定版本号
./scripts/publish-to-github-pages.sh "1.0.1"

# 方式三：指定版本号和仓库地址
./scripts/publish-to-github-pages.sh "1.0.1" "https://github.com/YOUR_ORG/your-repo.git"
```

### 3.3 脚本执行过程

执行脚本时，你会看到以下输出：

```
🚀 开始发布 Helm Chart 到 GitHub Pages...
📋 验证 Helm Chart...
📝 更新 Chart 版本到 1.0.1...
📦 打包 Helm Chart...
📥 克隆 GitHub Pages 仓库...
🔄 更新 Helm 仓库索引...
💾 提交更改到 GitHub...
🧹 清理临时文件...
✅ Helm Chart 已成功发布到 GitHub Pages!
🌐 仓库地址: https://Kymo-MCP.github.io/mcp-box-deploy/
📦 Chart 版本: 1.0.1
```

## 步骤四：验证发布结果

### 4.1 检查 GitHub Pages 部署

1. 访问 GitHub Pages URL：`https://Kymo-MCP.github.io/mcp-box-deploy/`
2. 应该能看到自动生成的 README 页面
3. 访问索引文件：`https://Kymo-MCP.github.io/mcp-box-deploy/index.yaml`

### 4.2 检查 gh-pages 分支

1. 在 GitHub 仓库中切换到 `gh-pages` 分支
2. 应该能看到以下文件：
   - `index.yaml` - Helm 仓库索引
   - `mcp-box-*.tgz` - 打包的 Chart 文件
   - `README.md` - 使用说明

## 步骤五：使用 Helm 仓库

### 5.1 添加 Helm 仓库

```bash
# 添加仓库
helm repo add mcp-box https://Kymo-MCP.github.io/mcp-box-deploy/

# 更新仓库索引
helm repo update

# 搜索可用的 Chart
helm search repo mcp-box
```

### 5.2 安装 Chart

```bash
# 查看 Chart 信息
helm show chart mcp-box/mcp-box
helm show values mcp-box/mcp-box

# 安装 Chart
helm install my-mcp-box mcp-box/mcp-box

# 使用自定义配置安装
helm install my-mcp-box mcp-box/mcp-box -f custom-values.yaml

# 安装到指定命名空间
helm install my-mcp-box mcp-box/mcp-box -n mcp-system --create-namespace
```

## 步骤六：版本管理和更新

### 6.1 发布新版本

```bash
# 更新版本号并发布
./scripts/publish-to-github-pages.sh "1.0.2"
```

### 6.2 升级已安装的 Chart

```bash
# 更新仓库
helm repo update

# 升级安装
helm upgrade my-mcp-box mcp-box/mcp-box

# 查看升级历史
helm history my-mcp-box
```

## 故障排除

### 常见问题

1. **权限错误**: 确保有 GitHub 仓库的推送权限
2. **分支不存在**: 脚本会自动创建 `gh-pages` 分支
3. **GitHub Pages 未启用**: 检查仓库设置中的 Pages 配置
4. **版本文件不存在**: 确保 `backend/VERSION` 文件存在

### 调试命令

```bash
# 检查 Helm Chart 语法
helm lint .

# 测试模板渲染
helm template . --debug

# 验证打包
helm package . --debug

# 检查仓库连接
curl -I https://Kymo-MCP.github.io/mcp-box-deploy/index.yaml
```

## 自动化发布（可选）

可以使用 GitHub Actions 实现自动发布：

```yaml
# .github/workflows/publish-helm-chart.yml
name: Publish Helm Chart
on:
  push:
    tags:
      - 'v*'
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - name: Install Helm
      uses: azure/setup-helm@v3
    - name: Publish Chart
      run: |
        cd helm
        ./scripts/publish-to-github-pages.sh ${{ github.ref_name }}
```

这样，每次推送新的 tag 时，就会自动发布新版本的 Helm Chart。