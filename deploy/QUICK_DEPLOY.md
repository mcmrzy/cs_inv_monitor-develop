# 光伏逆变器监控系统 - 快速部署指南

## 方案一：使用 Git 推送（推荐）

### 步骤 1: 在服务器上初始化 Git 仓库

打开 PowerShell，执行以下命令：

```powershell
# SSH 登录服务器
ssh cskj@192.168.8.50
# 输入密码: cskj9527

# 在服务器上执行
sudo mkdir -p /opt/inv-mqtt
sudo chown cskj:cskj /opt/inv-mqtt
cd /opt/inv-mqtt
git init --bare
exit
```

### 步骤 2: 在本地推送代码

```powershell
# 进入项目目录
cd d:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop

# 添加服务器为远程仓库
git remote add deploy ssh://cskj@192.168.8.50/opt/inv-mqtt

# 推送代码
git push deploy main
# 输入密码: cskj9527
```

### 步骤 3: 在服务器上部署

```powershell
# SSH 登录服务器
ssh cskj@192.168.8.50
# 输入密码: cskj9527

# 在服务器上执行
cd /opt
git clone /opt/inv-mqtt inv-mqtt-work
cd inv-mqtt-work/deploy

# 创建环境配置
cat > .env << 'EOF'
DB_HOST=postgres
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=InvMonitor@2026!Secure
DB_NAME=inv_mqtt
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=RCq/G7b4T00dt5bprW7o34c/OOgPHPKe55Iwz3GvQYQ=
JWT_SECRET=fq2T9il2RpZpSmUH1pLbV4cIwaEWypg3wjT629+GPeassiiW6A+wXdC+4jennVyN
API_SERVER_URL=http://inv-api-server:8080
DEVICE_SERVER_URL=http://inv-device-server:8081
INTERNAL_KEY=inv-monitor-internal-secret-2026
MQTT_BROKER=jiuxiaoyw.online
MQTT_PORT=8883
MQTT_CLIENT_ID=CSKJ-INV-SERVER-DEVICE-LOCAL
MQTT_USERNAME=CSKJ-INV-SERVER-DEVICE
MQTT_PASSWORD=CSKJINVSERVERDEVICE
MQTT_TLS_INSECURE=true
EMAIL_HOST=smtp.qq.com
EMAIL_PORT=465
EMAIL_USER=sunhaoyu0221@qq.com
EMAIL_PASS=uqcomryxtnimbeha
EMAIL_FROM=sunhaoyu0221@qq.com
EOF

# 启动服务
docker-compose up -d --build

# 检查状态
docker ps
```

## 方案二：直接 SCP 上传

```powershell
# 进入项目目录
cd d:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop

# 上传整个项目到服务器
scp -r . cskj@192.168.8.50:/opt/inv-mqtt/
# 输入密码: cskj9527

# SSH 登录服务器部署
ssh cskj@192.168.8.50
# 输入密码: cskj9527

# 在服务器上执行
cd /opt/inv-mqtt/deploy
docker-compose up -d --build
docker ps
```

## 访问地址

- API 网关: http://192.168.8.50:8888
- 管理后台: http://192.168.8.50:3000
- Grafana: http://192.168.8.50:3001
- Prometheus: http://192.168.8.50:9090

## 后续更新

```powershell
# 本地推送更新
git push deploy main

# 服务器部署
ssh cskj@192.168.8.50 "cd /opt/inv-mqtt-work && git pull && cd deploy && docker-compose up -d --build"
```
