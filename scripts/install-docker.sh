#!/usr/bin/env bash

# ==============================================
# Docker & Docker Compose Installation and Deployment Script
# Supports Ubuntu/Debian/CentOS/RHEL Linux distributions
# ==============================================

# Source common functions if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/bash.sh" ]]; then
    source "${SCRIPT_DIR}/bash.sh"
else
    # Define basic functions if bash.sh is not available
    log() { echo "[$(basename "$0")] $*"; }
    info() { echo "✅ $*"; }
    warn() { echo "💡️ $*"; }
    error() { echo "❌ $*" >&2; }
    
    check_command() {
        local cmd="$1"
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "Command not found: $cmd"
            return 1
        fi
        return 0
    }
    
    check_root() {
        if [[ $EUID -eq 0 ]]; then
            return 0
        else
            return 1
        fi
    }
fi

# --- Docker installation default parameters ---
DOCKER_VERSION=${DOCKER_VERSION:-"latest"}
DOCKER_COMPOSE_VERSION=${DOCKER_COMPOSE_VERSION:-"v2.24.5"}
DOCKER_MIRROR=${DOCKER_MIRROR:-"cn"}
DOCKER_DATA_ROOT=${DOCKER_DATA_ROOT:-"/var/lib/docker"}
DOCKER_REGISTRY_MIRRORS=${DOCKER_REGISTRY_MIRRORS:-"https://registry.cn-hangzhou.aliyuncs.com,https://docker.mirrors.ustc.edu.cn"}

# --- Application deployment parameters ---
APP_NAME=${APP_NAME:-"mcpcan"}
APP_VERSION=${APP_VERSION:-"v1.1.0-dev"}
APP_DOMAIN=${APP_DOMAIN:-"localhost"}
APP_PORT=${APP_PORT:-"80"}
APP_SSL_PORT=${APP_SSL_PORT:-"443"}
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-"mcpcan"}

# Detect Linux distribution
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [[ -f /etc/redhat-release ]]; then
        OS="centos"
        OS_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
    else
        error "Unsupported operating system"
        return 1
    fi
    
    log "Detected OS: $OS $OS_VERSION"
    return 0
}

# Check system requirements
check_system_requirements() {
    log "Checking system requirements..."
    
    # Check if running on Linux
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        error "This script is designed for Linux systems only"
        return 1
    fi
    
    # Check architecture
    local arch=$(uname -m)
    case $arch in
        x86_64|amd64)
            info "Architecture: $arch (supported)"
            ;;
        aarch64|arm64)
            info "Architecture: $arch (supported)"
            ;;
        *)
            error "Unsupported architecture: $arch"
            return 1
            ;;
    esac
    
    # Check available disk space (minimum 10GB)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local min_space=$((10 * 1024 * 1024)) # 10GB in KB
    
    if [[ $available_space -lt $min_space ]]; then
        error "Insufficient disk space. Required: 10GB, Available: $((available_space / 1024 / 1024))GB"
        return 1
    fi
    
    info "System requirements check passed"
    return 0
}

# Install Docker on Ubuntu/Debian
install_docker_ubuntu() {
    log "Installing Docker on Ubuntu/Debian..."
    
    # Update package index
    sudo apt-get update -y
    
    # Install prerequisites
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common
    
    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    if [[ "$DOCKER_MIRROR" == "cn" ]]; then
        # Use Aliyun mirror for China
        curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    else
        # Use official Docker repository
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi
    
    # Update package index again
    sudo apt-get update -y
    
    # Install Docker Engine
    if [[ "$DOCKER_VERSION" == "latest" ]]; then
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        sudo apt-get install -y docker-ce=$DOCKER_VERSION docker-ce-cli=$DOCKER_VERSION containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    
    info "Docker installation completed on Ubuntu/Debian"
}

# Install Docker on CentOS/RHEL
install_docker_centos() {
    log "Installing Docker on CentOS/RHEL..."
    
    # Install prerequisites
    sudo yum install -y yum-utils device-mapper-persistent-data lvm2
    
    # Add Docker repository
    if [[ "$DOCKER_MIRROR" == "cn" ]]; then
        # Use Aliyun mirror for China
        sudo yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
    else
        # Use official Docker repository
        sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    fi
    
    # Install Docker Engine
    if [[ "$DOCKER_VERSION" == "latest" ]]; then
        sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        sudo yum install -y docker-ce-$DOCKER_VERSION docker-ce-cli-$DOCKER_VERSION containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    
    info "Docker installation completed on CentOS/RHEL"
}

