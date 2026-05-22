# INV-MQTT 光伏逆变器物联网监控系统

基于 MQTT 协议的光伏逆变器远程监控平台，支持设备数据采集、实时监控、告警管理、用户管理等功能。

## 系统架构

```
┌──────────────────────────────────────────────────────────────┐
│                      用户端                                   │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  Flutter APP (inv_app)                               │    │
│  │  Android / iOS / Web / Windows / macOS / Linux       │    │
│  └────────┬────────────────────────┬────────────────────┘    │
│           │  HTTP REST (Dio)       │  MQTT over WS           │
│           │  :8080/api/v1          │  :8083/mqtt              │
└───────────┼────────────────────────┼─────────────────────────┘
            │                        │
┌───────────┼────────────────────────┼─────────────────────────┐
│           ▼                        ▼                          │
│  ┌───────────────┐     ┌──────────────────────┐              │
│  │ inv_api_server │     │  inv_device_server   │              │
│  │ (Go :8080)     │◄───►│  (Go :8081)          │              │
│  └───────┬───────┘     └──────────┬───────────┘              │
│          │                        │                           │
│          ▼                        ▼                           │
│  ┌───────────────┐     ┌──────────────────────┐              │
│  │  PostgreSQL    │     │  MQTT Broker         │              │
│  │  (inv_mqtt)    │     │  (Mosquitto :1883)   │              │
│  └───────────────┘     └──────────┬───────────┘              │
│                                   │                           │
│                          ┌────────▼───────────┐              │
│                          │  ESP32-C3 WiFi 模块 │              │
│                          │  (逆变器端)          │              │
│                          └────────────────────┘              │
└──────────────────────────────────────────────────────────────┘
```

## 项目结构

```
INV-MQTT/
├── inv_app/                    # Flutter 移动端应用
│   ├── lib/
│   │   ├── core/               # 核心模块（配置、路由、服务、主题、通用组件）
│   │   └── features/           # 功能模块
│   │       ├── alarm/          # 告警管理
│   │       ├── auth/           # 用户认证（登录/注册）
│   │       ├── device/         # 设备管理
│   │       ├── profile/        # 个人中心/设置
│   │       ├── station/        # 电站管理
│   │       └── statistics/     # 数据统计
│   ├── android/                # Android 原生配置
│   ├── ios/                    # iOS 原生配置
│   └── pubspec.yaml            # Flutter 依赖
│
├── inv_api_server/             # Go REST API 服务
│   ├── cmd/                    # 入口文件
│   ├── internal/
│   │   ├── config/             # 配置管理
│   │   ├── handler/            # HTTP 路由处理
│   │   ├── middleware/         # JWT 认证中间件
│   │   ├── model/              # 数据模型
│   │   ├── repository/         # 数据库操作
│   │   └── service/            # 业务逻辑
│   └── web/admin/              # 管理后台页面
│
├── inv_device_server/          # Go 设备通讯服务
│   ├── cmd/                    # 入口文件
│   ├── internal/
│   │   ├── config/             # 配置管理
│   │   ├── mqtt/               # MQTT 客户端
│   │   ├── model/              # 设备模型
│   │   ├── repository/         # 数据持久化
│   │   └── service/            # 数据服务
│
├── database/                   # 数据库迁移脚本
│   ├── schema.sql              # 初始化建表
│   └── migration_*.sql         # 增量迁移脚本
│
├── docs/                       # 文档
│   ├── MQTT协议文档.md          # MQTT 通信协议规范
│   ├── 系统参数规范_48V离网逆变器.md
│   └── ARM_ESP32_UART_Protocol.md
│
├── 光伏逆变器物联网监控系统 — 流程文档.md   # 架构流程文档
├── start_all.bat               # Windows 一键启动脚本
└── README.md
```

## 技术栈

| 组件 | 技术 |
|------|------|
| 移动端 | Flutter 3.x + Dart |
| 状态管理 | flutter_bloc (BLoC 模式) |
| 路由 | go_router |
| HTTP 客户端 | Dio |
| MQTT 客户端 | mqtt_client |
| 后端 API | Go 1.22 + Gin |
| 后端设备 | Go 1.21 |
| 数据库 | PostgreSQL |
| 缓存 | Redis |
| 消息协议 | MQTT 3.1.1 (Mosquitto Broker) |
| 认证 | JWT |
| 图表 | fl_chart |

## 快速开始

### 环境要求

- Flutter 3.x
- Go 1.21+
- PostgreSQL 15+
- Redis
- Mosquitto MQTT Broker

### 1. 启动 MQTT Broker

```bash
# Windows
"C:\Program Files\mosquitto\mosquitto.exe" -c mosquitto_custom.conf -v
```

### 2. 初始化数据库

```bash
psql -U postgres -c "CREATE DATABASE inv_mqtt;"
psql -U postgres -d inv_mqtt -f database/schema.sql
```

### 3. 启动后端服务

```bash
# 启动设备通讯服务 (端口 8081)
cd inv_device_server
go run cmd/main.go

# 启动 API 服务 (端口 8080)
cd inv_api_server
go run cmd/main.go
```

或使用一键启动脚本（Windows）：

```bash
start_all.bat
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
| API Server | 8080 | REST API + 管理后台 |
| Device Server | 8081 | 设备 MQTT 数据桥接 |
| MQTT TCP | 1883 | MQTT 协议端口 |
| MQTT WebSocket | 8083 | MQTT over WebSocket |

## 主要功能

### Flutter APP
- 用户登录/注册/密码重置
- 电站概览与设备详情
- 设备实时数据监控（电压、电流、功率、电量）
- 告警管理与推送
- 数据统计与图表分析
- 设备分享与权限管理
- 设备 Wi-Fi 配网（ESP32）

### API Server
- 用户认证与授权（JWT）
- 电站与设备 CRUD
- 告警记录查询
- WebSocket 实时推送
- 管理后台（Admin Panel）

### Device Server
- MQTT Broker 连接
- 设备数据解析与入库
- 设备在线状态管理
- 命令下发（控制参数）

## 适用的逆变器型号

- **CS-I10-6k2** 48V 单相离网逆变器（ESP32-C3 WiFi 通讯模块）

## 文档

- [MQTT 协议文档](docs/MQTT协议文档.md) — 完整的 MQTT 主题定义和数据格式
- [系统参数规范](docs/系统参数规范_48V离网逆变器.md) — 逆变器参数定义
- [架构流程文档](光伏逆变器物联网监控系统 — 流程文档.md) — 系统架构与数据流程说明
