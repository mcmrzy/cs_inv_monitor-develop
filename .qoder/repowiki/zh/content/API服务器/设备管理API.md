# 设备管理API

<cite>
**本文档引用的文件**
- [device_handler.go](file://inv_api_server/internal/handler/device_handler.go)
- [model_handler.go](file://inv_api_server/internal/handler/model_handler.go)
- [services.go](file://inv_api_server/internal/service/services.go)
- [repositories.go](file://inv_api_server/internal/repository/repositories.go)
- [model_service.go](file://inv_api_server/internal/service/model_service.go)
- [model_repository.go](file://inv_api_server/internal/repository/model_repository.go)
- [device.go](file://inv_device_server/internal/model/device.go)
- [models.go](file://inv_api_server/internal/model/models.go)
- [ws_handler.go](file://inv_api_server/internal/handler/ws_handler.go)
- [auth.go](file://inv_api_server/internal/middleware/auth.go)
- [helpers.go](file://inv_api_server/internal/handler/helpers.go)
- [config.go](file://inv_api_server/internal/config/config.go)
- [main.go](file://inv_api_server/cmd/main.go)
- [schema.sql](file://database/schema.sql)
</cite>

## 目录
1. [项目概述](#项目概述)
2. [系统架构](#系统架构)
3. [核心组件](#核心组件)
4. [设备管理API详解](#设备管理api详解)
5. [设备模型管理](#设备模型管理)
6. [实时监控与数据流](#实时监控与数据流)
7. [权限控制与安全](#权限控制与安全)
8. [错误处理与验证](#错误处理与验证)
9. [性能优化与最佳实践](#性能优化与最佳实践)
10. [前端集成指南](#前端集成指南)
11. [总结](#总结)

## 项目概述

本项目是一个基于Go语言构建的设备管理系统API，主要服务于光伏逆变器设备的远程监控、管理和控制。系统采用微服务架构，通过MQTT协议实现设备与服务器之间的实时通信，结合WebSocket提供实时数据推送功能。

### 核心特性
- **设备全生命周期管理**：从设备注册、绑定到解绑、删除的完整流程
- **实时监控**：通过WebSocket实现实时数据推送
- **历史数据分析**：支持多种时间粒度的历史数据查询
- **设备模型管理**：灵活的设备类型定义和字段配置
- **权限控制**：基于角色的访问控制和数据隔离
- **告警管理**：完整的告警检测、通知和处理机制

## 系统架构

```mermaid
graph TB
subgraph "客户端层"
FE[前端应用]
Mobile[移动APP]
Device[设备端]
end
subgraph "网关层"
APIGateway[API网关]
Auth[认证中间件]
CORS[CORS处理]
end
subgraph "业务逻辑层"
DeviceHandler[设备处理器]
ModelHandler[模型处理器]
WSHandler[WebSocket处理器]
AuthHandler[认证处理器]
end
subgraph "服务层"
DeviceService[设备服务]
ModelService[模型服务]
AlarmService[告警服务]
RBACService[权限服务]
end
subgraph "数据存储层"
Postgres[(PostgreSQL)]
Redis[(Redis)]
TimescaleDB[(TimescaleDB)]
end
subgraph "设备通信层"
MQTT[MQTT Broker]
Kafka[Kafka消息队列]
end
FE --> APIGateway
Mobile --> APIGateway
Device --> MQTT
APIGateway --> Auth
Auth --> DeviceHandler
DeviceHandler --> DeviceService
ModelHandler --> ModelService
WSHandler --> Redis
DeviceService --> Postgres
DeviceService --> Redis
ModelService --> Postgres
AlarmService --> Postgres
MQTT --> Kafka
Kafka --> Postgres
```

**图表来源**
- [main.go:344-576](file://inv_api_server/cmd/main.go#L344-L576)
- [device_handler.go:1-832](file://inv_api_server/internal/handler/device_handler.go#L1-L832)

## 核心组件

### 设备管理核心组件

```mermaid
classDiagram
class DeviceHandler {
+List(c *gin.Context)
+GetDetail(c *gin.Context)
+GetRealtimeData(c *gin.Context)
+Bind(c *gin.Context)
+Unbind(c *gin.Context)
+Control(c *gin.Context)
+GetHistory(c *gin.Context)
+GetStatistics(c *gin.Context)
}
class DeviceService {
+GetBySN(ctx, sn) Device
+GetRealtimeData(ctx, sn) map[string]interface{}
+EnsureDevice(ctx, sn) error
+Bind(ctx, sn, userID, stationID) error
+Unbind(ctx, sn) error
+ValidateControlCommand(ctx, sn, command) error
+SendCommand(ctx, sn, cmdType, params) error
}
class DeviceRepository {
+GetBySN(ctx, sn) Device
+GetRealtimeData(ctx, sn) map[string]interface{}
+EnsureDevice(ctx, sn) error
+Bind(ctx, sn, userID, stationID) error
+Unbind(ctx, sn) error
}
class Device {
+int64 id
+string sn
+string model
+float64 rated_power
+int status
+time.Time last_online_at
}
DeviceHandler --> DeviceService : "依赖"
DeviceService --> DeviceRepository : "使用"
DeviceRepository --> Device : "操作"
```

**图表来源**
- [device_handler.go:20-31](file://inv_api_server/internal/handler/device_handler.go#L20-L31)
- [services.go:302-327](file://inv_api_server/internal/service/services.go#L302-L327)
- [repositories.go:796-800](file://inv_api_server/internal/repository/repositories.go#L796-L800)
- [models.go:43-66](file://inv_api_server/internal/model/models.go#L43-L66)

### 权限控制架构

```mermaid
flowchart TD
Request[API请求] --> Auth[JWT认证]
Auth --> CheckRole{检查角色权限}
CheckRole --> |普通用户| DataPerm{数据权限检查}
CheckRole --> |管理员| AdminPerm{管理员权限}
DataPerm --> UserDeviceRel{用户-设备关联}
UserDeviceRel --> DevicePerm{设备权限验证}
DevicePerm --> |有权限| Handler[执行业务逻辑]
DevicePerm --> |无权限| Forbidden[拒绝访问]
AdminPerm --> |是管理员| Handler
AdminPerm --> |非管理员| Forbidden
Handler --> Response[返回响应]
Forbidden --> ErrorResponse[错误响应]
```

**图表来源**
- [auth.go:15-56](file://inv_api_server/internal/middleware/auth.go#L15-L56)
- [services.go:385-391](file://inv_api_server/internal/service/services.go#L385-L391)

**章节来源**
- [device_handler.go:20-31](file://inv_api_server/internal/handler/device_handler.go#L20-L31)
- [services.go:302-327](file://inv_api_server/internal/service/services.go#L302-L327)
- [auth.go:15-56](file://inv_api_server/internal/middleware/auth.go#L15-L56)

## 设备管理API详解

### 设备注册与发现

设备注册流程通过自动发现机制实现，当设备首次连接时系统会自动创建设备记录：

```mermaid
sequenceDiagram
participant Device as 设备端
participant API as API服务器
participant Repo as 设备仓库
participant DB as 数据库
Device->>API : MQTT连接
API->>Repo : 查询设备是否存在
Repo->>DB : SELECT devices WHERE sn = ?
DB-->>Repo : 设备不存在
Repo->>API : 返回空结果
API->>Repo : 创建设备记录
Repo->>DB : INSERT INTO devices
DB-->>Repo : 插入成功
Repo-->>API : 设备对象
API-->>Device : 设备注册完成
```

**图表来源**
- [device_handler.go:297-318](file://inv_api_server/internal/handler/device_handler.go#L297-L318)
- [services.go:369-371](file://inv_api_server/internal/service/services.go#L369-L371)

### 设备绑定与解绑流程

设备绑定流程确保设备与用户之间的正确关联：

```mermaid
flowchart TD
Start[开始绑定] --> ValidateSN{验证SN格式}
ValidateSN --> |格式错误| BadRequest[返回400错误]
ValidateSN --> |格式正确| CheckDevice{检查设备是否存在}
CheckDevice --> |设备不存在| CreateDevice[创建设备记录]
CheckDevice --> |设备存在| CheckOwner{检查设备归属}
CheckOwner --> |已有归属| AlreadyBound[返回5002错误]
CheckOwner --> |无人绑定| BindDevice[执行绑定]
CreateDevice --> BindDevice
BindDevice --> UpdateDB[更新数据库]
UpdateDB --> Success[绑定成功]
BadRequest --> End[结束]
AlreadyBound --> End
Success --> End
```

**图表来源**
- [device_handler.go:288-335](file://inv_api_server/internal/handler/device_handler.go#L288-L335)
- [services.go:373-375](file://inv_api_server/internal/service/services.go#L373-L375)

### 设备控制命令系统

系统支持基于设备模型的动态控制命令验证：

```mermaid
sequenceDiagram
participant Client as 客户端
participant API as API服务器
participant Service as 设备服务
participant ModelRepo as 模型仓库
participant DeviceServer as 设备服务器
Client->>API : POST /devices/ : sn/control
API->>Service : ValidateControlCommand(sn, command)
Service->>ModelRepo : GetModelIDByDeviceSN(sn)
ModelRepo-->>Service : modelID
Service->>ModelRepo : GetControlFieldsByModelID(modelID)
ModelRepo-->>Service : 控制字段列表
alt 命令在白名单中
Service-->>API : 验证通过
else 命令需要模型验证
Service->>Service : 检查命令是否在控制字段中
Service-->>API : 验证通过或失败
end
API->>Service : SendCommand(sn, cmdType, params)
Service->>DeviceServer : HTTP POST /api/v1/device/ : sn/command
DeviceServer-->>Service : 命令响应
Service-->>API : 命令发送结果
API-->>Client : 响应结果
```

**图表来源**
- [device_handler.go:372-402](file://inv_api_server/internal/handler/device_handler.go#L372-L402)
- [services.go:403-438](file://inv_api_server/internal/service/services.go#L403-L438)
- [services.go:480-526](file://inv_api_server/internal/service/services.go#L480-L526)

**章节来源**
- [device_handler.go:288-335](file://inv_api_server/internal/handler/device_handler.go#L288-L335)
- [device_handler.go:372-402](file://inv_api_server/internal/handler/device_handler.go#L372-L402)
- [services.go:369-375](file://inv_api_server/internal/service/services.go#L369-L375)

## 设备模型管理

### 设备模型架构

设备模型系统提供了灵活的设备类型定义和字段配置能力：

```mermaid
erDiagram
DEVICE_MODEL {
int64 id PK
string model_code UK
string model_name
string manufacturer
string category
float rated_power_kw
string description
boolean is_active
timestamp created_at
timestamp updated_at
}
DEVICE_MODEL_FIELD {
int64 id PK
int32 model_id FK
string field_key
string field_name
string field_type
string unit
int sort
boolean is_show
boolean is_control
string parse_rule
string group_name
jsonb control_params
}
DEVICE_MODEL_PROTOCOL {
int64 id PK
int32 model_id FK
string topic_pattern
string parse_type
jsonb parse_config
boolean is_active
timestamp created_at
}
DEVICE {
int64 id PK
string sn UK
string model
int32 model_id
int64 user_id
int64 station_id
int status
timestamp last_online_at
}
DEVICE_MODEL ||--o{ DEVICE_MODEL_FIELD : "包含"
DEVICE_MODEL ||--o{ DEVICE_MODEL_PROTOCOL : "包含"
DEVICE_MODEL ||--o{ DEVICE : "定义"
```

**图表来源**
- [models.go:223-261](file://inv_api_server/internal/model/models.go#L223-L261)
- [model_repository.go:20-45](file://inv_api_server/internal/repository/model_repository.go#L20-L45)

### 动态字段配置

系统支持基于模型的动态字段配置，实现设备参数的灵活管理：

| 字段类型 | 描述 | 示例 |
|---------|------|------|
| string | 文本字段 | "设备名称" |
| number | 数字字段 | 100.5 |
| boolean | 布尔字段 | true/false |
| select | 下拉选择 | ["选项1","选项2"] |
| array | 数组字段 | [1,2,3] |

**章节来源**
- [model_handler.go:13-28](file://inv_api_server/internal/handler/model_handler.go#L13-L28)
- [model_service.go:19-34](file://inv_api_server/internal/service/model_service.go#L19-L34)
- [model_repository.go:117-143](file://inv_api_server/internal/repository/model_repository.go#L117-L143)

## 实时监控与数据流

### WebSocket实时数据推送

系统通过WebSocket提供实时数据推送功能：

```mermaid
sequenceDiagram
participant Client as 客户端
participant WSHandler as WebSocket处理器
participant Redis as Redis订阅
participant DeviceServer as 设备服务器
Client->>WSHandler : GET /ws/device/ : sn?token=JWT
WSHandler->>WSHandler : 验证JWT令牌
WSHandler->>Redis : Subscribe realtime : channel : +sn
Redis-->>WSHandler : 订阅成功
loop 实时数据推送
DeviceServer->>Redis : 发布设备数据
Redis->>WSHandler : 推送消息
WSHandler->>Client : WebSocket文本消息
end
Client->>WSHandler : Ping消息
WSHandler->>Client : Pong响应
```

**图表来源**
- [ws_handler.go:39-122](file://inv_api_server/internal/handler/ws_handler.go#L39-L122)

### 设备状态管理

系统维护设备的实时状态并通过多种渠道同步：

```mermaid
flowchart TD
MQTTData[MQTT数据] --> ParseData[解析数据]
ParseData --> UpdateCache[更新Redis缓存]
UpdateCache --> WSNotify[WebSocket通知]
UpdateCache --> APICache[API缓存更新]
Heartbeat[心跳检测] --> CheckStale[检查超时设备]
CheckStale --> MarkOffline[标记离线]
MarkOffline --> UpdateDB[更新数据库]
WSNotify --> RealtimeUI[实时界面更新]
APICache --> APIResponse[API响应]
UpdateDB --> DeviceStatus[设备状态同步]
```

**图表来源**
- [main.go:165-183](file://inv_api_server/cmd/main.go#L165-L183)
- [repositories.go:796-800](file://inv_api_server/internal/repository/repositories.go#L796-L800)

**章节来源**
- [ws_handler.go:39-122](file://inv_api_server/internal/handler/ws_handler.go#L39-L122)
- [main.go:165-183](file://inv_api_server/cmd/main.go#L165-L183)

## 权限控制与安全

### 认证与授权机制

系统采用JWT令牌进行身份认证，并结合RBAC实现细粒度的权限控制：

```mermaid
flowchart TD
Login[用户登录] --> IssueToken[签发JWT令牌]
IssueToken --> StoreRefresh[存储刷新令牌]
Request[API请求] --> ValidateToken{验证令牌有效性}
ValidateToken --> |有效| CheckBlacklist{检查黑名单}
ValidateToken --> |无效| Unauthorized[401未授权]
CheckBlacklist --> |在黑名单| Unauthorized
CheckBlacklist --> |不在黑名单| CheckPermission{检查权限}
CheckPermission --> |有权限| Allow[允许访问]
CheckPermission --> |无权限| Forbidden[403禁止访问]
Allow --> ProcessRequest[处理业务请求]
ProcessRequest --> UpdateToken{需要刷新令牌}
UpdateToken --> RefreshToken[刷新令牌]
RefreshToken --> ProcessRequest
```

**图表来源**
- [auth.go:15-56](file://inv_api_server/internal/middleware/auth.go#L15-L56)
- [services.go:85-107](file://inv_api_server/internal/service/services.go#L85-L107)

### 数据隔离策略

系统通过用户-设备关联实现数据隔离：

```mermaid
erDiagram
USER_DEVICE_REL {
int64 id PK
int64 user_id FK
string device_sn FK
timestamp created_at
}
USER {
int64 id PK
string phone UK
int role
int status
}
DEVICE {
int64 id PK
string sn UK
int64 user_id FK
int64 station_id FK
int status
}
USER ||--o{ USER_DEVICE_REL : "拥有"
DEVICE ||--o{ USER_DEVICE_REL : "关联"
USER ||--o{ DEVICE : "拥有"
```

**图表来源**
- [model_repository.go:325-342](file://inv_api_server/internal/repository/model_repository.go#L325-L342)

**章节来源**
- [auth.go:15-56](file://inv_api_server/internal/middleware/auth.go#L15-L56)
- [services.go:85-107](file://inv_api_server/internal/service/services.go#L85-L107)
- [model_repository.go:325-342](file://inv_api_server/internal/repository/model_repository.go#L325-L342)

## 错误处理与验证

### 请求参数验证

系统采用结构化的请求体验证机制：

```mermaid
flowchart TD
Request[HTTP请求] --> BindJSON{绑定JSON}
BindJSON --> |验证失败| BadRequest[400参数错误]
BindJSON --> |验证成功| Validation{业务验证}
Validation --> FieldValidation{字段验证}
FieldValidation --> |格式错误| FieldError[字段验证错误]
FieldValidation --> |格式正确| BusinessValidation{业务规则验证}
BusinessValidation --> |规则不满足| BusinessError[业务规则错误]
BusinessValidation --> |规则满足| Success[处理成功]
BadRequest --> Response[错误响应]
FieldError --> Response
BusinessError --> Response
Success --> Response
```

**图表来源**
- [device_handler.go:291-295](file://inv_api_server/internal/handler/device_handler.go#L291-L295)
- [helpers.go:25-47](file://inv_api_server/internal/handler/helpers.go#L25-L47)

### 错误响应标准化

系统提供统一的错误响应格式：

| 错误码 | 含义 | 响应内容 |
|--------|------|----------|
| 200 | 成功 | {"code":0,"message":"success","data":{}} |
| 400 | 参数错误 | {"code":-1,"message":"参数错误","data":null} |
| 401 | 未授权 | {"code":401,"message":"未授权","data":null} |
| 403 | 权限不足 | {"code":403,"message":"权限不足","data":null} |
| 429 | 请求过于频繁 | {"code":429,"message":"请求过于频繁","data":null} |
| 500 | 系统错误 | {"code":500,"message":"系统错误","data":null} |

**章节来源**
- [device_handler.go:291-295](file://inv_api_server/internal/handler/device_handler.go#L291-L295)
- [helpers.go:25-47](file://inv_api_server/internal/handler/helpers.go#L25-L47)

## 性能优化与最佳实践

### 缓存策略

系统采用多层缓存机制提升性能：

```mermaid
graph LR
subgraph "缓存层次"
Redis[Redis缓存]
API[API响应缓存]
Browser[浏览器缓存]
end
subgraph "数据源"
DB[(PostgreSQL)]
MQ[MQTT Broker]
TSDB[(TimescaleDB)]
end
Redis --> API
API --> Browser
DB --> Redis
MQ --> Redis
TSDB --> Redis
Browser --> API
API --> Redis
Redis --> DB
```

### 性能监控指标

系统监控的关键性能指标包括：

- **响应时间**：API请求平均响应时间 < 100ms
- **并发处理**：支持1000+并发连接
- **内存使用**：Redis内存使用率 < 80%
- **数据库连接**：PG连接池利用率 < 70%

**章节来源**
- [config.go:58-63](file://inv_api_server/internal/config/config.go#L58-L63)
- [main.go:299-322](file://inv_api_server/cmd/main.go#L299-L322)

## 前端集成指南

### API调用示例

#### 设备列表查询
```javascript
// GET /api/v1/devices?page=1&pageSize=20&station_id=123&status=1
const response = await fetch('/api/v1/devices', {
  method: 'GET',
  headers: {
    'Authorization': 'Bearer ' + accessToken,
    'Content-Type': 'application/json'
  },
  query: {
    page: 1,
    pageSize: 20,
    station_id: 123,
    status: 1
  }
})
```

#### 设备绑定
```javascript
// POST /api/v1/devices/bind
const response = await fetch('/api/v1/devices/bind', {
  method: 'POST',
  headers: {
    'Authorization': 'Bearer ' + accessToken,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    sn: 'ABC123DEF456',
    station_id: 123
  })
})
```

#### 实时数据订阅
```javascript
// WebSocket连接
const ws = new WebSocket(
  `ws://localhost:8080/ws/device/${deviceSN}?token=${accessToken}`
)

ws.onmessage = function(event) {
  const data = JSON.parse(event.data)
  updateRealtimeDisplay(data)
}

ws.onclose = function() {
  // 重新连接逻辑
  setTimeout(connectWebSocket, 3000)
}
```

### 最佳实践建议

1. **错误处理**：始终检查API响应状态，实现重试机制
2. **缓存策略**：合理使用本地缓存减少重复请求
3. **连接管理**：WebSocket连接断开后实现自动重连
4. **权限验证**：在每次请求前验证JWT令牌有效性
5. **性能优化**：批量请求减少网络开销

**章节来源**
- [main.go:428-449](file://inv_api_server/cmd/main.go#L428-L449)
- [ws_handler.go:39-122](file://inv_api_server/internal/handler/ws_handler.go#L39-L122)

## 总结

本设备管理API系统提供了完整的设备生命周期管理功能，具有以下特点：

### 核心优势
- **完整的设备管理**：从注册到删除的全流程支持
- **实时监控能力**：通过WebSocket提供实时数据推送
- **灵活的模型系统**：支持动态设备类型和字段配置
- **强大的权限控制**：基于JWT和RBAC的多层次安全机制
- **高性能架构**：多层缓存和优化的数据处理流程

### 技术亮点
- **微服务架构**：清晰的职责分离和模块化设计
- **异步处理**：基于消息队列的异步数据处理
- **实时通信**：WebSocket + Redis的实时推送机制
- **数据一致性**：事务处理和数据同步保证
- **可观测性**：完善的日志记录和监控指标

### 适用场景
该系统适用于分布式能源管理、智能设备监控、工业物联网等场景，能够有效支撑大规模设备的远程管理和控制需求。