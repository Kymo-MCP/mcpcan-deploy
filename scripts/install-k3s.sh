#!/usr/bin/env bash
set -euo pipefail

# ==============================================
# k3s 安装脚本（Ubuntu 环境，基于节点 IP 列表自动判断）
# 自动判断节点类型：第一个 IP 为 master，其余为 worker
# 配置优先级：命令行参数 > 环境变量 > 默认值
# 依赖：curl、sudo（如非 root）
# ==============================================

# 加载公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bash.sh"

# --- 默认值（从环境变量读取，如未设置则使用默认值）---
k3s_version="${K3S_VERSION:-}"                           # 留空使用官方最新稳定版
k3s_token="${K3S_TOKEN:-}"                               # 为空时脚本将自动生成
k3s_data_dir="${K3S_DATA_DIR:-/var/lib/rancher/k3s}"     # k3s 数据目录
k3s_kubeconfig_mode="${K3S_KUBECONFIG_MODE:-644}"        # kubeconfig 权限
# 修改默认禁用组件，添加 rancher
k3s_disable_components="${K3S_DISABLE_COMPONENTS:-traefik,rancher}"  # 禁用组件
k3s_mirror="${K3S_MIRROR:-cn}"                           # 镜像源
k3s_install_url="${K3S_INSTALL_URL:-https://rancher-mirror.rancher.cn/k3s/k3s-install.sh}"  # 安装脚本 URL
tls_sans="${TLS_SANS:-}"                                 # 可选，逗号分隔: my.domain.com,10.0.0.10
extra_args="${K3S_EXTRA_ARGS:-}"                         # 透传给 k3s 的额外参数

# 添加获取所有节点IP的函数
get_all_node_ips() {
  local ips=()
  if [ -n "${K3S_INSTALL_NODE_IP_LIST:-}" ]; then
    read -ra nodes <<< "${K3S_INSTALL_NODE_IP_LIST}"
    for node in "${nodes[@]}"; do
      ips+=("$node")
    done
  fi
  printf '%s\n' "${ips[@]}"
}

# 检查 Kubernetes 环境是否已安装（k3s 或其他 k8s 发行版）
check_kubernetes_installed() {
  local k8s_found=false
  local k8s_type=""
  
  # 检查 k3s
  if command -v k3s >/dev/null 2>&1; then
    k8s_found=true
    k8s_type="k3s"
    info "检测到 k3s，版本: $(k3s --version | head -n1)"
  fi
  
  # 检查 kubectl
  if command -v kubectl >/dev/null 2>&1; then
    k8s_found=true
    if [ -z "$k8s_type" ]; then
      k8s_type="kubernetes"
    fi
    info "检测到 kubectl，版本: $(kubectl version --client --short 2>/dev/null || echo "无法获取版本")"
  fi
  
  # 检查 systemd 服务
  if systemctl is-active --quiet k3s 2>/dev/null; then
    k8s_found=true
    k8s_type="k3s"
    info "检测到 k3s 服务正在运行"
  elif systemctl is-active --quiet k3s-agent 2>/dev/null; then
    k8s_found=true
    k8s_type="k3s"
    info "检测到 k3s-agent 服务正在运行"
  elif systemctl is-active --quiet kubelet 2>/dev/null; then
    k8s_found=true
    if [ -z "$k8s_type" ]; then
      k8s_type="kubernetes"
    fi
    info "检测到 kubelet 服务正在运行"
  fi
  
  if [ "$k8s_found" = true ]; then
    echo "$k8s_type"
    return 0
  else
    return 1
  fi
}

# 卸载现有 Kubernetes 环境
uninstall_kubernetes() {
  local k8s_type="$1"
  
  log "卸载现有 $k8s_type 环境..."
  
  if [ "$k8s_type" = "k3s" ]; then
    # 卸载 k3s server
    if command -v /usr/local/bin/k3s-uninstall.sh >/dev/null 2>&1; then
      sudo /usr/local/bin/k3s-uninstall.sh || true
      info "k3s server 卸载完成"
    fi
    
    # 卸载 k3s agent
    if command -v /usr/local/bin/k3s-agent-uninstall.sh >/dev/null 2>&1; then
      sudo /usr/local/bin/k3s-agent-uninstall.sh || true
      info "k3s agent 卸载完成"
    fi
  else
    warn "检测到其他 Kubernetes 环境，请手动卸载后重新运行脚本"
    error "或使用 --force 参数强制继续安装"
    return 1
  fi
}

