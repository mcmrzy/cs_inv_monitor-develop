# data/status系统状态主题

<cite>
**本文档引用的文件**
- [protocol_parser.go](file://inv_device_server/internal/service/protocol_parser.go)
- [client.go](file://inv_device_server/internal/mqtt/client.go)
- [models.go](file://inv_api_server/internal/model/models.go)
- [repositories.go](file://inv_api_server/internal/repository/repositories.go)
- [README.md](file://README.md)
- [main.go](file://tools/stress_test/main.go)
</cite>

## 目录
1. [简介](#简介)
2. [项目结构](#项目结构)
3. [核心组件](#核心组件)
4. [架构概览](#架构概览)
5. [详细组件分析](#详细组件分析)
6. [依赖关系分析](#依赖关系分析)
7. [性能考虑](#性能考虑)
8. [故障诊断与处理](#故障诊断与处理)
9. [结论](#结论)
10. [附录](#附录)

## 简介

data/status系统状态主题是光伏逆变器物联网监控系统中的关键通信协议，负责逆变器系统状态的周期性上报和故障检测。该系统采用5秒上报频率，使用MQTT QoS级别0进行非保留消息传输，确保实时性和低延迟的数据传输。

系统状态主题采用统一的JSON payload结构，包含逆变器运行状态、故障码、告警码、温度监测、电压电流参数、效率指标和运行时长等关键运行参数。通过标准化的状态码定义和故障诊断逻辑，实现了完整的系统保护机制和异常处理流程。

## 项目结构

系统围绕data/status主题构建了完整的数据采集、处理和监控体系：

```mermaid
graph TB
subgraph "设备层"
Device[逆变器设备<br/>ESP32-C3]
Sensor[传感器<br/>温度/电压/电流]
end
subgraph "MQTT传输层"
Broker[EMQX Broker<br/>JWT认证]
Topic[data/status主题<br/>QoS=0, Retain=false]
end
subgraph "设备服务器"
Parser[协议解析器<br/>5秒防抖]
Fault[Fault检测<br/>故障码分析]
Status[状态上报<br/>API服务器]
end
subgraph "应用服务器"
Model[数据模型<br/>状态定义]
Repo[仓库层<br/>数据持久化]
Frontend[前端监控<br/>实时显示]
end
Device --> Sensor
Sensor --> Device
Device --> Broker
Broker --> Topic
Topic --> Parser
Parser --> Fault
Fault --> Status
Status --> Model
Model --> Repo
Repo --> Frontend
```

**图表来源**
- [README.md:208-251](file://README.md#L208-L251)
- [protocol_parser.go:1-60](file://inv_device_server/internal/service/protocol_parser.go#L1-L60)

**章节来源**
- [README.md:1-251](file://README.md#L1-L251)

## 核心组件

### 系统状态主题定义

data/status主题遵循以下规范：
- **上报频率**: 5秒固定间隔
- **QoS级别**: 0（最多一次传递）
- **保留策略**: 非保留消息（Retain=false）
- **主题格式**: `cs_inv/{sn}/data/status`

### payload结构定义

系统状态payload包含以下核心字段：

| 字段名称 | 数据类型 | 单位 | 描述 | 必填 |
|---------|---------|------|------|------|
| state | string | - | 运行状态字符串 | 是 |
| fault_code | int | - | 故障码 | 否 |
| alarm_code | int | - | 告警码 | 否 |
| temp_inv | float | ℃ | 逆变器内部温度 | 是 |
| temp_mos | float | ℃ | 散热器温度 | 是 |
| temp_ambient | float | ℃ | 环境温度 | 是 |
| dc_bus_voltage | float | V | 直流母线电压 | 是 |
| efficiency | float | % | 逆变效率 | 是 |
| runtime_hours | float | h | 累计运行时长 | 是 |
| fan_speed | float | % | 风扇转速 | 是 |

### 状态码定义

系统运行状态码定义：

```mermaid
stateDiagram-v2
[*] --> Shutdown : "初始状态"
Shutdown --> Standby : "上电/待机"
Standby --> Inverting : "开始发电"
Inverting --> Standby : "功率下降"
Inverting --> Fault : "发生故障"
Inverting --> Shutdown : "正常关机"
Fault --> Standby : "故障恢复"
Fault --> Shutdown : "严重故障"
Standby --> Bypass : "旁路模式"
Bypass --> Inverting : "恢复正常"
```

**图表来源**
- [protocol_parser.go:527-609](file://inv_device_server/internal/service/protocol_parser.go#L527-L609)

**章节来源**
- [protocol_parser.go:527-609](file://inv_device_server/internal/service/protocol_parser.go#L527-L609)

## 架构概览

系统采用分布式架构，通过MQTT协议实现实时数据传输：

```mermaid
sequenceDiagram
participant Device as 逆变器设备
participant Broker as EMQX Broker
participant Parser as 设备服务器解析器
participant API as API服务器
participant DB as 数据库
Device->>Broker : "发布 data/status (QoS=0)"
Broker->>Parser : "转发消息"
Parser->>Parser : "解析payload"
Parser->>Parser : "故障检测"
alt 故障状态
Parser->>API : "上报故障状态"
API->>DB : "更新设备状态"
else 正常状态
Parser->>API : "上报正常状态"
API->>DB : "更新设备状态"
end
API-->>Device : "状态确认"
```

**图表来源**
- [protocol_parser.go:285-309](file://inv_device_server/internal/service/protocol_parser.go#L285-L309)
- [protocol_parser.go:447-484](file://inv_device_server/internal/service/protocol_parser.go#L447-L484)

## 详细组件分析

### 协议解析器组件

协议解析器负责处理data/status主题的消息：

```mermaid
classDiagram
class ProtocolParser {
+consumer KafkaReader
+repo DeviceRepository
+metaRepo MetadataRepository
+rdb redisClient
+hub mqttHub
+apiServer string
+internalKey string
+httpClient http.Client
+workerCount int
+msgChan chan parsedMessage
+parseEngine ParseRuleEngine
+handleTelemetry(RawMessage) error
+handleInfo(RawMessage) error
+postInternal(string, map) error
}
class RawMessage {
+string SN
+string ClientID
+string MsgType
+json.RawMessage Payload
+string ReceivedAt
}
class ParseRuleEngine {
+rules []ParseRule
+applyRules(map) map
+validateSchema(map) bool
}
ProtocolParser --> RawMessage : "处理"
ProtocolParser --> ParseRuleEngine : "使用"
```

**图表来源**
- [protocol_parser.go:29-61](file://inv_device_server/internal/service/protocol_parser.go#L29-L61)

### 故障检测机制

故障检测系统具有智能防抖功能：

```mermaid
flowchart TD
Start([接收data/status消息]) --> ParsePayload["解析payload内容"]
ParsePayload --> CheckFaultCode{"检查fault_code"}
CheckFaultCode --> |存在且非零| IsFault["标记为故障状态"]
CheckFaultCode --> |不存在或为零| CheckState["检查state字段"]
CheckState --> |state='fault'| IsFault
CheckState --> |其他状态| Normal["标记为正常状态"]
IsFault --> FaultKey["设置故障防抖key"]
FaultKey --> ReportFault["上报故障状态"]
ReportFault --> End([完成])
Normal --> StatusKey["检查状态防抖"]
StatusKey --> ShouldReport{"是否需要上报"}
ShouldReport --> |是| ReportStatus["上报状态"]
ShouldReport --> |否| End
ReportStatus --> End
```

**图表来源**
- [protocol_parser.go:527-609](file://inv_device_server/internal/service/protocol_parser.go#L527-L609)

**章节来源**
- [protocol_parser.go:527-609](file://inv_device_server/internal/service/protocol_parser.go#L527-L609)

### 在线状态管理

系统通过Redis实现设备在线状态跟踪：

```mermaid
flowchart LR
subgraph "在线状态检测"
A[接收设备消息] --> B{检查消息类型}
B --> |data/status| C[更新心跳时间]
B --> |其他数据| D[更新在线状态]
C --> E[标记设备在线]
D --> E
end
subgraph "状态同步"
E --> F[更新Redis哈希表]
F --> G[广播在线设备列表]
G --> H[API服务器同步]
end
```

**图表来源**
- [client.go:186-224](file://inv_device_server/internal/mqtt/client.go#L186-L224)

**章节来源**
- [client.go:186-224](file://inv_device_server/internal/mqtt/client.go#L186-L224)

## 依赖关系分析

系统各组件之间的依赖关系如下：

```mermaid
graph TB
subgraph "设备服务器"
A[protocol_parser.go] --> B[client.go]
A --> C[models.go]
A --> D[repositories.go]
end
subgraph "API服务器"
C --> D
C --> E[handlers]
D --> F[database]
end
subgraph "外部依赖"
B --> G[EMQX Broker]
A --> H[Redis]
D --> I[PostgreSQL]
end
```

**图表来源**
- [protocol_parser.go:1-45](file://inv_device_server/internal/service/protocol_parser.go#L1-L45)
- [client.go:1-30](file://inv_device_server/internal/mqtt/client.go#L1-L30)

**章节来源**
- [protocol_parser.go:1-45](file://inv_device_server/internal/service/protocol_parser.go#L1-L45)
- [client.go:1-30](file://inv_device_server/internal/mqtt/client.go#L1-L30)

## 性能考虑

### 上报频率优化

系统采用5秒固定上报间隔，在保证实时性的同时平衡网络负载：

- **CPU使用率**: 低频上报减少设备CPU占用
- **网络带宽**: QoS=0避免消息堆积，降低网络压力
- **存储成本**: 非保留消息减少Broker存储开销

### 防抖机制

系统实现多层次防抖机制：

```mermaid
flowchart TD
A[设备频繁上报] --> B{状态是否变化}
B --> |无变化| C[本地防抖10秒]
B --> |有变化| D{是否故障状态}
D --> |是| E[故障防抖15秒]
D --> |否| F[立即上报]
C --> G[合并上报]
E --> G
F --> G
G --> H[减少API调用]
```

**图表来源**
- [protocol_parser.go:285-309](file://inv_device_server/internal/service/protocol_parser.go#L285-L309)

**章节来源**
- [protocol_parser.go:285-309](file://inv_device_server/internal/service/protocol_parser.go#L285-L309)

## 故障诊断与处理

### 故障码分类

系统根据故障严重程度分为不同级别：

| 故障级别 | 故障码范围 | 处理方式 | 系统响应 |
|---------|-----------|---------|---------|
| 严重故障 | 1001-1999 | 立即停机 | shutdown |
| 一般故障 | 2001-2999 | 降额运行 | standby |
| 轻微故障 | 3001-3999 | 继续运行 | inverting |
| 通信故障 | 4001-4999 | 重连尝试 | bypass |

### 异常处理流程

```mermaid
sequenceDiagram
participant Device as 设备
participant Parser as 解析器
participant API as API服务器
participant Monitor as 监控系统
Device->>Parser : "上报状态"
Parser->>Parser : "检查故障码"
alt 发生故障
Parser->>API : "上报故障状态"
API->>Monitor : "触发告警"
Monitor->>Device : "下发降额指令"
else 正常状态
Parser->>API : "上报正常状态"
API->>Monitor : "更新设备状态"
end
Note over Parser,Monitor : "防抖机制防止重复上报"
```

**图表来源**
- [protocol_parser.go:577-606](file://inv_device_server/internal/service/protocol_parser.go#L577-L606)

**章节来源**
- [protocol_parser.go:577-606](file://inv_device_server/internal/service/protocol_parser.go#L577-L606)

### 系统保护机制

系统具备多重保护机制：

1. **温度保护**: 当temp_inv超过设定阈值时自动降额
2. **电压保护**: dc_bus_voltage异常时立即停机
3. **效率保护**: efficiency异常时降低功率输出
4. **风扇保护**: fan_speed异常时触发报警

## 结论

data/status系统状态主题为光伏逆变器监控系统提供了可靠的实时状态传输机制。通过标准化的payload结构、智能的故障检测算法和高效的防抖机制，系统实现了高可靠性的设备状态监控。

该设计充分考虑了实际应用场景的需求，在保证数据实时性的同时有效控制了系统开销，为大规模设备接入提供了良好的技术基础。

## 附录

### JSON示例

标准系统状态payload示例：

```json
{
  "sn": "H1CNA00135000014",
  "type": "status",
  "payload": {
    "state": "inverting",
    "fault_code": 0,
    "alarm_code": 0,
    "temp_inv": 45.5,
    "temp_mos": 42.3,
    "temp_ambient": 38.7,
    "dc_bus_voltage": 780.2,
    "efficiency": 94.2,
    "runtime_hours": 1245.7,
    "fan_speed": 65.0
  }
}
```

### 状态码对照表

| 状态码 | 状态名称 | 描述 | 系统行为 |
|-------|---------|------|---------|
| inverting | 发电中 | 设备正常发电运行 | 继续运行，记录数据 |
| standby | 待机 | 设备准备就绪但未发电 | 等待条件满足 |
| fault | 故障 | 设备发生故障 | 停止发电，触发保护 |
| shutdown | 关机 | 设备正常关闭 | 停止运行，保存状态 |
| bypass | 旁路 | 设备旁路运行 | 降额运行或停止 |

### 性能基准测试

系统支持大规模设备并发测试：

- **设备数量**: 支持1000+设备同时在线
- **上报间隔**: 5秒固定间隔
- **网络负载**: 低频上报减少带宽占用
- **存储效率**: 非保留消息降低存储成本

**章节来源**
- [main.go:21-26](file://tools/stress_test/main.go#L21-L26)