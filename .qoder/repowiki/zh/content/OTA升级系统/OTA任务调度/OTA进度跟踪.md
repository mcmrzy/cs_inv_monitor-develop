# OTA进度跟踪

<cite>
**本文档引用的文件**
- [README.md](file://README.md)
- [inv_api_server/internal/handler/ota_handler.go](file://inv_api_server/internal/handler/ota_handler.go)
- [inv_api_server/internal/service/ota_service.go](file://inv_api_server/internal/service/ota_service.go)
- [inv_api_server/internal/repository/ota_repository.go](file://inv_api_server/internal/repository/ota_repository.go)
- [inv_api_server/internal/repository/repositories.go](file://inv_api_server/internal/repository/repositories.go)
- [inv_api_server/internal/handler/ws_handler.go](file://inv_api_server/internal/handler/ws_handler.go)
- [inv_device_server/internal/mqtt/client.go](file://inv_device_server/internal/mqtt/client.go)
- [inv_device_server/internal/service/protocol_parser.go](file://inv_device_server/internal/service/protocol_parser.go)
- [inv_device_server/internal/model/device.go](file://inv_device_server/internal/model/device.go)
- [inv-admin-frontend/src/pages/ota/index.tsx](file://inv-admin-frontend/src/pages/ota/index.tsx)
- [inv-admin-frontend/src/pages/portal/DeviceMonitorPage.tsx](file://inv-admin-frontend/src/pages/portal/DeviceMonitorPage.tsx)
- [tools/stress_test/main.go](file://tools/stress_test/main.go)
- [database/schema.sql](file://database/schema.sql)
</cite>

## 目录
1. [简介](#简介)
2. [项目结构](#项目结构)
3. [核心组件](#核心组件)
4. [架构总览](#架构总览)
5. [详细组件分析](#详细组件分析)
6. [依赖关系分析](#依赖关系分析)
7. [性能考虑](#性能考虑)
8. [故障排查指南](#故障排查指南)
9. [结论](#结论)
10. [附录](#附录)

## 简介
本文件面向OTA进度跟踪系统，系统化阐述任务进度计算算法与逻辑（总体进度、设备级别进度、完成率）、进度数据的采集与聚合机制、实时性保障（WebSocket推送与轮询）、进度数据存储结构与查询优化、异常处理策略（设备离线、进度丢失等）、可视化展示与数据导出、性能监控与优化建议，以及相关API接口与使用示例。

## 项目结构
系统采用前后端分离架构，主要模块包括：
- API网关与后端服务：负责认证、路由、OTA任务管理、进度聚合与推送
- 设备侧服务：负责MQTT连接、协议解析、OTA命令下发与状态接收
- 前端管理端：负责OTA任务管理、进度可视化与实时监控
- 数据库与缓存：持久化设备与遥测数据，支撑查询与聚合
- 工具链：压力测试、部署脚本、监控配置等

```mermaid
graph TB
subgraph "前端"
FE_Admin["管理端页面<br/>OTA任务与进度"]
FE_Portal["门户页面<br/>实时监控轮询"]
end
subgraph "后端"
GW["API网关"]
API_Server["API服务<br/>OTA处理器/服务/仓储"]
WS["WebSocket处理器"]
end
subgraph "设备侧"
Dev_Server["设备服务<br/>MQTT客户端/协议解析"]
Device["设备终端<br/>上报OTA状态"]
end
subgraph "数据层"
PG[(PostgreSQL<br/>device_telemetry等)]
Redis[(Redis缓存)]
end
FE_Admin --> GW
FE_Portal --> GW
GW --> API_Server
API_Server --> PG
API_Server --> Redis
API_Server --> WS
WS --> FE_Admin
API_Server --> Dev_Server
Dev_Server --> Device
Device --> Dev_Server
Dev_Server --> PG
Dev_Server --> Redis
```

图示来源
- [README.md:253-342](file://README.md#L253-L342)
- [inv_api_server/internal/handler/ws_handler.go:1-61](file://inv_api_server/internal/handler/ws_handler.go#L1-L61)
- [inv_device_server/internal/mqtt/client.go:1-283](file://inv_device_server/internal/mqtt/client.go#L1-L283)

章节来源
- [README.md:253-342](file://README.md#L253-L342)

## 核心组件
- OTA处理器（API层）：负责OTA任务的创建、推送、重试、取消与仪表盘查询
- OTA服务（业务层）：封装OTA命令构建、HTTP分发、并发控制与错误处理
- OTA仓储（数据层）：负责OTA任务、设备升级记录与进度状态的持久化与查询
- 设备服务（设备侧）：负责MQTT连接、OTA命令下发、状态变更处理与在线状态维护
- 协议解析器（设备侧）：负责消息解包、payload解析与状态防抖
- WebSocket处理器（后端）：负责实时推送与鉴权
- 前端页面：负责进度展示、操作按钮与轮询刷新

章节来源
- [inv_api_server/internal/handler/ota_handler.go](file://inv_api_server/internal/handler/ota_handler.go)
- [inv_api_server/internal/service/ota_service.go:1-231](file://inv_api_server/internal/service/ota_service.go#L1-L231)
- [inv_api_server/internal/repository/ota_repository.go](file://inv_api_server/internal/repository/ota_repository.go)
- [inv_device_server/internal/mqtt/client.go:1-283](file://inv_device_server/internal/mqtt/client.go#L1-L283)
- [inv_device_server/internal/service/protocol_parser.go:242-287](file://inv_device_server/internal/service/protocol_parser.go#L242-L287)
- [inv_api_server/internal/handler/ws_handler.go:1-61](file://inv_api_server/internal/handler/ws_handler.go#L1-L61)
- [inv-admin-frontend/src/pages/ota/index.tsx:674-705](file://inv-admin-frontend/src/pages/ota/index.tsx#L674-L705)

## 架构总览
OTA进度跟踪的整体流程如下：
- 管理后台上传固件并创建升级任务
- API服务将OTA命令通过HTTP分发至设备服务
- 设备服务通过MQTT将命令推送到设备
- 设备执行升级并向设备服务上报进度状态
- 设备服务转换格式并写入数据库
- API服务聚合进度并可通过WebSocket或轮询向前端展示

```mermaid
sequenceDiagram
participant Admin as "管理后台"
participant API as "API服务"
participant DevSvc as "设备服务"
participant MQ as "MQTT Broker"
participant Device as "设备终端"
Admin->>API : "创建OTA任务"
API->>DevSvc : "HTTP下发OTA命令"
DevSvc->>MQ : "发布OTA命令到cs_inv/{sn}/ota/cmd"
MQ-->>Device : "下行OTA命令"
Device->>DevSvc : "上报进度状态cs_inv/{sn}/ota/status"
DevSvc->>API : "转换并入库"
API-->>Admin : "WebSocket/轮询推送进度"
```

图示来源
- [README.md:253-342](file://README.md#L253-L342)
- [inv_api_server/internal/service/ota_service.go:185-231](file://inv_api_server/internal/service/ota_service.go#L185-L231)
- [inv_device_server/internal/mqtt/client.go:270-283](file://inv_device_server/internal/mqtt/client.go#L270-L283)

## 详细组件分析

### 任务进度计算与完成率
- 总体进度：基于任务下设备总数与已完成（成功+失败）数量计算百分比
- 设备级别进度：由设备上报的progress字段反映
- 完成率：成功数占已处理（成功+失败）的比例

```mermaid
flowchart TD
Start(["开始"]) --> Load["加载任务详情<br/>total_devices, success_count, failed_count"]
Load --> CalcDone["done = success + failed"]
CalcDone --> CheckTotal{"total > 0 ?"}
CheckTotal --> |否| PctZero["pct = 0"]
CheckTotal --> |是| PctCalc["pct = round(done/total*100)"]
PctZero --> Render["渲染进度条"]
PctCalc --> Render
Render --> End(["结束"])
```

图示来源
- [inv-admin-frontend/src/pages/ota/index.tsx:674-705](file://inv-admin-frontend/src/pages/ota/index.tsx#L674-L705)

章节来源
- [inv-admin-frontend/src/pages/ota/index.tsx:674-705](file://inv-admin-frontend/src/pages/ota/index.tsx#L674-L705)

### 进度数据采集与聚合
- 设备上报：设备通过MQTT主题上报进度状态
- 设备服务解析：协议解析器处理payload并进行状态防抖
- 数据入库：设备服务将状态转换并写入数据库
- API聚合：API服务从数据库聚合任务进度并提供查询接口

```mermaid
sequenceDiagram
participant Device as "设备"
participant DevSvc as "设备服务"
participant DB as "数据库"
participant API as "API服务"
participant Admin as "管理后台"
Device->>DevSvc : "上报进度状态"
DevSvc->>DevSvc : "解析payload/状态防抖"
DevSvc->>DB : "写入进度记录"
API->>DB : "聚合任务进度"
API-->>Admin : "返回进度数据"
```

图示来源
- [inv_device_server/internal/service/protocol_parser.go:242-287](file://inv_device_server/internal/service/protocol_parser.go#L242-L287)
- [inv_device_server/internal/mqtt/client.go:270-283](file://inv_device_server/internal/mqtt/client.go#L270-L283)
- [inv_api_server/internal/repository/repositories.go:1111-1273](file://inv_api_server/internal/repository/repositories.go#L1111-L1273)

章节来源
- [inv_device_server/internal/service/protocol_parser.go:242-287](file://inv_device_server/internal/service/protocol_parser.go#L242-L287)
- [inv_device_server/internal/mqtt/client.go:270-283](file://inv_device_server/internal/mqtt/client.go#L270-L283)
- [inv_api_server/internal/repository/repositories.go:1111-1273](file://inv_api_server/internal/repository/repositories.go#L1111-L1273)

### 实时性保障（WebSocket与轮询）
- WebSocket推送：后端建立长连接，前端订阅任务进度变化
- 轮询机制：前端定时请求后端接口以刷新进度
- 鉴权与限流：WebSocket接入需JWT校验，限制单用户并发连接数

```mermaid
sequenceDiagram
participant FE as "前端"
participant WS as "WebSocket处理器"
participant API as "API服务"
participant DB as "数据库"
FE->>WS : "建立WebSocket连接(带token)"
WS->>WS : "JWT鉴权/连接数限制"
WS-->>FE : "连接成功"
API->>DB : "查询/更新进度"
API-->>WS : "推送进度事件"
WS-->>FE : "实时推送进度"
FE->>API : "定时轮询(如需)"
```

图示来源
- [inv_api_server/internal/handler/ws_handler.go:1-61](file://inv_api_server/internal/handler/ws_handler.go#L1-L61)
- [inv-admin-frontend/src/pages/portal/DeviceMonitorPage.tsx:61-103](file://inv-admin-frontend/src/pages/portal/DeviceMonitorPage.tsx#L61-L103)

章节来源
- [inv_api_server/internal/handler/ws_handler.go:1-61](file://inv_api_server/internal/handler/ws_handler.go#L1-L61)
- [inv-admin-frontend/src/pages/portal/DeviceMonitorPage.tsx:61-103](file://inv-admin-frontend/src/pages/portal/DeviceMonitorPage.tsx#L61-L103)

### 存储结构与查询优化
- 关键表：device_telemetry（设备遥测/状态）、devices（设备元数据）、device_lifecycle（生命周期事件）
- 查询优化点：按设备与时间分区、索引、按topic与设备分组取最新记录、聚合查询
- JSON字段：支持灵活的数据结构，便于扩展

```mermaid
erDiagram
DEVICES {
string sn PK
string model
string firmware_arm
string firmware_esp
int status
timestamp last_online_at
}
DEVICE_TELEMETRY {
int id PK
string device_sn FK
string topic
jsonb data
timestamp time
}
DEVICE_LIFECYCLE {
int id PK
string device_sn FK
string event_type
string description
int triggered_by
json metadata
timestamp created_at
}
DEVICES ||--o{ DEVICE_TELEMETRY : "has"
DEVICES ||--o{ DEVICE_LIFECYCLE : "has"
```

图示来源
- [database/schema.sql](file://database/schema.sql)

章节来源
- [database/schema.sql](file://database/schema.sql)
- [inv_api_server/internal/repository/repositories.go:1111-1273](file://inv_api_server/internal/repository/repositories.go#L1111-L1273)

### 异常处理与容错
- 设备离线：通过在线状态维护与超时检测，将离线设备标记为离线
- 进度丢失：通过增量上报与最终一致性保证，结合重试与取消机制
- 错误传播：设备服务在命令下发失败时记录错误并返回响应码
- 并发控制：OTA服务限制并发度，避免资源争用

```mermaid
flowchart TD
A["接收设备状态"] --> B{"payload有效?"}
B --> |否| E["解析错误/丢弃"]
B --> |是| C["状态防抖/去重"]
C --> D["写入数据库/更新任务"]
D --> F{"是否离线?"}
F --> |是| G["标记离线/清理缓存"]
F --> |否| H["保持在线/更新时间戳"]
```

图示来源
- [inv_device_server/internal/service/protocol_parser.go:242-287](file://inv_device_server/internal/service/protocol_parser.go#L242-L287)
- [inv_api_server/internal/repository/repositories.go:1689-1694](file://inv_api_server/internal/repository/repositories.go#L1689-L1694)

章节来源
- [inv_device_server/internal/service/protocol_parser.go:242-287](file://inv_device_server/internal/service/protocol_parser.go#L242-L287)
- [inv_api_server/internal/repository/repositories.go:1689-1694](file://inv_api_server/internal/repository/repositories.go#L1689-L1694)

### 可视化展示与数据导出
- 管理后台：展示任务进度条、重试/取消操作入口
- 门户页面：定时轮询实时数据，生成图表（如功率曲线）
- 数据导出：可通过API接口批量拉取进度与事件数据

章节来源
- [inv-admin-frontend/src/pages/ota/index.tsx:674-705](file://inv-admin-frontend/src/pages/ota/index.tsx#L674-L705)
- [inv-admin-frontend/src/pages/portal/DeviceMonitorPage.tsx:61-103](file://inv-admin-frontend/src/pages/portal/DeviceMonitorPage.tsx#L61-L103)

### API接口与使用示例
- OTA固件管理
  - GET /api/v1/ota/firmware
  - GET /api/v1/ota/firmware/:id
  - POST /api/v1/ota/firmware
  - DELETE /api/v1/ota/firmware/:id
- 升级任务管理
  - GET /api/v1/ota/upgrades/dashboard
  - POST /api/v1/ota/upgrades/push
  - GET /api/v1/ota/upgrades/firmware/:firmwareId
  - POST /api/v1/ota/upgrades/retry
  - POST /api/v1/ota/upgrades/cancel
- APP端接口（公开）
  - GET /api/v1/ota/tasks
  - GET /api/v1/ota/tasks/:id
  - GET /api/v1/ota/tasks/:id/devices

章节来源
- [inv_api_server/cmd/main.go:548-563](file://inv_api_server/cmd/main.go#L548-L563)

## 依赖关系分析
- 组件耦合
  - API服务依赖仓储与Redis缓存
  - 设备服务依赖MQTT客户端与Redis
  - 前端依赖后端REST与WebSocket
- 外部依赖
  - PostgreSQL/Redis/MQTT Broker
  - JWT鉴权与限流中间件

```mermaid
graph LR
API["API服务"] --> Repo["OTA仓储"]
API --> RDB["Redis缓存"]
API --> DevSvc["设备服务(HTTP)"]
DevSvc --> MQ["MQTT Broker"]
DevSvc --> RDB
FE_Admin["管理端前端"] --> API
FE_Portal["门户前端"] --> API
```

图示来源
- [inv_api_server/internal/service/ota_service.go:1-231](file://inv_api_server/internal/service/ota_service.go#L1-L231)
- [inv_device_server/internal/mqtt/client.go:1-283](file://inv_device_server/internal/mqtt/client.go#L1-283)

## 性能考虑
- 并发控制：OTA服务限制并发度，避免对下游造成压力
- 缓存策略：Redis缓存在线状态与热点数据，降低数据库压力
- 查询优化：按设备与topic分组取最新记录，减少全表扫描
- 压力测试：提供压力测试工具模拟高并发上报场景
- 网络优化：WebSocket长连接减少轮询开销，必要时配合短周期轮询

章节来源
- [inv_api_server/internal/service/ota_service.go:32-42](file://inv_api_server/internal/service/ota_service.go#L32-L42)
- [tools/stress_test/main.go:1-97](file://tools/stress_test/main.go#L1-L97)

## 故障排查指南
- 设备无进度：检查MQTT主题订阅、命令下发与状态上报路径
- 进度不更新：确认WebSocket连接状态与轮询间隔设置
- 离线判定异常：核查在线状态维护逻辑与超时阈值
- 数据库慢查询：审查索引与分区策略，关注按设备与topic的聚合查询

章节来源
- [inv_device_server/internal/service/protocol_parser.go:267-287](file://inv_device_server/internal/service/protocol_parser.go#L267-L287)
- [inv_api_server/internal/repository/repositories.go:1689-1694](file://inv_api_server/internal/repository/repositories.go#L1689-L1694)

## 结论
本系统通过清晰的职责划分与成熟的中间件选型，实现了从任务创建、命令分发、状态上报、数据聚合到实时展示的完整闭环。通过合理的并发控制、缓存与查询优化，以及完善的异常处理与可视化能力，能够满足大规模设备OTA进度跟踪的需求。

## 附录
- MQTT主题规范与命令格式详见项目说明
- 前端页面与API接口路径见对应源文件

章节来源
- [README.md:253-342](file://README.md#L253-L342)