# 检查 helm 是否已安装
check_helm_installed() {
  if command -v helm >/dev/null 2>&1; then
    info "helm 已安装，版本: $(helm version --short 2>/dev/null || echo "无法获取版本")"
    return 0
  else
    return 1
  fi
}

# 安装 helm
install_helm() {
  log "开始安装 helm..."
  
  # 下载并安装 helm
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  else
    error "需要 curl 命令来安装 helm"
    return 1
  fi
  
  # 验证安装
  if check_helm_installed; then
    info "helm 安装成功"
  else
    error "helm 安装失败"
    return 1
  fi
}

# 检查 ingress-nginx 是否已安装
check_ingress_nginx_installed() {
  if ! command -v kubectl >/dev/null 2>&1; then
    return 1
  fi
  
  # 检查 ingress-nginx namespace 是否存在
  if kubectl get namespace ingress-nginx >/dev/null 2>&1; then
    # 检查 ingress-nginx controller 是否运行
    if kubectl get deployment -n ingress-nginx ingress-nginx-controller >/dev/null 2>&1; then
      local ready_replicas
      ready_replicas=$(kubectl get deployment -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
      if [ "$ready_replicas" -gt 0 ]; then
        info "ingress-nginx controller 已安装并运行"
        return 0
      fi
    fi
  fi
  
  return 1
}

# 安装 ingress-nginx controller
install_ingress_nginx() {
  log "开始安装 ingress-nginx controller..."
  
  if ! command -v kubectl >/dev/null 2>&1; then
    error "需要 kubectl 命令来安装 ingress-nginx"
    return 1
  fi
  
  # 创建 ingress-nginx namespace
  kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
  
  # 使用官方 manifest 安装 ingress-nginx
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
  
  # 等待 ingress-nginx controller 就绪
  log "等待 ingress-nginx controller 就绪..."
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=300s
  
  # 验证安装
  if check_ingress_nginx_installed; then
    info "ingress-nginx controller 安装成功"
  else
    error "ingress-nginx controller 安装失败"
    return 1
  fi
}

# --- 解析命令行参数 ---
usage() {
  cat <<EOF
用法: ./install-k3s.sh [选项]

该脚本基于节点 IP 列表自动判断节点类型：
- 第一个 IP 为 master 节点（初始化集群）
- 其余 IP 为 worker 节点（加入集群）
- 当前服务器 IP 必须在配置的节点列表中

选项：
  --token TOKEN                  集群 token，不提供时自动生成（master）
  --version VERSION              指定 k3s 版本，如 v1.32.1+k3s1（默认使用环境变量）
  --data-dir PATH                k3s 数据目录（默认: /var/lib/rancher/k3s）
  --kubeconfig-mode MODE         kubeconfig 权限
  --mirror [cn|global]           镜像源（默认: cn）
  --disable COMPONENTS           禁用组件，逗号分隔（默认: traefik,rancher）
  --tls-sans "a.com,1.2.3.4"     追加 TLS SANs（可选）
  --extra-args "..."             追加传给 k3s 的额外参数
  --force                        强制重新安装（卸载现有环境）
  --uninstall                    卸载 k3s
  -h, --help                     显示帮助

环境变量（../env/dev.env）：
  K3S_INSTALL_NODE_IP_LIST       节点 IP 列表，空格分隔（必需）
  K3S_VERSION                    k3s 版本（默认: v1.32.1+k3s1）
  K3S_MIRROR                     镜像源（默认: cn）
  K3S_INSTALL_URL                安装脚本 URL
  K3S_DATA_DIR                   数据目录
  K3S_KUBECONFIG_MODE            kubeconfig 权限
  K3S_DISABLE_COMPONENTS         禁用组件
  K3S_EXTRA_ARGS                 额外参数
  INSTALL_DOMAIN                 安装域名（默认: mcp.qm.com）

示例：
  自动安装（根据当前服务器 IP 判断节点类型）
    sudo ./install-k3s.sh

  强制重新安装
    sudo ./install-k3s.sh --force

  使用自定义版本
    sudo K3S_VERSION=v1.30.4+k3s1 ./install-k3s.sh

  指定 token（用于 worker 节点）
    sudo ./install-k3s.sh --token mytoken
EOF
}

uninstall=false
force_install=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token) k3s_token="$2"; shift 2 ;;
    --version) k3s_version="$2"; shift 2 ;;
    --data-dir) k3s_data_dir="$2"; shift 2 ;;
    --kubeconfig-mode) k3s_kubeconfig_mode="$2"; shift 2 ;;
    --mirror) k3s_mirror="$2"; shift 2 ;;
    --disable) k3s_disable_components="$2"; shift 2 ;;
    --tls-sans) tls_sans="$2"; shift 2 ;;
    --extra-args) extra_args="$2"; shift 2 ;;
    --force) force_install=true; shift ;;
    --uninstall) uninstall=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "未知参数: $1"; usage; exit 2 ;;
  esac
