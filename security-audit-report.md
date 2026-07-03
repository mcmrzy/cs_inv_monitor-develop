# 光伏逆变器物联网监控平台安全评估报告

## 评估概述

**评估日期**: 2026年7月3日  
**评估范围**: 全平台（API网关、API服务器、设备服务器、前端应用、数据库、MQTT通信）  
**总体安全评分**: 5/10（基础认证机制良好，但存在多个严重配置问题）

---

## 一、高危问题（需要立即修复）

### 1. CORS 配置允许所有来源
**位置**: `api-gateway/internal/middleware/cors.go:11`

```go
c.Header("Access-Control-Allow-Origin", "*")
c.Header("Access-Control-Allow-Credentials", "true")
```

**风险**: 
- 允许任意来源携带凭证（Cookie）意味着任何网站都可以发起跨域请求读取用户数据
- 可导致 CSRF 攻击和数据泄露

**修复建议**:
```go
func CORS(allowedOrigins []string) gin.HandlerFunc {
    originSet := make(map[string]bool, len(allowedOrigins))
    for _, o := range allowedOrigins {
        originSet[o] = true
    }
    return func(c *gin.Context) {
        origin := c.GetHeader("Origin")
        if originSet[origin] {
            c.Header("Access-Control-Allow-Origin", origin)
        }
        c.Header("Access-Control-Allow-Credentials", "true")
        // ...
    }
}
```

### 2. JWT 密钥硬编码且使用弱默认值
**位置**: `deploy/.env:18`

```
JWT_SECRET=inv-monitor-jwt-secret-key-2026-production-change-me
```

**风险**:
- 生产环境使用可预测的弱密钥
- 攻击者可伪造任意用户的 JWT Token
- 完全绕过认证系统

**修复建议**:
```bash
# 生成强密钥
openssl rand -base64 48

# 更新 .env
JWT_SECRET=K7gNU3sdo+OL0wNhqoVWhr3g6s1xYv72ol/pe/Unols=
```

### 3. Redis 无密码保护
**位置**: `deploy/.env:15`

```
REDIS_PASSWORD=
```

**风险**:
- Redis 端口暴露且无密码，任何能访问该端口的人可直接操作数据库
- 可用于存储恶意数据、窃取会话信息

**修复建议**:
```bash
# 生成强密码
openssl rand -base64 32

# 更新配置
REDIS_PASSWORD=your_strong_redis_password_here
```

### 4. PostgreSQL 端口暴露
**位置**: `deploy/docker-compose.yml`

**风险**:
- 数据库端口暴露到宿主机，如果服务器有公网 IP，数据库将直接暴露在互联网上

**修复建议**:
```yaml
# 生产环境配置
postgres:
  expose:
    - "5432"
  # 不暴露端口，仅通过 Docker 内部网络访问
```

### 5. TLS 证书验证禁用
**位置**: `deploy/.env:31`

```
MQTT_TLS_INSECURE=true
```

**风险**:
- 禁用 TLS 证书验证使得中间人攻击（MITM）成为可能
- 攻击者可截获和篡改 MQTT 通信数据

**修复建议**:
```bash
MQTT_TLS_INSECURE=false
MQTT_CA_CERT=/path/to/ca.crt
```

---

## 二、中危问题（建议尽快修复）

### 1. 前端 Token 存储在 localStorage
**位置**: `inv-admin-frontend/src/stores/authStore.ts:54-63`

**风险**:
- localStorage 可被任何 JavaScript 代码访问
- XSS 攻击可直接窃取 Token

**修复建议**:
- 使用 sessionStorage 或完全依赖 httpOnly Cookie

### 2. HTTPOnly Cookie 的 Secure 标志未设置
**位置**: `inv_api_server/internal/handler/auth_handler.go:24-26`

**风险**:
- Cookie 可通过 HTTP 明文传输
- 在非 HTTPS 环境下可被网络嗅探工具截获

**修复建议**:
```go
// 生产环境设置 Secure=true
c.SetCookie("access_token", accessToken, int(accessExpire.Seconds()), "/", "", isProduction, true)
```

### 3. Nginx 仅监听 HTTP（无 HTTPS）
**位置**: `deploy/nginx.conf`

**风险**:
- 所有数据（包括密码、Token）以明文传输

**修复建议**:
```nginx
server {
    listen 443 ssl http2;
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
}
```

### 4. 缺少安全响应头
**缺失的安全头**:
- `X-Frame-Options`: 防止点击劫持
- `Content-Security-Policy`: 防止 XSS
- `X-Content-Type-Options`: 防止 MIME 类型嗅探
- `Strict-Transport-Security`: 强制 HTTPS

