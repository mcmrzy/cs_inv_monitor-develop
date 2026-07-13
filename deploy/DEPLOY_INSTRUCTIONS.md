# 光伏逆变器监控系统 - 服务器部署指南

## 部署步骤

### 1. 在服务器上初始化 Git 仓库

```bash
# SSH 登录服务器
ssh cskj@192.168.8.50
# 密码: REDACTED_ROTATE_CREDENTIAL

# 创建项目目录
sudo mkdir -p /opt/inv-mqtt
sudo chown cskj:cskj /opt/inv-mqtt

# 初始化 Git 仓库
cd /opt/inv-mqtt
git init --bare
```

### 2. 在本地添加远程仓库并推送

```bash
# 在本地项目目录
cd d:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop

# 添加服务器为远程仓库
git remote add deploy ssh://cskj@192.168.8.50/opt/inv-mqtt

# 推送代码
git push deploy main
```

### 3. 在服务器上部署

```bash
# SSH 登录服务器
ssh cskj@192.168.8.50

# 克隆代码到工作目录
cd /opt
git clone /opt/inv-mqtt inv-mqtt-work
cd inv-mqtt-work/deploy

# 创建环境配置文件
cat > .env << 'EOF'
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

# Email
EMAIL_HOST=smtp.qq.com
EMAIL_PORT=465
EMAIL_USER=sunhaoyu0221@qq.com
EMAIL_PASS=REDACTED_ROTATE_CREDENTIAL
EMAIL_FROM=sunhaoyu0221@qq.com
EOF

# 启动服务
docker-compose up -d --build

# 检查服务状态
docker ps
```

### 4. 访问服务

- API 网关: http://192.168.8.50:8888
- 管理后台: http://192.168.8.50:3000
- Grafana: http://192.168.8.50:3001
- Prometheus: http://192.168.8.50:9090

## 快速部署脚本

在服务器上创建部署脚本：

```bash
# 在服务器上创建部署脚本
cat > /opt/deploy.sh << 'DEPLOYEOF'
#!/bin/bash
set -e

cd /opt/inv-mqtt-work/deploy

# 拉取最新代码
cd /opt/inv-mqtt-work
git pull origin main
cd deploy

# 停止现有服务
docker-compose down

# 启动服务
docker-compose up -d --build

# 等待服务启动
sleep 10

# 检查服务状态
docker ps

echo "部署完成！"
echo "访问地址: http://192.168.8.50:8888"
DEPLOYEOF

chmod +x /opt/deploy.sh
```

## 更新部署

```bash
# 在本地推送更新
git push deploy main

# 在服务器上执行部署
ssh cskj@192.168.8.50 "bash /opt/deploy.sh"
```

## 服务管理命令

```bash
# 查看服务状态
docker ps

# 查看服务日志
docker logs inv-api-server
docker logs inv-device-server
docker logs inv-api-gateway

# 重启服务
docker-compose restart

# 停止服务
docker-compose down
```
