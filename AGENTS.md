# AGENTS.md — cs_inv_monitor-develop

光伏逆变器物联网监控系统，实现设备接入、数据采集、远程监控、告警管理、OTA 升级等功能。多服务架构，含 Go 后端、React 管理后台、Flutter 移动端。

## 子系统

| 服务 | 目录 | 端口 | 技术栈 | 职责 |
|------|------|------|--------|------|
| inv-api-server | `business-api/` | 8080 | Go + Gin + PostgreSQL + Redis | 用户端 REST API（认证、设备、告警、OTA、RBAC） |
| inv-device-server | `device-communication/` | 8081 | Go + Gin + MQTT + Kafka | 设备通信（MQTT 管理、数据解析、告警消费） |
| api-gateway | `api-gateway/` | 80 | Go + Gin | 反向代理（JWT 校验、限流、RBAC 权限、请求转发） |
| mqtt-kafka-bridge | `mqtt-kafka-bridge/` | 8080(webhook) | Go | EMQX Webhook → Kafka 消息转发 |
| inv-admin-frontend | `inv-admin-frontend/` | 5173(dev) / 3000(prod) | React + TypeScript + Vite + Ant Design | 管理后台 Web UI |
| inv_app | `inv_app/` | — | Flutter + Dart | 手机 App（设备监控、OTA 升级、WiFi 配网） |

### 基础设施

- **数据库**: PostgreSQL 16 + TimescaleDB（时序数据压缩）
- **缓存**: Redis 7（设备心跳、RBAC 缓存、会话）
- **消息队列**: EMQX (MQTT) + Kafka（数据管道）
- **部署**: Docker Compose

## 构建 / 测试 / 部署命令

```bash
# Go 构建
make build-go          # 构建所有 Go 服务
make build-api         # 仅构建 business-api
make build-device      # 仅构建 device-communication
make build-gateway     # 仅构建 api-gateway
make build-bridge      # 仅构建 mqtt-kafka-bridge

# Go 测试
make test-go           # 运行所有 Go 测试
make test-unit-go      # 含 race 检测和覆盖率
make vet-go            # 静态检查
make tidy              # 所有 Go 模块 go mod tidy

# 前端
make build-web         # 构建管理后台
make dev-web           # 启动前端开发服务器
make type-check        # TypeScript 类型检查
make lint-web          # ESLint

# Flutter
make build-app         # 构建 APK
make test-app          # 运行测试
make analyze-app       # Flutter 静态分析

# Docker 部署
make docker-up         # 构建并启动所有服务
make docker-down       # 停止所有服务
make docker-logs       # 查看所有服务日志
make docker-build      # 仅构建镜像（不启动）

# 本地开发
make run-api           # 本地运行 API Server
make run-device        # 本地运行 Device Server
make run-gateway       # 本地运行 API Gateway

# 集成测试
make test-integration  # 需要 Docker 环境
make test-security     # 安全测试
make test-all          # 所有测试（单元 + 安全）

# Git Hooks
make install-hooks     # 安装 pre-commit + commit-msg hooks
```

## 提交前验证清单

推送代码前，至少执行以下最小验证：