# Install Docker based on distribution
install_docker() {
    log "Starting Docker installation..."
    
    # Check if Docker is already installed
    if command -v docker >/dev/null 2>&1; then
        local docker_version=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
        warn "Docker is already installed (version: $docker_version)"
        read -p "Do you want to reinstall Docker? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Skipping Docker installation"
            return 0
        fi
    fi
    
    # Detect OS and install accordingly
    detect_os
    
    case $OS in
        ubuntu|debian)
            install_docker_ubuntu
            ;;
        centos|rhel|rocky|almalinux)
            install_docker_centos
            ;;
        *)
            error "Unsupported distribution: $OS"
            return 1
            ;;
    esac
    
    # Start and enable Docker service
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add current user to docker group
    sudo usermod -aG docker $USER
    
    info "Docker installation completed successfully"
    info "Please log out and log back in to use Docker without sudo"
}

# Configure Docker daemon
configure_docker() {
    log "Configuring Docker daemon..."
    
    # Create Docker daemon configuration directory
    sudo mkdir -p /etc/docker
    
    # Configure Docker daemon with registry mirrors and other settings
    local daemon_config='{
  "registry-mirrors": ['
    
    # Add registry mirrors
    IFS=',' read -ra MIRRORS <<< "$DOCKER_REGISTRY_MIRRORS"
    for i in "${!MIRRORS[@]}"; do
        if [[ $i -gt 0 ]]; then
            daemon_config+=','
        fi
        daemon_config+="\"${MIRRORS[$i]}\""
    done
    
    daemon_config+='],
  "data-root": "'$DOCKER_DATA_ROOT'",
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "live-restore": true,
  "userland-proxy": false,
  "experimental": false
}'
    
    # Write daemon configuration
    echo "$daemon_config" | sudo tee /etc/docker/daemon.json > /dev/null
    
    # Restart Docker service to apply configuration
    sudo systemctl restart docker
    
    info "Docker daemon configuration completed"
}

# Install Docker Compose (standalone version)
install_docker_compose_standalone() {
    log "Installing Docker Compose standalone..."
    
    # Determine architecture
    local arch=$(uname -m)
    case $arch in
        x86_64) arch="x86_64" ;;
        aarch64) arch="aarch64" ;;
        *) 
            error "Unsupported architecture for Docker Compose: $arch"
            return 1
            ;;
    esac
    
    # Download Docker Compose
    local compose_url="https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-${arch}"
    
    if [[ "$DOCKER_MIRROR" == "cn" ]]; then
        # Use GitHub proxy for China
        compose_url="https://ghproxy.com/${compose_url}"
    fi
    
    sudo curl -L "$compose_url" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    # Create symlink for compatibility
    sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    info "Docker Compose standalone installation completed"
}

# Verify Docker installation
verify_docker_installation() {
    log "Verifying Docker installation..."
    
    # Check Docker version
    if ! docker --version; then
        error "Docker installation verification failed"
        return 1
    fi
    
    # Check Docker Compose version
    if docker compose version >/dev/null 2>&1; then
        docker compose version
        info "Docker Compose plugin is available"
    elif docker-compose --version >/dev/null 2>&1; then
        docker-compose --version
        info "Docker Compose standalone is available"
    else
        warn "Docker Compose is not available, installing standalone version..."
        install_docker_compose_standalone
    fi
    
    # Test Docker functionality
    if docker run --rm hello-world >/dev/null 2>&1; then
        info "Docker is working correctly"
    else
        error "Docker test failed"
        return 1
    fi
    
    info "Docker installation verification completed successfully"
}

