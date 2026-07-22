# Email Service Setup Guide

> 逆变器云平台邮件服务配置与使用指南

## 目录

- [概述](#概述)
- [SMTP 配置参数](#smtp-配置参数)
- [环境变量参考](#环境变量参考)
- [常见邮件服务商配置](#常见邮件服务商配置)
  - [QQ 邮箱](#qq-邮箱)
  - [Gmail SMTP](#gmail-smtp)
  - [阿里云 DirectMail](#阿里云-directmail)
  - [SendGrid](#sendgrid)
- [邮件模板](#邮件模板)
- [本地开发测试](#本地开发测试)
  - [MailHog](#mailhog)
  - [Mailcatcher](#mailcatcher)
- [故障排除](#故障排除)
- [生产环境安全最佳实践](#生产环境安全最佳实践)
- [相关文档](#相关文档)

---

## 概述

`business-api` 服务内置了完整的邮件发送功能，基于 **gomail** 库通过 SMTP 协议发送 HTML 模板邮件。邮件服务用于以下场景：

- 用户注册/登录验证码
- 组织成员邀请
- 设备转移通知
- 密码重置
- 新用户欢迎

邮件服务在配置无效时（如 `EMAIL_HOST` 为空或为 `smtp.example.com`）会自动降级为**开发模式**，仅在日志中打印验证码而不实际发送邮件，不影响系统运行。

---

## SMTP 配置参数

| 参数 | 类型 | 说明 | 默认值 |
|------|------|------|--------|
| `email.host` | string | SMTP 服务器地址 | `""` |
| `email.port` | int | SMTP 端口号 | `465` (SSL) / `587` (TLS) |
| `email.username` | string | SMTP 认证用户名 | `""` |
| `email.password` | string | SMTP 认证密码/授权码 | `""` |
| `email.from` | string | 发件人地址 | `""` |
| `email.sender_name` | string | 发件人显示名称 | `"逆变器监控平台"` |
| `email.ssl` | bool | 是否启用 SSL | `true`（端口 465） |
| `email.insecure_skip_verify` | bool | 跳过 TLS 证书验证 | `false` |

---

## 环境变量参考

在 `.env.prod` 或 Docker Compose 环境中，以下环境变量会被自动绑定：

```bash
# ---------- Email ----------
EMAIL_HOST=smtp.qq.com          # SMTP 服务器地址
EMAIL_PORT=465                  # SMTP 端口（465=SSL, 587=STARTTLS）
EMAIL_USER=your-email@qq.com    # SMTP 认证用户名（通常为完整邮箱）
EMAIL_PASS=xxxxxxxxxxxxxxxx     # SMTP 密码或授权码
EMAIL_FROM=your-email@qq.com    # 发件人地址（需与认证用户一致）
EMAIL_SENDER_NAME=逆变器监控平台  # 发件人显示名称（可选）
```

> **注意：** 大部分国内邮件服务商（QQ、163 等）需使用**授权码**而非登录密码。

### 在 docker-compose 中配置

```yaml
services:
  inv-api-server:
    environment:
      - EMAIL_HOST=${EMAIL_HOST}
      - EMAIL_PORT=${EMAIL_PORT:-465}
      - EMAIL_USER=${EMAIL_USER}
      - EMAIL_PASS=${EMAIL_PASS}
      - EMAIL_FROM=${EMAIL_FROM}
      - EMAIL_SENDER_NAME=${EMAIL_SENDER_NAME:-逆变器监控平台}
```

---

## 常见邮件服务商配置

### QQ 邮箱

| 配置项 | 值 |
|--------|-----|
| `EMAIL_HOST` | `smtp.qq.com` |
| `EMAIL_PORT` | `465` |
| `EMAIL_USER` | `your-qq@qq.com` |
| `EMAIL_PASS` | 在 QQ 邮箱设置中生成的**授权码** |
| `EMAIL_FROM` | `your-qq@qq.com` |

**获取授权码步骤：**

1. 登录 QQ 邮箱 → 设置 → 账户
2. 找到「POP3/IMAP/SMTP/Exchange/CardDAV/CalDAV 服务」
3. 开启「SMTP 服务」
4. 按提示用手机发短信验证，获得授权码
5. 将授权码填入 `EMAIL_PASS`

### Gmail SMTP

| 配置项 | 值 |
|--------|-----|
| `EMAIL_HOST` | `smtp.gmail.com` |
| `EMAIL_PORT` | `465`（SSL）或 `587`（STARTTLS） |
| `EMAIL_USER` | `your-email@gmail.com` |
| `EMAIL_PASS` | App Password（需启用两步验证后生成） |
| `EMAIL_FROM` | `your-email@gmail.com` |

**生成 App Password：**

1. 开启 Google 账户两步验证
2. 前往 https://myaccount.google.com/apppasswords
3. 选择「邮件」→ 生成 16 位应用专用密码
4. 填入 `EMAIL_PASS`（空格可忽略）

> **注意：** 国内服务器访问 Gmail SMTP 可能不稳定，建议海外部署时使用。

### 阿里云 DirectMail

| 配置项 | 值 |
|--------|-----|
| `EMAIL_HOST` | `smtpdm.aliyun.com` |
| `EMAIL_PORT` | `465`（SSL）或 `25`（普通） |
| `EMAIL_USER` | `noreply@your-domain.com` |
| `EMAIL_PASS` | DirectMail 账户设置的 SMTP 密码 |
| `EMAIL_FROM` | `noreply@your-domain.com` |

**配置步骤：**

1. 登录阿里云控制台 → 邮件推送（DirectMail）
2. 配置发信域名并完成 SPF/DKIM/MX 验证
3. 创建发信地址（如 `noreply@your-domain.com`）
4. 设置 SMTP 密码
5. 填入上述配置

### SendGrid

| 配置项 | 值 |
|--------|-----|
| `EMAIL_HOST` | `smtp.sendgrid.net` |
| `EMAIL_PORT` | `465`（SSL）或 `587`（STARTTLS） |
| `EMAIL_USER` | `apikey` |
| `EMAIL_PASS` | SendGrid API Key（需开启 SMTP 权限） |
| `EMAIL_FROM` | 已验证的发件人地址 |

---

## 邮件模板

系统使用 Go `html/template` 引擎渲染邮件内容，模板文件位于 `business-api/internal/templates/` 目录：

| 模板文件 | 用途 | 触发场景 |
|----------|------|----------|
| `invitation_email.tmpl` | 组织邀请 | 管理员发送邀请时 |
| `transfer_notification.tmpl` | 设备转移通知 | 设备转移请求创建时 |
| `verification_code.tmpl` | 验证码邮件 | 注册/登录发送验证码时 |
| `welcome.tmpl`（预留） | 欢迎邮件 | 新用户首次注册时 |
| `password_reset.tmpl`（预留） | 密码重置 | 用户请求重置密码时 |

### 模板变量

**邀请邮件 (`invitation_email.tmpl`)**

```go
data := map[string]string{
    "ToEmail":          "user@example.com",
    "InviteLink":       "https://app.example.com/invite?token=xxx",
    "RoleName":         "管理员",
    "OrganizationName": "企业A",
    "ExpiresHours":     "168",
    "SenderName":       "逆变器监控平台",
}
```

**转移通知 (`transfer_notification.tmpl`)**

```go
data := map[string]string{
    "RequesterEmail": "admin@company.com",
    "DeviceSN":       "CS6K2-001234",
    "FromOrg":        "企业A",
    "ToOrg":          "企业B",
    "Reason":         "项目移交",
    "SenderName":     "逆变器监控平台",
}
```

### 自定义模板

修改模板文件后重新编译或重启服务即可生效，无需重新部署。

---

## 本地开发测试

在本地开发环境中，不建议配置真实 SMTP 服务器，可使用以下工具捕获邮件：

### MailHog

[MailHog](https://github.com/mailhog/MailHog) 是一个用 Go 编写的邮件测试工具，提供 Web UI 查看所有捕获的邮件。

**安装与启动：**

```bash
# Docker 方式（推荐）
docker run -d -p 1025:1025 -p 8025:8025 --name mailhog mailhog/mailhog

# Go 安装
go install github.com/mailhog/MailHog@latest
mailhog
```

**配置环境变量：**

```bash
EMAIL_HOST=localhost
EMAIL_PORT=1025
EMAIL_USER=
EMAIL_PASS=
EMAIL_FROM=dev@local.test
```

**访问 Web UI：** 浏览器打开 `http://localhost:8025`

### Mailcatcher

[Mailcatcher](https://mailcatcher.me/) 是一个 Ruby 实现的邮件捕获工具。

**安装与启动：**

```bash
gem install mailcatcher
mailcatcher
```

**配置环境变量：**

```bash
EMAIL_HOST=localhost
EMAIL_PORT=1025
EMAIL_USER=
EMAIL_PASS=
EMAIL_FROM=dev@local.test
```

**访问 Web UI：** 浏览器打开 `http://localhost:1080`

> **提示：** 开发模式下（未配置 SMTP），验证码会直接打印在控制台日志中，格式如：
> ```
> [DEBUG] Email code generated (dev mode)  email="te***@example.com"  type="register"
> ```

---

## 故障排除

### 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| `邮件发送失败：dial tcp: connection refused` | SMTP 服务器连接被拒绝 | 检查 `EMAIL_HOST` 和 `EMAIL_PORT` 是否正确，确认防火墙未拦截 |
| `邮件发送失败：x509: certificate signed by unknown authority` | TLS 证书验证失败 | 设置 `email.insecure_skip_verify: true`（仅开发环境） |
| `535 Error: authentication failed` | SMTP 认证失败 | 确认使用了授权码而非登录密码；检查用户名是否为完整邮箱地址 |
| `550 User has no permission` | 发件人无权限 | 确认已在邮件服务商后台开启 SMTP 服务 |
| `邮件未收到但无报错` | 被垃圾邮件过滤 | 检查收件箱的垃圾邮件目录；确认 SPF/DKIM 记录已配置 |
| `连接超时 timeout` | 网络不通或端口被屏蔽 | 检查服务器出口网络；部分云服务商默认封锁 25 端口，改用 465 |
| `验证码冷却中` | 60 秒发送间隔限制 | 等待冷却时间到期（Redis key: `email:{addr}:{type}:cooldown`） |

### 调试步骤

1. **检查配置是否加载：**
   ```bash
   # 在容器内查看环境变量
   docker exec inv-api-server env | grep EMAIL
   ```

2. **手动测试 SMTP 连接：**
   ```bash
   # 使用 openssl 测试 SSL 连接
   openssl s_client -connect smtp.qq.com:465 -quiet
   ```

3. **查看服务日志：**
   ```bash
   docker logs inv-api-server 2>&1 | grep -i email
   ```

4. **验证 Redis 验证码存储：**
   ```bash
   docker exec redis redis-cli -a <password> KEYS "email:*"
   ```

---

## 生产环境安全最佳实践

### 凭证管理

- **绝不**将真实 SMTP 密码提交到 Git，始终通过 `.env.prod` 注入
- `.env.prod` 文件权限设置为 `600`，仅允许运行用户读取
- 定期轮换 SMTP 授权码（建议每 60 天）
- 使用独立的邮件账户，不复用个人账户

### 网络安全

- 始终使用 SSL (465) 或 STARTTLS (587) 加密连接，**禁止**使用明文端口 25
- 确保 `email.insecure_skip_verify` 在生产环境为 `false`
- 配置 SPF、DKIM、DMARC 记录，防止邮件被标记为垃圾邮件

### 发送限制

- 系统内置 60 秒发送冷却（防滥用）
- 验证码有效期 5 分钟（Redis TTL）
- 验证失败 5 次后锁定（Redis key: `email:{addr}:{type}:fail`）
- 建议配合邮件服务商的日发送限额监控

### 监控告警

- 监控邮件发送失败率（日志关键字：`邮件发送失败`）
- 设置 SMTP 连接失败的 Prometheus 告警
- 定期检查邮件服务商后台的发送统计和退信报告

---

## 相关文档

- [Email Queue Implementation](./email-queue-implementation.md) — 异步邮件队列架构
- [Email Queue Summary](./email-queue-summary.md) — 邮件队列 API 摘要
- [Delivery Checklist](./DELIVERY-CHECKLIST.md) — 交付检查清单
- [Deploy Environment Variables](../deploy/.env.prod.example) — 生产环境变量模板

---

*最后更新：2026-07-22*
