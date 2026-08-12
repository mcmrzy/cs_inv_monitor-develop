# 光伏逆变器监控系�?- 快速部署指�?

## 方案一：使�?Git 推送（推荐�?

### 步骤 1: 在服务器上初始化 Git 仓库

打开 PowerShell，执行以下命令：

```powershell
# SSH 登录服务�?
ssh cskj@example.invalid
# 输入密码: CHANGE_ME_ROTATE_CREDENTIAL

# 在服务器上执�?
sudo mkdir -p /opt/inv-mqtt
sudo chown cskj:cskj /opt/inv-mqtt
cd /opt/inv-mqtt
git init --bare
exit
```

### 步骤 2: 在本地推送代�?

```powershell
# 进入项目目录
cd d:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop

# 添加服务器为远程仓库
git remote add deploy ssh://cskj@example.invalid/opt/inv-mqtt

# 推送代�?
git push deploy main
# 输入密码: CHANGE_ME_ROTATE_CREDENTIAL
```

### 步骤 3: 在服务器上部�?

```powershell
# SSH 登录服务�?
ssh cskj@example.invalid
# 输入密码: CHANGE_ME_ROTATE_CREDENTIAL

# 在服务器上执�?
cd /opt
git clone /opt/inv-mqtt inv-mqtt-work
cd inv-mqtt-work/deploy

# 创建环境配置
cat > .env << 'EOF'
DB_HOST=postgres
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=CHANGE_ME_ROTATE_CREDENTIAL
DB_NAME=inv_mqtt
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=CHANGE_ME_STRONG_REDIS_PASSWORD
JWT_SECRET=CHANGE_ME_ROTATE_CREDENTIAL
API_SERVER_URL=http://inv-api-server:8080
DEVICE_SERVER_URL=http://inv-device-server:8081
INTERNAL_KEY=CHANGE_ME_INTERNAL_SECRET
MQTT_BROKER=jiuxiaoyw.online
MQTT_PORT=8883
MQTT_CLIENT_ID=CSKJ-INV-SERVER-DEVICE-LOCAL
MQTT_USERNAME=CSKJ-INV-SERVER-DEVICE
MQTT_PASSWORD=CHANGE_ME_ROTATE_CREDENTIAL
MQTT_TLS_INSECURE=false  # standard CA verification (no fingerprint pinning)
EMAIL_HOST=smtp.qq.com
EMAIL_PORT=465
EMAIL_USER=ops@example.invalid
EMAIL_PASS=CHANGE_ME_ROTATE_CREDENTIAL
EMAIL_FROM=ops@example.invalid
EOF

# 启动服务
docker-compose up -d --build

# 检查状�?
docker ps
```

## 方案二：直接 SCP 上传

```powershell
# 进入项目目录
cd d:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop

# 上传整个项目到服务器
scp -r . cskj@example.invalid:/opt/inv-mqtt/
# 输入密码: CHANGE_ME_ROTATE_CREDENTIAL

# SSH 登录服务器部�?
ssh cskj@example.invalid
# 输入密码: CHANGE_ME_ROTATE_CREDENTIAL

# 在服务器上执�?
cd /opt/inv-mqtt/deploy
docker-compose up -d --build
docker ps
```

## 访问地址

- API 网关: http://example.invalid:8888
- 管理后台: http://example.invalid:3000
- Grafana: http://example.invalid:3001
- Prometheus: http://example.invalid:9090

## 后续更新

```powershell
# 本地推送更�?
git push deploy main

# 服务器部�?
ssh cskj@example.invalid "cd /opt/inv-mqtt-work && git pull && cd deploy && docker-compose up -d --build"
```
