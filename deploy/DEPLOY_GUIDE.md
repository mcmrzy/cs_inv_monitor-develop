# 光伏逆变器监控系�?- 部署指南

## 部署方案选择

### 方案 A: Git 推送部署（推荐，支持增量更新）

#### 1. 设置 SSH 密钥（一次性操作）

�?PowerShell 中执行：

```powershell
# 生成 SSH 密钥
ssh-keygen -t rsa -b 4096 -f "$env:USERPROFILE\.ssh\id_rsa_deploy" -N '""'

# 查看公钥
Get-Content "$env:USERPROFILE\.ssh\id_rsa_deploy.pub"

# SSH 登录服务�?
ssh cskj@example.invalid
# 输入密码: CHANGE_ME_ROTATE_CREDENTIAL

# 在服务器上添加公�?
mkdir -p ~/.ssh
echo "你的公钥内容" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
exit
```

#### 2. 在服务器初始�?Git 仓库

```powershell
ssh cskj@example.invalid
# 输入密码: CHANGE_ME_ROTATE_CREDENTIAL

sudo mkdir -p /opt/inv-mqtt
sudo chown cskj:cskj /opt/inv-mqtt
cd /opt/inv-mqtt
git init --bare
exit
```

#### 3. 本地推送代�?

```powershell
cd d:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop

# 添加远程仓库
git remote add deploy ssh://cskj@example.invalid/opt/inv-mqtt

# 推送代�?
git push deploy main
```

#### 4. 服务器部�?

```powershell
ssh cskj@example.invalid

# 克隆代码
cd /opt
git clone /opt/inv-mqtt inv-mqtt-work
cd inv-mqtt-work/deploy

# 创建 .env 文件（内容见下方�?
cat > .env << 'EOF'
DB_HOST=postgres
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=CHANGE_ME_STRONG_PASSWORD
DB_NAME=inv_mqtt
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=CHANGE_ME_STRONG_REDIS_PASSWORD
JWT_SECRET=CHANGE_ME_GENERATE_WITH_OPENSSL
API_SERVER_URL=http://inv-api-server:8080
DEVICE_SERVER_URL=http://inv-device-server:8081
INTERNAL_KEY=CHANGE_ME_INTERNAL_SECRET
MQTT_BROKER=jiuxiaoyw.online
MQTT_PORT=8883
MQTT_CLIENT_ID=CSKJ-INV-SERVER-DEVICE-LOCAL
MQTT_USERNAME=CSKJ-INV-SERVER-DEVICE
MQTT_PASSWORD=CHANGE_ME_MQTT_PASSWORD
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

### 方案 B: SCP 直接上传（简单直接）

```powershell
cd d:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop

# 上传代码
scp -r . cskj@example.invalid:/opt/inv-mqtt/
# 输入密码: CHANGE_ME_ROTATE_CREDENTIAL

# SSH 登录部署
ssh cskj@example.invalid
cd /opt/inv-mqtt/deploy
docker-compose up -d --build
docker ps
```

## 服务访问地址

| 服务 | 地址 | 说明 |
|------|------|------|
| API 网关 | http://example.invalid:8888 | �?API 入口 |
| 管理后台 | http://example.invalid:3000 | Web 管理界面 |
| Grafana | http://example.invalid:3001 | 监控仪表�?|
| Prometheus | http://example.invalid:9090 | 指标监控 |

## 后续更新流程

```powershell
# 本地推送更�?
git push deploy main

# 服务器拉取并部署
ssh cskj@example.invalid "cd /opt/inv-mqtt-work && git pull && cd deploy && docker-compose up -d --build"
```

## 服务管理命令

```powershell
# 查看服务状�?
ssh cskj@example.invalid "docker ps"

# 查看日志
ssh cskj@example.invalid "docker logs business-api"
ssh cskj@example.invalid "docker logs device-communication"
ssh cskj@example.invalid "docker logs api-gateway"

# 重启服务
ssh cskj@example.invalid "cd /opt/inv-mqtt-work/deploy && docker-compose restart"

# 停止服务
ssh cskj@example.invalid "cd /opt/inv-mqtt-work/deploy && docker-compose down"
```

## 部署前置条件：强制清理旧容器

在每次部署前，建议先强制删除可能冲突的旧容器，避�?`Conflict. The container name is already in use` 错误�?

```bash
# 强制删除所有项目相关容器（即使不存在也不会报错�?
docker rm -f inv-admin-frontend api-gateway business-api device-communication inv-postgres inv-redis 2>/dev/null || true
```

> **说明**：`docker compose down --remove-orphans` 只能清理 compose 管理的容器，无法处理由旧�?compose 文件或手动创建的孤立容器。`docker rm -f` 可以确保所有同名容器被彻底清除�?

## 故障排查

1. **容器名冲�?*: 运行上方 `docker rm -f` 命令强制清理旧容�?
2. **端口冲突**: 检查端口是否被占用
3. **Docker 未启�?*: 确保 Docker 服务已启�?
4. **数据库连接失�?*: 检�?.env 中的数据库配�?
5. **MQTT 连接失败**: 检�?MQTT_BROKER 和端口配�?

## 环境变量说明

| 变量 | 说明 | 示例�?|
|------|------|--------|
| DB_PASSWORD | 数据库密�?| CHANGE_ME_STRONG_PASSWORD |
| REDIS_PASSWORD | Redis 密码 | CHANGE_ME_STRONG_REDIS_PASSWORD |
| JWT_SECRET | JWT 密钥 | CHANGE_ME_GENERATE_WITH_OPENSSL |
| MQTT_BROKER | MQTT 服务�?| jiuxiaoyw.online |
| MQTT_PASSWORD | MQTT 密码 | CHANGE_ME_MQTT_PASSWORD |
