#!/bin/bash
# download.jiuxiaoyw.online 下载站点部署脚本

set -e

echo "=== 辰烁光伏 APP 下载站点部署 ==="

# 检查是否安装了 Docker
if ! command -v docker &> /dev/null; then
    echo "错误: 未安装 Docker"
    exit 1
fi

# 检查 docker compose 命令
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif docker-compose --version &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    echo "错误: 未安装 Docker Compose"
    exit 1
fi

# 进入部署目录
cd "$(dirname "$0")"

# 检查必要文件
echo "检查必要文件..."
if [ ! -f "web/download.html" ]; then
    echo "错误: 缺少下载页面 web/download.html"
    exit 1
fi

if [ ! -f "web/apk/app-release.apk" ]; then
    echo "错误: 缺少 APK 文件 web/apk/app-release.apk"
    exit 1
fi

# 申请 SSL 证书（如果还没有）
if [ ! -d "/etc/letsencrypt/live/download.jiuxiaoyw.online" ]; then
    echo "SSL 证书不存在，正在申请..."
    if command -v certbot &> /dev/null; then
        sudo certbot certonly --standalone -d download.jiuxiaoyw.online --agree-tos --email admin@jiuxiaoyw.online --no-eff-email
    else
        echo "警告: 未安装 certbot，请手动申请 SSL 证书"
        echo "  certbot certonly --standalone -d download.jiuxiaoyw.online"
        echo ""
        echo "或者修改 nginx-download.conf 使用 HTTP 模式"
    fi
fi

# 启动服务
echo "启动下载站点..."
$COMPOSE_CMD -f docker-compose.download.yml up -d

# 检查状态
echo ""
echo "部署完成！"
echo ""
$COMPOSE_CMD -f docker-compose.download.yml ps

echo ""
echo "访问地址: https://download.jiuxiaoyw.online"
echo "APK 下载: https://download.jiuxiaoyw.online/apk/app-release.apk"
