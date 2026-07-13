# Git 部署脚本 - 推送服务到服务器
# 服务器: cskj@192.168.8.50

$SERVER = "cskj@192.168.8.50"
$PASSWORD = "REDACTED_ROTATE_CREDENTIAL"
$REMOTE_DIR = "/opt/inv-mqtt"
$GIT_REPO = "https://github.com/your-username/cs_inv_monitor.git"  # 修改为你的 Git 仓库地址

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "光伏逆变器监控系统 - Git部署" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 创建部署脚本内容
$deployScript = @"
#!/bin/bash
set -e

echo "========================================"
echo "开始部署光伏逆变器监控系统"
echo "========================================"

# 创建目录
mkdir -p $REMOTE_DIR
cd $REMOTE_DIR

# 检查是否已初始化 Git
if [ -d ".git" ]; then
    echo "[1/4] 更新代码..."
    git fetch origin
    git reset --hard origin/main
else
    echo "[1/4] 克隆仓库..."
    git clone $GIT_REPO .
fi

# 进入部署目录
cd deploy

# 创建 .env 文件（如果不存在）
if [ ! -f ".env" ]; then
    echo "[2/4] 创建环境配置文件..."
    cat > .env << 'ENVEOF'
# Database
DB_HOST=postgres
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=REDACTED_ROTATE_CREDENTIAL
DB_NAME=inv_mqtt

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=RCq/G7b4T00dt5bprW7o34c/OOgPHPKe55Iwz3GvQYQ=

# JWT
JWT_SECRET=REDACTED_ROTATE_CREDENTIAL

# API Gateway
API_SERVER_URL=http://inv-api-server:8080
DEVICE_SERVER_URL=http://inv-device-server:8081
INTERNAL_KEY=inv-monitor-internal-secret-2026

# MQTT Broker
MQTT_BROKER=jiuxiaoyw.online
MQTT_PORT=8883
MQTT_CLIENT_ID=CSKJ-INV-SERVER-DEVICE-LOCAL
MQTT_USERNAME=CSKJ-INV-SERVER-DEVICE
MQTT_PASSWORD=REDACTED_ROTATE_CREDENTIAL
MQTT_TLS_INSECURE=true

# Kafka
KAFKA_BROKER=kafka:29092
KAFKA_TELEMETRY_TOPIC=inv-telemetry
KAFKA_ALARM_TOPIC=inv-alerts
KAFKA_COMMAND_TOPIC=inv-commands

# Email
EMAIL_HOST=smtp.qq.com
EMAIL_PORT=465
EMAIL_USER=sunhaoyu0221@qq.com
EMAIL_PASS=REDACTED_ROTATE_CREDENTIAL
EMAIL_FROM=sunhaoyu0221@qq.com
ENVEOF
else
    echo "[2/4] 使用现有环境配置文件"
fi

# 停止现有服务
echo "[3/4] 停止现有服务..."
docker-compose down

# 启动服务
echo "[4/4] 启动服务..."
docker-compose up -d --build

# 等待服务启动
sleep 10

# 检查服务状态
echo ""
echo "========================================"
echo "服务状态:"
echo "========================================"
docker ps

echo ""
echo "========================================"
echo "部署完成！"
echo "访问地址: http://192.168.8.50:8888"
echo "========================================"
"@

# 将部署脚本写入临时文件
$tempScript = [System.IO.Path]::GetTempFileName() + ".sh"
$deployScript | Out-File -FilePath $tempScript -Encoding UTF8

Write-Host "[1/3] 上传部署脚本到服务器..." -ForegroundColor Green
Write-Host "请在弹出的终端中输入密码: $PASSWORD" -ForegroundColor Yellow
scp -o StrictHostKeyChecking=no $tempScript ${SERVER}:/tmp/deploy.sh

Write-Host "[2/3] 执行部署脚本..." -ForegroundColor Green
Write-Host "请在弹出的终端中输入密码: $PASSWORD" -ForegroundColor Yellow
ssh -o StrictHostKeyChecking=no $SERVER "chmod +x /tmp/deploy.sh && bash /tmp/deploy.sh"

# 清理临时文件
Remove-Item $tempScript -Force -ErrorAction SilentlyContinue

Write-Host "[3/3] 部署完成!" -ForegroundColor Green
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "部署完成！" -ForegroundColor Green
Write-Host "访问地址: http://192.168.8.50:8888" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
