# download.jiuxiaoyw.online 下载站点配置指南

## 概述

下载页面已集成到管理后台前端，路径为 `/download`。版本信息通过后端 OTA 接口获取，与管理后台的 App 版本管理完全联动。

## 架构

```
用户访问 download.jiuxiaoyw.online
         │
         ▼
   Nginx 反向代理
         │
         ├─ /download ──→ inv-admin-frontend:8080 (React SPA)
         │                      │
         │                      └─ /api/ota/app/check ──→ 获取最新版本
         │
         └─ /api/* ────→ api-gateway:8080
```

## 部署方式

### 方式1：添加到现有 Nginx 配置（推荐）

如果已经在运行主服务，只需将下载站点配置添加到主 Nginx：

1. **复制配置文件到 Nginx 容器挂载目录**

```bash
# 在服务器上执行
cp deploy/configs/nginx-download.conf /path/to/nginx/conf.d/download.conf
```

2. **修改配置中的上游地址**（如果主服务在同一 Docker 网络）

将配置中的 `inv-admin-frontend:8080` 和 `api-gateway:8080` 修改为实际的服务地址。

3. **申请 SSL 证书**

```bash
# 如果使用 Let's Encrypt
sudo certbot certonly --nginx -d download.jiuxiaoyw.online

# 或者使用已有证书，更新配置中的证书路径
```

4. **重新加载 Nginx 配置**

```bash
docker exec nginx nginx -s reload
```

### 方式2：独立部署

如果下载站点需要独立部署在另一台服务器：

1. **上传文件到服务器**

```bash
# 上传必要文件
scp deploy/configs/nginx-download.conf user@server:/opt/download-site/configs/
scp deploy/docker-compose.download.yml user@server:/opt/download-site/
```

2. **配置上游地址**

编辑 `nginx-download.conf`，将 Docker 服务名改为实际的服务器地址：

```nginx
# 如果主服务在其他服务器
proxy_pass http://主服务器IP:3000;  # 前端
proxy_pass http://主服务器IP:8080;  # API 网关
```

3. **申请 SSL 证书**

```bash
sudo certbot certonly --standalone -d download.jiuxiaoyw.online
```

4. **启动服务**

```bash
cd /opt/download-site
docker compose -f docker-compose.download.yml up -d
```

## 版本管理联动

下载页面会自动从后端获取最新版本信息：

1. **在管理后台发布新版本**
   - 进入 "OTA 升级" → "App版本管理"
   - 点击 "创建新版本"
   - 填写版本信息并上传 APK
   - 设置下载链接（可使用 `/firmware/xxx.apk` 或外部链接）

2. **下载页面自动更新**
   - 用户访问 `https://download.jiuxiaoyw.online`
   - 页面调用 `/api/v1/ota/app/check?platform=android&version_code=0`
   - 自动显示最新版本号、文件大小、更新日志
   - 点击下载按钮直接下载 APK

## 访问地址

- 下载页面: `https://download.jiuxiaoyw.online`
- 管理后台: `https://your-admin-domain.com`
- 版本检查 API: `https://your-domain.com/api/v1/ota/app/check?platform=android`

## 测试验证

```bash
# 1. 测试域名解析
nslookup download.jiuxiaoyw.online

# 2. 测试 HTTPS 连接
curl -I https://download.jiuxiaoyw.online

# 3. 测试 API 接口
curl https://your-domain.com/api/v1/ota/app/check?platform=android&version_code=0

# 4. 测试下载页面
curl -L https://download.jiuxiaoyw.online/download | grep "辰烁光伏"
```

## 常见问题

### Q: 下载页面显示"暂无可用下载链接"

A: 需要在管理后台的 OTA → App版本管理中创建版本，并设置 `download_url` 字段。

### Q: SSL 证书申请失败

A: 确保 DNS 已正确解析到服务器 IP，且 80/443 端口未被占用。

### Q: 版本信息不更新

A: 检查 API 接口是否正常：
```bash
curl http://localhost:8080/api/v1/ota/app/check?platform=android
```

## 相关文件

- `inv-admin-frontend/src/pages/download/index.tsx` - 下载页面组件
- `deploy/configs/nginx-download.conf` - Nginx 配置
- `business-api/internal/handler/ota_handler.go` - OTA 接口（CheckAppUpdate）