done

# --- 前置检查 ---
check_ubuntu || exit 1

# 处理卸载请求
if [ "$uninstall" = true ]; then
  log "卸载 k3s..."
  
  # 尝试卸载 server
  if command -v /usr/local/bin/k3s-uninstall.sh >/dev/null 2>&1; then
    sudo /usr/local/bin/k3s-uninstall.sh || true
    info "k3s server 卸载完成"
  # 尝试卸载 agent
  elif command -v /usr/local/bin/k3s-agent-uninstall.sh >/dev/null 2>&1; then
    sudo /usr/local/bin/k3s-agent-uninstall.sh || true
    info "k3s agent 卸载完成"
  else
    error "未找到 k3s 卸载脚本"
  fi
  exit 0
fi

# 检查是否已安装
if check_k3s_installed; then
  warn "k3s 已安装，如需重新安装请先卸载"
  exit 0
fi

# 安装依赖
install_dependencies curl

# 配置镜像仓库
if [ "$k3s_mirror" = "cn" ]; then
  setup_k3s_registry
fi

# --- 节点类型自动判断 ---
if ! node_info=$(check_node_in_list); then
  error "节点 IP 检查失败"
  exit 1
fi

# 解析节点信息：类型:IP:索引
IFS=':' read -r node_type node_ip node_index <<< "$node_info"
info "检测到节点类型: $node_type，IP: $node_ip，索引: $node_index"

# 构建通用安装参数的函数
build_install_args() {
  local role="$1"
  local args=()
  
  if [ "$role" = "master" ]; then
    args=(server --cluster-init)
  else
    args=(agent)
  fi
  
  # 禁用组件
  if [ -n "$k3s_disable_components" ]; then
    IFS=',' read -ra components <<< "$k3s_disable_components"
    for comp in "${components[@]}"; do
      args+=("--disable" "$comp")
    done
  fi
  
  # TLS SANs (仅master节点)
  if [ "$role" = "master" ]; then
    # 添加通过--tls-sans参数指定的SANs
    if [ -n "$tls_sans" ]; then
      IFS=',' read -ra sans <<< "$tls_sans"
      for s in "${sans[@]}"; do 
        args+=("--tls-san" "$s")
      done
      log "添加 TLS SANs: $tls_sans"
    fi

    # 添加所有节点IP到TLS SANs中
    local node_ips
    node_ips=$(get_all_node_ips)
    while IFS= read -r ip; do
      [ -n "$ip" ] && args+=("--tls-san" "$ip")
    done <<< "$node_ips"
    
    # 添加k8s常用的内部服务IP到TLS SANs中
    args+=("--tls-san" "10.43.0.1") # kubernetes服务IP
    args+=("--tls-san" "127.0.0.1") # localhost

    # 添加K3S_API_URL到TLS SANs中
    if [ -n "$K3S_API_URL" ]; then
      args+=("--tls-san" "$K3S_API_URL")
    fi

    # 添加域名到TLS SANs中
    if [ -n "$INSTALL_DOMAIN" ]; then
      args+=("--tls-san" "$INSTALL_DOMAIN")
    fi
  fi
  
  # 额外参数
  if [ -n "$extra_args" ]; then
    # shellcheck disable=SC2206
    local extra_array=( $extra_args )
    args+=("${extra_array[@]}")
    log "额外参数: $extra_args"
  fi
  
  printf '%s\n' "${args[@]}"
}

# 执行k3s安装的函数
install_k3s() {
  local install_env="$1"
  shift
  local args=("$@")
  
  if [ -n "$k3s_version" ]; then
    log "安装指定版本: $k3s_version"
    curl -ksfL "$k3s_install_url" | INSTALL_K3S_VERSION="$k3s_version" sudo env $install_env sh -s - "${args[@]}"
  else
    log "安装最新版本"
    curl -ksfL "$k3s_install_url" | sudo env $install_env sh -s - "${args[@]}"
  fi
}