# Create Docker Compose configuration
create_docker_compose_config() {
    log "Creating Docker Compose configuration..."
    
    local compose_dir="${SCRIPT_DIR}/../compose"
    mkdir -p "$compose_dir"
    
    # Create docker-compose.yml
    cat > "$compose_dir/docker-compose.yml" <<EOF
version: '3.8'

services:
  # Frontend service
  frontend:
    image: ccr.ccs.tencentyun.com/itqm-private/mcpcan-frontend:${APP_VERSION}
    container_name: \${COMPOSE_PROJECT_NAME:-mcpcan}-frontend
    restart: unless-stopped
    ports:
      - "\${APP_PORT:-80}:80"
      - "\${APP_SSL_PORT:-443}:443"
    environment:
      - NODE_ENV=production
      - API_BASE_URL=http://gateway:8080
    depends_on:
      - gateway
    networks:
      - mcpcan-network
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # API Gateway service
  gateway:
    image: ccr.ccs.tencentyun.com/itqm-private/mcpcan-gateway:${APP_VERSION}
    container_name: \${COMPOSE_PROJECT_NAME:-mcpcan}-gateway
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      - GIN_MODE=release
      - DB_HOST=mysql
      - DB_PORT=3306
      - DB_NAME=mcpcan
      - DB_USER=mcpcan
      - DB_PASSWORD=\${DB_PASSWORD:-mcpcan123}
      - REDIS_HOST=redis
      - REDIS_PORT=6379
    depends_on:
      - mysql
      - redis
    networks:
      - mcpcan-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Market service
  market:
    image: ccr.ccs.tencentyun.com/itqm-private/mcpcan-market:${APP_VERSION}
    container_name: \${COMPOSE_PROJECT_NAME:-mcpcan}-market
    restart: unless-stopped
    ports:
      - "8081:8081"
    environment:
      - GIN_MODE=release
      - DB_HOST=mysql
      - DB_PORT=3306
      - DB_NAME=mcpcan
      - DB_USER=mcpcan
      - DB_PASSWORD=\${DB_PASSWORD:-mcpcan123}
    depends_on:
      - mysql
    networks:
      - mcpcan-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8081/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Authorization service
  authz:
    image: ccr.ccs.tencentyun.com/itqm-private/mcpcan-authz:${APP_VERSION}
    container_name: \${COMPOSE_PROJECT_NAME:-mcpcan}-authz
    restart: unless-stopped
    ports:
      - "8082:8082"
    environment:
      - GIN_MODE=release
      - DB_HOST=mysql
      - DB_PORT=3306
      - DB_NAME=mcpcan
      - DB_USER=mcpcan
      - DB_PASSWORD=\${DB_PASSWORD:-mcpcan123}
    depends_on:
      - mysql
    networks:
      - mcpcan-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8082/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # MySQL database
  mysql:
    image: mysql:8.0
    container_name: \${COMPOSE_PROJECT_NAME:-mcpcan}-mysql
    restart: unless-stopped
    ports:
      - "3306:3306"
    environment:
      - MYSQL_ROOT_PASSWORD=\${MYSQL_ROOT_PASSWORD:-root123}
      - MYSQL_DATABASE=mcpcan
      - MYSQL_USER=mcpcan
      - MYSQL_PASSWORD=\${DB_PASSWORD:-mcpcan123}
    volumes:
      - mysql-data:/var/lib/mysql
      - ./mysql/init:/docker-entrypoint-initdb.d:ro
    networks:
      - mcpcan-network
    command: --default-authentication-plugin=mysql_native_password
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Redis cache
  redis:
    image: redis:7-alpine
    container_name: \${COMPOSE_PROJECT_NAME:-mcpcan}-redis
    restart: unless-stopped
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    networks:
      - mcpcan-network
    command: redis-server --appendonly yes
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  mcpcan-network:
    driver: bridge
    name: \${COMPOSE_PROJECT_NAME:-mcpcan}-network

volumes:
  mysql-data:
    name: \${COMPOSE_PROJECT_NAME:-mcpcan}-mysql-data
  redis-data:
    name: \${COMPOSE_PROJECT_NAME:-mcpcan}-redis-data
EOF

    # Create environment file
    cat > "$compose_dir/.env" <<EOF
# Project configuration
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}
APP_VERSION=${APP_VERSION}
APP_DOMAIN=${APP_DOMAIN}
APP_PORT=${APP_PORT}
APP_SSL_PORT=${APP_SSL_PORT}

# Database configuration
DB_PASSWORD=mcpcan123
MYSQL_ROOT_PASSWORD=root123

# Application configuration
GIN_MODE=release
NODE_ENV=production
EOF

    info "Docker Compose configuration created in $compose_dir"
}

