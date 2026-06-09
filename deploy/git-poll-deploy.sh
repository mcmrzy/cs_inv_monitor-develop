#!/bin/bash

# Git Polling 自动部署脚本
# 通过定时检查 Git 仓库更新实现自动部署
# 适用于无法暴露 Webhook 端口的环境

set -e

APP_DIR="/opt/inv-mqtt"
GIT_REPO="https://your-git-repo/inv-mqtt.git"  # 修改为你的仓库地址
BRANCH="main"
LAST_COMMIT_FILE="/var/lib/inv-mqtt/last_commit"
DEPLOY_LOG="/var/log/inv-mqtt/git-poll.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$DEPLOY_LOG"
}

cd "$APP_DIR"

# 初始化（首次运行）
if [ ! -d ".git" ]; then
    log "首次运行，克隆仓库..."
    git clone -b "$BRANCH" "$GIT_REPO" .
    git config core.filemode false
    git log -1 --format="%H" > "$LAST_COMMIT_FILE"
    log "仓库已克隆"
    exit 0
fi

# 获取远程最新提交
git fetch origin
REMOTE_COMMIT=$(git log origin/$BRANCH -1 --format="%H")

# 获取本地记录的提交
if [ -f "$LAST_COMMIT_FILE" ]; then
    LOCAL_COMMIT=$(cat "$LAST_COMMIT_FILE")
else
    LOCAL_COMMIT=""
fi

# 比较
if [ "$REMOTE_COMMIT" != "$LOCAL_COMMIT" ]; then
    log "检测到新提交: $REMOTE_COMMIT (本地: $LOCAL_COMMIT)"

    # 检查是否有部署正在进行
    if [ -f "/var/run/inv-mqtt/deploying" ]; then
        log "部署正在进行中，跳过"
        exit 0
    fi

    # 标记部署开始
    mkdir -p /var/run/inv-mqtt
    touch /var/run/inv-mqtt/deploying

    # 捕获 SIGTERM
    trap 'rm -f /var/run/inv-mqtt/deploying; exit 0' SIGTERM SIGINT

    # 更新到最新版本
    log "拉取更新..."
    git checkout $BRANCH
    git pull origin $BRANCH

    # 记录新提交
    echo "$REMOTE_COMMIT" > "$LAST_COMMIT_FILE"

    # 重新编译
    log "重新编译服务..."

    # API Server
    log "编译 inv_api_server..."
    cd "$APP_DIR/inv_api_server"
    go build -o "$APP_DIR/inv_api_server" ./cmd/main.go

    # Device Server
    log "编译 inv_device_server..."
    cd "$APP_DIR/inv_device_server"
    go build -o "$APP_DIR/inv_device_server" ./cmd/main.go

    # API Gateway
    log "编译 api_gateway..."
    cd "$APP_DIR/api_gateway"
    go build -o "$APP_DIR/api_gateway" ./cmd/main.go

    # 重启服务
    log "重启服务..."
    systemctl restart inv-api-server
    systemctl restart inv-device-server
    systemctl restart inv-api-gateway

    # 清理标记
    rm -f /var/run/inv-mqtt/deploying

    log "部署完成!"
else
    log "没有更新"
fi
