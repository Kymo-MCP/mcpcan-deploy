#!/bin/bash

# chmod +x ./flow-step/git-push.sh
# ./flow-step/git-push.sh -r "remote-http-url"

# 任一命令返回非 0 时立即退出
set -euo pipefail

# 帮助信息
show_help() {
    echo "Usage: $0 -r <remote_url>"
    echo ""
    echo "This script automatically detects the current branch and pushes it"
    echo "to the specified remote URL with the same branch name."
    echo ""
    echo "By default it will:"
    echo "1) Force push"
    echo "2) Always filter out the 'flow-step' directory from the pushed content"
    echo ""
    echo "Options:"
    echo "  -r, --remote <url>     Target remote repository URL (required)"
    echo "  -b, --branch <branch>  Target remote branch (optional, overrides detection)"
    echo "  -h, --help             Show this help"
    exit 0
}

REMOTE_URL=""
TARGET_BRANCH=""
BOT_NAME="KEYMO-BOT"
BOT_EMAIL="opensource@kymo.cn"

ensure_git_identity() {
    local existing_name=""
    local existing_email=""

    existing_name="$(git config --global user.name 2>/dev/null || true)"
    existing_email="$(git config --global user.email 2>/dev/null || true)"

    if [ -z "$existing_name" ] || [ -z "$existing_email" ]; then
        git config --global user.name "$BOT_NAME" >/dev/null 2>&1 || return 1
        git config --global user.email "$BOT_EMAIL" >/dev/null 2>&1 || return 1
    fi

    return 0
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--remote)
            REMOTE_URL="$2"
            shift 2
            ;;
        -b|--branch)
            TARGET_BRANCH="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Error: Unknown argument $1"
            show_help
            ;;
    esac
done

# 参数校验
if [ -z "$REMOTE_URL" ]; then
    echo "Error: Remote URL is required (-r)"
    exit 1
fi

# 检查当前目录是否为 git 仓库
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: Current directory is not a git repository."
    exit 1
fi

# 自动识别当前分支
# 1) 如果指定了 -b 参数，直接使用
# 2) 优先使用 symbolic-ref（常规分支场景）
# 3) 兜底使用 branch --show-current（git >= 2.22）
# 4) 再兜底使用 rev-parse（git < 2.22）
DETECTED_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || git branch --show-current 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null)

if [ -n "$TARGET_BRANCH" ]; then
    CURRENT_BRANCH="$TARGET_BRANCH"
elif [ -n "$DETECTED_BRANCH" ] && [ "$DETECTED_BRANCH" != "HEAD" ]; then
    CURRENT_BRANCH="$DETECTED_BRANCH"
else
    echo "Error: Could not determine current branch (Detached HEAD state detected)."
    echo "In detached HEAD state, you MUST specify the target branch name using -b/--branch."
    echo "Example: $0 -r <remote_url> -b <target_branch>"
    exit 1
fi

if [[ "$REMOTE_URL" == *"gitee."* ]] && [ "$CURRENT_BRANCH" != "main" ]; then
    echo "Skip: gitee remote only pushes 'main'. Current branch is '$CURRENT_BRANCH'."
    exit 0
fi

echo "----------------------------------------"
echo "Configuration:"
echo "  Remote: (Hidden for security)"
echo "  Branch: $CURRENT_BRANCH (Auto-detected)"
echo "  Force:  true"
echo "  Filter: flow-step/ excluded = true"
echo "----------------------------------------"

# 生成临时 remote 名称（避免与现有 remote 冲突）
TEMP_REMOTE="temp_push_$(date +%s)_$$"
TMP_INDEX=""
PUSH_REF="$CURRENT_BRANCH"

# 退出清理：移除临时 remote、删除临时 index 文件
cleanup() {
    # 删除前先判断 remote 是否存在，避免退出时额外报错
    if git remote | grep -q "^$TEMP_REMOTE$"; then
        echo "Cleaning up remote '$TEMP_REMOTE'..."
        git remote remove "$TEMP_REMOTE"
    fi
    if [ -n "${TMP_INDEX:-}" ] && [ -f "$TMP_INDEX" ]; then
        rm -f "$TMP_INDEX" || true
    fi
}
trap cleanup EXIT

# 构造一个过滤后的提交（排除 flow-step/），不改动工作区
echo "Preparing filtered commit (excluding flow-step/)..."
if ! git cat-file -e "HEAD:flow-step" 2>/dev/null; then
    echo "No flow-step/ directory found in HEAD. Skipping filtering."
else
    TMP_INDEX="$(mktemp -t gitpushnew_index.XXXXXX)"
    ORIGINAL_GIT_INDEX_FILE="${GIT_INDEX_FILE-}"
    export GIT_INDEX_FILE="$TMP_INDEX"

    git read-tree HEAD
    git rm -r --cached --ignore-unmatch flow-step >/dev/null 2>&1 || true
    FILTERED_TREE="$(git write-tree)"
    COMMIT_MSG="chore: filtered push (exclude flow-step/)"
    if ensure_git_identity; then
        PUSH_REF="$(printf "%s\n" "$COMMIT_MSG" | git commit-tree "$FILTERED_TREE" -p HEAD)"
    else
        PUSH_REF="$(printf "%s\n" "$COMMIT_MSG" | GIT_AUTHOR_NAME="$BOT_NAME" GIT_AUTHOR_EMAIL="$BOT_EMAIL" GIT_COMMITTER_NAME="$BOT_NAME" GIT_COMMITTER_EMAIL="$BOT_EMAIL" git commit-tree "$FILTERED_TREE" -p HEAD)"
    fi

    if [ -n "$ORIGINAL_GIT_INDEX_FILE" ]; then
        export GIT_INDEX_FILE="$ORIGINAL_GIT_INDEX_FILE"
    else
        unset GIT_INDEX_FILE
    fi
fi

# 添加临时 remote
echo "Adding remote '$TEMP_REMOTE'..."
git remote add "$TEMP_REMOTE" "$REMOTE_URL"

# 拉取远端信息（用于提前发现鉴权/网络问题）
echo "Fetching from remote..."
git fetch "$TEMP_REMOTE" --prune >/dev/null 2>&1 || {
    echo "❌ Fetch failed!"
    echo "Possible reasons: network/auth/remote URL error."
    exit 1
}

# 推送命令（默认强制推送）
PUSH_CMD="git push -f"

echo "Pushing local '$CURRENT_BRANCH' to remote '$CURRENT_BRANCH'..."

# 执行推送
if $PUSH_CMD "$TEMP_REMOTE" "$PUSH_REF:refs/heads/$CURRENT_BRANCH"; then
    echo "✅ Push successful!"
else
    echo "❌ Push failed!"
    echo "----------------------------------------"
    echo "Possible reasons:"
    echo "1. Network connection issues."
    echo "2. Authentication failure (check your PAT in URL)."
    echo "3. Branch protection or insufficient permission."
    echo "4. Remote has changes that you don't have (Conflict) (only relevant when not force pushing)."
    echo ""
    echo "Resolution:"
    echo "  - This script always force-pushes. Check branch protection and permissions."
    echo "  - Verify the remote URL and your credentials (PAT)."
    echo "----------------------------------------"
    exit 1
fi
