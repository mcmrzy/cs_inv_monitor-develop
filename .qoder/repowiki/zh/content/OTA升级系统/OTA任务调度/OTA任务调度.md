# OTA任务调度

<cite>
**本文引用的文件**
- [ota_handler.go](file://inv_api_server/internal/handler/ota_handler.go)
- [ota_service.go](file://inv_api_server/internal/service/ota_service.go)
- [ota_repository.go](file://inv_api_server/internal/repository/ota_repository.go)
- [models.go](file://inv_api_server/internal/model/models.go)
- [ota_constants.go](file://inv_api_server/internal/model/ota_constants.go)
- [internal_handler.go](file://inv_api_server/internal/handler/internal_handler.go)
- [main.go](file://inv_api_server/cmd/main.go)
- [config.go](file://inv_api_server/internal/config/config.go)
- [006_refactor_ota_to_device_upgrades.sql](file://database/migrations/006_refactor_ota_to_device_upgrades.sql)
- [008_upgrade_packages.up.sql](file://database/migrations/008_upgrade_packages.up.sql)
- [009_upgrade_tasks.up.sql](file://database/migrations/009_upgrade_tasks.up.sql)
- [013_ota_source_and_package_enhance.up.sql](file://database/migrations/013_ota_source_and_package_enhance.up.sql)
- [device.go](file://inv_device_server/internal/model/device.go)
- [client.go](file://inv_device_server/internal/mqtt/client.go)
- [stream_consumer.go](file://inv_device_server/internal/mqtt/stream_consumer.go)
- [protocol_adapter.go](file://inv_device_server/internal/service/protocol_adapter.go)
- [protocol_parser.go](file://inv_device_server/internal/service/protocol_parser.go)
- [kafka.go](file://inv_device_server/pkg/kafka/kafka.go)
- [data_service.go](file://inv_device_server/internal/service/data_service.go)
</cite>

## 更新摘要
**所做更改**
- 新增UpgradeTask结构体，统一管理单设备和多设备升级操作
- 增强执行模式支持，包括立即执行、定时执行和手动执行
- 完善任务生命周期管理，涵盖draft、pending、scheduled、running、completed、partial_success、failed、cancelled状态
- 数据库架构重构，新增upgrade_tasks表和device_upgrades的task_id关联
- 新增OTA升级超时检测和自动清理机制
- 增强任务状态管理和智能数据库同步

## 目录
1. [引言](#引言)
2. [项目结构](#项目结构)
3. [核心组件](#核心组件)
4. [架构概览](#架构概览)
5. [详细组件分析](#详细组件分析)
6. [依赖关系分析](#依赖关系分析)
7. [性能考虑](#性能考虑)
8. [故障排除指南](#故障排除指南)
9. [结论](#结论)

## 引言

OTA（Over-The-Air）任务调度系统是一个完整的远程固件更新解决方案，支持设备批量升级、任务状态管理和实时监控。该系统采用微服务架构，包含API网关、设备服务器、数据库和前端管理界面。

**重要变更**: 系统已从原有的ota_tasks和ota_task_devices架构重构为基于device_upgrades的新架构，同时引入了upgrade_tasks表来管理升级任务。最新增强功能包括全面的OTA升级超时检测和自动清理机制，以及智能的任务状态管理。

系统主要功能包括：
- OTA任务创建和配置管理
- 设备范围选择和推送策略
- 任务调度和执行控制
- 实时状态跟踪和进度监控
- 设备匹配和任务分发机制
- 暂停、恢复和取消操作
- 多芯片升级包的精细化进度跟踪
- **新增** Unified UpgradeTask结构体支持单设备和多设备升级
- **新增** 增强的执行模式（immediate、scheduled、manual）
- **新增** 完整的任务生命周期管理
- **新增** OTA升级超时检测和自动清理
- **新增** 智能任务状态管理和数据库同步
- **新增** 设备上线时的OTA状态协调机制

## 项目结构

该项目采用多模块架构，主要包含以下核心模块：

```mermaid
graph TB
subgraph "前端应用"
FE[管理前端]
FE_API[OTA API服务]
end
subgraph "后端服务"
API[API网关]
OTA_API[OTA业务服务]
DEVICE_SERVER[设备服务器]
BRIDGE[MQTT-Kafka桥接]
TIMEOUT_CLEANER[超时清理器]
end
subgraph "数据存储"
DB[(PostgreSQL数据库)]
KAFKA[(Kafka消息队列)]
MQTT[(MQTT Broker)]
end
FE --> FE_API
FE_API --> API
API --> OTA_API
API --> DEVICE_SERVER
DEVICE_SERVER --> BRIDGE
BRIDGE --> KAFKA
OTA_API --> DB
DEVICE_SERVER --> MQTT
DEVICE_SERVER --> DB
TIMEOUT_CLEANER --> DB
```

**图表来源**
- [main.go:168](file://inv_api_server/cmd/main.go#L168)
- [main.go:302-381](file://inv_api_server/cmd/main.go#L302-L381)

**章节来源**
- [main.go:168](file://inv_api_server/cmd/main.go#L168)
- [main.go:302-381](file://inv_api_server/cmd/main.go#L302-L381)

## 核心组件

### OTA任务管理系统架构

系统采用分层架构设计，确保职责分离和可维护性：

```mermaid
classDiagram
class OTAManager {
+createTask(taskConfig) Task
+scheduleTask(taskId) void
+monitorProgress(taskId) Progress
+pauseTask(taskId) void
+resumeTask(taskId) void
+cancelTask(taskId) void
+getDevicePackageUpgradeInfo(sn, packageId) DevicePackageUpgradeInfo
}
class TimeoutCleanup {
+runOTATimeoutCleanup() void
+scanStaleUpgrades() []staleRecord
+markAsFailed(id) void
+updateTaskStats(taskID) void
}
class UpgradeTask {
+id : string
+name : string
+taskType : string
+firmwareId : string
+packageId : string
+model : string
+targetVersion : string
+status : TaskStatus
+executeMode : string
+scheduledAt : datetime
+rolloutPercent : number
+totalDevices : number
+successCount : number
+failedCount : number
+createdBy : number
}
class DeviceUpgrade {
+id : string
+deviceSn : string
+firmwareId : string
+firmwareVersion : string
+targetChip : string
+oldVersion : string
+status : DeviceStatus
+progress : number
+errorMessage : string
+retryCount : number
+pushedBy : number
+taskId : number
+upgradePackageId : number
+startedAt : datetime
+completedAt : datetime
}
class DevicePackageUpgradeInfo {
+deviceSn : string
+deviceModel : string
+mainVersion : string
+packageId : number
+packageVersion : string
+chips : ChipUpgradeDetail[]
+overallStatus : string
+overallProgress : number
}
class ChipUpgradeDetail {
+chip : string
+currentVersion : string
+targetVersion : string
+status : string
+progress : number
+errorMessage : string
}
class TaskStatus {
+DRAFT
+PENDING
+SCHEDULED
+RUNNING
+COMPLETED
+PARTIAL_SUCCESS
+FAILED
+CANCELLED
}
class DeviceStatus {
+PENDING
+DOWNLOADING
+UPGRADING
+SUCCESS
+FAILED
+CANCELLED
}
OTAManager --> UpgradeTask : "管理"
OTAManager --> DeviceUpgrade : "跟踪"
TimeoutCleanup --> DeviceUpgrade : "清理"
TimeoutCleanup --> UpgradeTask : "更新统计"
OTAManager --> DevicePackageUpgradeInfo : "查询"
UpgradeTask --> DeviceUpgrade : "包含"
DeviceUpgrade --> TaskStatus : "状态"
DeviceUpgrade --> DeviceStatus : "状态"
DevicePackageUpgradeInfo --> ChipUpgradeDetail : "包含"
```

**图表来源**
- [main.go:302-381](file://inv_api_server/cmd/main.go#L302-L381)
- [internal_handler.go:900-1099](file://inv_api_server/internal/handler/internal_handler.go#L900-L1099)
- [ota_service.go:828-985](file://inv_api_server/internal/service/ota_service.go#L828-L985)

### 数据模型设计

系统的核心数据模型包括升级任务、设备升级和进度跟踪：

```mermaid
erDiagram
UPGRADE_TASK {
bigint id PK
varchar name
varchar task_type
bigint firmware_id
bigint package_id
varchar model
varchar target_version
varchar status
varchar execute_mode
timestamp scheduled_at
integer rollout_percent
integer total_devices
integer success_count
integer failed_count
bigint created_by
timestamp created_at
timestamp executed_at
timestamp completed_at
timestamp updated_at
}
DEVICE_UPGRADE {
bigint id PK
varchar device_sn
bigint firmware_id
varchar firmware_version
varchar target_chip
varchar old_version
varchar status
integer progress
text error_message
integer retry_count
bigint pushed_by
bigint task_id FK
bigint upgrade_package_id FK
timestamp started_at
timestamp completed_at
timestamp created_at
timestamp updated_at
}
UPGRADE_PACKAGE {
bigint id PK
varchar model
varchar main_version
varchar changelog
boolean is_force
bigint created_by
integer status
timestamp created_at
timestamp updated_at
}
UPGRADE_PACKAGE_ITEM {
bigint id PK
bigint package_id FK
bigint firmware_id FK
varchar target_chip
varchar firmware_version
}
FIRMWARE_VERSIONS {
bigint id PK
varchar model
varchar target_chip
varchar main_version
varchar version
varchar file_url
integer file_size
varchar file_md5
varchar file_sha256
varchar changelog
boolean is_force
bigint uploaded_by
integer status
timestamp created_at
}
UPGRADE_TASK ||--o{ DEVICE_UPGRADE : "包含"
DEVICE_UPGRADE ||--|| FIRMWARE_VERSIONS : "关联"
DEVICE_UPGRADE ||--|| UPGRADE_PACKAGE : "关联"
UPGRADE_PACKAGE ||--o{ UPGRADE_PACKAGE_ITEM : "包含"
UPGRADE_PACKAGE_ITEM ||--|| FIRMWARE_VERSIONS : "关联"
```

**图表来源**
- [006_refactor_ota_to_device_upgrades.sql:6-31](file://database/migrations/006_refactor_ota_to_device_upgrades.sql#L6-L31)
- [008_upgrade_packages.up.sql:8-50](file://database/migrations/008_upgrade_packages.up.sql#L8-L50)
- [009_upgrade_tasks.up.sql:7-27](file://database/migrations/009_upgrade_tasks.up.sql#L7-L27)

**章节来源**
- [006_refactor_ota_to_device_upgrades.sql:6-31](file://database/migrations/006_refactor_ota_to_device_upgrades.sql#L6-L31)
- [008_upgrade_packages.up.sql:8-50](file://database/migrations/008_upgrade_packages.up.sql#L8-L50)
- [009_upgrade_tasks.up.sql:7-27](file://database/migrations/009_upgrade_tasks.up.sql#L7-L27)
- [ota_service.go:828-985](file://inv_api_server/internal/service/ota_service.go#L828-L985)

## 架构概览

### 系统整体架构

```mermaid
graph TB
subgraph "用户界面层"
ADMIN[管理界面]
MONITOR[监控面板]
end
subgraph "API网关层"
GATEWAY[API网关]
AUTH[认证中间件]
RATE_LIMIT[限流中间件]
end
subgraph "业务逻辑层"
OTA_SERVICE[OTA服务]
DEVICE_SERVICE[设备服务]
ALERT_SERVICE[告警服务]
TIMEOUT_MANAGER[超时管理器]
end
subgraph "数据访问层"
OTA_REPO[OTA仓库]
DEVICE_REPO[设备仓库]
ALERT_REPO[告警仓库]
end
subgraph "基础设施层"
DB[(PostgreSQL)]
MQ[Kafka消息队列]
MQTT_BROKER[(MQTT Broker)]
REDIS[(Redis缓存)]
end
ADMIN --> GATEWAY
MONITOR --> GATEWAY
GATEWAY --> AUTH
AUTH --> OTA_SERVICE
GATEWAY --> DEVICE_SERVICE
OTA_SERVICE --> OTA_REPO
DEVICE_SERVICE --> DEVICE_REPO
OTA_SERVICE --> MQ
DEVICE_SERVICE --> MQTT_BROKER
TIMEOUT_MANAGER --> DB
OTA_REPO --> DB
DEVICE_REPO --> DB
```

**图表来源**
- [main.go:168](file://inv_api_server/cmd/main.go#L168)
- [main.go:302-381](file://inv_api_server/cmd/main.go#L302-L381)

### 任务执行流程

```mermaid
sequenceDiagram
participant User as 用户
participant API as API网关
participant Service as OTA服务
participant Repo as 仓库层
participant DeviceServer as 设备服务器
participant Device as 目标设备
participant TimeoutCleaner as 超时清理器
User->>API : 创建升级任务
API->>Service : 验证任务配置
Service->>Repo : 创建升级任务
Repo-->>Service : 返回任务ID
Service->>Service : 为设备创建升级记录
Service->>DeviceServer : 发送任务指令
DeviceServer->>Device : 下发OTA更新
Device-->>DeviceServer : 设备响应
DeviceServer->>Service : 进度上报
Service->>Repo : 更新任务状态
Note over TimeoutCleaner : 每5分钟检查一次
TimeoutCleaner->>Repo : 扫描超时的升级记录
Repo-->>TimeoutCleaner : 返回卡住的记录
TimeoutCleaner->>Repo : 标记为失败并更新统计
Service-->>API : 返回执行结果
API-->>User : 显示任务状态
```

**图表来源**
- [main.go:302-381](file://inv_api_server/cmd/main.go#L302-L381)
- [internal_handler.go:900-1099](file://inv_api_server/internal/handler/internal_handler.go#L900-L1099)

**章节来源**
- [main.go:302-381](file://inv_api_server/cmd/main.go#L302-L381)
- [internal_handler.go:900-1099](file://inv_api_server/internal/handler/internal_handler.go#L900-L1099)

## 详细组件分析

### OTA任务创建和配置

#### 升级任务参数定义

系统支持两种任务类型：

**单芯片升级任务**
| 参数名称 | 类型 | 必填 | 描述 | 默认值 |
|---------|------|------|------|--------|
| 任务名称 | string | 否 | OTA任务的显示名称 | - |
| 任务类型 | string | 是 | 'single' | - |
| 固件ID | bigint | 是 | 要推送的固件版本标识 | - |
| 设备SN列表 | string[] | 是 | 目标设备序列号数组 | - |
| 执行模式 | string | 否 | 'immediate' | 'manual' |
| 定时执行 | datetime | 否 | 任务计划执行时间 | 立即执行 |
| 灰度比例 | integer | 否 | 设备总数的百分比 | 100 |

**升级包任务**
| 参数名称 | 类型 | 必填 | 描述 | 默认值 |
|---------|------|------|------|--------|
| 任务名称 | string | 否 | OTA任务的显示名称 | - |
| 任务类型 | string | 是 | 'package' | - |
| 升级包ID | bigint | 是 | 要推送的升级包标识 | - |
| 设备SN列表 | string[] | 是 | 目标设备序列号数组 | - |
| 执行模式 | string | 否 | 'immediate' | 'manual' |
| 定时执行 | datetime | 否 | 任务计划执行时间 | 立即执行 |
| 灰度比例 | integer | 否 | 设备总数的百分比 | 100 |

#### 设备范围选择策略

```mermaid
flowchart TD
START[开始任务创建] --> INPUT[输入任务参数]
INPUT --> TASK_TYPE{选择任务类型}
TASK_TYPE --> |单芯片模式| SINGLE_FIRMWARE[选择固件ID]
TASK_TYPE --> |升级包模式| PACKAGE_ID[选择升级包ID]
SINGLE_FIRMWARE --> DEVICE_LIST[输入设备SN列表]
PACKAGE_ID --> DEVICE_LIST
DEVICE_LIST --> VALIDATE[验证设备存在性]
VALIDATE --> GRAY_ROLL{是否灰度推送?}
GRAY_ROLL --> |是| APPLY_ROLL[应用灰度比例]
GRAY_ROLL --> |否| MATCH_DEVICES[匹配目标设备]
APPLY_ROLL --> MATCH_DEVICES
MATCH_DEVICES --> CREATE_TASK[创建升级任务]
CREATE_TASK --> CREATE_UPGRADES[为设备创建升级记录]
CREATE_UPGRADES --> END[任务创建完成]
```

**图表来源**
- [ota_service.go:841-985](file://inv_api_server/internal/service/ota_service.go#L841-L985)
- [ota_repository.go:935-1100](file://inv_api_server/internal/repository/ota_repository.go#L935-L1100)

**章节来源**
- [ota_service.go:841-985](file://inv_api_server/internal/service/ota_service.go#L841-L985)
- [ota_repository.go:935-1100](file://inv_api_server/internal/repository/ota_repository.go#L935-L1100)

### 任务调度策略

#### 升级任务调度机制

系统支持三种执行模式：

```mermaid
classDiagram
class UpgradeTask {
+id : bigint
+name : string
+taskType : string
+executeMode : string
+status : string
+scheduledAt : datetime
+rolloutPercent : integer
}
class ImmediateMode {
+立即执行 : boolean
+自动下发命令
+更新任务状态
}
class ScheduledMode {
+定时执行 : datetime
+等待到达时间
+自动触发执行
}
class ManualMode {
+手动执行 : boolean
+等待用户触发
+支持暂停恢复
}
UpgradeTask --> ImmediateMode : "立即模式"
UpgradeTask --> ScheduledMode : "定时模式"
UpgradeTask --> ManualMode : "手动模式"
```

**图表来源**
- [ota_service.go:828-840](file://inv_api_server/internal/service/ota_service.go#L828-L840)

#### 灰度发布策略

```mermaid
flowchart TD
START[开始灰度发布] --> CHECK_PERCENT{检查灰度比例}
CHECK_PERCENT --> |100%| DIRECT_SEND[直接下发]
CHECK_PERCENT --> |<100%| SHUFFLE[随机打乱设备列表]
SHUFFLE --> CALCULATE[计算目标数量]
CALCULATE --> SELECT_DEVICES[选择设备子集]
SELECT_DEVICES --> SEND_COMMAND[下发升级命令]
DIRECT_SEND --> SEND_COMMAND
SEND_COMMAND --> UPDATE_TASK[更新任务统计]
UPDATE_TASK --> END[灰度发布完成]
```

**图表来源**
- [ota_service.go:867-878](file://inv_api_server/internal/service/ota_service.go#L867-L878)

**章节来源**
- [ota_service.go:828-840](file://inv_api_server/internal/service/ota_service.go#L828-L840)
- [ota_service.go:867-878](file://inv_api_server/internal/service/ota_service.go#L867-L878)

### 任务状态管理

#### 升级任务状态转换

```mermaid
stateDiagram-v2
[*] --> 草稿
草稿 --> 待执行 : 创建任务
待执行 --> 已调度 : 设置定时执行
待执行 --> 运行中 : 立即执行或设备上报状态
已调度 --> 运行中 : 到达执行时间
运行中 --> 已完成 : 全部成功
运行中 --> 部分成功 : 部分失败
运行中 --> 失败 : 全部失败
运行中 --> 已取消 : 用户取消
已完成 --> [*]
部分成功 --> [*]
失败 --> [*]
已取消 --> [*]
note right of 运行中 : 正在向设备下发OTA更新
note right of 已完成 : 所有设备升级完成
note right of 部分成功 : 存在失败设备
```

**图表来源**
- [ota_service.go:1009-1020](file://inv_api_server/internal/service/ota_service.go#L1009-L1020)
- [internal_handler.go:1035-1045](file://inv_api_server/internal/handler/internal_handler.go#L1035-L1045)

#### 设备升级状态管理

```mermaid
stateDiagram-v2
[*] --> 待执行
待执行 --> 下载中 : 设备开始下载
下载中 --> 升级中 : 设备开始升级
升级中 --> 成功 : 升级完成
升级中 --> 失败 : 升级失败或超时
待执行 --> 已取消 : 用户取消
成功 --> [*]
失败 --> [*]
已取消 --> [*]
note right of 下载中 : 设备正在下载固件
note right of 升级中 : 设备正在执行升级
note right of 失败 : 可能因超时被自动标记
```

**图表来源**
- [ota_service.go:252-316](file://inv_api_server/internal/service/ota_service.go#L252-L316)
- [main.go:338-342](file://inv_api_server/cmd/main.go#L338-L342)

**章节来源**
- [ota_service.go:1009-1020](file://inv_api_server/internal/service/ota_service.go#L1009-L1020)
- [ota_service.go:252-316](file://inv_api_server/internal/service/ota_service.go#L252-L316)
- [internal_handler.go:1035-1045](file://inv_api_server/internal/handler/internal_handler.go#L1035-L1045)
- [main.go:338-342](file://inv_api_server/cmd/main.go#L338-L342)

### 任务下发机制

#### 设备升级记录创建

```mermaid
flowchart TD
START[开始下发任务] --> CHECK_TASK_TYPE{检查任务类型}
CHECK_TASK_TYPE --> |单芯片模式| SINGLE_MODE[单芯片模式处理]
CHECK_TASK_TYPE --> |升级包模式| PACKAGE_MODE[升级包模式处理]
SINGLE_MODE --> GET_FIRMWARE[获取固件信息]
GET_FIRMWARE --> GET_DEVICE[获取设备信息]
GET_DEVICE --> CREATE_DU[创建设备升级记录]
PACKAGE_MODE --> GET_PACKAGE[获取升级包信息]
GET_PACKAGE --> GET_DEVICE_INFO[获取设备芯片版本]
GET_DEVICE_INFO --> COMPARE_VERSIONS[对比版本信息]
COMPARE_VERSIONS --> CREATE_MULTI_DU[创建多个设备升级记录]
CREATE_DU --> ASSIGN_TASK_ID[分配任务ID]
CREATE_MULTI_DU --> ASSIGN_TASK_ID
ASSIGN_TASK_ID --> SEND_COMMAND[发送升级命令]
SEND_COMMAND --> END[下发完成]
```

**图表来源**
- [ota_service.go:907-971](file://inv_api_server/internal/service/ota_service.go#L907-L971)

#### 任务ID关联机制

系统通过task_id字段实现任务与设备升级记录的关联：

```mermaid
sequenceDiagram
participant Task as 升级任务
participant Repo as 仓库层
participant DeviceUpgrade as 设备升级记录
Task->>Repo : 创建升级任务
Repo-->>Task : 返回任务ID
Task->>Repo : 为设备创建升级记录
Repo->>DeviceUpgrade : 插入记录并设置task_id
DeviceUpgrade->>Task : 关联任务ID
Note over Task,DeviceUpgrade : 同一任务下的所有设备升级记录共享task_id
```

**图表来源**
- [ota_repository.go:1072-1100](file://inv_api_server/internal/repository/ota_repository.go#L1072-L1100)

**章节来源**
- [ota_service.go:907-971](file://inv_api_server/internal/service/ota_service.go#L907-L971)
- [ota_repository.go:1072-1100](file://inv_api_server/internal/repository/ota_repository.go#L1072-L1100)

### 多芯片升级包进度跟踪

#### 设备级升级详情查询

系统新增了GetDevicePackageUpgradeInfo方法，提供设备在指定升级包下的详细升级进度信息：

```mermaid
flowchart TD
START[查询设备升级详情] --> GET_DEVICE[获取设备信息]
GET_DEVICE --> GET_PACKAGE[获取升级包信息]
GET_PACKAGE --> GET_UPGRADES[获取设备升级记录]
GET_UPGRADES --> BUILD_CHIP_MAP[构建芯片版本映射]
BUILD_CHIP_MAP --> PROCESS_CHIPS[处理各芯片升级详情]
PROCESS_CHIPS --> CALCULATE_STATUS[计算整体状态]
CALCULATE_STATUS --> RETURN_INFO[返回升级详情]
```

**图表来源**
- [ota_service.go:407-511](file://inv_api_server/internal/service/ota_service.go#L407-L511)

#### 复合状态管理机制

系统支持复杂的复合状态判断，特别是针对多芯片升级场景：

| 状态值 | 含义 | 触发条件 |
|--------|------|----------|
| idle | 空闲 | 无芯片需要升级 |
| pending | 待执行 | 所有芯片都待执行 |
| upgrading | 升级中 | 至少一个芯片正在升级 |
| partial | 部分成功 | 既有成功又有失败的芯片 |
| success | 成功 | 所有芯片都成功 |
| failed | 失败 | 有失败且无进行中的芯片 |

**章节来源**
- [ota_service.go:407-511](file://inv_api_server/internal/service/ota_service.go#L407-L511)

### OTA升级超时检测和清理机制

#### 后台超时清理器

系统实现了专门的后台goroutine来定期检测和清理卡住的OTA升级记录：

```mermaid
flowchart TD
START[启动超时清理器] --> TICKER[每5分钟触发]
TICKER --> SCAN_QUERY[查询超时的升级记录]
SCAN_QUERY --> FILTER_STALE[筛选超过15分钟的记录]
FILTER_STALE --> HAS_RECORDS{是否有卡住记录?}
HAS_RECORDS --> |否| WAIT_NEXT_CYCLE[等待下一个周期]
HAS_RECORDS --> |是| BATCH_MARK_FAILED[批量标记为失败]
BATCH_MARK_FAILED --> UPDATE_TASK_STATS[更新任务统计]
UPDATE_TASK_STATS --> CHECK_COMPLETION[检查任务是否完成]
CHECK_COMPLETION --> AUTO_COMPLETE[自动完成或标记部分成功]
AUTO_COMPLETE --> LOG_RESULTS[记录清理结果]
LOG_RESULTS --> WAIT_NEXT_CYCLE
WAIT_NEXT_CYCLE --> TICKER
```

**图表来源**
- [main.go:302-381](file://inv_api_server/cmd/main.go#L302-L381)

#### 实时超时检测

在OTA状态处理器中集成了实时超时检测逻辑：

```mermaid
sequenceDiagram
participant Device as 设备
participant Handler as OTA状态处理器
participant DB as 数据库
participant Cleanup as 超时检测
Device->>Handler : 上报升级状态
Handler->>DB : 更新升级记录
Handler->>Cleanup : 异步执行超时检测
Cleanup->>DB : 查询该设备的升级记录
Cleanup->>DB : 检查started_at是否超过15分钟
Cleanup->>DB : 标记超时的记录为失败
Cleanup->>DB : 更新关联任务的统计数据
Cleanup->>DB : 检查任务是否需要自动完成
```

**图表来源**
- [internal_handler.go:956-1022](file://inv_api_server/internal/handler/internal_handler.go#L956-L1022)

#### 设备上线状态协调

系统实现了设备上线时的OTA状态协调机制：

```mermaid
flowchart TD
START[设备上线] --> RECONCILE[触发状态协调]
RECONCILE --> QUERY_OLD_VERSIONS[查询旧固件版本]
QUERY_OLD_VERSIONS --> QUERY_UPGRADING[查询进行中的升级记录]
QUERY_UPGRADING --> COMPARE_VERSIONS[比较版本变化]
COMPARE_VERSIONS --> VERSION_MATCHED{版本匹配?}
VERSION_MATCHED --> |是| MARK_SUCCESS[标记升级成功]
VERSION_MATCHED --> |否| TIME_EXCEEDED{超过5分钟?}
TIME_EXCEEDED --> |是| MARK_FAILED[标记升级失败]
TIME_EXCEEDED --> |否| NO_ACTION[无需操作]
MARK_SUCCESS --> UPDATE_DEVICE_VERSION[更新设备固件版本]
UPDATE_DEVICE_VERSION --> CASCADE_UPGRADE[触发级联升级]
MARK_FAILED --> LOG_FAILURE[记录失败日志]
NO_ACTION --> END[结束]
CASCADE_UPGRADE --> END
LOG_FAILURE --> END
```

**图表来源**
- [internal_handler.go:429-544](file://inv_api_server/internal/handler/internal_handler.go#L429-L544)

**章节来源**
- [main.go:302-381](file://inv_api_server/cmd/main.go#L302-L381)
- [internal_handler.go:956-1022](file://inv_api_server/internal/handler/internal_handler.go#L956-L1022)
- [internal_handler.go:429-544](file://inv_api_server/internal/handler/internal_handler.go#L429-L544)

### 任务监控和进度跟踪

#### 任务级进度统计

```mermaid
classDiagram
class TaskProgressTracker {
+taskId : bigint
+totalDevices : number
+successCount : number
+failedCount : number
+pendingCount : number
+successRate : number
+failureRate : number
+calculateSuccessRate() number
+calculateFailureRate() number
+updateDeviceProgress(deviceId, status) void
}
class DeviceUpgrade {
+id : bigint
+deviceSn : string
+status : string
+progress : number
+startedAt : datetime
+completedAt : datetime
}
class TaskStatistics {
+pending : number
+running : number
+todayCompleted : number
+failed : number
+getTaskStats() void
}
TaskProgressTracker --> DeviceUpgrade : "跟踪"
TaskProgressTracker --> TaskStatistics : "计算"
```

**图表来源**
- [ota_service.go:1177-1181](file://inv_api_server/internal/service/ota_service.go#L1177-L1181)
- [ota_repository.go:1022-1032](file://inv_api_server/internal/repository/ota_repository.go#L1022-L1032)

#### 实时监控面板

前端提供实时监控功能，包括：
- 任务状态统计（待执行、运行中、已完成、失败）
- 今日完成任务数
- 各任务的成功率和失败率
- 设备级别的进度详情
- **新增** 升级包模式的多芯片进度跟踪
- **新增** 复合状态显示（如'partial'表示部分成功）
- **新增** 超时清理状态监控

**章节来源**
- [ota_service.go:1177-1181](file://inv_api_server/internal/service/ota_service.go#L1177-L1181)

### 任务控制操作

#### 升级任务控制流程

```mermaid
flowchart TD
START[用户发起操作] --> CHECK_TASK_STATUS{检查任务状态}
CHECK_TASK_STATUS --> |草稿| EXECUTE_TASK[执行任务]
CHECK_TASK_STATUS --> |待执行| EXECUTE_TASK
CHECK_TASK_STATUS --> |已调度| EXECUTE_TASK
CHECK_TASK_STATUS --> |运行中| CANCEL_TASK[取消任务]
CHECK_TASK_STATUS --> |部分成功| RETRY_TASK[重试失败设备]
CHECK_TASK_STATUS --> |失败| DELETE_TASK[删除任务]
CHECK_TASK_STATUS --> |已取消| DELETE_TASK
EXECUTE_TASK --> UPDATE_TASK_STATUS[更新任务状态为运行中]
UPDATE_TASK_STATUS --> SEND_COMMANDS[发送升级命令]
SEND_COMMANDS --> END[操作完成]
CANCEL_TASK --> CANCEL_UPGRADES[取消待执行的设备升级]
CANCEL_UPGRADES --> UPDATE_TASK_STATUS2[更新任务状态为已取消]
UPDATE_TASK_STATUS2 --> END
RETRY_TASK --> RESET_FAILED[重置失败设备状态]
RESET_FAILED --> RESEND_COMMANDS[重新发送命令]
RESEND_COMMANDS --> UPDATE_TASK_STATUS3[更新任务状态为运行中]
UPDATE_TASK_STATUS3 --> END
DELETE_TASK --> DELETE_TASK_RECORD[删除任务记录]
DELETE_TASK_RECORD --> END
```

**图表来源**
- [ota_service.go:1148-1175](file://inv_api_server/internal/service/ota_service.go#L1148-L1175)

**章节来源**
- [ota_service.go:1148-1175](file://inv_api_server/internal/service/ota_service.go#L1148-L1175)

## 依赖关系分析

### 组件依赖图

```mermaid
graph TB
subgraph "外部依赖"
JWT[jwt-go]
GORM[gorm v2]
Kafka[kafka-go]
MQTT[github.com/eclipse/paho.mqtt.golang]
PGX[pgx连接池]
end
subgraph "内部模块"
Handler[OTA处理器]
InternalHandler[内部处理器]
Service[OTA服务]
Repository[OTA仓库]
Model[数据模型]
TimeoutCleanup[超时清理器]
end
Handler --> Service
InternalHandler --> Repository
Service --> Repository
Repository --> Model
Service --> JWT
Repository --> PGX
Service --> Kafka
Service --> MQTT
TimeoutCleanup --> PGX
```

**图表来源**
- [main.go:168](file://inv_api_server/cmd/main.go#L168)
- [main.go:302-381](file://inv_api_server/cmd/main.go#L302-L381)

### 数据流分析

系统中的主要数据流向：

```mermaid
flowchart LR
subgraph "数据入口"
API[API请求]
MQTT[MQTT消息]
Kafka[Kafka事件]
TIMEOUT_TICK[超时定时器]
end
subgraph "处理层"
Validation[数据验证]
Transformation[数据转换]
BusinessLogic[业务逻辑]
TimeoutDetection[超时检测]
StateReconciliation[状态协调]
end
subgraph "存储层"
PostgreSQL[PostgreSQL]
Redis[Redis缓存]
end
subgraph "输出层"
Response[API响应]
DeviceCommands[设备指令]
Notifications[通知消息]
AutoCleanup[自动清理]
end
API --> Validation
MQTT --> Validation
Kafka --> Validation
TIMEOUT_TICK --> TimeoutDetection
Validation --> Transformation
Transformation --> BusinessLogic
TimeoutDetection --> StateReconciliation
BusinessLogic --> PostgreSQL
BusinessLogic --> Redis
PostgreSQL --> Response
Redis --> Response
BusinessLogic --> DeviceCommands
BusinessLogic --> Notifications
StateReconciliation --> AutoCleanup
```

**图表来源**
- [main.go:302-381](file://inv_api_server/cmd/main.go#L302-L381)
- [internal_handler.go:900-1099](file://inv_api_server/internal/handler/internal_handler.go#L900-L1099)

**章节来源**
- [main.go:302-381](file://inv_api_server/cmd/main.go#L302-L381)
- [internal_handler.go:900-1099](file://inv_api_server/internal/handler/internal_handler.go#L900-L1099)

## 性能考虑

### 性能优化策略

#### 数据库优化

1. **索引优化**
   - 为device_upgrades表创建复合索引：device_sn、status、created_at
   - 为upgrade_tasks表创建状态索引：status、created_at
   - 为firmware_versions表创建版本索引：model、target_chip、created_at
   - **新增** 为upgrade_package_items表创建索引：package_id、firmware_id
   - **新增** 为device_upgrades表的started_at字段创建索引以优化超时查询
   - **新增** 为upgrade_tasks表的task_type和status创建复合索引

2. **查询优化**
   - 实现分页查询避免大数据集加载
   - 使用连接池管理数据库连接
   - 实施查询缓存策略
   - **新增** 优化多芯片升级记录的批量查询
   - **新增** 优化超时检测的批量更新操作

#### 并发处理

系统采用并发处理模式提高响应性能：
- 升级任务执行使用goroutine池控制并发
- 设备升级状态更新异步化
- 通知发送异步化
- **新增** 多芯片升级的并行处理机制
- **新增** 超时清理的独立goroutine，避免阻塞主流程
- **新增** 设备上线状态协调的异步处理

### 错误处理策略

#### 错误分类和处理

```mermaid
flowchart TD
ERROR[发生错误] --> ERROR_TYPE{错误类型分类}
ERROR_TYPE --> |网络错误| NETWORK_ERROR[网络异常处理]
ERROR_TYPE --> |数据库错误| DB_ERROR[数据库异常处理]
ERROR_TYPE --> |设备错误| DEVICE_ERROR[设备异常处理]
ERROR_TYPE --> |业务逻辑错误| BUSINESS_ERROR[业务异常处理]
ERROR_TYPE --> |超时错误| TIMEOUT_ERROR[超时异常处理]
NETWORK_ERROR --> RETRY[重试机制]
DB_ERROR --> ROLLBACK[事务回滚]
DEVICE_ERROR --> MARK_FAILED[标记失败设备]
BUSINESS_ERROR --> VALIDATION[参数验证]
TIMEOUT_ERROR --> AUTO_CLEANUP[自动清理]
RETRY --> BACKOFF[指数退避]
BACKOFF --> MAX_RETRY{达到最大重试次数?}
MAX_RETRY --> |是| FAIL_FAST[快速失败]
MAX_RETRY --> |否| RETRY
MARK_FAILED --> UPDATE_TASK_STATS[更新任务统计]
UPDATE_TASK_STATS --> NOTIFY[通知相关方]
AUTO_CLEANUP --> LOG_TIMEOUT[记录超时日志]
LOG_TIMEOUT --> UPDATE_TASK_STATS
```

**图表来源**
- [main.go:338-342](file://inv_api_server/cmd/main.go#L338-L342)
- [internal_handler.go:975-985](file://inv_api_server/internal/handler/internal_handler.go#L975-L985)

#### 监控和告警

系统实施多层次监控：
- 应用性能监控（APM）
- 业务指标监控
- 设备状态监控
- 错误率监控
- **新增** 多芯片升级成功率监控
- **新增** 超时清理效果监控
- **新增** 状态协调成功率监控

**章节来源**
- [main.go:338-342](file://inv_api_server/cmd/main.go#L338-L342)
- [internal_handler.go:975-985](file://inv_api_server/internal/handler/internal_handler.go#L975-L985)

## 故障排除指南

### 常见问题诊断

#### 任务创建失败

**症状**: 任务创建接口返回错误
**可能原因**:
- 设备SN列表为空或无效
- 固件或升级包不存在
- 权限不足
- 参数验证失败

**解决步骤**:
1. 检查设备SN格式和有效性
2. 验证固件或升级包存在性
3. 确认用户权限
4. 查看详细的错误日志

#### 设备升级失败

**症状**: 设备长时间处于升级状态
**可能原因**:
- 网络连接不稳定
- 设备离线
- 固件包损坏
- 设备存储空间不足
- **新增** 升级超时被自动标记为失败

**解决步骤**:
1. 检查设备在线状态
2. 验证固件完整性
3. 确认设备存储空间
4. 查看设备日志
5. **新增** 检查超时清理日志

#### 多芯片升级进度异常

**症状**: 多芯片升级包的部分芯片升级失败
**可能原因**:
- 某些芯片固件不兼容
- 芯片间依赖关系未满足
- 升级顺序问题
- 资源竞争冲突
- **新增** 芯片升级超时

**解决步骤**:
1. 检查各芯片的升级状态
2. 验证芯片间的兼容性
3. 确认升级顺序配置
4. 查看具体的错误信息
5. **新增** 检查超时清理记录

#### 任务进度异常

**症状**: 任务进度统计与实际不符
**可能原因**:
- 设备上报延迟
- 网络传输问题
- 系统时间不同步
- 缓存数据不一致
- **新增** 超时清理导致的统计更新延迟

**解决步骤**:
1. 检查系统时间同步
2. 清理缓存数据
3. 重新计算进度
4. 查看网络连接质量
5. **新增** 检查超时清理器的运行状态

#### 超时清理相关问题

**症状**: 升级记录长时间停留在upgrading状态
**可能原因**:
- 超时清理器未正常运行
- 数据库连接问题
- 超时阈值配置不当
- 设备持续上报状态但实际已断连

**解决步骤**:
1. 检查超时清理器的日志输出
2. 验证数据库连接状态
3. 调整超时阈值配置
4. 检查设备心跳状态
5. **新增** 手动触发状态协调

### 调试工具和方法

#### 日志分析

系统提供详细的日志记录：
- 请求日志：记录所有API调用
- 业务日志：记录关键业务操作
- 错误日志：记录异常和错误信息
- 性能日志：记录性能指标
- **新增** 超时清理的详细日志
- **新增** 状态协调的调试日志
- **新增** 多芯片升级的详细日志

#### 性能分析

```mermaid
graph LR
subgraph "性能分析工具"
PPROF[pprof分析器]
PROMETHEUS[Prometheus监控]
GRAFANA[Grafana可视化]
end
subgraph "监控指标"
CPU[CPU使用率]
MEMORY[内存使用量]
REQUEST_RATE[请求速率]
ERROR_RATE[错误率]
RESPONSE_TIME[响应时间]
CHIP_PROGRESS[芯片升级进度]
TIMEOUT_CLEANUP[超时清理效率]
STATE_RECONCILIATION[状态协调成功率]
```

**章节来源**
- [main.go:302-381](file://inv_api_server/cmd/main.go#L302-L381)
- [internal_handler.go:900-1099](file://inv_api_server/internal/handler/internal_handler.go#L900-L1099)

## 结论

OTA任务调度系统经过重构后，从原有的ota_tasks和ota_task_devices架构转变为基于device_upgrades的新架构，同时引入了upgrade_tasks表来管理升级任务。最新的增强功能包括全面的OTA升级超时检测和自动清理机制，以及智能的任务状态管理。

### 主要优势

1. **架构设计合理**: 采用微服务架构，职责分离明确
2. **功能完善**: 支持复杂的任务配置和灵活的调度策略
3. **监控全面**: 提供实时的状态跟踪和进度监控
4. **扩展性强**: 模块化设计便于功能扩展和维护
5. **性能优化**: 实施多种性能优化策略确保系统稳定性
6. **任务管理**: 引入升级任务表实现任务级别的统一管理
7. **多芯片支持**: 支持复杂的多芯片升级包场景
8. **复合状态**: 提供精确的状态管理，如'partial'状态表示部分成功
9. **超时保护**: 新增超时检测和自动清理机制，防止资源泄漏
10. **状态一致性**: 实现设备上线时的状态协调，确保数据一致性
11. **统一升级操作**: 新增UpgradeTask结构体支持单设备和多设备升级
12. **增强执行模式**: 支持immediate、scheduled、manual三种执行模式
13. **完整生命周期**: 提供从draft到completed的完整任务状态管理

### 改进方向

1. **增强安全机制**: 添加更细粒度的权限控制
2. **优化用户体验**: 改进前端交互和报表展示
3. **提升可靠性**: 增加更多容错和自愈能力
4. **扩展支持**: 支持更多类型的设备和固件格式
5. **智能调度**: 基于设备状态的智能升级调度
6. **批量优化**: 进一步优化大规模设备的升级性能
7. **超时配置**: 支持动态调整超时阈值
8. **清理策略**: 实现更智能的清理策略和优先级管理

该系统为工业物联网场景下的设备固件管理提供了优秀的解决方案，具有良好的实用价值和推广前景。新增的超时检测和状态协调机制使得系统能够更好地处理复杂的网络环境和设备异常情况，提高了系统的稳定性和可靠性。