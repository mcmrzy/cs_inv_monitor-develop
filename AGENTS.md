# AGENTS.md — cs_inv_monitor-develop

光伏逆变器物联网监控平台。多服务架构，含 Go 后端、React 管理后台、Flutter 移动端。

## 子系统

| 服务 | 目录 | 端口 | 技术栈 | 职责 |
|------|------|------|--------|------|
| business-api | `business-api/` | 8080 | Go + Gin + PostgreSQL + Redis | REST API（认证、设备、告警、OTA、RBAC） |
| device-communication | `device-communication/` | 8081 | Go + Gin + MQTT + Kafka | 设备通信（MQTT 管理、数据解析、告警消费） |
| api-gateway | `api-gateway/` | 80 | Go + Gin | 反向代理（JWT 校验、限流、RBAC 权限） |
| mqtt-kafka-bridge | `mqtt-kafka-bridge/` | 8080(webhook) | Go | EMQX Webhook → Kafka 消息转发 |
| inv-admin-frontend | `inv-admin-frontend/` | 5173(dev) | React + TypeScript + Vite + Ant Design | 管理后台 Web UI |
| inv_app | `inv_app/` | — | Flutter | 移动端 App |

## 构建 / 测试 / 部署命令

```bash
# Go 构建
make build-go          # 构建所有 Go 服务
make build-api         # 仅构建 business-api
make build-device      # 仅构建 device-communication

# Go 测试
make test-go           # 运行所有 Go 测试
make test-unit-go      # 含 race 检测和覆盖率
make vet-go            # 静态检查

# 前端
make build-web         # 构建管理后台
make type-check        # TypeScript 类型检查
make lint-web          # ESLint

# Flutter
make build-app         # 构建 APK
make test-app          # 运行测试

# Docker 部署
make docker-up         # 构建并启动所有服务
make docker-down       # 停止所有服务

# 集成测试
make test-integration  # 需要 Docker 环境
```

## 提交前验证清单

推送代码前，至少执行以下最小验证：

```bash
# 1. Go 编译检查（必须通过）
make build-go

# 2. Go 静态检查
make vet-go

# 3. 前端类型检查（如涉及前端修改）
make type-check

# 4. Flutter 分析（如涉及移动端修改）
make analyze-app
```

## 核心文件保护

以下文件/目录变更需格外谨慎：

- `database/schema.sql` — 数据库主 schema，变更需伴随迁移脚本
- `database/migrations/` — 迁移文件，只增不改
- `deploy/docker-compose.yml` — 生产部署配置
- `deploy/.secrets/` — 敏感配置，禁止提交到版本控制
- `.github/workflows/` — CI/CD 管线定义
- `contracts/` — API 契约与事件定义

## 变更边界

- **许可区域**：所有 `internal/`、`pkg/`、`cmd/`、`src/`、`lib/` 下的业务代码
- **需谨慎**：`database/`、`deploy/`、`.github/`、`contracts/`
- **禁止**：`deploy/.secrets/`、任何含密钥/token 的文件

## 架构约定

- Go 服务遵循 Handler → Service → Repository 三层架构
- 错误处理使用 `business-api/pkg/apperr` 统一错误码
- API 响应格式：`{"code": 0, "message": "success", "data": ...}`
- 时间处理：设备端生成 UTC 时间戳，服务端存储 UTC，前端展示转本地时区
- MQTT 主题格式：`inv/{device_sn}/telemetry`、`inv/{device_sn}/command`