**修复建议**:
```go
func SecurityHeaders() gin.HandlerFunc {
    return func(c *gin.Context) {
        c.Header("X-Frame-Options", "DENY")
        c.Header("X-Content-Type-Options", "nosniff")
        c.Header("X-XSS-Protection", "1; mode=block")
        c.Header("Referrer-Policy", "strict-origin-when-cross-origin")
        c.Next()
    }
}
```

### 5. 邮箱密码明文存储在配置文件
**位置**: `deploy/.env:43`

```
EMAIL_PASS=uqcomryxtnimbeha
```

**风险**:
- SMTP 授权码明文存储
- 配置文件泄露可导致邮箱被盗用

**修复建议**:
- 使用环境变量而非硬编码
- 使用密钥管理服务存储敏感信息

---

## 三、低危问题（可以计划修复）

### 1. 数据库连接未使用 SSL
**位置**: `inv_api_server/config.docker.yaml:13`

```yaml
database:
  ssl_mode: disable
```

**修复建议**:
```yaml
database:
  ssl_mode: require
```

### 2. 服务间通信使用明文 HTTP
**修复建议**: 为内部服务配置 mTLS（双向 TLS）

### 3. 登录失败次数限制基于账号而非 IP
**修复建议**: 组合限制：账号 + IP

### 4. 缺少请求体大小限制
**修复建议**: 设置 `MaxMultipartMemory` 限制

---

## 四、安全评分总结

| 类别 | 当前状态 | 风险等级 |
|------|---------|---------|
| 认证与授权 | ✅ 良好（JWT + RBAC + bcrypt） | 低 |
| 密码安全 | ✅ 良好（bcrypt 哈希） | 低 |
| 登录保护 | ✅ 良好（失败次数限制） | 低 |
| CORS 配置 | ❌ 严重问题 | 高 |
| TLS/HTTPS | ❌ 严重问题 | 高 |
| 密钥管理 | ❌ 严重问题 | 高 |
| Redis 安全 | ❌ 严重问题 | 高 |
| 安全头 | ⚠️ 缺失 | 中 |
| Token 存储 | ⚠️ 风险 | 中 |
| 日志安全 | ⚠️ 需改进 | 低 |

---

## 五、优先修复清单

### 立即修复（24小时内）
1. 修复 CORS 配置，限制允许的来源
2. 更换 JWT 密钥为强随机值
3. 为 Redis 设置强密码并移除端口暴露
4. 移除 PostgreSQL 端口暴露

### 一周内修复
5. 部署 HTTPS/TLS
6. 启用 MQTT TLS 证书验证
7. 添加安全响应头
8. 移除配置文件中的明文密码

### 一个月内完成
9. 实施密钥管理最佳实践
10. 部署 WAF 和监控系统
11. 完善审计日志系统
12. 进行渗透测试

---

## 六、安全最佳实践建议

### 密钥管理
- 使用密钥管理服务（AWS Secrets Manager、HashiCorp Vault）
- 定期（每 90 天）更换 JWT 密钥
- 开发、测试、生产环境使用不同密钥

### 认证增强
- 为管理员账号启用多因素认证（MFA）
- 强制要求密码复杂度
- 实现会话超时和并发会话限制

### 网络安全
- 部署 Web 应用防火墙（WAF）
- 将数据库、缓存等内部服务放在独立的网络段
- 管理后台通过 VPN 访问

### 监控与审计
- 记录所有敏感操作的审计日志
- 监控异常登录行为
- 部署入侵检测系统（IDS/IPS）

### 代码安全
- 对所有用户输入进行严格验证和清理
- 使用参数化查询防止 SQL 注入（当前已实现 ✅）
- 定期检查依赖库的安全漏洞

---

## 七、当前安全优势

项目在以下方面做得很好：

1. **密码安全**: 使用 bcrypt 进行密码哈希，符合行业标准
2. **JWT 实现**: 支持 access_token/refresh_token 双 token 机制，有 jti 用于 token 撤销
3. **RBAC 权限控制**: 基于角色的访问控制，支持细粒度权限管理
4. **登录保护**: 有登录失败次数限制（5次后锁定15分钟）
5. **验证码机制**: 支持手机短信和邮箱验证码
6. **审计日志**: 有登录审计日志记录
7. **参数化查询**: 使用 pgx 参数化查询，防止 SQL 注入
8. **速率限制**: 有全局和路由级别的速率限制

---

**评估结论**: 项目的基础认证机制设计良好，但存在多个严重的配置安全问题。建议立即修复高危问题，特别是 CORS 配置、JWT 密钥、Redis 密码和数据库端口暴露问题。这些修复可以在不影响现有功能的情况下显著提升系统安全性。
