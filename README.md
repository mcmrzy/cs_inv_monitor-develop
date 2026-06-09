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

# 可选：启用 TimescaleDB 时序优化（需先安装 timescaledb 扩展）
psql -U postgres -d inv_mqtt -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"
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