# Create additional configuration files
create_additional_configs() {
    log "Creating additional configuration files..."
    
    local compose_dir="${SCRIPT_DIR}/../compose"
    
    # Create nginx configuration
    mkdir -p "$compose_dir/nginx"
    cat > "$compose_dir/nginx/nginx.conf" <<EOF
events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
    
    upstream api_gateway {
        server gateway:8080;
    }
    
    server {
        listen 80;
        server_name ${APP_DOMAIN};
        
        # Health check endpoint
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
        
        # API proxy
        location /api/ {
            proxy_pass http://api_gateway/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
        
        # Static files
        location / {
            root /usr/share/nginx/html;
            index index.html index.htm;
            try_files \$uri \$uri/ /index.html;
        }
    }
}
EOF

    # Create MySQL initialization script
    mkdir -p "$compose_dir/mysql/init"
    cat > "$compose_dir/mysql/init/01-init.sql" <<EOF
-- Create database if not exists
CREATE DATABASE IF NOT EXISTS mcpcan CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Use the database
USE mcpcan;

-- Create basic tables (example)
CREATE TABLE IF NOT EXISTS users (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Insert default admin user (password: admin123)
INSERT IGNORE INTO users (username, email, password_hash) VALUES 
('admin', 'admin@mcpcan.com', '\$2a\$10\$rOzJqQjQjQjQjQjQjQjQjOzJqQjQjQjQjQjQjQjQjQjQjQjQjQjQjQ');

-- Grant privileges
GRANT ALL PRIVILEGES ON mcpcan.* TO 'mcpcan'@'%';
FLUSH PRIVILEGES;
EOF

    # Create SSL directory
    mkdir -p "$compose_dir/ssl"
    
    info "Additional configuration files created"
}

# Deploy application using Docker Compose
deploy_application() {
    log "Deploying application using Docker Compose..."
    
    local compose_dir="${SCRIPT_DIR}/../compose"
    
    if [[ ! -f "$compose_dir/docker-compose.yml" ]]; then
        error "Docker Compose configuration not found. Please run create configuration first."
        return 1
    fi
    
    cd "$compose_dir"
    
    # Pull latest images
    log "Pulling Docker images..."
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose pull
    else
        docker compose pull
    fi
    
    # Start services
    log "Starting services..."
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose up -d
    else
        docker compose up -d
    fi
    
    # Wait for services to be healthy
    log "Waiting for services to be ready..."
    sleep 30
    
    # Check service status
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose ps
    else
        docker compose ps
    fi
    
    info "Application deployment completed"
    info "Access the application at: http://${APP_DOMAIN}:${APP_PORT}"
}

# Stop and remove application
stop_application() {
    log "Stopping application..."
    
    local compose_dir="${SCRIPT_DIR}/../compose"
    
    if [[ ! -f "$compose_dir/docker-compose.yml" ]]; then
        error "Docker Compose configuration not found"
        return 1
    fi
    
    cd "$compose_dir"
    
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose down
    else
        docker compose down
    fi
    
    info "Application stopped"
}

# Show application status
show_status() {
    log "Checking application status..."
    
    local compose_dir="${SCRIPT_DIR}/../compose"
    
    if [[ ! -f "$compose_dir/docker-compose.yml" ]]; then
        error "Docker Compose configuration not found"
        return 1
    fi
    
    cd "$compose_dir"
    
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose ps
        echo
        docker-compose logs --tail=20
    else
        docker compose ps
        echo
        docker compose logs --tail=20
    fi
}

# Show script usage
show_usage() {
    cat <<EOF
Usage: $0 [command] [options]

Commands:
  install           Install Docker and Docker Compose
  configure         Configure Docker daemon
  create-config     Create Docker Compose configuration
  deploy            Deploy the application
  stop              Stop the application
  status            Show application status
  restart           Restart the application
  logs              Show application logs
  clean             Clean up Docker resources
  help              Show this help message

Environment Variables:
  DOCKER_VERSION              Docker version (default: latest)
  DOCKER_COMPOSE_VERSION      Docker Compose version (default: v2.24.5)
  DOCKER_MIRROR              Mirror source (default: cn)
  DOCKER_DATA_ROOT           Docker data directory (default: /var/lib/docker)
  DOCKER_REGISTRY_MIRRORS    Registry mirrors (comma-separated)
  APP_NAME                   Application name (default: mcpcan)
  APP_VERSION                Application version (default: v1.1.0-dev)
  APP_DOMAIN                 Application domain (default: localhost)
  APP_PORT                   Application HTTP port (default: 80)
  APP_SSL_PORT               Application HTTPS port (default: 443)
  COMPOSE_PROJECT_NAME       Docker Compose project name (default: mcpcan)

Examples:
  $0 install                 # Install Docker and Docker Compose
  $0 deploy                  # Deploy the application
  $0 status                  # Check application status
  APP_DOMAIN=example.com $0 deploy  # Deploy with custom domain
EOF
}

# Main function
main() {
    case "${1:-}" in
        install)
            check_system_requirements
            install_docker
            configure_docker
            verify_docker_installation
            ;;
        configure)
            configure_docker
            ;;
        create-config)
            create_docker_compose_config
            create_additional_configs
            ;;
        deploy)
            check_system_requirements
            if ! command -v docker >/dev/null 2>&1; then
                warn "Docker not found, installing..."
                install_docker
                configure_docker
            fi
            create_docker_compose_config
            create_additional_configs
            deploy_application
            ;;
        stop)
            stop_application
            ;;
        status)
            show_status
            ;;
        restart)
            stop_application
            sleep 5
            deploy_application
            ;;
        logs)
            local compose_dir="${SCRIPT_DIR}/../compose"
            cd "$compose_dir"
            if command -v docker-compose >/dev/null 2>&1; then
                docker-compose logs -f
            else
                docker compose logs -f
            fi
            ;;
        clean)
            log "Cleaning up Docker resources..."
            docker system prune -f
            docker volume prune -f
            info "Docker cleanup completed"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            error "Unknown command: ${1:-}"
            echo
            show_usage
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi