# CS-INV 光伏逆变器物联网监控系统

> 基于 MQTT 协议的光伏逆变器远程监控平台，支持万级设备接入、实时数据监控、告警管理、OTA 固件升级，覆盖移动端 APP 与 Web 管理后台的多端协同场景。

---

## 功能特性

- [x] **BLE 蓝牙配网** — 通过蓝牙低功耗协议为设备配置 WiFi，无需切换手机网络
- [x] **实时数据采集** — 设备通过 MQTT 上报遥测数据，毫秒级延迟推送至 APP 与管理后台
- [x] **万级设备接入** — EMQX 共享订阅 + 多实例水平扩展，支撑大规模设备并发
- [x] **告警管理** — 实时告警检测、分级告警、推送通知、告警确认与处理
- [x] **OTA 固件升级** — ARM/ESP 双芯片远程升级，MQTT 命令下发 + 进度实时跟踪
- [x] **多端协同** — Flutter 跨平台 APP（MQTT 直连）+ React Web 管理后台（WebSocket 推送）
- [x] **SN 编号校验** — 16 位编码 + CRC16-Modbus 校验，所有入库入口强制验证
- [x] **电站管理** — 电站分组、设备绑定、发电统计、能量聚合分析
- [x] **用户体系** — JWT 认证、RBAC 权限控制、设备分享、多角色管理
- [x] **时序数据优化** — TimescaleDB 超表 + 7 天自动压缩 + 生命周期清理
- [x] **可观测性** — Prometheus 指标采集 + Grafana 仪表盘 + 结构化日志

---

## 系统架构

```
Flutter App ── MQTT (JWT认证) ──→ EMQX Broker ←── 设备(ESP32-C3+ARM) 数据上报
    │                                  │
    │                            共享订阅 $share/inv-group/
    │                                  │
    │                     inv_device_server (Go, 多实例)
    │                                  │
    │                          PostgreSQL + Redis
    │
    └── HTTP REST ──→ api-gateway ──→ inv_api_server (Go :8080)
                           │
                     Web 管理后台 + WebSocket
```

**设计原则**：实时数据走 MQTT 直连（低延迟推送），历史/统计数据走 HTTP API（按需查询），安全靠 EMQX 内置 JWT 认证 + 网关层统一鉴权。

### 数据流说明

| 链路 | 路径 | 场景 |
|------|------|------|
| 实时上行 | 设备 → EMQX → 共享订阅 → Device Server → PostgreSQL + Redis | 遥测数据入库 |
| 实时下行 | App MQTT 直连 EMQX（JWT 认证） | APP 设备详情页实时推送 |
| 历史查询 | App/Web → API Gateway → API Server → PostgreSQL | 统计报表、告警记录 |
| 命令下发 | Web/App → API Server → Device Server → MQTT → 设备 | OTA 升级、参数配置 |

---

## 技术栈

### 后端服务

| 技术 | 版本 | 用途 |
|------|------|------|
| Go | 1.25 | 后端编程语言 |
| Gin | v1.9 | HTTP 框架与路由 |
| pgx | v5 | PostgreSQL 驱动 |
| go-redis | v9 | Redis 客户端（Pub/Sub + Streams） |
| paho.mqtt.golang | - | MQTT 客户端（Device Server） |
| kafka-go | - | Kafka 消费者（Bridge） |
| Viper | - | 配置管理（YAML + 环境变量） |
| Zap | - | 结构化日志 |
| Prometheus | - | 指标采集与 `/metrics` 端点 |
| OpenTelemetry | - | 链路追踪 |

### 前端与移动端

| 技术 | 版本 | 用途 |
|------|------|------|
| React | 18 | Web 管理后台 |
| TypeScript | 5.x | 类型安全 |
| Vite | 5 | 构建工具 |
| Ant Design | v5 | UI 组件库 |
| ECharts | - | 数据可视化图表 |
| React Query | - | 服务端状态管理 |
| Zustand | - | 全局状态管理 |
| Socket.IO | - | WebSocket 实时推送 |
| Leaflet | - | 地图组件 |
| Flutter | 3.x | 跨平台移动端 |
| flutter_bloc | - | BLoC 状态管理 |
| go_router | - | 声明式路由 + AuthGuard |
| Dio | - | HTTP 客户端 |
| mqtt_client | - | APP MQTT 直连 |
| flutter_blue_plus | - | BLE 蓝牙配网 |
| get_it + injectable | - | 依赖注入 |

### 基础设施

| 技术 | 版本 | 用途 |
|------|------|------|
| PostgreSQL | 16 | 关系型数据库 + 元数据 |
| TimescaleDB | - | 时序数据扩展（超表 + 压缩） |
| Redis | 7 | 缓存 + 设备影子 + Pub/Sub + Streams |
| EMQX | 5.x | MQTT Broker（JWT 认证 + 共享订阅） |
| Kafka | - | 消息队列（可选，Bridge 桥接） |
| Docker Compose | - | 容器化编排 |
| Nginx | - | 前端静态资源托管 + 反向代理 |

---

## 项目结构

```
cs_inv_monitor/
├── api-gateway/                      # API 网关 — JWT/RBAC/限流/反向代理
│   ├── internal/
│   │   ├── config/                   # 配置管理
│   │   ├── middleware/               # 认证、权限、限流、CORS 中间件
│   │   ├── proxy/                    # 反向代理（api-server / device-server）
│   │   └── routes/                   # 路由注册
│   ├── config.docker.yaml            # Docker 环境配置
│   └── main.go                       # 入口文件
│
├── inv_api_server/                   # 运维 API 服务 — 用户/电站/设备/告警/OTA
│   ├── cmd/main.go                   # 入口文件
│   ├── internal/
│   │   ├── config/                   # 配置管理（Viper + YAML）
│   │   ├── handler/                  # HTTP 处理器（Auth/Device/Station/Alarm/Admin/WS/OTA）
│   │   ├── middleware/               # JWT 认证中间件
│   │   ├── model/                    # 数据模型
│   │   ├── repository/               # 数据库访问层
│   │   └── service/                  # 业务逻辑（邮件/天气/OTA 等）
│   └── pkg/                          # 公共包（jwt/logger/response/sn/telemetry/timezone）
│
├── inv_device_server/                # 设备通信服务 — MQTT 订阅/数据解析/OTA 下发
│   ├── cmd/main.go                   # 入口文件
│   ├── internal/
│   │   ├── config/                   # 配置管理
│   │   ├── mqtt/                     # MQTT 客户端 + 共享订阅 + Redis Streams 消费
│   │   ├── model/                    # 设备实时数据模型
│   │   ├── repository/               # 数据持久化（SN 校验门禁）
│   │   └── service/                  # 数据处理 + Redis Pub/Sub + Streams 发布
│   └── pkg/                          # 公共包（logger/sn/telemetry）
│
├── mqtt-kafka-bridge/                # EMQX Webhook → Kafka 消息桥接
│   └── main.go
│
├── inv-admin-frontend/               # Web 管理后台 — React 18 + Ant Design
│   ├── src/
│   │   ├── components/               # 通用组件
│   │   ├── pages/                    # 页面（设备/电站/用户/告警/OTA/统计）
│   │   ├── services/                 # API 请求封装
│   │   ├── stores/                   # Zustand 状态管理
│   │   ├── hooks/                    # 自定义 Hooks
│   │   ├── locales/                  # 国际化（中/英）
│   │   └── utils/                    # 工具函数
│   └── vite.config.ts
│
├── inv_app/                          # Flutter 移动端 APP
│   ├── lib/
│   │   ├── core/                     # 核心模块（配置/路由/服务/主题/SN校验）
│   │   ├── features/                 # 功能模块（BLoC 模式）
│   │   │   ├── auth/                 # 登录/注册/找回密码
│   │   │   ├── dashboard/            # 仪表盘
│   │   │   ├── device/               # 设备详情/控制/WiFi配网
│   │   │   ├── alarm/                # 告警管理
│   │   │   ├── station/              # 电站管理
│   │   │   ├── statistics/           # 数据统计/图表
│   │   │   └── profile/              # 个人中心/设备分享
│   │   └── l10n/                     # 国际化
│   └── pubspec.yaml
│
├── database/                         # 数据库
│   ├── schema.sql                    # 初始化建表（20+ 表/视图/触发器）
│   ├── migration_timescaledb.sql     # TimescaleDB 兼容引导（实际结构由编号迁移管理）
│   └── migrations/                   # 增量迁移（001-011）
│
├── deploy/                           # 部署与运维
│   ├── docker-compose.yml            # 开发环境编排
│   ├── docker-compose.prod.yml       # 生产环境编排
│   ├── k8s-device-server.yaml        # K8s Deployment + HPA
│   ├── prometheus.yml                # Prometheus 配置
│   ├── prometheus_alerts.yml         # 告警规则
│   ├── grafana-dashboard.json        # Grafana 仪表盘
│   ├── nginx.conf                    # Nginx 配置
│   └── .env / .env.prod              # 环境变量（敏感配置）
│
├── docs/                             # 技术文档
├── Makefile                          # 统一构建入口
└── start_all.bat                     # Windows 一键启动
```

