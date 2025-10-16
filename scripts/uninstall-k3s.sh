#!/usr/bin/env bash
set -euo pipefail

# ==============================================
# k3s 卸载脚本（Ubuntu 环境）
# 完全卸载 k3s 集群并清理相关资源
# 支持 master 和 worker 节点的卸载
# ==============================================

# 加载公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bash.sh"

# --- 解析命令行参数 ---
usage() {
  cat <<EOF
用法: ./uninstall-k3s.sh [选项]

该脚本用于完全卸载 k3s 集群：
- 自动检测节点类型（master/worker）
- 停止并卸载 k3s 服务
- 清理数据目录和配置文件
- 移除相关的网络配置

选项：
  --force                        强制卸载，跳过确认
  --keep-data                    保留数据目录
  --clean-all                    清理所有相关文件（包括镜像）
  -h, --help                     显示帮助

示例：
  标准卸载
    sudo ./uninstall-k3s.sh

  强制卸载（跳过确认）
    sudo ./uninstall-k3s.sh --force

  完全清理
    sudo ./uninstall-k3s.sh --clean-all
EOF
}

force=false
keep_data=false
clean_all=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) force=true; shift ;;
    --keep-data) keep_data=true; shift ;;
    --clean-all) clean_all=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "未知参数: $1"; usage; exit 2 ;;
  esac
done

# --- 前置检查 ---
check_ubuntu || exit 1

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
  error "此脚本需要 root 权限运行"
  exit 1
fi

# 检查 k3s 是否已安装
if ! check_k3s_installed; then
  warn "k3s 未安装或已被卸载"
  exit 0
fi

# 确认卸载（除非使用 --force）
if [ "$force" != true ]; then
  echo "${YELLOW}警告: 此操作将完全卸载 k3s 集群并删除所有相关数据！"
  echo "这将影响："
  echo "- 停止所有 k3s 服务"
  echo "- 删除所有容器和镜像"
  echo "- 清理网络配置"
  echo "- 删除数据目录（除非使用 --keep-data）"
  echo ""
  read -p "确定要继续吗？(y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    info "取消卸载操作"
    exit 0
  fi
fi

log "开始卸载 k3s..."

# 检测节点类型
node_type="unknown"
if systemctl is-active --quiet k3s 2>/dev/null; then
  node_type="master"
  info "检测到 k3s server 节点"
elif systemctl is-active --quiet k3s-agent 2>/dev/null; then
  node_type="worker"
  info "检测到 k3s agent 节点"
else
  # 检查服务文件是否存在
  if [ -f "/etc/systemd/system/k3s.service" ]; then
    node_type="master"
  elif [ -f "/etc/systemd/system/k3s-agent.service" ]; then
    node_type="worker"
  fi
fi

# 停止服务
log "停止 k3s 服务..."
if [ "$node_type" = "master" ]; then
  systemctl stop k3s 2>/dev/null || true
  systemctl disable k3s 2>/dev/null || true
elif [ "$node_type" = "worker" ]; then
  systemctl stop k3s-agent 2>/dev/null || true
  systemctl disable k3s-agent 2>/dev/null || true
else
  # 尝试停止所有可能的服务
  systemctl stop k3s 2>/dev/null || true
  systemctl stop k3s-agent 2>/dev/null || true
  systemctl disable k3s 2>/dev/null || true
  systemctl disable k3s-agent 2>/dev/null || true
fi

# 使用官方卸载脚本
log "执行官方卸载脚本..."
if [ "$node_type" = "master" ] || [ "$node_type" = "unknown" ]; then
  if command -v /usr/local/bin/k3s-uninstall.sh >/dev/null 2>&1; then
    /usr/local/bin/k3s-uninstall.sh || true
    info "k3s server 卸载脚本执行完成"
  fi
fi

if [ "$node_type" = "worker" ] || [ "$node_type" = "unknown" ]; then
  if command -v /usr/local/bin/k3s-agent-uninstall.sh >/dev/null 2>&1; then
    /usr/local/bin/k3s-agent-uninstall.sh || true
    info "k3s agent 卸载脚本执行完成"
  fi
fi

# 清理残留进程
log "清理残留进程..."
pkill -f k3s 2>/dev/null || true
pkill -f containerd 2>/dev/null || true

# 清理网络配置
log "清理网络配置..."
# 删除 CNI 网络接口
for iface in $(ip link show | grep -E 'cni0|flannel|veth' | awk -F: '{print $2}' | tr -d ' '); do
  ip link delete "$iface" 2>/dev/null || true
done

# 清理 iptables 规则
iptables -t nat -F 2>/dev/null || true
iptables -t mangle -F 2>/dev/null || true
iptables -F 2>/dev/null || true
iptables -X 2>/dev/null || true

# 清理数据目录（除非指定保留）
if [ "$keep_data" != true ]; then
  log "清理数据目录..."
  rm -rf /var/lib/rancher/k3s 2>/dev/null || true
  rm -rf /etc/rancher/k3s 2>/dev/null || true
  rm -rf /var/lib/kubelet 2>/dev/null || true
  rm -rf /var/lib/cni 2>/dev/null || true
  rm -rf /opt/cni 2>/dev/null || true
else
  info "保留数据目录（使用了 --keep-data 选项）"
fi

# 清理配置文件
log "清理配置文件..."
rm -f /usr/local/bin/k3s 2>/dev/null || true
rm -f /usr/local/bin/kubectl 2>/dev/null || true
rm -f /usr/local/bin/crictl 2>/dev/null || true
rm -f /usr/local/bin/ctr 2>/dev/null || true
rm -f /usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
rm -f /usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null || true

# 清理 systemd 服务文件
rm -f /etc/systemd/system/k3s.service 2>/dev/null || true
rm -f /etc/systemd/system/k3s-agent.service 2>/dev/null || true
systemctl daemon-reload

# 清理镜像仓库配置
rm -f /etc/rancher/k3s/registries.yaml 2>/dev/null || true

# 完全清理（如果指定）
if [ "$clean_all" = true ]; then
  log "执行完全清理..."
  
  # 清理容器运行时数据
  rm -rf /var/lib/containerd 2>/dev/null || true
  rm -rf /run/containerd 2>/dev/null || true
  rm -rf /run/k3s 2>/dev/null || true
  
  # 清理日志
  rm -rf /var/log/pods 2>/dev/null || true
  rm -rf /var/log/containers 2>/dev/null || true
  
  # 清理临时文件
  rm -rf /tmp/k3s-* 2>/dev/null || true
  
  info "完全清理已完成"
fi

# 清理环境变量
unset KUBECONFIG 2>/dev/null || true

# 验证卸载结果
log "验证卸载结果..."
if command -v k3s >/dev/null 2>&1; then
  warn "k3s 命令仍然存在，可能需要手动清理"
else
  info "k3s 命令已成功移除"
fi

if systemctl is-active --quiet k3s 2>/dev/null || systemctl is-active --quiet k3s-agent 2>/dev/null; then
  warn "k3s 服务仍在运行，可能需要手动停止"
else
  info "k3s 服务已成功停止"
fi

info "k3s 卸载完成！"
info "如果需要重新安装，请运行: ./install-k3s.sh"

# 提示重启（可选）
if [ "$clean_all" = true ]; then
  echo ""
  echo "${YELLOW}建议重启系统以确保所有网络配置完全清理"
  if [ "$force" != true ]; then
    read -p "是否现在重启？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      info "正在重启系统..."
      reboot
    fi
  fi
fi