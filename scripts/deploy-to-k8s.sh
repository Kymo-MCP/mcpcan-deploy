#!/bin/bash

# MCP-Box Kubernetes Deployment Script
# Deploy to Kubernetes cluster from GitHub Pages Helm repository
# Usage: ./deploy-to-k8s.sh [environment] [namespace] [values-file]

set -e

# Configuration parameters
ENVIRONMENT=${1:-"dev"}
NAMESPACE=${2:-"mcp-system"}
VALUES_FILE=${3:-"values-${ENVIRONMENT}.yaml"}
CHART_NAME="mcp-box"
RELEASE_NAME="mcp-box"
HELM_REPO_NAME="mcp-box"
HELM_REPO_URL="https://kymo-mcp.github.io/mcp-box-helm-charts/"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check necessary tools
check_prerequisites() {
    log_info "Checking necessary tools..."
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed, please install kubectl first"
        exit 1
    fi
    
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed, please install Helm first"
        exit 1
    fi
    
    log_success "Necessary tools check completed"
}

# Check Kubernetes connection
check_k8s_connection() {
    log_info "Checking Kubernetes cluster connection..."
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster, please check kubeconfig"
        exit 1
    fi
    
    CURRENT_CONTEXT=$(kubectl config current-context)
    log_success "Connected to cluster: $CURRENT_CONTEXT"
}

# Create namespace
create_namespace() {
    log_info "Checking namespace $NAMESPACE..."
    
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_info "Creating namespace $NAMESPACE..."
        kubectl create namespace "$NAMESPACE"
        log_success "Namespace $NAMESPACE created successfully"
    else
        log_success "Namespace $NAMESPACE already exists"
    fi
}

# Add Helm repository
add_helm_repo() {
    log_info "Adding Helm repository..."
    
    # Check if repository already exists
    if helm repo list | grep -q "$HELM_REPO_NAME"; then
        log_info "Updating existing Helm repository..."
        helm repo update "$HELM_REPO_NAME"
    else
        log_info "Adding new Helm repository..."
        helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL"
        helm repo update
    fi
    
    log_success "Helm repository configuration completed"
}

# Check configuration file
check_values_file() {
    if [ ! -f "$VALUES_FILE" ]; then
        log_warning "Configuration file $VALUES_FILE does not exist, will use default configuration"
        VALUES_FILE=""
    else
        log_success "Using configuration file: $VALUES_FILE"
    fi
}

# Deploy application
deploy_application() {
    log_info "Starting deployment of MCP-Box to environment: $ENVIRONMENT"
    
    # Build helm install/upgrade command
    HELM_CMD="helm upgrade --install $RELEASE_NAME $HELM_REPO_NAME/$CHART_NAME"
    HELM_CMD="$HELM_CMD --namespace $NAMESPACE"
    HELM_CMD="$HELM_CMD --create-namespace"
    HELM_CMD="$HELM_CMD --wait"
    HELM_CMD="$HELM_CMD --timeout 10m"
    
    if [ -n "$VALUES_FILE" ]; then
        HELM_CMD="$HELM_CMD -f $VALUES_FILE"
    fi
    
    # Add environment-specific configuration
    case $ENVIRONMENT in
        "prod")
            HELM_CMD="$HELM_CMD --set global.environment=production"
            HELM_CMD="$HELM_CMD --set services.web.replicas=3"
            HELM_CMD="$HELM_CMD --set services.market.replicas=2"
            ;;
        "staging")
            HELM_CMD="$HELM_CMD --set global.environment=staging"
            HELM_CMD="$HELM_CMD --set services.web.replicas=2"
            ;;
        "dev")
            HELM_CMD="$HELM_CMD --set global.environment=development"
            ;;
    esac
    
    log_info "Executing deployment command: $HELM_CMD"
    
    if eval "$HELM_CMD"; then
        log_success "MCP-Box deployment successful!"
    else
        log_error "MCP-Box deployment failed"
        exit 1
    fi
}

# 验证部署
verify_deployment() {
    log_info "验证部署状态..."
    
    # 等待 Pod 就绪
    log_info "等待 Pod 启动..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=$RELEASE_NAME -n $NAMESPACE --timeout=300s
    
    # 检查服务状态
    log_info "检查服务状态..."
    kubectl get pods,svc,ingress -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME
    
    # 获取访问地址
    log_info "获取访问地址..."
    INGRESS_IP=$(kubectl get ingress -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    INGRESS_HOST=$(kubectl get ingress -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "")
    
    if [ -n "$INGRESS_HOST" ]; then
        log_success "应用访问地址: http://$INGRESS_HOST"
    elif [ -n "$INGRESS_IP" ]; then
        log_success "应用访问地址: http://$INGRESS_IP"
    else
        log_warning "无法获取外部访问地址，请检查 Ingress 配置"
    fi
    
    log_success "部署验证完成"
}

# 显示部署信息
show_deployment_info() {
    log_info "部署信息摘要:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🚀 应用名称: $RELEASE_NAME"
    echo "🏷️  Chart: $HELM_REPO_NAME/$CHART_NAME"
    echo "🌍 环境: $ENVIRONMENT"
    echo "📦 命名空间: $NAMESPACE"
    echo "⚙️  配置文件: ${VALUES_FILE:-"默认配置"}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 显示管理命令
    log_info "常用管理命令:"
    echo "# 查看部署状态"
    echo "kubectl get all -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME"
    echo ""
    echo "# 查看日志"
    echo "kubectl logs -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME -f"
    echo ""
    echo "# 升级应用"
    echo "helm upgrade $RELEASE_NAME $HELM_REPO_NAME/$CHART_NAME -n $NAMESPACE"
    echo ""
    echo "# 卸载应用"
    echo "helm uninstall $RELEASE_NAME -n $NAMESPACE"
}

# 主函数
main() {
    echo "🚀 MCP-Box Kubernetes 部署工具"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    check_prerequisites
    check_k8s_connection
    create_namespace
    add_helm_repo
    check_values_file
    deploy_application
    verify_deployment
    show_deployment_info
    
    log_success "🎉 MCP-Box 部署完成!"
}

# 显示帮助信息
show_help() {
    echo "MCP-Box Kubernetes 部署脚本"
    echo ""
    echo "用法: $0 [environment] [namespace] [values-file]"
    echo ""
    echo "参数:"
    echo "  environment  部署环境 (dev|staging|prod)，默认: dev"
    echo "  namespace    Kubernetes 命名空间，默认: mcp-system"
    echo "  values-file  Helm values 配置文件，默认: values-{environment}.yaml"
    echo ""
    echo "示例:"
    echo "  $0                                    # 使用默认配置部署到 dev 环境"
    echo "  $0 prod mcp-prod values-prod.yaml    # 部署到生产环境"
    echo "  $0 staging mcp-staging               # 部署到预发布环境"
    echo ""
    echo "环境变量:"
    echo "  HELM_REPO_URL  Helm 仓库地址"
    echo "  KUBECONFIG     Kubernetes 配置文件路径"
}

# 处理命令行参数
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac