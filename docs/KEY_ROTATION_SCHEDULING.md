# Key Rotation & Scheduling Guide

> 逆变器云平台密钥轮换策略与自动化提醒指南

## 目录

- [概述](#概述)
- [轮换周期总览](#轮换周期总览)
- [密钥清单与存储位置](#密钥清单与存储位置)
- [自动化提醒配置](#自动化提醒配置)
  - [GitHub Actions 定时工作流](#github-actions-定时工作流)
  - [Slack 通知集成](#slack-通知集成)
  - [日历事件模板](#日历事件模板)
- [轮换前检查清单](#轮换前检查清单)
- [各密钥轮换步骤](#各密钥轮换步骤)
  - [JWT Secret 轮换](#jwt-secret-轮换)
  - [加密密钥轮换](#加密密钥轮换)
  - [SMTP 授权码轮换](#smtp-授权码轮换)
  - [Redis 密码轮换](#redis-密码轮换)
  - [MQTT 凭证轮换](#mqtt-凭证轮换)
  - [INTERNAL_KEY 轮换](#internal_key-轮换)
- [轮换后验证步骤](#轮换后验证步骤)
- [漏轮换升级流程](#漏轮换升级流程)
- [审计日志要求](#审计日志要求)
- [相关文档](#相关文档)

---

## 概述

密钥轮换是安全合规的核心实践。本文档定义了平台所有密钥的轮换周期、操作步骤和自动化提醒机制，确保密钥在过期前完成更新，降低凭证泄露风险。

**核心原则：**

- 所有密钥通过 `.env.prod` 文件注入，不存入代码仓库
- 轮换操作需在维护窗口内进行，避免影响在线用户
- 每次轮换必须记录到审计日志
- 轮换后需执行完整的验证流程

---

## 轮换周期总览

| 密钥类型 | 轮换周期 | 提前提醒 | 影响范围 | 优先级 |
|----------|----------|----------|----------|--------|
| **JWT Secret** | 90 天 | 14 天前 | 所有用户认证 | 高 |
| **加密密钥（Encryption Key）** | 180 天 | 21 天前 | 数据加密/解密 | 高 |
| **SMTP 授权码** | 60 天 | 7 天前 | 邮件发送 | 中 |
| **Redis 密码** | 90 天 | 14 天前 | 缓存、会话、令牌黑名单 | 高 |
| **MQTT 凭证** | 90 天 | 14 天前 | 设备通信 | 高 |
| **INTERNAL_KEY** | 180 天 | 21 天前 | 服务间通信 | 中 |

> **提示：** 发生安全事件或疑似泄露时，应立即触发**紧急轮换**，不受周期限制。

---

## 密钥清单与存储位置

| 密钥 | 环境变量 | 存储文件 | 使用服务 |
|------|----------|----------|----------|
| JWT Secret | `JWT_SECRET` | `deploy/.env.prod` | `inv-api-server`, `api-gateway` |
| Internal Key | `INTERNAL_KEY` | `deploy/.env.prod` | `inv-api-server`, `api-gateway`, `inv-device-server` |
| Redis 密码 | `REDIS_PASSWORD` | `deploy/.env.prod` | `redis`, `inv-api-server` |
| SMTP 授权码 | `EMAIL_PASS` | `deploy/.env.prod` | `inv-api-server` |
| MQTT 用户名 | `MQTT_USERNAME` | `deploy/.env.prod` | `inv-device-server` |
| MQTT 密码 | `MQTT_PASSWORD` | `deploy/.env.prod` | `inv-device-server` |
| 数据库密码 | `DB_PASSWORD` | `deploy/.env.prod` | `postgres`, 所有后端服务 |

---

## 自动化提醒配置

### GitHub Actions 定时工作流

在 `.github/workflows/key-rotation-reminder.yml` 创建定时检查：

```yaml
name: Key Rotation Reminder

on:
  schedule:
    # 每周一 UTC 9:00（北京时间 17:00）
    - cron: '0 9 * * 1'
  workflow_dispatch: # 支持手动触发

jobs:
  check-rotation:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Check rotation schedule
        id: check
        run: |
          TODAY=$(date +%s)
          ALERT=false

          # 从 Git log 获取各密钥最后修改时间
          JWT_LAST=$(git log --all --oneline -S "JWT_SECRET" -- deploy/.env.prod.example --format="%ct" | head -1)
          INTERNAL_LAST=$(git log --all --oneline -S "INTERNAL_KEY" -- deploy/.env.prod.example --format="%ct" | head -1)

          JWT_AGE_DAYS=$(( (TODAY - ${JWT_LAST:-0}) / 86400 ))
          INTERNAL_AGE_DAYS=$(( (TODAY - ${INTERNAL_LAST:-0}) / 86400 ))

          echo "## 🔑 密钥轮换状态报告" >> $GITHUB_STEP_SUMMARY
          echo "| 密钥 | 上次轮换 | 距今天数 | 状态 |" >> $GITHUB_STEP_SUMMARY
          echo "|------|----------|----------|------|" >> $GITHUB_STEP_SUMMARY

          if [ "$JWT_AGE_DAYS" -ge 76 ]; then
            echo "| JWT Secret | $(date -d @$JWT_LAST +%Y-%m-%d) | $JWT_AGE_DAYS 天 | ⚠️ 即将过期 |" >> $GITHUB_STEP_SUMMARY
            ALERT=true
          else
            echo "| JWT Secret | $(date -d @$JWT_LAST +%Y-%m-%d) | $JWT_AGE_DAYS 天 | ✅ 正常 |" >> $GITHUB_STEP_SUMMARY
          fi

          if [ "$ALERT" = true ]; then
            echo "ALERT=true" >> $GITHUB_OUTPUT
          fi

      - name: Notify if rotation needed
        if: steps.check.outputs.ALERT == 'true'
        run: |
          echo "⚠️ 有密钥即将到期，请及时轮换！"
          # 可在此处添加 Slack/邮件通知（见下方集成）
```

### Slack 通知集成

在 GitHub Actions 中集成 Slack 通知：

```yaml
      - name: Slack Notification
        if: steps.check.outputs.ALERT == 'true'
        uses: slackapi/slack-github-action@v2
        with:
          webhook: ${{ secrets.SLACK_WEBHOOK_URL }}
          payload: |
            {
              "blocks": [
                {
                  "type": "header",
                  "text": { "type": "plain_text", "text": "🔑 密钥轮换提醒" }
                },
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "以下密钥即将到期，请在 *7 天内* 完成轮换：\n• JWT Secret (90天周期)\n• 详情请查看 GitHub Actions 运行记录"
                  }
                },
                {
                  "type": "actions",
                  "elements": [
                    {
                      "type": "button",
                      "text": { "type": "plain_text", "text": "查看轮换指南" },
                      "url": "https://github.com/your-org/cs_inv_monitor/blob/develop/docs/KEY_ROTATION_SCHEDULING.md"
                    }
                  ]
                }
              ]
            }
```

### 日历事件模板

为每个轮换周期创建循环日历事件：

| 事件名称 | 频率 | 描述 |
|----------|------|------|
| `[安全] JWT Secret 轮换` | 每 90 天 | 轮换 JWT 签名密钥，需同步更新 api-gateway 和 inv-api-server |
| `[安全] Redis 密码轮换` | 每 90 天 | 更新 Redis 密码，需同步更新 docker-compose 和所有依赖服务 |
| `[安全] SMTP 授权码轮换` | 每 60 天 | 在邮件服务商后台重新生成授权码并更新 .env.prod |
| `[安全] MQTT 凭证轮换` | 每 90 天 | 更新 EMQX/Mosquitto 账户密码，需考虑设备重连影响 |
| `[安全] 加密密钥轮换` | 每 180 天 | 轮换数据加密密钥，需评估历史数据解密兼容性 |
| `[安全] INTERNAL_KEY 轮换` | 每 180 天 | 更新服务间通信密钥，需同步所有后端服务 |

---

## 轮换前检查清单

每次轮换前，确认以下事项：

- [ ] **确认维护窗口**：选择低峰期（如凌晨 2:00-4:00）
- [ ] **通知团队**：在 Slack/群组中发布轮换计划
- [ ] **备份当前配置**：`cp deploy/.env.prod deploy/.env.prod.bak.$(date +%Y%m%d)`
- [ ] **验证服务健康**：确认所有服务当前运行正常
  ```bash
  docker compose ps
  ```
- [ ] **准备回滚方案**：保留旧密钥，可在出问题快速恢复
- [ ] **确认新密钥强度**：使用 `openssl rand -base64 48` 生成
- [ ] **检查依赖服务列表**：确认所有使用该密钥的服务都将被更新

---

## 各密钥轮换步骤

### JWT Secret 轮换

**影响范围：** 轮换后所有在线用户的 access token 和 refresh token 失效，需重新登录。

```bash
# 1. 生成新密钥
NEW_JWT_SECRET=$(openssl rand -base64 48)
echo "New JWT Secret: $NEW_JWT_SECRET"

# 2. 更新 .env.prod
sudo sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$NEW_JWT_SECRET|" deploy/.env.prod

# 3. 重启相关服务
docker compose restart inv-api-server api-gateway

# 4. 验证服务启动
docker compose ps inv-api-server api-gateway

# 5. 验证登录功能
curl -X POST https://api.example.com/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"test123"}'

# 6. 清除 Redis 中的旧 token 黑名单（可选）
docker exec redis redis-cli -a "$REDIS_PASSWORD" KEYS "token:*" | head -5
```

> **双密钥过渡方案（可选）：** 如需无感轮换，可临时让 api-gateway 同时接受新旧两个密钥，过渡期设为 access token 有效期（2小时），然后移除旧密钥。

### 加密密钥轮换

**影响范围：** 影响加密数据的解密操作。需确保旧数据仍可解密。

```bash
# 1. 生成新密钥
NEW_ENC_KEY=$(openssl rand -base64 32)

# 2. 更新 .env.prod
sudo sed -i "s|^ENCRYPTION_KEY=.*|ENCRYPTION_KEY=$NEW_ENC_KEY|" deploy/.env.prod

# 3. 重启服务
docker compose restart inv-api-server

# 4. 验证已有数据解密正常
# 通过 API 测试读取加密字段
```

### SMTP 授权码轮换

**影响范围：** 轮换期间邮件发送短暂中断。

```bash
# 1. 在邮件服务商后台生成新授权码
# QQ邮箱：设置 → 账户 → 重新生成授权码

# 2. 更新 .env.prod
sudo sed -i "s|^EMAIL_PASS=.*|EMAIL_PASS=新授权码|" deploy/.env.prod

# 3. 重启服务
docker compose restart inv-api-server

# 4. 测试邮件发送
curl -X POST https://api.example.com/api/v1/auth/send-email-code \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","type":"login"}'
```

### Redis 密码轮换

**影响范围：** 所有依赖 Redis 的服务需要重启。

```bash
# 1. 生成新密码
NEW_REDIS_PASS=$(openssl rand -base64 32)

# 2. 更新 Redis 容器密码（通过 docker-compose.yml 或 redis.conf）
sudo sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=$NEW_REDIS_PASS|" deploy/.env.prod

# 3. 重启 Redis 和所有依赖服务
docker compose restart redis inv-api-server api-gateway

# 4. 验证 Redis 连接
docker exec redis redis-cli -a "$NEW_REDIS_PASS" PING

# 5. 验证服务正常
docker compose ps
```

### MQTT 凭证轮换

**影响范围：** 设备将断开连接并使用新凭证重连。需考虑设备端重连时序。

```bash
# 1. 在 EMQX 管理后台更新设备认证凭证
# 或更新 mosquitto 密码文件

# 2. 更新 .env.prod
sudo sed -i "s|^MQTT_PASSWORD=.*|MQTT_PASSWORD=新密码|" deploy/.env.prod

# 3. 重启 device-server
docker compose restart inv-device-server

# 4. 监控设备重连情况
docker logs inv-device-server 2>&1 | grep "connected"
```

> **注意：** MQTT 凭证轮换可能导致设备短暂离线，建议在设备端已实现自动重连机制后进行。

### INTERNAL_KEY 轮换

**影响范围：** 服务间通信认证失效，需同步更新所有后端服务。

```bash
# 1. 生成新密钥
NEW_INTERNAL_KEY=$(openssl rand -base64 48)

# 2. 更新 .env.prod
sudo sed -i "s|^INTERNAL_KEY=.*|INTERNAL_KEY=$NEW_INTERNAL_KEY|" deploy/.env.prod

# 3. 重启所有后端服务
docker compose restart inv-api-server api-gateway inv-device-server

# 4. 验证服务间通信
docker logs api-gateway 2>&1 | tail -20
```

---

## 轮换后验证步骤

每次轮换完成后，按以下清单验证：

```bash
# 1. 确认所有服务正常运行
docker compose ps
# 所有服务状态应为 Up (healthy)

# 2. 测试用户登录
curl -s -X POST https://api.example.com/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"admin123"}' | jq .code

# 3. 测试 API 认证（使用新 token）
TOKEN=$(curl -s -X POST https://api.example.com/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"admin123"}' | jq -r .data.accessToken)
curl -s -H "Authorization: Bearer $TOKEN" https://api.example.com/api/v1/user/profile | jq .code

# 4. 测试邮件发送（如轮换了 SMTP）
curl -s -X POST https://api.example.com/api/v1/auth/send-email-code \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","type":"login"}'

# 5. 检查 Redis 连接
docker exec redis redis-cli -a "$REDIS_PASSWORD" PING

# 6. 检查 MQTT 设备在线数
docker logs inv-device-server 2>&1 | grep -c "device connected"

# 7. 清理备份文件（保留 48 小时后删除）
ls -la deploy/.env.prod.bak.*
```

---

## 漏轮换升级流程

当密钥超过轮换周期未更新时，按以下升级流程处理：

| 超时天数 | 级别 | 操作 |
|----------|------|------|
| **0-7 天** | 提醒 | GitHub Actions 自动发送 Slack 提醒 |
| **7-14 天** | 警告 | 邮件通知技术负责人 + Slack @channel |
| **14-30 天** | 严重 | 升级至 CTO/安全负责人，安排紧急轮换窗口 |
| **30+ 天** | 紧急 | 立即执行强制轮换，评估安全风险 |

### 升级通知模板

```
🚨 [安全告警] 密钥轮换超时

密钥类型：JWT Secret
计划轮换日期：2026-07-01
已超时天数：21 天
当前状态：⚠️ 严重

请立即安排轮换，避免安全风险。
参考文档：docs/KEY_ROTATION_SCHEDULING.md

联系人：@security-lead
```

---

## 审计日志要求

每次密钥轮换必须记录以下信息：

### 日志格式

```json
{
  "event": "key_rotation",
  "timestamp": "2026-07-22T10:00:00Z",
  "key_type": "jwt_secret",
  "operator": "admin@example.com",
  "rotation_cycle_days": 90,
  "previous_key_hash": "sha256:abc123...",
  "new_key_hash": "sha256:def456...",
  "affected_services": ["inv-api-server", "api-gateway"],
  "verification_status": "passed",
  "notes": "定期轮换，无异常"
}
```

### 记录要求

| 字段 | 说明 | 必填 |
|------|------|------|
| `key_type` | 密钥类型标识 | 是 |
| `operator` | 执行轮换的操作人员 | 是 |
| `timestamp` | 轮换执行时间 | 是 |
| `previous_key_hash` | 旧密钥的 SHA-256 哈希（**绝不记录明文**） | 是 |
| `new_key_hash` | 新密钥的 SHA-256 哈希 | 是 |
| `affected_services` | 受影响的服务列表 | 是 |
| `verification_status` | 验证结果 (passed/failed) | 是 |
| `notes` | 备注（紧急轮换原因等） | 否 |

### 审计日志存储

- 轮换日志保存在 `deploy/scripts/rotation-log.json`（本地记录）
- 同时通过应用日志系统记录（关键字：`key_rotation`）
- 建议集成到集中式日志平台（如 ELK、Loki）
- 审计日志保留期限：**至少 1 年**

---

## 相关文档

- [Deploy Environment Variables](../deploy/.env.prod.example) — 环境变量模板
- [Email Service Setup](../business-api/docs/EMAIL_SERVICE_SETUP.md) — SMTP 配置指南
- [JWT 认证机制](../.qoder/repowiki/) — JWT 配置与 Token 管理
- [Docker Compose 部署](../deploy/docker-compose.prod.yml) — 生产部署配置

---

*最后更新：2026-07-22*
