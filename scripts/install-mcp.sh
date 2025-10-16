#!/bin/bash

# 项目模板部署脚本
# 功能：自动化部署项目模板到 K3s 集群

set -e  # 遇到错误立即退出
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bash.sh"

# 检查必要的命令
check_dependencies() {
    info "检查依赖命令..."
    
    local deps=("kubectl" "envsubst")
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

# 2. 拷贝模板到指定目录
copy_templates() {
    info "步骤2: 拷贝模板到指定目录..."
    
    mkdir -p "$PROJECT_DIR"
    
    local tpl_dir="$SCRIPT_DIR/../template"
    if [[ -d "$tpl_dir" ]]; then
        info "开始拷贝模板文件到: $PROJECT_DIR"
        if cp -r "$tpl_dir"/* "$PROJECT_DIR/"; then
            info "模板文件拷贝完成"
        else
            error "模板文件拷贝失败"
            exit 1
        fi
    else
        error "模板目录不存在: $tpl_dir"
        exit 1
    fi
}

# 3. 替换config文件中的环境变量占位符
process_config_files() {
    info "步骤3: 替换config文件中所有环境变量占位符..."
    
    local config_dir="$PROJECT_DIR/config"
    
    if [[ ! -d "$config_dir" ]]; then
        warn "配置目录不存在: $config_dir"
        return
    fi
    
    local config_files
    config_files=$(find "$config_dir" -type f)
    
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        info "处理配置文件: $file"
        
        if envsubst < "$file" > "${file}.tmp"; then
            mv "${file}.tmp" "$file"
            
            local file_name
            file_name=$(basename "$file")
            local file_content
            file_content=$(cat "$file")
            file_content=$(echo "$file_content" | sed '1!s/^/    /')
            
            # 导出不带后缀的文件名作为环境变量
            local var_name
            var_name=$(echo "$file_name" | sed 's/\.[^.]*$//' | sed 's/[.-]/_/g')
            export "$var_name"="$file_content"
            
        else
            error "配置文件变量替换失败: $file"
            rm -f "${file}.tmp"
            exit 1
        fi
    done <<< "$config_files"
    
    info "配置文件处理完成"
}

# 4. 替换k3s文件夹中的环境变量占位符和文件名称内容映射占位符
process_k3s_files() {
    info "步骤4: 替换k3s文件夹中所有环境变量占位符和文件名称内容映射占位符..."
    
    local k3s_dir="$PROJECT_DIR/k3s"
    
    if [[ ! -d "$k3s_dir" ]]; then
        error "k3s目录不存在: $k3s_dir"
        exit 1
    fi
    
    local k3s_files
    k3s_files=$(find "$k3s_dir" -type f)
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        info "处理k3s文件: $file"
        
        # 先进行环境变量替换
        if envsubst < "$file" > "${file}.tmp"; then
            mv "${file}.tmp" "$file"
        else
            error "k3s文件环境变量替换失败: $file"
            rm -f "${file}.tmp"
            exit 1
        fi
        
        # 再进行config文件内容映射替换
        local config_dir="$PROJECT_DIR/config"
        if [[ -d "$config_dir" ]]; then
            local config_files
            config_files=$(find "$config_dir" -type f)
            
            while IFS= read -r config_file; do
                [[ -z "$config_file" ]] && continue
                
                local config_name
                config_name=$(basename "$config_file" | sed 's/\.[^.]*$//')
                
                local config_content
                config_content=$(cat "$config_file")
                config_content=$(echo "$config_content" | sed '1!s/^/    /')
                
                # 替换 ${config_name} 占位符
                if grep -q "\${$config_name}" "$file"; then
                    info "替换 $file 中的 \${$config_name} 占位符"
                    # 使用临时文件进行替换，避免特殊字符问题
                    awk -v config_name="$config_name" -v config_content="$config_content" '
                    {
                        gsub("\\${" config_name "}", config_content)
                        print
                    }' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
                fi
            done <<< "$config_files"
        fi
    done <<< "$k3s_files"
    
    info "k3s文件处理完成"
}

# 5. 创建命名空间
create_namespace() {
    info "步骤5: 创建命名空间..."
    
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
    
    info "创建命名空间: $PROJECT_NAMESPACE"
    if kubectl create namespace "$PROJECT_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -; then
        info "命名空间创建/更新成功"
    else
        error "命名空间创建失败"
        exit 1
    fi
}

# 6. 按顺序部署服务
deploy_services() {
    info "步骤6: 按顺序部署服务..."
    
    local template_k3s_dir="$PROJECT_DIR/k3s"
    
    if [[ ! -d "$template_k3s_dir" ]]; then
        error "模板k3s目录不存在: $template_k3s_dir"
        exit 1
    fi
    
    # 按照部署顺序定义文件列表
    local ordered_files=(
        "nginx-ingress-controller.yaml"
        "mysql.yaml"
        "redis.yaml"
        "configmap.yaml" 
        # "mcp-init.yaml"
        "mcp-market.yaml"
        "mcp-authz.yaml"
        "mcp-gateway.yaml"
        "mcp-web.yaml"
        "ingress.yaml"
    )

    # 遍历按顺序部署每个服务
    for file_name in "${ordered_files[@]}"; do
        local file="$template_k3s_dir/$file_name"
        
        # 检查文件是否存在
        if [[ ! -f "$file" ]]; then
            warn "跳过不存在的文件: $file_name"
            continue
        fi

        info "部署K8s资源YAML: $file"

        # 特殊处理 nginx-ingress-controller，它有自己的命名空间
        if [[ "$file_name" == "nginx-ingress-controller.yaml" ]]; then
            # 检查YAML语法（不指定命名空间）
            if ! envsubst < "$file" | kubectl apply --dry-run=client -f - &>/dev/null; then
                error "$file_name YAML语法检查失败"
                exit 1
            fi

            # 部署服务（不指定命名空间）
            echo "kubectl apply -f $file"
            if ! envsubst < "$file" | kubectl apply -f -; then
                error "$file_name 部署失败"
                envsubst < "$file" | kubectl describe -f - || true
                exit 1
            fi
        else
            # 检查YAML语法
            if ! envsubst < "$file" | kubectl apply --dry-run=client -n "$PROJECT_NAMESPACE" -f - &>/dev/null; then
                error "$file_name YAML语法检查失败"
                exit 1
            fi

            # 部署服务
            echo "kubectl apply -f $file -n $PROJECT_NAMESPACE"
            if ! envsubst < "$file" | kubectl apply -n "$PROJECT_NAMESPACE" -f -; then
                error "$file_name 部署失败"
                envsubst < "$file" | kubectl describe -n "$PROJECT_NAMESPACE" -f - || true
                exit 1
            fi
        fi
        
        info "$file_name 部署成功"

        # 获取资源类型和名称用于等待就绪
        local resource_info
        resource_info=$(envsubst < "$file" | grep -E "^kind:|^  name:" | paste - -)
        local resource_type
        resource_type=$(echo "$resource_info" | grep "kind:" | awk '{print $2}' | head -1)
        
        case "$resource_type" in
            "Deployment")
                local deployment_name
                deployment_name=$(envsubst < "$file" | grep -A1 "kind: Deployment" | grep "name:" | awk '{print $2}' | head -1)
                if [[ -n "$deployment_name" ]]; then
                    info "等待 Deployment/$deployment_name 就绪..."
                    if ! kubectl wait --for=condition=available --timeout=300s deployment/"$deployment_name" -n "$PROJECT_NAMESPACE"; then
                        warn "Deployment/$deployment_name 超时，继续下一个服务"
                    fi
                fi
                ;;
            "StatefulSet")
                local statefulset_name
                statefulset_name=$(envsubst < "$file" | grep -A1 "kind: StatefulSet" | grep "name:" | awk '{print $2}' | head -1)
                if [[ -n "$statefulset_name" ]]; then
                    info "等待 StatefulSet/$statefulset_name 就绪..."
                    if ! kubectl wait --for=condition=ready --timeout=300s statefulset/"$statefulset_name" -n "$PROJECT_NAMESPACE"; then
                        warn "StatefulSet/$statefulset_name 超时，继续下一个服务"
                    fi
                fi
                ;;
            "DaemonSet")
                local daemonset_name
                daemonset_name=$(envsubst < "$file" | grep -A1 "kind: DaemonSet" | grep "name:" | awk '{print $2}' | head -1)
                if [[ -n "$daemonset_name" ]]; then
                    info "等待 DaemonSet/$daemonset_name 就绪..."
                    # 特殊处理 nginx-ingress-controller 的命名空间
                    if [[ "$file_name" == "nginx-ingress-controller.yaml" ]]; then
                        if ! kubectl wait --for=condition=ready --timeout=300s daemonset/"$daemonset_name" -n ingress-nginx; then
                            warn "DaemonSet/$daemonset_name 超时，继续下一个服务"
                        fi
                    else
                        if ! kubectl wait --for=condition=ready --timeout=300s daemonset/"$daemonset_name" -n "$PROJECT_NAMESPACE"; then
                            warn "DaemonSet/$daemonset_name 超时，继续下一个服务"
                        fi
                    fi
                fi
                ;;
            "Job")
                local job_name
                job_name=$(envsubst < "$file" | grep -A1 "kind: Job" | grep "name:" | awk '{print $2}' | head -1)
                if [[ -n "$job_name" ]]; then
                    info "等待 Job/$job_name 完成..."
                    if ! kubectl wait --for=condition=complete --timeout=300s job/"$job_name" -n "$PROJECT_NAMESPACE"; then
                        warn "Job/$job_name 超时，继续下一个服务"
                    fi
                fi
                ;;
            "CronJob")
                local cronjob_name
                cronjob_name=$(envsubst < "$file" | grep -A1 "kind: CronJob" | grep "name:" | awk '{print $2}' | head -1)
                if [[ -n "$cronjob_name" ]]; then
                    info "检查 CronJob/$cronjob_name 创建状态..."
                    if ! kubectl get cronjob "$cronjob_name" -n "$PROJECT_NAMESPACE" &>/dev/null; then
                        warn "CronJob/$cronjob_name 创建可能失败，继续下一个服务"
                    else
                        info "CronJob/$cronjob_name 创建成功"
                    fi
                fi
                ;;
        esac

        sleep 2
    done
}
# 7. 验证部署状态
verify_deployment() {
    info "步骤7: 验证部署状态..."
    
    info "检查Pod状态..."
    kubectl get pods -n "$PROJECT_NAMESPACE" -o wide
    
    info "检查Service状态..."
    kubectl get services -n "$PROJECT_NAMESPACE"
    
    info "检查PVC状态..."
    kubectl get pvc -n "$PROJECT_NAMESPACE" 2>/dev/null || info "无PVC资源"
    
    local failed_pods
    failed_pods=$(kubectl get pods -n "$PROJECT_NAMESPACE" --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)
    
    if [[ "$failed_pods" -eq 0 ]]; then
        info "所有Pod运行正常"
    else
        warn "发现 $failed_pods 个异常Pod"
        kubectl get pods -n "$PROJECT_NAMESPACE" --field-selector=status.phase!=Running
    fi
}

# 清理函数
cleanup() {
    info "清理临时文件..."
    find "/tmp" -name "*.processed" -type f -delete 2>/dev/null || true
}

# 主函数
main() {
    info "开始项目模板部署..."
    info "==========================================="
    
    trap cleanup EXIT
    
    check_dependencies
    load_env_config
    copy_templates
    process_config_files
    process_k3s_files
    create_namespace
    deploy_services
    verify_deployment
    
    info "==========================================="
    info "项目模板部署完成！"
    
    info "访问信息:"
    info "- 命名空间: $PROJECT_NAMESPACE"
    
    local ingress_info
    ingress_info=$(kubectl get ingress -n "$PROJECT_NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "未配置Ingress")
    if [[ "$ingress_info" != "未配置Ingress" ]]; then
        info "- 访问地址: http://$ingress_info"
    fi
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi