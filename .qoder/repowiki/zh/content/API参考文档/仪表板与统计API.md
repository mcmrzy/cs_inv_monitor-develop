# 仪表板与统计API

<cite>
**本文档引用的文件**
- [inv_api_server/cmd/main.go](file://inv_api_server/cmd/main.go)
- [inv_api_server/internal/handler/dashboard_handler.go](file://inv_api_server/internal/handler/dashboard_handler.go)
- [inv_api_server/internal/handler/weather_handler.go](file://inv_api_server/internal/handler/weather_handler.go)
- [inv_api_server/internal/service/data_permission.go](file://inv_api_server/internal/service/data_permission.go)
- [inv_api_server/internal/service/perm_checker.go](file://inv_api_server/internal/service/perm_checker.go)
- [api-gateway/internal/middleware/rbac.go](file://api-gateway/internal/middleware/rbac.go)
- [inv_api_server/internal/middleware/permission.go](file://inv_api_server/internal/middleware/permission.go)
- [inv_api_server/internal/repository/repositories.go](file://inv_api_server/internal/repository/repositories.go)
- [inv_device_server/internal/service/protocol_parser.go](file://inv_device_server/internal/service/protocol_parser.go)
- [inv_device_server/internal/mqtt/client.go](file://inv_device_server/internal/mqtt/client.go)
- [inv_device_server/internal/model/device.go](file://inv_device_server/internal/model/device.go)
- [inv-admin-frontend/src/pages/portal/DeviceMonitorPage.tsx](file://inv-admin-frontend/src/pages/portal/DeviceMonitorPage.tsx)
- [inv-admin-frontend/src/pages/portal/AlertsPage.tsx](file://inv-admin-frontend/src/pages/portal/AlertsPage.tsx)
- [tools/stress_test/main.go](file://tools/stress_test/main.go)
</cite>

## 目录
1. [简介](#简介)
2. [项目结构](#项目结构)
3. [核心组件](#核心组件)
4. [架构概览](#架构概览)
5. [详细组件分析](#详细组件分析)
6. [依赖关系分析](#依赖关系分析)
7. [性能考虑](#性能考虑)
8. [故障排除指南](#故障排除指南)
9. [结论](#结论)

## 简介

本项目是一个基于Go语言开发的智能逆变器监控系统，专注于提供全面的仪表板与统计API功能。系统采用微服务架构，通过API网关统一管理各个服务模块，实现了设备运行统计、发电量计算、效率分析、实时监控、图表数据展示、权限控制等核心功能。

系统支持多种数据源接入，包括MQTT协议的设备数据、Kafka消息队列、PostgreSQL数据库和Redis缓存系统。通过TimescaleDB进行时间序列数据存储，实现了高效的设备状态监控和历史数据分析。

## 项目结构

项目采用分层架构设计，主要包含以下核心模块：

```mermaid
graph TB
subgraph "API网关层"
GW[API网关]
RBAC[RBAC权限中间件]
end
subgraph "业务服务层"
API[API服务]
DS[设备服务]
WS[天气服务]
AS[告警服务]
end
subgraph "数据访问层"
PG[(PostgreSQL数据库)]
RD[(Redis缓存)]
TS[(TimescaleDB)]
end
subgraph "前端应用"
FE[管理前端]
BP[大屏展示]
end
GW --> RBAC
RBAC --> API
API --> PG
API --> RD
DS --> TS
DS --> RD
WS --> PG
FE --> GW
BP --> GW
```

**图表来源**
- [inv_api_server/cmd/main.go:487-496](file://inv_api_server/cmd/main.go#L487-L496)
- [api-gateway/internal/middleware/rbac.go:190-239](file://api-gateway/internal/middleware/rbac.go#L190-L239)

**章节来源**
- [inv_api_server/cmd/main.go:125-507](file://inv_api_server/cmd/main.go#L125-L507)
- [inv_api_server/cmd/main.go:420-463](file://inv_api_server/cmd/main.go#L420-L463)

## 核心组件

### 仪表板处理器 (DashboardHandler)

仪表板处理器是系统的核心组件，负责提供各种统计数据和图表数据。主要功能包括：

- **设备运行统计**：统计设备总数、在线数量、离线数量和故障数量
- **发电量计算**：计算当日发电量、总发电量和月度发电量
- **趋势分析**：提供日、周、月维度的趋势数据
- **设备对比**：支持多设备数据对比分析
- **能源统计**：提供详细的能源流向数据
- **站点排名**：按发电量对站点进行排名

### 天气数据处理器 (WeatherHandler)

天气处理器集成了多个天气服务提供商，提供准确的气象信息：

- **Open-Meteo集成**：提供全球天气数据
- **高德地图天气**：提供中国地区的天气预报
- **自动切换机制**：根据配置自动选择最优的天气服务

### 权限控制系统

系统实现了多层次的权限控制机制：

- **RBAC中间件**：基于角色的访问控制
- **数据权限验证**：确保用户只能访问其权限范围内的数据
- **API级权限检查**：在每个API调用时进行权限验证

**章节来源**
- [inv_api_server/internal/handler/dashboard_handler.go:54-232](file://inv_api_server/internal/handler/dashboard_handler.go#L54-L232)
- [inv_api_server/internal/handler/weather_handler.go:47-78](file://inv_api_server/internal/handler/weather_handler.go#L47-L78)
- [inv_api_server/internal/service/perm_checker.go:41-74](file://inv_api_server/internal/service/perm_checker.go#L41-L74)

## 架构概览

系统采用分布式微服务架构，通过API网关统一对外提供服务：

```mermaid
sequenceDiagram
participant Client as 客户端
participant Gateway as API网关
participant RBAC as 权限中间件
participant Handler as 业务处理器
participant Service as 服务层
participant DB as 数据库
Client->>Gateway : HTTP请求
Gateway->>RBAC : 权限验证
RBAC->>RBAC : 检查用户权限
RBAC-->>Gateway : 权限通过/拒绝
Gateway->>Handler : 转发请求
Handler->>Service : 业务逻辑处理
Service->>DB : 数据查询/更新
DB-->>Service : 返回数据
Service-->>Handler : 处理结果
Handler-->>Gateway : 响应数据
Gateway-->>Client : 最终响应
```

**图表来源**
- [api-gateway/internal/middleware/rbac.go:190-239](file://api-gateway/internal/middleware/rbac.go#L190-L239)
- [inv_api_server/internal/middleware/permission.go:40-56](file://inv_api_server/internal/middleware/permission.go#L40-L56)

## 详细组件分析

### 仪表板统计API

#### 设备运行统计接口

系统提供全面的设备运行统计功能：

**接口定义**
- 路径：`GET /api/v1/dashboard/statistics`
- 功能：获取设备总体运行状态统计

**返回数据结构**
```json
{
  "deviceStats": {
    "total": 100,
    "online": 95,
    "offline": 3,
    "fault": 2
  },
  "todayEnergy": 450.5,
  "totalEnergy": 125000.0,
  "recentAlarms": [
    {
      "id": 1001,
      "device_sn": "INV-001",
      "alarm_level": 2,
      "fault_code": "E001",
      "fault_message": "过载保护",
      "occurred_at": "2024-01-15T10:30:00Z"
    }
  ]
}
```

#### 发电量统计接口

**接口定义**
- 路径：`GET /api/v1/dashboard/energy-stats`
- 参数：
  - `type`: 统计类型（day/week/month）
  - `stationId`: 站点ID（可选）

**数据处理逻辑**
系统通过JSONB字段兼容不同格式的数据，支持以下字段：
- `daily_pv`: 当日发电量
- `total_pv`: 总发电量  
- `energy_daily_pv`: 日发电量（备用字段）

#### 趋势分析接口

**接口定义**
- 路径：`GET /api/v1/dashboard/trend`
- 参数：
  - `type`: 趋势类型（day/week/month，默认day）

**数据聚合策略**
- 日趋势：按天聚合，支持7天、4周、12个月的时间范围
- 自动填充：缺失日期自动填充为0值
- 累计值处理：保持累计发电量的连续性

#### 实时监控接口

**接口定义**
- 路径：`GET /api/v1/dashboard/sse`
- 功能：Server-Sent Events实时推送

**推送内容**
- 设备状态更新
- 最近告警信息
- 系统时间戳

```mermaid
flowchart TD
Start([开始推送]) --> GetData["获取最新数据"]
GetData --> FormatData["格式化推送数据"]
FormatData --> SendData["发送SSE事件"]
SendData --> WaitDelay["等待10秒"]
WaitDelay --> GetData
subgraph "推送数据结构"
PushData["{
'type': 'dashboard_update',
'deviceStats': {...},
'recentAlarms': [...],
'timestamp': '2024-01-15T10:30:00Z'
}"]
end
SendData --> PushData
```

**图表来源**
- [inv_api_server/internal/handler/dashboard_handler.go:1228-1240](file://inv_api_server/internal/handler/dashboard_handler.go#L1228-L1240)

**章节来源**
- [inv_api_server/internal/handler/dashboard_handler.go:54-232](file://inv_api_server/internal/handler/dashboard_handler.go#L54-L232)
- [inv_api_server/internal/handler/dashboard_handler.go:277-407](file://inv_api_server/internal/handler/dashboard_handler.go#L277-L407)
- [inv_api_server/internal/handler/dashboard_handler.go:522-670](file://inv_api_server/internal/handler/dashboard_handler.go#L522-L670)

### 图表数据接口

#### 折线图数据接口

**接口定义**
- 路径：`GET /api/v1/dashboard/trend`
- 返回格式：时间序列数组

**数据格式**
```json
[
  {
    "date": "2024-01-01",
    "energy": 150.5,
    "load": 120.3,
    "cumulative": 1500.0
  },
  {
    "date": "2024-01-02", 
    "energy": 180.2,
    "load": 140.1,
    "cumulative": 1680.2
  }
]
```

#### 柱状图数据接口

**接口定义**
- 路径：`GET /api/v1/dashboard/energy-stats`
- 返回格式：多个数组并行

**数据格式**
```json
{
  "dates": ["2024-01-01", "2024-01-02"],
  "pv": [150.5, 180.2],
  "batteryCharge": [0, 0],
  "batteryDischarge": [0, 0],
  "load": [120.3, 140.1],
  "inverterOutput": [0, 0],
  "gridExport": [0, 0],
  "gridImport": [0, 0]
}
```

#### 饼图数据接口

**接口定义**
- 路径：`GET /api/v1/dashboard/device-distribution`
- 返回格式：设备状态分布

**数据格式**
```json
{
  "online": 95,
  "offline": 3,
  "fault": 2
}
```

**章节来源**
- [inv_api_server/internal/handler/dashboard_handler.go:234-275](file://inv_api_server/internal/handler/dashboard_handler.go#L234-L275)
- [inv_api_server/internal/handler/dashboard_handler.go:522-670](file://inv_api_server/internal/handler/dashboard_handler.go#L522-L670)

### 权限控制接口

#### RBAC权限中间件

系统实现了一个完整的RBAC权限控制中间件：

**核心功能**
- 用户角色获取和缓存
- 权限规则检查
- 资源访问控制
- 缓存失效管理

**权限映射**
```mermaid
classDiagram
class RBACMiddleware {
+getUserRole(userID) int
+hasPermission(userID, resource, action) bool
+RBACGuard() gin.HandlerFunc
+InvalidateUserCache(userID)
+InvalidateRoleCache(role)
}
class PermissionEntry {
+string Resource
+string Action
}
class Role {
+int ID
+string Name
+[]PermissionEntry Permissions
}
RBACMiddleware --> PermissionEntry : "检查权限"
RBACMiddleware --> Role : "获取角色"
```

**图表来源**
- [api-gateway/internal/middleware/rbac.go:19-42](file://api-gateway/internal/middleware/rbac.go#L19-L42)

**权限检查流程**
```mermaid
flowchart TD
Request[HTTP请求] --> CheckPublic{公共路径?}
CheckPublic --> |是| Next[继续处理]
CheckPublic --> |否| GetUserID[获取用户ID]
GetUserID --> ParseResource[解析资源类型]
ParseResource --> GetAction[获取操作类型]
GetAction --> CheckCache{检查缓存}
CheckCache --> |命中| ValidatePerm[验证权限]
CheckCache --> |未命中| LoadRole[加载角色权限]
LoadRole --> ValidatePerm
ValidatePerm --> HasPerm{有权限?}
HasPerm --> |是| Next
HasPerm --> |否| Forbidden[返回403]
```

**图表来源**
- [api-gateway/internal/middleware/rbac.go:190-239](file://api-gateway/internal/middleware/rbac.go#L190-L239)

#### 数据权限验证

**接口定义**
- 路径：`GET /api/v1/dashboard/statistics`
- 功能：根据用户权限过滤数据

**数据权限实现**
```mermaid
sequenceDiagram
participant Client as 客户端
participant API as API服务
participant DP as 数据权限
participant DB as 数据库
Client->>API : 请求统计信息
API->>DP : GetAllowedDeviceSNs(userID)
DP->>DB : 查询用户设备权限
DB-->>DP : 返回设备SN列表
DP-->>API : 过滤后的设备列表
API->>DB : 查询统计数据
DB-->>API : 统计结果
API-->>Client : 返回受限数据
```

**图表来源**
- [inv_api_server/internal/service/data_permission.go:22-46](file://inv_api_server/internal/service/data_permission.go#L22-L46)

**章节来源**
- [api-gateway/internal/middleware/rbac.go:190-239](file://api-gateway/internal/middleware/rbac.go#L190-L239)
- [inv_api_server/internal/service/data_permission.go:22-46](file://inv_api_server/internal/service/data_permission.go#L22-L46)

### 天气数据接口

#### 多源天气服务集成

**接口定义**
- 路径：`GET /api/v1/stations/:id/weather`
- 功能：获取指定站点的天气信息

**支持的天气服务**
- **Open-Meteo**: 全球天气数据，支持150+天气代码
- **高德地图**: 中国地区天气预报，支持中文描述

**天气图标映射**
```mermaid
flowchart LR
WeatherCode[天气代码] --> IconMapping{图标映射}
subgraph "Open-Meteo代码映射"
0-1[晴] --> Sun[☀️]
2-3[多云] --> Cloud[☁️]
4-48[阴] --> Overcast[⛅]
49-57[小雨] --> Rain[🌧️]
58-67[雨夹雪] --> Sleet[🌨️]
68-77[雪] --> Snow[❄️]
78-82[大雨] --> HeavyRain[🌦️]
83-100[雷阵雨] --> Thunder[⛈️]
end
```

**图表来源**
- [inv_api_server/internal/handler/weather_handler.go:269-309](file://inv_api_server/internal/handler/weather_handler.go#L269-L309)

**环境影响分析**
系统通过天气数据为发电量预测提供环境因素分析：
- 温度对光伏板效率的影响
- 云量对发电量的衰减系数
- 风速对散热效果的影响

**章节来源**
- [inv_api_server/internal/handler/weather_handler.go:47-78](file://inv_api_server/internal/handler/weather_handler.go#L47-L78)
- [inv_api_server/internal/handler/weather_handler.go:80-133](file://inv_api_server/internal/handler/weather_handler.go#L80-L133)

### 设备状态监控

#### 实时数据处理

**数据流处理**
```mermaid
flowchart TD
DeviceData[设备数据] --> ProtocolParser[协议解析器]
ProtocolParser --> TopicRouting{主题路由}
TopicRouting --> ACData[data/ac]
TopicRouting --> BatteryData[data/battery]
TopicRouting --> PVData[data/pv]
TopicRouting --> EnergyData[data/energy]
TopicRouting --> StatusData[data/status]
ACData --> Normalize[数据标准化]
BatteryData --> Normalize
PVData --> Normalize
EnergyData --> Normalize
StatusData --> Normalize
Normalize --> RedisCache[Redis缓存]
RedisCache --> RealtimeAPI[实时API]
RedisCache --> SSEPush[SSE推送]
```

**图表来源**
- [inv_device_server/internal/service/protocol_parser.go:835-845](file://inv_device_server/internal/service/protocol_parser.go#L835-L845)

**设备状态跟踪**
- 在线状态：基于Redis心跳检测
- 故障状态：通过故障码识别
- 运行状态：设备工作模式

**章节来源**
- [inv_device_server/internal/service/protocol_parser.go:447-476](file://inv_device_server/internal/service/protocol_parser.go#L447-L476)
- [inv_device_server/internal/mqtt/client.go:79-104](file://inv_device_server/internal/mqtt/client.go#L79-L104)

## 依赖关系分析

### 数据模型关系

```mermaid
erDiagram
USERS {
int id PK
string phone
string email
int role
string timezone
}
DEVICES {
string sn PK
int station_id FK
int user_id FK
int status
datetime created_at
datetime updated_at
}
STATIONS {
int id PK
string name
int user_id FK
float latitude
float longitude
string timezone
}
DEVICE_TELEMETRY {
string device_sn FK
timestamp time
string topic
jsonb data
}
ALARMS {
int id PK
string device_sn FK
int alarm_level
string fault_code
string fault_message
timestamp occurred_at
timestamp handled_at
}
USERS ||--o{ DEVICES : "拥有"
STATIONS ||--o{ DEVICES : "包含"
DEVICES ||--o{ DEVICE_TELEMETRY : "产生"
DEVICES ||--o{ ALARMS : "触发"
```

**图表来源**
- [inv_api_server/internal/repository/repositories.go:638-655](file://inv_api_server/internal/repository/repositories.go#L638-L655)

### 组件依赖关系

```mermaid
graph TB
subgraph "API层"
DH[DashboardHandler]
WH[WeatherHandler]
AH[AlarmHandler]
end
subgraph "服务层"
DS[DeviceService]
SS[StationService]
AS[AlarmService]
end
subgraph "数据访问层"
DR[DeviceRepository]
SR[StationRepository]
AR[AlarmRepository]
end
subgraph "外部服务"
PG[PostgreSQL]
RD[Redis]
OM[Open-Meteo]
AM[Amap]
end
DH --> DS
DH --> SS
WH --> SS
AH --> AS
DS --> DR
SS --> SR
AS --> AR
DR --> PG
SR --> PG
AR --> PG
DR --> RD
SR --> RD
AR --> RD
WH --> OM
WH --> AM
```

**图表来源**
- [inv_api_server/cmd/main.go:125-136](file://inv_api_server/cmd/main.go#L125-L136)

**章节来源**
- [inv_api_server/cmd/main.go:125-136](file://inv_api_server/cmd/main.go#L125-L136)
- [inv_api_server/internal/repository/repositories.go:638-655](file://inv_api_server/internal/repository/repositories.go#L638-L655)

## 性能考虑

### 缓存策略

系统采用了多层次的缓存策略来提升性能：

**Redis缓存层次**
- **用户权限缓存**：5分钟TTL，减少数据库查询
- **设备在线状态**：120秒TTL，实时反映设备状态
- **实时数据缓存**：120秒TTL，支持快速查询
- **查询结果缓存**：针对热点查询结果进行缓存

**数据库优化**
- **索引优化**：为常用查询字段建立复合索引
- **分区策略**：按时间分区存储设备遥测数据
- **连接池管理**：合理配置数据库连接池大小

### 性能监控

**压力测试工具**
系统提供了专门的压力测试工具，模拟大量设备并发上报数据：

```mermaid
flowchart TD
StressTest[压力测试] --> SimulateDevices[模拟设备]
SimulateDevices --> GeneratePayload[生成数据负载]
GeneratePayload --> SendRequests[发送HTTP请求]
SendRequests --> MonitorMetrics[监控指标]
subgraph "监控指标"
Latency[延迟(ms)]
Throughput[吞吐量]
ErrorRate[错误率]
ResourceUsage[资源使用]
end
MonitorMetrics --> Latency
MonitorMetrics --> Throughput
MonitorMetrics --> ErrorRate
MonitorMetrics --> ResourceUsage
```

**图表来源**
- [tools/stress_test/main.go:21-97](file://tools/stress_test/main.go#L21-L97)

**性能优化建议**
1. **数据库查询优化**：使用EXPLAIN分析慢查询，优化索引策略
2. **缓存预热**：在系统启动时预热热点数据
3. **异步处理**：将非关键操作异步化处理
4. **批量操作**：合并多次数据库操作为批量操作

## 故障排除指南

### 常见问题诊断

**权限相关问题**
- 检查用户角色是否正确设置
- 验证权限缓存是否正常工作
- 确认RBAC中间件是否正确配置

**数据权限问题**
- 验证用户设备绑定关系
- 检查数据权限查询结果
- 确认设备SN过滤条件

**实时数据问题**
- 检查Redis连接状态
- 验证MQTT消息订阅
- 确认协议解析器正常工作

### 日志分析

系统提供了详细的日志记录机制：

**关键日志级别**
- **DEBUG**: 详细的操作流程记录
- **INFO**: 正常业务操作记录  
- **WARN**: 异常但可恢复的问题
- **ERROR**: 严重错误和异常情况

**监控脚本**
部署目录提供了系统监控脚本，可以自动检测服务状态和资源使用情况。

**章节来源**
- [api-gateway/internal/middleware/rbac.go:226-234](file://api-gateway/internal/middleware/rbac.go#L226-L234)
- [inv_api_server/internal/service/perm_checker.go:50-54](file://inv_api_server/internal/service/perm_checker.go#L50-L54)

## 结论

本仪表板与统计API系统提供了完整的企业级监控解决方案，具有以下特点：

**技术优势**
- 分布式微服务架构，具备良好的扩展性
- 多层次权限控制，确保数据安全
- 实时数据处理能力，支持大规模设备接入
- 完善的缓存策略，保证高性能响应

**功能特性**
- 全面的设备运行统计和分析
- 灵活的图表数据接口
- 多源天气服务集成
- 完善的权限管理和数据隔离

**应用场景**
- 光伏电站远程监控
- 多站点能源管理
- 实时告警和通知
- 历史数据分析和报表

系统通过合理的架构设计和技术选型，能够满足大规模工业监控场景的需求，为企业数字化转型提供强有力的技术支撑。