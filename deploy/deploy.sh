#!/bin/bash

# INV-MQTT 部署脚本
# 用法: ./deploy.sh [options]
# Options:
#   --api        只部署 API 服务
#   --device     只部署设备服务
#   --frontend   只部署前端
#   --all        部署所有服务 (默认)
#   --restart    重启服务
#   --logs       查看日志

set -e

# 配置
APP_DIR="/opt/inv-mqtt"
GIT_REPO="https://your-git-repo/inv-mqtt.git"  # 修改为你的 Git 仓库地址
BRANCH="main"
LOG_DIR="/var/log/inv-mqtt"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 创建目录
mkdir -p "$APP_DIR" "$LOG_DIR"

# 解析参数
DEPLOY_API=true
DEPLOY_DEVICE=true
DEPLOY_FRONTEND=true
RESTART_SERVICES=false
SHOW_LOGS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --api) DEPLOY_DEVICE=false; DEPLOY_FRONTEND=false;;
        --device) DEPLOY_API=false; DEPLOY_FRONTEND=false;;
        --frontend) DEPLOY_API=false; DEPLOY_DEVICE=false;;
        --restart) RESTART_SERVICES=true;;
        --logs) SHOW_LOGS=true;;
        --all) ;;
        *) log_error "未知参数: $1"; exit 1;;
    esac
    shift
done

# 查看日志
if [ "$SHOW_LOGS" = true ]; then
    log_info "最近的日志:"
    tail -100 "$LOG_DIR"/*.log 2>/dev/null || log_warn "没有日志文件"
    exit 0
fi

cd "$APP_DIR"

# Git 拉取更新
if [ -d ".git" ]; then
    log_info "从 Git 拉取更新..."
    git stash
    git fetch origin
    git checkout "$BRANCH"
    git pull origin "$BRANCH"
else
    log_info "首次部署，克隆仓库..."
    git clone -b "$BRANCH" "$GIT_REPO" .
fi

# 编译 Go 服务
build_go_service() {
    local service=$1
    local name=$2
    log_info "编译 $name..."
    cd "$APP_DIR/$service"

    # 下载依赖
    go mod download

    # 编译
    CGO_ENABLED=0 GOOS=linux go build -o "$APP_DIR/$name" ./cmd/main.go

    if [ $? -eq 0 ]; then
        log_info "$name 编译成功"
    else
        log_error "$name 编译失败"
        return 1
    fi
}

# 部署 API 服务
if [ "$DEPLOY_API" = true ]; then
    build_go_service "inv_api_server" "inv_api_server"

    # 创建 systemd 服务
    cat > /etc/systemd/system/inv-api-server.service <<EOF
[Unit]
Description=INV API Server
After=network.target postgresql.service redis.service

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/inv_api_server -config $APP_DIR/inv_api_server/config.docker.yaml
Restart=always
RestartSec=5
StandardOutput=append:$LOG_DIR/inv_api_server.log
StandardError=append:$LOG_DIR/inv_api_server_error.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable inv-api-server
    systemctl restart inv-api-server
    log_info "API 服务已部署并启动"
fi

# 部署设备服务
if [ "$DEPLOY_DEVICE" = true ]; then
    build_go_service "inv_device_server" "inv_device_server"

    cat > /etc/systemd/system/inv-device-server.service <<EOF
[Unit]
Description=INV Device Server
After=network.target postgresql.service redis.service kafka.service

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/inv_device_server -config $APP_DIR/inv_device_server/config.docker.yaml
Restart=always
RestartSec=5
StandardOutput=append:$LOG_DIR/inv_device_server.log
StandardError=append:$LOG_DIR/inv_device_server_error.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable inv-device-server
    systemctl restart inv-device-server
    log_info "设备服务已部署并启动"
fi

# 部署 API 网关
if [ "$DEPLOY_API" = true ]; then
    build_go_service "api-gateway" "api-gateway"

    cat > /etc/systemd/system/inv-api-gateway.service <<EOF
[Unit]
Description=INV API Gateway
After=network.target inv-api-server.service

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/api-gateway -config $APP_DIR/api-gateway/config.docker.yaml
Restart=always
RestartSec=5
StandardOutput=append:$LOG_DIR/api_gateway.log
StandardError=append:$LOG_DIR/api_gateway_error.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable inv-api-gateway
    systemctl restart inv-api-gateway
    log_info "API 网关已部署并启动"
fi

# 部署前端
if [ "$DEPLOY_FRONTEND" = true ]; then
    log_info "部署前端..."
    cd "$APP_DIR/inv-admin-frontend"

    npm ci
    npm run build

    # 部署到 Nginx
    rm -rf /var/www/inv-admin
    mv dist /var/www/inv-admin

    cat > /etc/nginx/sites-available/inv-admin <<EOF
server {
    listen 80;
    server_name your-domain.com;  # 修改为你的域名

    root /var/www/inv-admin;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8080/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/inv-admin /etc/nginx/sites-enabled/
    nginx -t && systemctl reload nginx

    log_info "前端已部署"
fi

# 检查服务状态
log_info "服务状态:"
systemctl status inv-api-server --no-pager || true
systemctl status inv-device-server --no-pager || true
systemctl status inv-api-gateway --no-pager || true

log_info "部署完成!"