---

## 快速开始

### 环境要求

| 依赖 | 最低版本 | 说明 |
|------|---------|------|
| Go | 1.25+ | 后端编译 |
| Flutter | 3.x | 移动端构建 |
| Node.js | 18+ | 前端构建 |
| PostgreSQL | 16 | 数据库 |
| Redis | 7 | 缓存 |
| EMQX | 5.x | MQTT Broker（外部部署） |
| Docker & Docker Compose | - | 容器化部署（可选） |

### 1. 数据库初始化

```bash
# 创建数据库
psql -U postgres -c "CREATE DATABASE inv_mqtt;"

# 执行建表脚本
psql -U postgres -d inv_mqtt -f database/schema.sql

# 按序号执行增量迁移（001-011）
for f in database/migrations/*.up.sql; do
  psql -U postgres -d inv_mqtt -f "$f"
done

# 启用 TimescaleDB 扩展；后续时序结构和策略由编号迁移统一管理
psql -U postgres -d inv_mqtt -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"
# migration_timescaledb.sql 仅作为旧环境兼容引导，不再作为当前结构的独立迁移入口
```

### 2. 后端启动

```bash
# API Gateway（端口 8080）
cd api-gateway && go run main.go

# API Server（端口 8080）
cd inv_api_server && go run cmd/main.go

# Device Server（端口 8081）
# 需设置 MQTT_PASSWORD 为有效的 JWT token（由 API Server 签发）
export MQTT_PASSWORD="<your_jwt_token>"
cd inv_device_server && go run cmd/main.go
```

### 3. 前端启动

```bash
# Web 管理后台（开发模式）
cd inv-admin-frontend
npm install
npm run dev
```

### 4. 移动端启动

```bash
cd inv_app
flutter pub get
flutter run
```

### 5. Docker 一键启动

```bash
cd deploy
docker compose up -d
```

启动后通过 `http://localhost:3000` 访问管理后台，API 网关入口为 `http://localhost:80`。

---

## 服务端口

| 服务 | 内部端口 | 映射端口 | 说明 |
|------|---------|---------|------|
| API Gateway | 8080 | 80 | 统一 HTTP 入口（JWT/RBAC/限流） |
| API Server | 8080 | — | REST API + WebSocket（内部） |
| Device Server | 8081 | — | 设备通信 + `/metrics`（内部） |
| Admin Frontend | 80 | 3000 | Web 管理后台（Nginx 托管） |
| PostgreSQL | 5432 | 5432 | 数据库 |
| Redis | 6379 | 6379 | 缓存 + Pub/Sub + Streams |
| EMQX MQTT | 8883 | 8883 | MQTT SSL |

---

## 核心设计

### 实时数据链路

```
设备(ESP32-C3+ARM) → EMQX → $share/inv-group/ → Device Server(Go)
                                                      ├→ PostgreSQL（时序 + 元数据）
                                                      ├→ Redis（缓存 + Pub/Sub + Streams）
                                                      └→ Prometheus（/metrics）

App 设备详情页 → MQTT 直连 EMQX（JWT 认证，订阅 cs_inv/{sn}/#）→ 实时推送
```

APP 设备详情页实时数据**完全走 MQTT 推送**，不通过 HTTP 轮询。进入页面即开始订阅推送，下拉刷新不触发额外请求。

### 高可用设计

- **共享订阅** — `$share/inv-group/` 前缀，EMQX 轮询分发消息给多个 Device Server 实例
- **Redis 共享状态** — 多实例通过 Redis HSET 共享设备在线状态，无本地状态依赖
- **Session 清理** — `SetCleanSession(true)`，断开即清理会话
- **K8s HPA** — 基于 CPU/内存指标自动扩缩 2~10 副本（参见 `deploy/k8s-device-server.yaml`）

### OTA 固件升级

支持 ARM 和 ESP 双芯片远程固件升级，通过 MQTT 命令下发 + 进度实时跟踪：

```
管理后台上传固件 → 创建升级任务 → API Server
                                      │
                                      ▼
                              Device Server → MQTT 下发
                                      │
                                      ▼
                          cs_inv/{sn}/ota/cmd → 设备下载固件 → 升级
                                      │
                                      ▼
                          cs_inv/{sn}/ota/status → 进度上报
                                      │
                                      ▼
                          Device Server → API Server → 数据库更新
                                      │
                                      ▼
                              APP / 管理后台实时显示进度
```

| MQTT 主题 | 方向 | 说明 |
|-----------|------|------|
| `cs_inv/{sn}/ota/cmd` | 下行 | 升级命令（start / cancel） |
| `cs_inv/{sn}/ota/status` | 上行 | 进度上报（progress / success / failed） |

### SN 编号校验

设备 SN 为 16 位编码（例 `H1CNA00135000014`），**所有设备入库入口强制校验**，无效 SN 自动拒绝。

| 位置 | 含义 |
|------|------|
| 0-1 | 制造商代码 |
| 2-3 | 国家代码 |
| 4-7 | 客户等级 + 数字编号 |
| 8-9 | 年月（自定义编码） |
| 10-14 | 5 位序列号 |
| 15 | CRC16-Modbus 校验位 |

校验覆盖入口：`UpsertDeviceInfo`、`InternalDeviceStatus`、`InternalDeviceData`。

---

## Makefile 命令

| 命令 | 说明 |
|------|------|
| `make build-go` | 构建所有 Go 服务 |
| `make build-app` | 构建 Flutter APK |
| `make build-web` | 构建 Web 管理后台 |
| `make docker-up` | Docker Compose 启动全部服务 |
| `make test-go` | 运行 Go 单元测试 |
| `make dev-web` | 启动前端开发服务器 |
| `make install-hooks` | 安装 Git hooks（pre-commit / commit-msg） |

---

## 数据库迁移

项目采用增量迁移策略，迁移文件位于 `database/migrations/`，按序号递增：

| 序号 | 内容 |
|------|------|
| 001 | 初始化 Schema（表/索引/约束） |
| 002 | 性能索引优化 |
| 003 | TimescaleDB 压缩策略 |
| 004 | 能量统计列 |
| 005 | 设备日数据 JSONB 重构 |
| 006 | OTA 重构为 device_upgrades |
| 007 | 命令日志增强 |
| 008 | 升级包管理 |
| 009 | 升级任务管理 |
| 010 | DSP/BMS 固件版本 |
| 011 | 分组名称与控制参数 |

---

## 文档

| 文档 | 说明 |
|------|------|
| [BLE 配网协议](docs/BLE_Provisioning_Protocol.md) | BLE 蓝牙配网协议规范与实现 |
| [MQTT 协议文档](docs/MQTT接口文档.md) | MQTT 主题定义与上下行数据格式 |
| [系统参数规范](docs/系统参数规范_48V离网逆变器.md) | 逆变器参数定义与映射 |
| [ARM-ESP32 UART 协议](docs/ARM_ESP32_UART_Protocol.md) | ARM ↔ ESP32 帧协议 |
| [EMQX 规则引擎](docs/emqx_rule_engine_sql.md) | Rule Engine SQL 参考 |
| [架构升级清单](docs/架构升级任务清单.md) | 架构升级执行手册 |
| [流程文档](光伏逆变器物联网监控系统%20—%20流程文档.md) | 系统架构与数据流程 |
| [OTA 开发指南](docs/设备端OTA程序开发指南.md) | 设备端 OTA 程序开发 |
| [设备接入指南](docs/device-onboarding-guide.md) | 新设备接入流程 |

---

## 许可证

本项目为私有/专有软件（Private / Proprietary），未经授权不得复制、修改或分发。
# INV-MQTT 光伏逆变器物联网监控系统

基于 MQTT 协议的光伏逆变器远程监控平台，支持万级设备接入、实时监控、告警管理、用户管理等功能。

## 系统架构

```
                              ┌── JWT 认证（HS256）──┐
                              │   Secret 统一         │
                              ▼                       ▼
  Flutter App ── MQTT (password=JWT) ──→ EMQX Broker ←── 设备(ESP32-C3) 数据上报
    │                                       │
    │                                 内置 JWT 验签
    │                                 过期自动断连
    │                                 共享订阅分发
    │                                       │
    │                                  ┌────┼────┐
    │                                  ▼    ▼    ▼
    │                           $share/inv-group/   ← EMQX 共享订阅
    │                           inv_device_server-1 / 2 （Go 多实例）
    │                                  │    │
    │                                  ▼    ▼
    │                        PostgreSQL + Redis + Redis Streams
    │
    └── HTTP REST ───────────→ inv_api_server (Go :8080)
                                       │
                                       ▼
                                 Admin Panel + WebSocket（管理后台推送）
```

**原则**：实时走 MQTT 直连 EMQX（低延迟），历史/统计走 HTTP API（按需查询），安全靠 EMQX 内置 JWT 认证。

## 项目结构

```
INV-MQTT/
├── inv_app/                          # Flutter 移动端应用
│   ├── lib/
│   │   ├── core/                     # 核心模块（配置、路由、服务、主题、通用组件）
│   │   │   ├── config/               # 应用配置（MQTT Broker / API 地址）
│   │   │   ├── entities/             # 逆变器数据模型
│   │   │   ├── router/               # go_router + AuthGuard 路由守卫
│   │   │   ├── services/             # MQTT / API / Storage / Provision 服务
│   │   │   ├── theme/                # 亮色/暗色主题
│   │   │   ├── utils/                # SN 校验工具（CRC16-Modbus）
│   │   │   └── widgets/              # 通用组件（仪表盘、状态灯、相位条）
│   │   └── features/                 # 功能模块（BLoC 模式）
│   │       ├── alarm/                # 告警管理
│   │       ├── auth/                 # 用户认证（登录/注册/找回密码）
│   │       ├── dashboard/            # 仪表盘
│   │       ├── device/               # 设备管理（详情/控制/参数/WiFi配网）
│   │       ├── profile/              # 个人中心/设置/设备分享
│   │       ├── station/              # 电站管理
│   │       └── statistics/           # 数据统计/图表分析
│   ├── android/                      # Android 原生配置
│   ├── ios/                          # iOS 原生配置
│   └── pubspec.yaml                  # Flutter 依赖
│
├── inv_api_server/                   # Go REST API 服务（端口 8080）
│   ├── cmd/                          # 入口文件
│   ├── internal/
│   │   ├── config/                   # 配置管理（YAML）
│   │   ├── handler/                  # HTTP 路由处理（Auth/Device/Station/Alarm/Admin/WS）
│   │   ├── middleware/               # JWT 认证中间件
│   │   ├── model/                    # 数据模型
│   │   ├── repository/               # 数据库操作
│   │   └── service/                  # 业务逻辑（邮件服务）
│   ├── pkg/
│   │   ├── jwt/                      # JWT 签发与验证（HS256）
│   │   ├── logger/                   # 日志（Uber Zap）
│   │   ├── response/                 # 统一响应格式
│   │   └── sn/                       # SN 编号规则与 CRC16 校验
│   └── web/admin/                    # 管理后台页面
│
├── inv_device_server/                # Go 设备通讯服务（端口 8081）
│   ├── cmd/                          # 入口文件
│   ├── internal/
│   │   ├── config/                   # 配置管理（MQTT_PASSWORD 支持环境变量注入）
│   │   ├── mqtt/                     # MQTT 客户端 + 共享订阅 + Redis Streams 消费者
│   │   │   ├── client.go            # EMQX 连接 + $share/inv-group/ 共享订阅
│   │   │   └── stream_consumer.go  # Redis Streams 消费（消费组/ACK/死信）
│   │   ├── model/                    # 设备实时数据模型
│   │   ├── repository/               # 数据持久化（SN 校验门禁）
│   │   └── service/                  # 数据处理 + remap兼容 + Redis Pub/Sub + Streams 发布
│   └── pkg/
│       ├── logger/                   # 日志
│       └── sn/                       # SN 编号生成与校验
│
├── deploy/                           # 部署与运维
│   ├── docker-compose.yml            # 一键部署（EMQX + device×2 + api + PG + Redis）
│   ├── k8s-device-server.yaml        # K8s Deployment + HPA（2~10 副本自动扩缩）
│   ├── prometheus_alerts.yml         # Prometheus 告警规则
│   └── mqtt_benchmark.sh             # MQTT 压测脚本
│
├── database/                         # 数据库脚本
│   ├── schema.sql                    # 初始化建表（20+ 表、视图、触发器、清理函数）
│   ├── migration_timescaledb.sql     # TimescaleDB 兼容引导（实际结构由编号迁移管理）
│   └── migration_*.sql               # 增量迁移脚本
│
├── docs/                             # 文档
│   ├── MQTT协议文档.md                # MQTT 通信协议规范（上下行数据格式）
│   ├── 系统参数规范_48V离网逆变器.md    # 逆变器参数定义
│   ├── ARM_ESP32_UART_Protocol.md    # ARM ↔ ESP32 UART 帧协议
│   ├── emqx_rule_engine_sql.md       # EMQX Rule Engine SQL 参考
│   └── 架构升级任务清单.md             # 架构升级执行手册
│
├── 光伏逆变器物联网监控系统 — 流程文档.md   # 架构流程详细文档
├── start_all.bat                     # Windows 一键启动脚本
└── README.md
```

## 技术栈

| 组件 | 技术 | 说明 |
|------|------|------|
| 移动端 | Flutter 3.x + Dart | 跨平台 App（Android/iOS/Web/Desktop） |
| 状态管理 | flutter_bloc (BLoC 模式) | 事件驱动状态管理 |
| 路由 | go_router + AuthGuard | 声明式路由 + 鉴权守卫 |
| HTTP 客户端 | Dio | REST API 调用 + 拦截器 |
| MQTT 客户端 | mqtt_client（Flutter）/ paho.mqtt.golang（Go） | 设备数据订阅 |
| MQTT Broker | **EMQX** | 生产级 MQTT Broker，内置 JWT 认证 |
| App 鉴权 | **EMQX 内置 JWT（HS256）** | App 用 JWT token 直连 EMQX，与 API Server 共用 Secret |
| 共享订阅 | **EMQX $share 共享订阅** | inv_device_server 多实例自动负载均衡 |
| 后端 API | Go 1.22 + Gin | REST API + Admin Panel |
| 后端设备 | Go 1.21 + Gin | 设备通讯服务 + Redis Streams 消费 |
| 数据库 | PostgreSQL 15+ | 关系型数据 + 元数据 + JSONB |
| 时序数据库 | TimescaleDB（按需） | PG 插件，超表 + 自动压缩 + 连续聚合 |
| 缓存 | Redis 7 | 设备影子 + Pub/Sub 实时推送 + Streams 缓冲 |
| 消息缓冲 | **Redis Streams** | 消费组 + ACK + 死信队列 |
| 认证 | JWT（HS256） | API Server 签发，EMQX 验签 |
| 日志 | Uber Zap | 结构化日志 |
| 图表 | fl_chart | Flutter 端图表渲染 |

## 快速开始

### 环境要求

- Flutter 3.x
- Go 1.21+
- PostgreSQL 15+
- Redis 7
- EMQX 5.x（已单独部署在服务器上）

### 1. 初始化数据库

```bash
psql -U postgres -c "CREATE DATABASE inv_mqtt;"
psql -U postgres -d inv_mqtt -f database/schema.sql

# 启用 TimescaleDB 扩展；后续时序结构和策略由编号迁移统一管理
psql -U postgres -d inv_mqtt -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"
# migration_timescaledb.sql 仅作为旧环境兼容引导，不再作为当前结构的独立迁移入口
```

### 2. 配置 EMQX JWT 认证

在 EMQX Dashboard 中配置 JWT 认证：

| 字段 | 值 |
|------|-----|
| 认证方式 | JWT |
| JWT 来自于 | password |
| 加密方式 | hmac-based |
| Secret | `CSKJ_INV_APP_SERVER_APP_MQTT_KEY` |
| Secret 使用 Base64 编码 | 不勾选 |
| 过期后断开连接 | ✅ |

### 3. 启动后端服务

```bash
# Device Server（端口 8081）
# MQTT_PASSWORD 需设为有效的 JWT token（由 API Server 签发，Secret 与 EMQX 一致）
export MQTT_PASSWORD="your_jwt_token"
cd inv_device_server && go run cmd/main.go

# API Server（端口 8080）
cd inv_api_server && go run cmd/main.go
```

或使用 Docker Compose 一键启动全部服务：

```bash
cd deploy
docker compose up -d
```

### 4. 启动 Flutter 应用

```bash
cd inv_app
flutter pub get
flutter run
```

## 服务端口

| 服务 | 端口 | 说明 |
|------|------|------|
| API Server | 8080 | REST API + Admin Panel (`/admin`) |
| Device Server | 8081 | 设备 MQTT 数据桥接 + `/metrics` 端点 |
| EMQX MQTT | 8883 | MQTT SSL 端口（`jiuxiaoyw.online`） |
| EMQX Dashboard | 18083 | EMQX 管理后台 |
| PostgreSQL | 5432 | 数据库 |
| Redis | 6379 | 缓存 + Pub/Sub + Streams |

## 核心设计

### 实时数据链路

```
设备(ESP32) → EMQX → $share/inv-group/ → inv_device_server(Go) → PostgreSQL（时序 + 元数据）
                                                                  → Redis（缓存 + Pub/Sub + Streams）
                   → App MQTT 直连（JWT 认证，订阅 cs_inv/{sn}/#）
```

App 设备详情页实时数据**完全走 MQTT 推送**，不再通过 HTTP API 轮询。进入页面后 MQTT 订阅即开始推送，下拉刷新不触发额外网络请求。

### 历史/统计数据链路

```
App → HTTP REST → inv_api_server → PostgreSQL 查询返回
```

电站统计 `today_energy` 从 `device_day_data` 实时聚合，确保即使 `device_realtime_data` 或 `station_day_data` 数据不完整也能返回正确值。

### SN 编号校验

设备 SN 为 16 位编码（例 `H1CNA00135000014`），**所有设备入库入口均强制校验**，无效 SN 自动拒绝写入数据库。

校验入口：
- `device_repository.UpsertDeviceInfo`（设备信息入库）
- `InternalDeviceStatus`（设备状态上报）
- `InternalDeviceData`（设备数据上报）

SN 编码结构：

| 位置 | 含义 |
|------|------|
| 0-1 | 制造商（H/O/S + 0-9/A-Z） |
| 2-3 | 国家代码 |
| 4-7 | 客户等级 + 数字编号 |
| 8-9 | 年月（自定义编码） |
| 10-14 | 5 位序列号 |
| 15 | CRC16-Modbus 校验位 |

### 高可用设计

- **共享订阅**：`$share/inv-group/` 前缀，EMQX 轮询分发消息给多个 inv_device_server 实例
- **Redis 共享状态**：多实例通过 Redis HSET 共享设备在线状态
- **Session 清理**：`SetCleanSession(true)` 断开即清理
- **K8s HPA**：基于 CPU/内存自动扩缩 2~10 副本

### OTA 固件升级

OTA（Over-The-Air）支持通过管理后台远程升级设备固件，支持 ARM 和 ESP 芯片。

**升级流程：**

