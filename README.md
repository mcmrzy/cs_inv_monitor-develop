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
    │                                  │
    └── HTTP REST ───────────→ inv_api_server (Go :8080)
                                       │
                                       ▼
                                 Admin Panel + WebSocket 实时推送
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
│   │   │   ├── client.go            # EMQX 连接 + $share/inv-group/ 共享订阅 + remap
│   │   │   └── stream_consumer.go  # Redis Streams 消费（消费组/ACK/死信）
│   │   ├── model/                    # 设备实时数据模型
│   │   ├── repository/               # 数据持久化（SN 校验门禁）
│   │   └── service/                  # 数据处理 + Redis Pub/Sub + Streams 发布
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
│   ├── migration_timescaledb.sql     # TimescaleDB 超表 + 压缩 + 连续聚合
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
| 数据库 | PostgreSQL 15+ | 关系型数据 + 元数据 + JSONB 超表 |
| 时序数据库 | TimescaleDB（按需） | PG 插件，自动压缩 + 连续聚合 |
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

# 可选：启用 TimescaleDB 时序优化
psql -U postgres -d inv_mqtt -f database/migration_timescaledb.sql
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
# Device Server（端口 8081，需设 MQTT 密码环境变量）
export MQTT_PASSWORD="your_mqtt_password"
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

## 核心设计

### 实时数据链路

```
设备(ESP32) → EMQX → $share/inv-group/ → inv_device_server(Go) → PostgreSQL（时序 + 元数据）
                                                                  → Redis（缓存 + Pub/Sub + Streams）
                   → App MQTT 直连（JWT 认证，订阅 cs_inv/{sn}/#）
```

### 历史/统计数据链路

```
App → HTTP REST → inv_api_server → PostgreSQL 查询返回
App → WebSocket → inv_api_server → Redis Pub/Sub 实时推送
```

### 高可用设计

- **共享订阅**：`$share/inv-group/` 前缀，EMQX 轮询分发消息给多个 inv_device_server 实例
- **Redis 共享状态**：多实例通过 Redis HSET 共享设备在线状态
- **Session 清理**：`SetCleanSession(true)` 断开即清理
- **K8s HPA**：基于 CPU/内存自动扩缩 2~10 副本

### SN 编号校验

设备 SN 为 16 位编码（例 `H1CNA00135000014`），包含制造商、国家、客户等级、生产年月、序列号、CRC16-Modbus 校验位。所有设备入库入口均强制校验，无效 SN 自动拒绝。

| 位置 | 进制 |
|------|------|
| 0-1 | 制造商（H/O/S + 0-9/A-Z） |
| 2-3 | 国家代码 |
| 4-7 | 客户等级 + 数字编号 |
| 8-9 | 年月（自定义编码） |
| 10-14 | 5 位序列号 |
| 15 | CRC16-Modbus 校验位 |

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

### API Server
- 用户认证与授权（JWT HS256）
- 电站与设备 CRUD
- 告警记录查询与处理
- WebSocket 实时推送
- Admin Panel 管理后台（设备/用户/电站/告警/型号/日志）

### Device Server
- EMQX 共享订阅连接（`$share/inv-group/`）
- 设备数据解析（AC/Battery/PV/Status/Energy/Cells/Alarm）
- 旧字段兼容映射（remapLegacyPV/Energy）
- Redis Pub/Sub 实时推送
- Redis Streams 消息缓冲 + 死信队列
- 设备在线状态管理与离线检测
- Prometheus `/metrics` 端点

## 适用的逆变器型号

- **CS-I10-6k2** 48V 单相离网逆变器（ESP32-C3 WiFi 通讯模块）

## 文档

- [MQTT 协议文档](docs/MQTT协议文档.md) — 完整的 MQTT 主题定义和数据格式
- [系统参数规范](docs/系统参数规范_48V离网逆变器.md) — 逆变器参数定义
- [ARM ESP32 UART 协议](docs/ARM_ESP32_UART_Protocol.md) — ARM ↔ ESP32 帧协议
- [EMQX Rule Engine SQL](docs/emqx_rule_engine_sql.md) — 规则引擎 SQL 参考
- [架构升级任务清单](docs/架构升级任务清单.md) — 架构升级执行手册
- [架构流程文档](光伏逆变器物联网监控系统 — 流程文档.md) — 系统架构与数据流程说明
