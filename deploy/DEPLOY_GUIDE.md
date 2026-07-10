# 光伏逆变器监控系统 - 部署指南

## 部署方案选择

### 方案 A: Git 推送部署（推荐，支持增量更新）

#### 1. 设置 SSH 密钥（一次性操作）

在 PowerShell 中执行：

```powershell
# 生成 SSH 密钥
ssh-keygen -t rsa -b 4096 -f "$env:USERPROFILE\.ssh\id_rsa_deploy" -N '""'

# 查看公钥
Get-Content "$env:USERPROFILE\.ssh\id_rsa_deploy.pub"

# SSH 登录服务器
ssh cskj@192.168.8.50
# 输入密码: cskj9527

# 在服务器上添加公钥
mkdir -p ~/.ssh
echo "你的公钥内容" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
exit
```

#### 2. 在服务器初始化 Git 仓库

```powershell
ssh cskj@192.168.8.50
# 输入密码: cskj9527

sudo mkdir -p /opt/inv-mqtt
sudo chown cskj:cskj /opt/inv-mqtt
cd /opt/inv-mqtt
git init --bare
exit
```

#### 3. 本地推送代码

```powershell
cd d:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop

# 添加远程仓库
git remote add deploy ssh://cskj@192.168.8.50/opt/inv-mqtt

# 推送代码
git push deploy main
```

#### 4. 服务器部署

```powershell
ssh cskj@192.168.8.50

# 克隆代码
cd /opt
git clone /opt/inv-mqtt inv-mqtt-work
cd inv-mqtt-work/deploy

# 创建 .env 文件（内容见下方）
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

### 方案 B: SCP 直接上传（简单直接）

```powershell
cd d:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop

# 上传代码
scp -r . cskj@192.168.8.50:/opt/inv-mqtt/
# 输入密码: cskj9527

# SSH 登录部署
ssh cskj@192.168.8.50
cd /opt/inv-mqtt/deploy
docker-compose up -d --build
docker ps
```

## 服务访问地址

| 服务 | 地址 | 说明 |
|------|------|------|
| API 网关 | http://192.168.8.50:8888 | 主 API 入口 |
| 管理后台 | http://192.168.8.50:3000 | Web 管理界面 |
| Grafana | http://192.168.8.50:3001 | 监控仪表盘 |
| Prometheus | http://192.168.8.50:9090 | 指标监控 |

## 后续更新流程

```powershell
# 本地推送更新
git push deploy main

# 服务器拉取并部署
ssh cskj@192.168.8.50 "cd /opt/inv-mqtt-work && git pull && cd deploy && docker-compose up -d --build"
```

## 服务管理命令

```powershell
# 查看服务状态
ssh cskj@192.168.8.50 "docker ps"

# 查看日志
ssh cskj@192.168.8.50 "docker logs inv-api-server"
ssh cskj@192.168.8.50 "docker logs inv-device-server"
ssh cskj@192.168.8.50 "docker logs inv-api-gateway"

# 重启服务
ssh cskj@192.168.8.50 "cd /opt/inv-mqtt-work/deploy && docker-compose restart"

# 停止服务
ssh cskj@192.168.8.50 "cd /opt/inv-mqtt-work/deploy && docker-compose down"
```

## 部署前置条件：强制清理旧容器

在每次部署前，建议先强制删除可能冲突的旧容器，避免 `Conflict. The container name is already in use` 错误：

```bash
# 强制删除所有项目相关容器（即使不存在也不会报错）
docker rm -f inv-admin-frontend inv-api-gateway inv-api-server inv-device-server inv-postgres inv-redis 2>/dev/null || true
```

> **说明**：`docker compose down --remove-orphans` 只能清理 compose 管理的容器，无法处理由旧版 compose 文件或手动创建的孤立容器。`docker rm -f` 可以确保所有同名容器被彻底清除。

## 故障排查

1. **容器名冲突**: 运行上方 `docker rm -f` 命令强制清理旧容器
2. **端口冲突**: 检查端口是否被占用
3. **Docker 未启动**: 确保 Docker 服务已启动
4. **数据库连接失败**: 检查 .env 中的数据库配置
5. **MQTT 连接失败**: 检查 MQTT_BROKER 和端口配置

## 环境变量说明

| 变量 | 说明 | 示例值 |
|------|------|--------|
| DB_PASSWORD | 数据库密码 | InvMonitor@2026!Secure |
| REDIS_PASSWORD | Redis 密码 | RCq/G7b4T00dt5bprW7o34c/OOgPHPKe55Iwz3GvQYQ= |
| JWT_SECRET | JWT 密钥 | fq2T9il2RpZpSmUH1pLbV4cIwaEWypg3wjT629+GPeassiiW6A+wXdC+4jennVyN |
| MQTT_BROKER | MQTT 服务器 | jiuxiaoyw.online |
| MQTT_PASSWORD | MQTT 密码 | CSKJINVSERVERDEVICE |
