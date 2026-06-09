# INV-MQTT 部署指南

## 目录
- [手动部署](#手动部署)
- [Webhook 自动部署](#webhook-自动部署)
- [Git Polling 自动部署](#git-polling-自动部署)
- [服务监控](#服务监控)

---

## 手动部署

### 1. 服务器准备

```bash
# 安装依赖 (Ubuntu/Debian)
apt update && apt install -y \
    golang-go \
    nodejs \
    npm \
    nginx \
    postgresql-client \
    redis-tools \
    git \
    nc

# 安装 Go (如果版本过旧)
wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
```

### 2. 首次部署

```bash
# 创建目录
mkdir -p /opt/inv-mqtt /var/log/inv-mqtt /var/www/inv-admin
cd /opt/inv-mqtt

# 克隆仓库
git clone -b main https://your-git-repo/inv-mqtt.git .

# 执行部署脚本
chmod +x deploy/deploy.sh
./deploy/deploy.sh --all
```

### 3. 日常部署

```bash
# SSH 到服务器
ssh root@your-server

# 拉取更新并部署
cd /opt/inv-mqtt
git pull origin main
./deploy/deploy.sh --all

# 或选择性部署
./deploy/deploy.sh --api      # 只部署 API 服务
./deploy/deploy.sh --frontend # 只部署前端
./deploy/deploy.sh --restart  # 只重启服务

# 查看日志
./deploy/deploy.sh --logs
```

---

## Webhook 自动部署

适合服务器可以暴露端口（如通过 Nginx 反向代理）的环境。

### 1. 配置 Webhook 服务

```bash
# 复制服务文件
cp /opt/inv-mqtt/deploy/inv-webhook.service /etc/systemd/system/
cp /opt/inv-mqtt/deploy/webhook_server.py /opt/inv-mqtt/deploy/

# 安装 Python 依赖
pip3 install flask

# 启动服务
systemctl daemon-reload
systemctl enable inv-webhook
systemctl start inv-webhook
```

### 2. 配置 Nginx 反向代理

```nginx
server {
    listen 80;
    server_name your-domain.com;

    location /webhook/ {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Gitlab-Token YOUR_SECRET;
    }
}
```

### 3. 配置 GitLab Webhook

1. 登录 GitLab → 项目 → Settings → Webhooks
2. URL: `https://your-domain.com/webhook/`
3. Secret token: `YOUR_SECRET`（与 Nginx 配置一致）
4. 勾选: `Push events`, `Merge request events`
5. 点击 "Add webhook"

### 4. 配置 GitHub Webhook

1. 登录 GitHub → 项目 → Settings → Webhooks
2. Payload URL: `https://your-domain.com/webhook/`
3. Content type: `application/json`
4. Secret: `YOUR_SECRET`
5. 勾选: `Push`, `Pull requests`
6. 点击 "Add webhook"

### 5. 测试 Webhook

```bash
# 手动触发
curl -X POST https://your-domain.com/webhook/ \
  -H "Content-Type: application/json" \
  -H "X-Gitlab-Token: YOUR_SECRET" \
  -d '{"object_kind": "push", "ref": "refs/heads/main"}'

# 查看日志
journalctl -u inv-webhook -f
```

---

## Git Polling 自动部署

适合无法暴露 Webhook 端口的环境（如内网服务器）。

### 1. 配置定时任务

```bash
# 复制服务文件
cp /opt/inv-mqtt/deploy/inv-git-poll.service /etc/systemd/system/
cp /opt/inv-mqtt/deploy/inv-git-poll.timer /etc/systemd/system/
cp /opt/inv-mqtt/deploy/git-poll-deploy.sh /opt/inv-mqtt/deploy/
chmod +x /opt/inv-mqtt/deploy/git-poll-deploy.sh

# 启用定时器（每5分钟检查一次）
systemctl daemon-reload
systemctl enable inv-git-poll.timer
systemctl start inv-git-poll.timer

# 查看定时器状态
systemctl list-timers inv-git-poll.timer
```

### 2. 手动检查

```bash
# 立即运行一次检查
systemctl start inv-git-poll.service

# 查看日志
tail -f /var/log/inv-mqtt/git-poll.log
```

---

## 服务监控

### 1. 配置监控服务

```bash
# 复制监控文件
cp /opt/inv-mqtt/deploy/inv-monitor.service /etc/systemd/system/
cp /opt/inv-mqtt/deploy/inv-monitor.timer /etc/systemd/system/
cp /opt/inv-mqtt/deploy/monitor.sh /opt/inv-mqtt/deploy/
chmod +x /opt/inv-mqtt/deploy/monitor.sh

# 启用监控（每分钟检查一次）
systemctl daemon-reload
systemctl enable inv-monitor.timer
systemctl start inv-monitor.timer
```

### 2. 查看监控状态

```bash
# 查看所有定时器
systemctl list-timers --all | grep inv-

# 查看监控日志
tail -f /var/log/inv-mqtt/monitor.log

# 查看服务状态
systemctl status inv-api-server
systemctl status inv-device-server
systemctl status inv-api-gateway
```

---

## 常用维护命令

```bash
# 查看所有 INV 服务状态
systemctl list-units 'inv-*' --all

# 重启所有服务
systemctl restart inv-api-server inv-device-server inv-api-gateway nginx

# 查看实时日志
journalctl -u inv-api-server -f
journalctl -u inv-device-server -f
journalctl -u inv-api-gateway -f

# 查看 Nginx 日志
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log

# 查看应用日志
tail -f /var/log/inv-mqtt/inv_api_server.log
tail -f /var/log/inv-mqtt/inv_device_server.log

# 回滚到上一个版本
cd /opt/inv-mqtt
git revert HEAD
./deploy/deploy.sh --all
```

---

## 故障排除

### 服务无法启动

```bash
# 查看详细错误
journalctl -xe -u inv-api-server

# 手动运行查看输出
/opt/inv-mqtt/inv_api_server -config /opt/inv-mqtt/inv_api_server/config.docker.yaml
```

### 数据库连接失败

```bash
# 检查 PostgreSQL
psql -h localhost -U postgres -d inv_mqtt -c "SELECT 1"

# 检查 Redis
redis-cli -h localhost ping
```

### 前端加载白屏

```bash
# 检查 Nginx 配置
nginx -t

# 检查静态文件权限
ls -la /var/www/inv-admin/

# 查看 Nginx 错误日志
tail -50 /var/log/nginx/error.log
```