# 根据节点类型安装
if [ "$node_type" = "master" ]; then
  log "开始安装 k3s master 节点..."
  
  # 生成 token（如果未提供）
  if [ -z "$k3s_token" ]; then
    k3s_token="$(random_token)"
    log "未提供 token，自动生成: $k3s_token"
  fi

  # 构建环境变量
  install_env="K3S_TOKEN=$k3s_token K3S_KUBECONFIG_MODE=$k3s_kubeconfig_mode K3S_DATA_DIR=$k3s_data_dir K3S_NODE_IP=$node_ip K3S_INSTALL_NODE_IP_LIST=$K3S_INSTALL_NODE_IP_LIST"
  [ "$k3s_mirror" = "cn" ] && install_env+=" INSTALL_K3S_MIRROR=cn"

  # 构建安装参数并执行安装
  log "初始化集群，节点 IP: $node_ip"
  readarray -t args < <(build_install_args "master")
  install_k3s "$install_env" "${args[@]}"

  # 等待服务启动
  wait_for_service k3s
  
  info "k3s master 节点安装完成！"
  info "Token: $k3s_token"
  info "节点 IP: $node_ip"
  info "其他节点加入命令: sudo ./install-k3s.sh --token $k3s_token"

elif [ "$node_type" = "worker" ]; then
  log "开始安装 k3s worker 节点..."
  
  # 检查必需参数
  if [ -z "$k3s_token" ]; then
    error "worker 节点需要提供 --token 参数"
    exit 2
  fi
  
  # 获取 master 节点 IP（节点列表中的第一个）
  node_list="${K3S_INSTALL_NODE_IP_LIST//\"/}"
  master_ip=$(echo "$node_list" | awk '{print $1}')
  if [ -z "$master_ip" ]; then
    error "无法获取 master 节点 IP"
    exit 2
  fi
  
  k3s_url="https://$master_ip:6443"

  # 构建环境变量
  install_env="K3S_URL=$k3s_url K3S_TOKEN=$k3s_token K3S_DATA_DIR=$k3s_data_dir K3S_NODE_IP=$node_ip"
  [ "$k3s_mirror" = "cn" ] && install_env+=" INSTALL_K3S_MIRROR=cn"

  # 构建安装参数并执行安装
  log "连接到集群: $k3s_url，节点 IP: $node_ip"
  readarray -t args < <(build_install_args "worker")
  install_k3s "$install_env" "${args[@]}"

  # 等待服务启动
  wait_for_service k3s-agent
  
  info "k3s worker 节点安装完成！"
  info "已连接到集群: $k3s_url"
  info "节点 IP: $node_ip"

else
  error "未知节点类型: $node_type"
  exit 2
fi

# 安装后提示
if [ "$node_type" = "master" ]; then
  info "kubeconfig 路径: /etc/rancher/k3s/k3s.yaml"
  info "使用 kubectl: sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes"
  info "或者: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
  info "检查服务状态: systemctl status k3s"
  
  # 生成外部访问 kubeconfig
  log "生成外部访问 kubeconfig 配置文件"
  if [ -f /etc/rancher/k3s/k3s.yaml ]; then

    # 如果配置了 K3S_API_URL，也替换为域名
    if [ -n "${K3S_API_URL:-}" ]; then
      # 创建外部访问配置目录
      sudo mkdir -p /etc/rancher/k3s/external
      sudo cp /etc/rancher/k3s/k3s.yaml /etc/rancher/k3s/$K3S_API_URL.yaml
      sudo sed -i "s|https://127.0.0.1:6443|https://$K3S_API_URL:6443|g" /etc/rancher/k3s/$K3S_API_URL.yaml
      sudo sed -i "s|https://localhost:6443|https://$K3S_API_URL:6443|g" /etc/rancher/k3s/$K3S_API_URL.yaml
      info "外部访问 kubeconfig 已生成: /etc/rancher/k3s/$K3S_API_URL.yaml"
    fi

    # 生成容器内部使用的 https://kubernetes.default.svc:443 配置文件, kubernetes-internal.yaml
    sudo cp /etc/rancher/k3s/k3s.yaml /etc/rancher/k3s/kubernetes-internal.yaml
    sudo sed -i "s|https://127.0.0.1:6443|https://kubernetes.default.svc:443|g" /etc/rancher/k3s/kubernetes-internal.yaml
    sudo sed -i "s|https://localhost:6443|https://kubernetes.default.svc:443|g" /etc/rancher/k3s/kubernetes-internal.yaml
    info "容器内部 kubeconfig 已生成: /etc/rancher/k3s/kubernetes-internal.yaml"

  else
    error "无法找到默认 kubeconfig 文件，外部访问配置生成失败"
  fi

else
  info "检查服务状态: systemctl status k3s-agent"
fi

info "k3s 安装完成！节点类型: $node_type，IP: $node_ip"