```
管理后台上传固件 → 创建升级任务 → API Server 分发命令
                                      │
                                      ▼
                              inv_device_server（转发 MQTT 命令）
                                      │
                                      ▼
                              cs_inv/{sn}/ota/cmd → 设备
                                      │
                                      ▼
                              设备下载固件 → 升级 → 上报进度
                                      │
                                      ▼
                              cs_inv/{sn}/ota/status → inv_device_server
                                      │
                                      ▼
                              转换格式 → API Server（更新数据库）
                                      │
                                      ▼
                              APP / 管理后台显示进度
```

**MQTT 主题：**

| 主题 | 方向 | 说明 |
|------|------|------|
| `cs_inv/{sn}/ota/cmd` | 下行 | 升级命令（command: start） |
| `cs_inv/{sn}/ota/status` | 上行 | 状态上报（progress / success / failed） |

**OTA 命令格式：**

```json
{
  "command": "start",
  "target": "esp",
  "url": "http://server:8080/firmware/filename.bin",
  "version": "1.0.0",
  "file_size": 1081216,
  "file_md5": "abc123...",
  "task_id": "73"
}
```

**设备状态上报格式：**

```json
{
  "device_id": "H1CNA00135000014",
  "current_version": "1.1.0",
  "state": "upgrading",
  "progress": 45,
  "status_message": "正在下载固件...",
  "error_message": ""
}
```

**功能特性：**
- 支持 ARM / ESP 双芯片独立升级
- 固件文件自动计算 MD5 和 SHA256
- 升级失败自动标记任务状态
- 重复升级自动复用已有任务（避免重复创建）
- 实时进度跟踪（设备上报 → 数据库 → APP/后台显示）

## 主要功能

### Flutter APP
- 用户登录/注册/密码重置（手机 + 邮箱）
- 电站概览与设备详情
- 设备实时数据监控（电压、电流、功率、电量、温度）
- 告警管理与推送
- 数据统计与图表分析
- 设备分享与权限管理
- 设备 Wi-Fi 配网（ESP32）
- QR 码扫码添加设备
- **OTA 固件升级**（支持 ARM/ESP 芯片，实时进度显示）

### API Server
- 用户认证与授权（JWT HS256）
- 电站与设备 CRUD
- 告警记录查询与处理
- WebSocket 实时推送（管理后台用）
- Admin Panel 管理后台（设备/用户/电站/告警/型号/日志/OTA）
- **OTA 固件管理**（上传固件、创建升级任务、推送/分发、进度跟踪）
- **OTA 状态接收**（接收设备上报的升级进度，自动更新任务状态）

### Device Server
- EMQX 共享订阅连接（`$share/inv-group/`）
- 设备数据解析（AC/Battery/PV/Status/Energy/Cells/Alarm）
- 旧字段兼容映射（remapLegacyPV/Energy）
- Redis Pub/Sub 实时推送
- Redis Streams 消息缓冲 + 死信队列
- 设备在线状态管理与离线检测
- Prometheus `/metrics` 端点
- **OTA 命令下发**（转发升级命令到设备 MQTT 主题）
- **OTA 状态转发**（接收设备 OTA 状态上报，转换格式后转发给 API Server）

## 适用的逆变器型号

- **CS-I10-6k2** 48V 单相离网逆变器（ESP32-C3 WiFi 通讯模块）

## 文档

- [MQTT 协议文档](docs/MQTT协议文档.md) — 完整的 MQTT 主题定义和数据格式
- [系统参数规范](docs/系统参数规范_48V离网逆变器.md) — 逆变器参数定义
- [ARM ESP32 UART 协议](docs/ARM_ESP32_UART_Protocol.md) — ARM ↔ ESP32 帧协议
- [EMQX Rule Engine SQL](docs/emqx_rule_engine_sql.md) — 规则引擎 SQL 参考
- [架构升级任务清单](docs/架构升级任务清单.md) — 架构升级执行手册
- [架构流程文档](光伏逆变器物联网监控系统 — 流程文档.md) — 系统架构与数据流程说明

---

最后修改时间：2026-07-14 20:22:00（Asia/Shanghai）
