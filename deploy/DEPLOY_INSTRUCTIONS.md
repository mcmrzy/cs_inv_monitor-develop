# 光伏逆变器监控系�?- 服务器部署指�?

## 部署步骤

### 1. 在服务器上初始化 Git 仓库

```bash
# SSH 登录服务�?
ssh cskj@example.invalid
# 密码: CHANGE_ME_ROTATE_CREDENTIAL

# 创建项目目录
sudo mkdir -p /opt/inv-mqtt
sudo chown cskj:cskj /opt/inv-mqtt

# 初始�?Git 仓库
cd /opt/inv-mqtt
git init --bare
```

### 2. 在本地添加远程仓库并推�?

```bash
# 在本地项目目�?
cd d:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop

# 添加服务器为远程仓库
git remote add deploy ssh://cskj@example.invalid/opt/inv-mqtt

# 推送代�?
git push deploy main
```

### 3. 在服务器上部�?

```bash
# SSH 登录服务�?
ssh cskj@example.invalid

# 克隆代码到工作目�?
cd /opt
git clone /opt/inv-mqtt inv-mqtt-work
cd inv-mqtt-work/deploy

# 创建环境配置文件
cat > .env << 'EOF'
# Database
DB_HOST=postgres
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=CHANGE_ME_ROTATE_CREDENTIAL
DB_NAME=inv_mqtt

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=CHANGE_ME_STRONG_REDIS_PASSWORD

# JWT
JWT_SECRET=CHANGE_ME_ROTATE_CREDENTIAL

# API Gateway
API_SERVER_URL=http://inv-api-server:8080
DEVICE_SERVER_URL=http://inv-device-server:8081
INTERNAL_KEY=CHANGE_ME_INTERNAL_SECRET

# MQTT Broker
MQTT_BROKER=jiuxiaoyw.online
MQTT_PORT=8883
MQTT_CLIENT_ID=CSKJ-INV-SERVER-DEVICE-LOCAL
MQTT_USERNAME=CSKJ-INV-SERVER-DEVICE
MQTT_PASSWORD=CHANGE_ME_ROTATE_CREDENTIAL
MQTT_TLS_INSECURE=false  # standard CA verification (no fingerprint pinning)

# Email
EMAIL_HOST=smtp.qq.com
EMAIL_PORT=465
EMAIL_USER=ops@example.invalid
EMAIL_PASS=CHANGE_ME_ROTATE_CREDENTIAL
EMAIL_FROM=ops@example.invalid
EOF

# 启动服务
docker-compose up -d --build

# 检查服务状�?
docker ps
```

### 4. 访问服务

- API 网关: http://example.invalid:8888
- 管理后台: http://example.invalid:3000
- Grafana: http://example.invalid:3001
- Prometheus: http://example.invalid:9090

## 快速部署脚�?

在服务器上创建部署脚本：

```bash
# 在服务器上创建部署脚�?
cat > /opt/deploy.sh << 'DEPLOYEOF'
#!/bin/bash
set -e

cd /opt/inv-mqtt-work/deploy

# 拉取最新代�?
cd /opt/inv-mqtt-work
git pull origin main
cd deploy

# 停止现有服务
docker-compose down

# 启动服务
docker-compose up -d --build

# 等待服务启动
sleep 10

# 检查服务状�?
docker ps

echo "部署完成�?
echo "访问地址: http://example.invalid:8888"
DEPLOYEOF

chmod +x /opt/deploy.sh
```

## 更新部署

```bash
# 在本地推送更�?
git push deploy main

# 在服务器上执行部�?
ssh cskj@example.invalid "bash /opt/deploy.sh"
```

## 服务管理命令

```bash
# 查看服务状�?
docker ps

# 查看服务日志
docker logs business-api
docker logs device-communication
docker logs api-gateway

# 重启服务
docker-compose restart

# 停止服务
docker-compose down
```