```bash
# 最小本地检查（必须全部通过）
make build-go && make test-go && make vet-go

# 分步执行：
# 1. Go 编译检查（必须通过）
make build-go

# 2. Go 测试（必须通过）
make test-go

# 3. Go 静态检查（必须通过）
make vet-go

# 4. 前端类型检查（如涉及前端修改）
make type-check

# 5. Flutter 分析（如涉及移动端修改）
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

## 目录结构约定

### Go 服务（business-api / device-communication）

```
├── cmd/main.go           # 入口（配置加载、依赖初始化、路由注册、优雅退出）
├── internal/
│   ├── config/           # 配置结构体 + Viper 加载
│   ├── handler/          # HTTP Handler（Gin），一个文件对应一个业务领域
│   ├── middleware/        # JWT、CORS、限流等中间件
│   ├── model/            # 数据模型（struct，对应数据库表）
│   ├── repository/       # 数据访问层（SQL 查询）
│   └── service/          # 业务逻辑层
└── pkg/                  # 可复用的公共包
```

### Flutter App (inv_app)

```
lib/
├── core/                 # 路由、全局服务、网络、工具
├── features/             # 按功能模块划分（auth/device/ota/...）
│   └── <feature>/
│       ├── data/         # 数据源 + 仓库实现
│       ├── domain/       # 实体 + 仓库接口
│       └── presentation/ # Bloc + Page + Widget
├── l10n/                 # 国际化
└── main.dart
```

### React 管理后台 (inv-admin-frontend)

```
src/
├── components/           # 通用组件
├── hooks/                # 自定义 Hooks
├── layouts/              # 页面布局
├── locales/              # 国际化
├── pages/                # 页面（每个目录对应一个功能模块）
├── services/             # API 调用
├── stores/               # Zustand 状态管理
├── types/                # TypeScript 类型定义
└── utils/                # 工具函数
```

## 架构约定

- Go 服务遵循 Handler → Service → Repository 三层架构
- 错误处理使用 `business-api/pkg/apperr` 统一错误码
- API 响应格式：`{"code": 0, "message": "success", "data": ...}`
- 分页响应：`{"code": 0, "message": "success", "data": {"items": [...], "total": 100, "page": 1, "page_size": 20}}`
- 时间处理：设备端生成 UTC 时间戳，服务端存储 UTC，前端展示转本地时区
- Go 端使用 `business-api/pkg/response` 包的 `Success()` / `Error()` / `Page()` 方法
- 日志使用 `pkg/logger`（zap 结构化日志），禁止 `fmt.Println` 或 `log.Printf`

### 错误处理规范（Go）

- Handler 层：使用 `response` 包的统一方法返回错误
- Service 层：返回 `error`，包含上下文信息（`fmt.Errorf("xxx: %w", err)`）
- Repository 层：返回 `error`，不做日志打印（由上层决定）

## 认证与权限

- **JWT Token**：Bearer Token 认证，`Authorization: Bearer <token>`
- **角色**：0=超级管理员, 1=代理商, 2=安装商, 3=终端用户
- **多租户**：通过 `parent_id` 实现层级关系（代理商→安装商→终端用户）
- **RBAC**：基于角色的权限控制（Redis 缓存权限矩阵）
- **内部调用**：`X-Internal-Key` Header 认证（服务间通信）

## 命名约定

| 场景 | 规范 | 示例 |
|------|------|------|
| Go 数据库字段 | snake_case | `firmware_arm`, `created_at` |
| Go struct 字段 | PascalCase | `FirmwareArm`, `CreatedAt` |
| Go JSON tag | snake_case | `"firmware_arm"` |
| TypeScript | camelCase | `firmwareArm`, `createdAt` |
| Dart | snake_case | `firmware_arm`, `created_at` |
| 数据库表名 | snake_case 复数 | `device_upgrades`, `firmware_versions` |
| API 路径 | kebab-case | `/api/v1/device-upgrades` |
| Go 文件名 | snake_case | `ota_handler.go`, `device_handler.go` |

## MQTT 主题格式

```
inv/{device_sn}/telemetry    # 设备遥测数据
inv/{device_sn}/alarm        # 告警数据
inv/{device_sn}/status       # 在线状态
inv/{device_sn}/command      # 下行命令
inv/{device_sn}/ota/status   # OTA 升级状态回报
inv/{device_sn}/ota/progress # OTA 升级进度
```

## OTA 升级体系

### 版本号体系

- `firmware_versions.version`：芯片固件版本（如 `1.2.1`）
- `firmware_versions.main_version`：自动递增编号（如 `V1.0.1`），按芯片类型分别计数
- `upgrade_packages.main_version`：升级包版本（如 `V1.0.0.20260630`）
- `devices.firmware_esp` / `devices.firmware_arm`：设备当前芯片版本

### 升级模式

- **单固件模式**：推送单个固件给指定芯片
- **升级包模式**：打包多个芯片固件，按顺序逐芯片升级

### 升级流程

管理后台/App 推送 → `device_upgrades` 记录 → MQTT 命令 → 设备执行 → 状态回报 → 更新数据库

### 本地 OTA（App → 设备直连）

- App 通过 WiFi 直连设备热点（SSID: `CS-INV-xxxx`）
- HTTP 通信：`http://{device_ip}:80`
- 上传固件：`POST /ota/upload`
- 查询进度：`GET /ota/progress`
- 查询设备信息：`GET /ota/info`
