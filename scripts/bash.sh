#!/usr/bin/env bash

# ==============================================
# 公共 Bash 脚本库
# 包含环境变量加载、颜色定义、日志函数等公共逻辑
# ==============================================

# --- k3s 安装默认参数 ---
# K3S 安装默认参数
K3S_VERSION=${K3S_VERSION:-"v1.32.1+k3s1"}
K3S_MIRROR=${K3S_MIRROR:-"cn"}
K3S_INSTALL_URL=${K3S_INSTALL_URL:-"https://rancher-mirror.rancher.cn/k3s/k3s-install.sh"}
K3S_DATA_DIR=${K3S_DATA_DIR:-"/var/lib/rancher/k3s"}
K3S_KUBECONFIG_MODE=${K3S_KUBECONFIG_MODE:-"644"}
K3S_DISABLE_COMPONENTS=${K3S_DISABLE_COMPONENTS:-"traefik,rancher"}

# --- 颜色定义 ---
GREEN="✅ "
YELLOW="💡️ "
RED="❌"
GRAY="️🕒 "
NOTICE="⚠️ "

# --- 实用函数 ---
# 获取脚本所在目录的绝对路径
script_dir() { cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P; }

# 日志函数
log() { echo "[$(basename "$0")] $*"; }
err() { echo "[$(basename "$0")][ERROR] $*" >&2; }
info() { echo "${GREEN}$*"; }
warn() { echo "${YELLOW}$*"; }
error() { echo "${RED}$*" >&2; }

# 生成随机 token（当未提供时）
random_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  else
    head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

# 检查命令是否存在
check_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "未找到命令: $cmd"
    return 1
  fi
  return 0
}

# 检查是否为 root 用户
check_root() {
  if [[ $EUID -eq 0 ]]; then
    return 0
  else
    return 1
  fi
}

# 检查是否为 Ubuntu 系统
check_ubuntu() {
  if [[ "${OSTYPE:-linux}" != linux* ]]; then
    error "该脚本面向 Linux/Ubuntu 环境编写。当前系统: ${OSTYPE:-unknown}"
    return 1
  fi
  
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
      warn "检测到非 Ubuntu 系统: $ID，可能存在兼容性问题"
    fi
  fi
  
  return 0
}

