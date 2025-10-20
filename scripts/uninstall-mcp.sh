#!/bin/bash

# 项目模板卸载脚本
# 功能：自动化卸载项目模板从 K3s 集群

set -e  # 遇到错误立即退出
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bash.sh"

# 检查必要的命令
check_dependencies() {
    info "检查依赖命令..."
    
    local deps=("kubectl")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error "缺少必要命令: $dep"
            exit 1
        fi
    done
    
    info "依赖检查完成"
}

# 1. 加载环境变量
load_env_config() {
    info "步骤1: 加载环境变量..."
    
    local env_file="$SCRIPT_DIR/../env/def.env"
    if [[ ! -f "$env_file" ]]; then
        error "环境变量文件不存在: $env_file"
        exit 1
    fi
    
    set -a
    source "$env_file"
    set +a
    
    local required_vars=("PROJECT_DIR" "PROJECT_NAMESPACE")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            error "缺少必要的环境变量: $var"
            exit 1
        fi
    done
    
    info "环境变量加载完成"
    info "项目目录: $PROJECT_DIR"
    info "项目命名空间: $PROJECT_NAMESPACE"
}

# 2. 检查集群连接
check_cluster_connection() {
    info "步骤2: 检查集群连接..."
    
    local k3s_config="/etc/rancher/k3s/k3s.yaml"
    
    if [[ -f "$k3s_config" ]]; then
        export KUBECONFIG="$k3s_config"
        info "K3s配置加载完成"
    else
        warn "K3s配置文件不存在: $k3s_config，尝试使用默认kubectl配置"
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        error "kubectl连接失败，请检查K3s集群状态"
        exit 1
    fi
    
    info "集群连接正常"
}

# 3. 检查命名空间是否存在
check_namespace() {
    info "步骤3: 检查命名空间..."
    
    if ! kubectl get namespace "$PROJECT_NAMESPACE" &> /dev/null; then
        warn "命名空间 $PROJECT_NAMESPACE 不存在，可能已被删除"
        return 1
    fi
    
    info "命名空间 $PROJECT_NAMESPACE 存在"
    return 0
}

# 4. 按逆序删除服务
delete_services() {
    info "步骤4: 按逆序删除服务..."
    
    local template_k3s_dir="$PROJECT_DIR/k3s"
    
    if [[ ! -d "$template_k3s_dir" ]]; then
        warn "模板k3s目录不存在: $template_k3s_dir，尝试直接删除命名空间资源"
        delete_all_resources_in_namespace
        return
    fi
    
    # 按照卸载顺序定义文件列表（与安装顺序相反）
    local ordered_files=(
        "ingress.yaml"
        "mcp-web.yaml"
        "mcp-gateway.yaml"
        "mcp-authz.yaml"
        "mcp-market.yaml"
        "mcp-init.yaml"
        "configmap.yaml"
        "nginx-ingress-controller.yaml"
        "mysql.yaml"
        "redis.yaml"
    )

    # 遍历按逆序删除每个服务
    for file_name in "${ordered_files[@]}"; do
        local file="$template_k3s_dir/$file_name"
        
        # 检查文件是否存在
        if [[ ! -f "$file" ]]; then
            warn "跳过不存在的文件: $file_name"
            continue
        fi

        info "删除K8s资源YAML: $file"
        
        # 创建临时文件用于变量替换
        local temp_file="/tmp/${file_name}.processed"
        
        # 环境变量替换
        if ! envsubst < "$file" > "$temp_file"; then
            warn "$file_name 环境变量替换失败，跳过"
            continue
        fi

        # 特殊处理 nginx-ingress-controller，它有自己的命名空间
        if [[ "$file_name" == "nginx-ingress-controller.yaml" ]]; then
            # 删除服务（不指定命名空间，让kubectl自动处理）
            if kubectl delete -f "$temp_file" --ignore-not-found=true --timeout=60s; then
                info "$file_name 删除成功"
            else
                warn "$file_name 删除失败，继续下一个服务"
            fi
        else
            # 删除服务
            if kubectl delete -f "$temp_file" -n "$PROJECT_NAMESPACE" --ignore-not-found=true --timeout=60s; then
                info "$file_name 删除成功"
            else
                warn "$file_name 删除失败，继续下一个服务"
            fi
        fi
        
        rm -f "$temp_file"
        sleep 2
    done
}

# 5. 删除命名空间中的所有资源（备用方法）
delete_all_resources_in_namespace() {
    info "删除命名空间 $PROJECT_NAMESPACE 中的所有资源..."
    
    # 删除所有资源类型
    local resource_types=(
        "ingress"
        "service"
        "deployment"
        "statefulset"
        "daemonset"
        "job"
        "cronjob"
        "configmap"
        "secret"
        "pvc"
        "pv"
    )
    
    for resource_type in "${resource_types[@]}"; do
        info "删除 $resource_type 资源..."
        if kubectl delete "$resource_type" --all -n "$PROJECT_NAMESPACE" --ignore-not-found=true --timeout=60s; then
            info "$resource_type 资源删除完成"
        else
            warn "$resource_type 资源删除失败或不存在"
        fi
    done
}

# 6. 删除命名空间
delete_namespace() {
    info "步骤5: 删除命名空间..."
    
    if kubectl get namespace "$PROJECT_NAMESPACE" &> /dev/null; then
        info "删除命名空间: $PROJECT_NAMESPACE"
        if kubectl delete namespace "$PROJECT_NAMESPACE" --timeout=120s; then
            info "命名空间删除成功"
        else
            error "命名空间删除失败"
            return 1
        fi
    else
        info "命名空间 $PROJECT_NAMESPACE 已不存在"
    fi
}

# 7. 验证卸载状态
verify_uninstall() {
    info "步骤6: 验证卸载状态..."
    
    if kubectl get namespace "$PROJECT_NAMESPACE" &> /dev/null; then
        warn "命名空间 $PROJECT_NAMESPACE 仍然存在"
        
        info "检查剩余资源..."
        kubectl get all -n "$PROJECT_NAMESPACE" 2>/dev/null || info "无剩余资源"
        
        return 1
    else
        info "命名空间 $PROJECT_NAMESPACE 已成功删除"
    fi
    
    # 检查是否还有相关的PV资源
    local remaining_pvs
    remaining_pvs=$(kubectl get pv --no-headers 2>/dev/null | grep "$PROJECT_NAMESPACE" | wc -l || echo "0")
    
    if [[ "$remaining_pvs" -gt 0 ]]; then
        warn "发现 $remaining_pvs 个相关的PV资源可能需要手动清理"
        kubectl get pv | grep "$PROJECT_NAMESPACE" || true
    fi
}

# 8. 清理临时文件
cleanup() {
    info "清理临时文件..."
    find "/tmp" -name "*.processed" -type f -delete 2>/dev/null || true
}

# 主函数
main() {
    info "开始项目模板卸载..."
    info "==========================================="
    
    trap cleanup EXIT
    
    check_dependencies
    load_env_config
    check_cluster_connection
    
    if check_namespace; then
        delete_services
        delete_namespace
    else
        info "命名空间不存在，跳过资源删除"
    fi
    
    verify_uninstall
    
    info "==========================================="
    info "项目模板卸载完成！"
    
    info "卸载信息:"
    info "- 命名空间: $PROJECT_NAMESPACE (已删除)"
    info "- 项目目录: $PROJECT_DIR (保留)"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi