#!/usr/bin/env bash

# ==============================================
# 公共 Bash 脚本库
# 包含环境变量加载、颜色定义、日志函数等公共逻辑
# ==============================================

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

# 从 .env 文件加载环境变量（忽略注释和空行）
load_env_file() {
  local env_file="${1:-$script_dir/../env/def.env}"
  [ -f "$env_file" ] || return 0
  
  log "加载环境变量文件: $env_file"
  
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
      *)
        if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
          export "$line"
        fi
      ;;
    esac
  done < "$env_file"
}

# 自动加载项目根目录下的 dev.env 文件
load_project_env() {
  local env_file="$(script_dir)/../env/def.env"
  
  if [ -f "$env_file" ]; then
    load_env_file "$env_file"
  else
    warn "未找到环境变量文件: $env_file"
  fi
}

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
    for service in "http://ipinfo.io/ip" "http://icanhazip.com" "http://ifconfig.me/ip"; do
      public_ip=$(curl -s --connect-timeout 5 "$service" 2>/dev/null | tr -d '\n\r')
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
        fi
        break
      fi
    done
  fi
  
  printf '%s\n' "${ips[@]}"
}

# 检查当前服务器 IP 是否在节点列表中，并返回节点类型和位置
check_node_in_list() {
    # 检查变量是否已定义
    if [ -z "${K3S_INSTALL_NODE_IP_LIST:-}" ]; then
        error "K3S_INSTALL_NODE_IP_LIST 环境变量未定义"
        error "请确保已正确加载环境变量文件"
        return 1
    fi
    
    local node_list="${K3S_INSTALL_NODE_IP_LIST}"
  
  if [ -z "$node_list" ]; then
    error "K3S_INSTALL_NODE_IP_LIST 未配置"
    return 1
  fi
  
  # 将节点列表转换为数组
  local -a configured_nodes
  read -ra configured_nodes <<< "$node_list"
  
  if [ ${#configured_nodes[@]} -eq 0 ]; then
    error "节点 IP 列表为空"
    return 1
  fi
  
  # 获取当前服务器的所有 IP
  local server_ips_str
  server_ips_str=$(get_server_ips)
  
  # 检查匹配
  for i in "${!configured_nodes[@]}"; do
    local config_ip="${configured_nodes[$i]}"
    while IFS= read -r server_ip; do
      [ -z "$server_ip" ] && continue
      if [ "$server_ip" = "$config_ip" ]; then
        echo "$([ $i -eq 0 ] && echo "master" || echo "worker"):$config_ip:$i"
        return 0
      fi
    done <<< "$server_ips_str"
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

# 显示使用帮助
show_usage() {
  local script_name="$(basename "$0")"
  cat <<EOF
用法: ./$script_name [选项]

该脚本使用项目环境变量文件 ../env/dev.env 中的配置。

环境变量说明:
  K3S_VERSION              k3s 版本 (默认: v1.32.1+k3s1)
  K3S_MIRROR              镜像源 (默认: cn)
  K3S_INSTALL_URL         安装脚本 URL
  K3S_DATA_DIR            数据目录 (默认: /var/lib/rancher/k3s)
  K3S_KUBECONFIG_MODE     kubeconfig 权限 (默认: 644)
  K3S_DISABLE_COMPONENTS  禁用组件 (默认: traefik)
  INSTALL_DOMAIN          安装域名 (默认: mcp.qm.com)
  DB_PASSWORD             数据库密码

选项:
  -h, --help              显示此帮助信息

EOF
}

# 自动加载项目环境变量（当脚本被 source 时执行）
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  # 脚本被 source，自动加载环境变量
  load_project_env
fi