# 安装依赖包（Ubuntu）
install_dependencies() {
  local packages=("$@")
  
  if [ ${#packages[@]} -eq 0 ]; then
    return 0
  fi
  
  log "检查并安装依赖包: ${packages[*]}"
  
  local missing_packages=()
  for pkg in "${packages[@]}"; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
      missing_packages+=("$pkg")
    fi
  done
  
  if [ ${#missing_packages[@]} -gt 0 ]; then
    log "安装缺失的依赖包: ${missing_packages[*]}"
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -y
      sudo apt-get install -y "${missing_packages[@]}"
    else
      error "未找到 apt-get，请手动安装依赖包: ${missing_packages[*]}"
      return 1
    fi
  else
    info "所有依赖包已安装"
  fi
}

# 配置 k3s 国内镜像仓库
setup_k3s_registry() {
  log "配置 k3s 国内镜像仓库"
  sudo mkdir -p /etc/rancher/k3s
  sudo tee /etc/rancher/k3s/registries.yaml > /dev/null <<EOF
mirrors:
  docker.io:
    endpoint:
      - "https://registry.cn-hangzhou.aliyuncs.com"
      - "https://docker.mirrors.ustc.edu.cn"
      - "https://hub.docker.com"
  k8s.gcr.io:
    endpoint:
      - "https://registry.cn-hangzhou.aliyuncs.com"
      - "https://docker.mirrors.ustc.edu.cn"
      - "https://hub.docker.com"
  gcr.io:
    endpoint:
      - "https://gcr.mirrors.ustc.edu.cn"
  k8s.gcr.io:
    endpoint:
      - "https://k8s-gcr.mirrors.ustc.edu.cn"
  quay.io:
    endpoint:
      - "https://quay.mirrors.ustc.edu.cn"
  "ccr.ccs.tencentyun.com":
    endpoint:
      - "https://ccr.ccs.tencentyun.com"
  aliyun.com:
    endpoint:
      - "https://registry.cn-hangzhou.aliyuncs.com"
      - "https://registry.cn-guangzhou.aliyuncs.com"
EOF
  
  info "k3s 镜像仓库配置完成"
}

# 检查 k3s 是否已安装
check_k3s_installed() {
  if command -v k3s >/dev/null 2>&1; then
    info "k3s 已安装，版本: $(k3s --version | head -n1)"
    return 0
  else
    return 1
  fi
}

# 获取节点 IP 地址
get_node_ip() {

  if [ -n "${NODE_IP:-}" ]; then
    echo "$NODE_IP"
    return 0
  fi
  
  # 自动获取主网卡 IP
  local ip
  ip=$(hostname -I | awk '{print $1}')
  
  if [ -n "$ip" ]; then
    echo "$ip"
  else
    error "无法获取节点 IP 地址"
    return 1
  fi
}

# 获取当前服务器的所有 IP 地址（包括公网 IP）
get_server_ips() {
  local ips=()
  
  # 获取本地网卡 IP（兼容 Linux 和 macOS）
  local local_ips
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS 使用 ifconfig
    local_ips=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}')
  else
    # Linux 使用 hostname -I
    local_ips=$(hostname -I | tr ' ' '\n' | grep -v '^$')
  fi
  
  while IFS= read -r ip; do
    [ -n "$ip" ] && ips+=("$ip")
  done <<< "$local_ips"
  
  # 尝试获取公网 IP
  local public_ip
  if command -v curl >/dev/null 2>&1; then
    # 尝试多个服务获取公网 IP
    for service in "http://ipinfo.io/ip" "http://icanhazip.com" "http://ifconfig.me/ip" "http://checkip.amazonaws.com" "http://ip.42.pl/raw"; do
      public_ip=$(curl -s --connect-timeout 5 --max-time 10 "$service" 2>/dev/null | tr -d '\n\r\t ')
      if [[ "$public_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # 检查是否已存在于本地 IP 列表中
        local found=false
        for local_ip in "${ips[@]}"; do
          if [ "$local_ip" = "$public_ip" ]; then
            found=true
            break
          fi
        done
        if [ "$found" = false ]; then
          ips+=("$public_ip")
          # 只在调试模式下输出详细信息
          [ "${DEBUG:-}" = "1" ] && info "检测到公网 IP: $public_ip"
        fi
        break
      fi
    done
  fi
  
  # 如果没有获取到公网 IP，记录日志
  if [ -z "$public_ip" ] || ! [[ "$public_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    [ "${DEBUG:-}" = "1" ] && warn "无法获取公网 IP，将使用内网 IP"
  fi
  
  printf '%s\n' "${ips[@]}"
}

# 自动获取节点 IP 列表（优先使用公网 IP，没有则使用内网 IP）
auto_detect_node_ips() {
  local server_ips_str
  server_ips_str=$(get_server_ips)
  
  local primary_ip=""
  local public_ip=""
  local private_ip=""
  
  # 分析获取到的 IP 地址
  while IFS= read -r ip; do
    [ -z "$ip" ] && continue
    
    # 判断是否为公网 IP（排除私有网段）
    if [[ "$ip" =~ ^10\. ]] || [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || [[ "$ip" =~ ^192\.168\. ]]; then
      # 私有 IP
      if [ -z "$private_ip" ]; then
        private_ip="$ip"
      fi
    else
      # 公网 IP
      if [ -z "$public_ip" ]; then
        public_ip="$ip"
      fi
    fi
  done <<< "$server_ips_str"
  
  # 优先使用公网 IP，没有则使用私有 IP
  if [ -n "$public_ip" ]; then
    primary_ip="$public_ip"
    # 只在调试模式下输出详细信息
    [ "${DEBUG:-}" = "1" ] && info "使用公网 IP 作为节点 IP: $primary_ip"
  elif [ -n "$private_ip" ]; then
    primary_ip="$private_ip"
    # 只在调试模式下输出详细信息
    [ "${DEBUG:-}" = "1" ] && info "使用内网 IP 作为节点 IP: $primary_ip"
  else
    error "无法获取有效的 IP 地址"
    return 1
  fi
  
  # 设置 K3S_API_URL 为主 IP
  export K3S_API_URL="$primary_ip"
  
  # 返回主 IP（用作单节点安装）
  echo "$primary_ip"
}

# 检查当前服务器 IP 是否在节点列表中，并返回节点类型和位置
check_node_in_list() {
  # 如果没有配置节点列表，自动检测并设置为单节点
  if [ -z "${K3S_INSTALL_NODE_IP_LIST:-}" ]; then
    local auto_ip
    auto_ip=$(auto_detect_node_ips)
    if [ $? -eq 0 ] && [ -n "$auto_ip" ]; then
      export K3S_INSTALL_NODE_IP_LIST="$auto_ip"
      info "自动检测节点 IP 列表: $K3S_INSTALL_NODE_IP_LIST"
      # 直接返回 master 节点信息，不再输出额外的 info 信息
      echo "master:$auto_ip:0"
      return 0
    else
      error "自动检测节点 IP 失败"
      return 1
    fi
  fi
  
  local node_list="${K3S_INSTALL_NODE_IP_LIST}"
  
  if [ -z "$node_list" ]; then
    error "K3S_INSTALL_NODE_IP_LIST 未配置"
    return 1
  fi
  
  # 将节点列表转换为数组（兼容 bash 和 zsh）
  local configured_nodes
  if [ -n "$ZSH_VERSION" ]; then
    # zsh 环境，使用 word splitting
    setopt sh_word_split 2>/dev/null || true
    configured_nodes=($node_list)
  else
    # bash 环境
    IFS=' ' read -ra configured_nodes <<< "$node_list"
  fi
  
  if [ ${#configured_nodes[@]} -eq 0 ]; then
    error "节点 IP 列表为空"
    return 1
  fi
  
  # 获取当前服务器的所有 IP
  local server_ips_str
  server_ips_str=$(get_server_ips)
  
  # 检查匹配
  local i=0
  for config_ip in "${configured_nodes[@]}"; do
    while IFS= read -r server_ip; do
      [ -z "$server_ip" ] && continue
      if [ "$server_ip" = "$config_ip" ]; then
        if [ $i -eq 0 ]; then
          echo "master:$config_ip:$i"
        else
          echo "worker:$config_ip:$i"
        fi
        return 0
      fi
    done <<< "$server_ips_str"
    i=$((i + 1))
  done
  
  # 未找到匹配
  error "当前服务器不在配置的节点 IP 列表中"
  error "服务器 IP: $(echo "$server_ips_str" | tr '\n' ' ')"
  error "节点列表: ${configured_nodes[*]}"
  return 1
}

# 等待服务启动
wait_for_service() {
  local service_name="$1"
  local max_wait="${2:-60}"
  local wait_time=0
  
  log "等待服务启动: $service_name"
  
  while [ $wait_time -lt $max_wait ]; do
    if systemctl is-active --quiet "$service_name"; then
      info "服务 $service_name 已启动"
      return 0
    fi
    
    sleep 2
    wait_time=$((wait_time + 2))
    echo -n "."
  done
  
  echo
  error "服务 $service_name 启动超时"
  return 1
}

# 显示脚本使用帮助
show_usage() {
  cat <<EOF
用法: $0 [选项]

该脚本提供 k3s 安装的公共函数库。

环境变量:
  K3S_VERSION              k3s 版本 (默认: v1.32.1+k3s1)
  K3S_MIRROR              镜像源 (默认: cn)
  K3S_INSTALL_URL         安装脚本 URL
  K3S_DATA_DIR            数据目录 (默认: /var/lib/rancher/k3s)
  K3S_KUBECONFIG_MODE     kubeconfig 权限 (默认: 644)
  K3S_DISABLE_COMPONENTS  禁用组件 (默认: traefik,rancher)
示例:
  source bash.sh          # 加载公共函数库
EOF
}

# 处理命令行参数（当脚本直接执行时）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    -h|--help)
      show_usage
      exit 0
      ;;
    *)
      echo "这是一个公共函数库，请使用 source 命令加载："
      echo "  source bash.sh"
      echo ""
      echo "或查看帮助："
      echo "  bash bash.sh --help"
      exit 1
      ;;
  esac
fi