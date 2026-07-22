# 设备通信管道可靠性与可观测性深度改造设计

> **文档版本**: v1.0  
> **日期**: 2026-07-22  
> **项目**: cs_inv_monitor 光伏逆变器物联网监控平台  
> **状态**: 设计评审中

---

## 1. 概述

为 cs_inv_monitor 光伏逆变器物联网监控平台实施逐模块深度改造，同时提升设备通信管道的**可靠性**和**可观测性**。改造覆盖 mqtt-kafka-bridge、device-communication、business-api、React 管理后台四个层级，不引入新外部依赖，复用 Redis + SSE + REST API 现有架构。

### 1.1 改造目标

| 维度 | 目标 |
|------|------|
| 可靠性 | 消除重复代码、统一状态管理、实现组件故障降级而非崩溃 |
| 可观测性 | 暴露端到端管道健康状态、消息延迟追踪、DLQ 可视化管理 |
| 可维护性 | 提取公共帮助函数、统一错误处理模式、结构化审计日志 |

### 1.2 改造范围

- **mqtt-kafka-bridge**: 健康探针增强、原子计数器、Prometheus 指标暴露
- **device-communication**: 重试逻辑统一、Redis 断连恢复、状态管理统一、Kafka 消费延迟追踪
- **business-api**: 管道健康聚合 API、DLQ 管理接口、SSE 健康推送
- **React Admin**: 系统健康页面增强、DLQ 管理界面

---

## 2. 背景与动机

### 2.1 当前架构

```
Devices(ESP32/ARM) → EMQX(MQTT Broker) → mqtt-kafka-bridge → Kafka
                                                                  ↓
                                              device-communication → PostgreSQL/Redis
                                                                  ↓
                                              business-api → React Admin
```

**核心特征**:

- **4 层 IoT 消息管道**: 设备 → EMQX → Bridge → Kafka → Device-Server → DB → API → 前端
- **双路径数据流**: MQTT 直连（命令通道）+ Kafka 管道（遥测数据）
- **现有可靠性机制**: MQTT 自动重连、Redis 心跳 TTL、设备状态机（3 态 + 去抖）、Kafka 有序消费 + 重试 + DLQ、命令队列

### 2.2 已识别问题

#### 2.2.1 可靠性问题

| 编号 | 问题描述 | 影响范围 | 严重程度 |
|------|---------|---------|---------|
| R-01 | `data_service.go` 中 5 处重复重试逻辑（lines 107, 283, 326, 401, 523，覆盖 notifyAPIServerStatus/notifyAPIServerInfo/HandleCmdResult/HandleOTAStatus 及 OTA 相关通知） | device-communication | 高 |
| R-02 | Redis 断连无恢复策略 | device-communication | 高 |
| R-03 | Hub 与 DeviceStateManager 双状态管理不一致 | device-communication | 高 |
| R-04 | `hasActiveSevereAlarms()` 是空 stub（始终返回 false） | device-communication | 中 |
| R-05 | MQTT stats 非原子操作（`DataReceived++`, `CmdSent++`） | device-communication | 中 |
| R-06 | Kafka consumer 无优雅关闭机制 | device-communication | 中 |
| R-07 | Bridge `/health` 不检查 Kafka 连通性 | mqtt-kafka-bridge | 中 |
| R-08 | Bridge stats 非原子操作 | mqtt-kafka-bridge | 低 |

#### 2.2.2 可观测性问题

| 编号 | 问题描述 | 影响范围 | 严重程度 |
|------|---------|---------|---------|
| O-01 | IngestMetrics 未暴露到 HTTP 端点 | device-communication | 高 |
| O-02 | Bridge `/health` 不检查 Kafka 连通性 | mqtt-kafka-bridge | 中 |
| O-03 | 无端到端消息延迟追踪 | 全管道 | 高 |
| O-04 | 无命令投递 SLA 指标 | device-communication | 中 |
| O-05 | 无跨服务健康聚合 | business-api | 中 |
| O-06 | 无 DLQ 管理界面 | React Admin | 中 |

---

## 3. 设计原则

| 原则 | 说明 |
|------|------|
| **零新外部依赖** | 复用 Redis + SSE + REST API 现有通道，不引入 Prometheus Server、Grafana 等外部系统 |
| **逐模块深度改造** | 每完成一个模块即可独立验证和部署，模块间通过 Redis 键松耦合 |
| **降级而非崩溃** | 组件故障时降级运行（跳过缓存、记录日志），不触发服务重启 |
| **TDD 驱动** | 每个改进先写失败测试，再写最小实现，确保测试覆盖 |

### 3.1 术语约定

| 名称 | 含义 |
|------|------|
| device-communication | Go 服务源码目录名和模块路径 |
| device-server | 该服务的 Docker 容器名和 Redis 键前缀中的服务标识，两者指同一服务 |
| bridge | mqtt-kafka-bridge 服务的简称 |

---

## 4. 整体架构变更

### 4.1 数据流新增

> 用 `+` 标注新增部分

```
Devices → EMQX → mqtt-kafka-bridge → Kafka → device-communication → PostgreSQL/Redis
                    |                              |
                    + /health (含Kafka探针)          + /metrics (IngestMetrics暴露)
                    + /metrics (Prometheus格式)      + /health (含消费延迟+DLQ状态)
                    |                              |
                    +──────────────────────────────→ Redis: pipeline:health:{service}
                                                   |
                                              business-api
                                                   |
                                                   + GET /api/v1/system/pipeline-health (聚合)
                                                   + GET /api/v1/system/pipeline-metrics (指标)
                                                   + GET /api/v1/system/dlq (DLQ管理)
                                                   + SSE 推送管道健康更新
                                                   |
                                              React Admin
                                                   + 系统健康页面增强版
```

### 4.2 Redis 新增键设计

| Redis 键 | 类型 | TTL | 说明 |
|----------|------|-----|------|
| `pipeline:health:bridge` | String (JSON) | 90s | bridge 服务健康状态（含 Kafka 连通性） |
| `pipeline:health:device-server` | String (JSON) | 90s | device-communication 健康状态（含消费延迟） |
| `pipeline:health:api` | String (JSON) | 90s | business-api 健康状态 |
| `pipeline:metrics:snapshot` | String (JSON) | 30s | 聚合指标快照 |
| `pipeline:state_audit:{sn}` | List | 7 天 | 设备状态转换审计日志（最近 100 条） |

**Redis 键 JSON 结构示例**:

```json
{
  "service": "bridge",
  "status": "ok",
  "timestamp": "2026-07-22T10:30:00Z",
  "details": {
    "kafka_connected": true,
    "messages_in": 15234,
    "messages_out": 15200,
    "errors": 34,
    "uptime_seconds": 86400
  }
}
```

---

## 5. 模块 1 — mqtt-kafka-bridge 改造

### 5.1 可靠性修复

| 问题 | 修复方案 | 实现细节 |
|------|---------|---------|
| `/health` 不检查 Kafka 连通性 | 新增后台 Kafka 健康探针 | 每 10s 检测 Kafka writer 状态，结果缓存到内存中的 `atomic.Bool`。失败判定：连续 3 次检测失败（30s）后标记为 disconnected。`/health` 响应：Kafka disconnected 时 status 返回 `"degraded"`（HTTP 200），Kafka 完全不可达超过 90s 时返回 `"down"`（HTTP 503）。 |
| 请求体无大小限制 | 添加 `http.MaxBytesReader` | 限制 webhook 请求体最大 1MB，超限返回 `413 Request Entity Too Large` |
| bridge stats 非原子操作 | 改用 `sync/atomic` | 替代 mutex 保护的 int64 计数器，使用 `atomic.Int64` 类型 |

### 5.2 可观测性增强

| 新增能力 | 实现方式 |
|---------|---------|
| 结构化 `/health` 端点 | 返回 JSON 格式健康状态 |
| Prometheus 格式 `/metrics` | 新增端点暴露桥接服务核心指标 |
| Redis 健康上报 | 每 30s 将 bridge 健康状态写入 Redis |

**`/health` 响应格式**:

```json
{
  "status": "ok",
  "kafka": "connected",
  "emqx_webhook": true,
  "messages_in": 15234,
  "messages_out": 15200,
  "errors": 34,
  "uptime_seconds": 86400
}
```

> `status` 取值：`ok`（全部正常）、`degraded`（Kafka 断连但 EMQX 正常）、`down`（核心组件不可用）

**`/metrics` 暴露指标**:

| 指标名 | 类型 | 说明 |
|--------|------|------|
| `bridge_messages_received_total` | Counter | 从 EMQX 接收的消息总数 |
| `bridge_messages_forwarded_total` | Counter | 成功转发到 Kafka 的消息总数 |
| `bridge_errors_total` | Counter | 错误总数（含转发失败、解析失败） |
| `bridge_kafka_connected` | Gauge (0/1) | Kafka 连接状态 |

### 5.3 关键实现文件

- `mqtt-kafka-bridge/main.go` — 主入口，HTTP 路由注册
- `mqtt-kafka-bridge/internal/bridge/` — 桥接核心逻辑
- `mqtt-kafka-bridge/internal/kafka/` — Kafka writer 封装

---

## 6. 模块 2 — device-communication 通信层改造

### 6.1 可靠性修复

#### 6.1.1 统一重试帮助函数

**问题**: `data_service.go` 中 5 处重复重试逻辑（lines 107, 283, 326, 401, 523，覆盖 notifyAPIServerStatus/notifyAPIServerInfo/HandleCmdResult/HandleOTAStatus 及 OTA 相关通知）。

**修复**: 提取统一的 `retryHTTPPost` 帮助函数。

```go
// RetryConfig 重试配置
type RetryConfig struct {
    MaxRetries       int           // 最大重试次数，默认 3
    BaseDelay        time.Duration // 基础延迟，默认 500ms
    MaxDelay         time.Duration // 最大延迟，默认 5s
    RetryStatusCodes []int         // 可重试状态码列表，默认 [500, 502, 503, 504]
}

// retryHTTPPost 统一 HTTP POST 重试
func retryHTTPPost(ctx context.Context, client *http.Client, url string, payload []byte, opts RetryConfig) (*http.Response, error) {
    // 指数退避重试实现
    // 每次重试记录日志
    // 返回最终响应或错误
}
```

> **作用域扩展**：除 `data_service.go` 的 5 处外，以下 3 处 `postInternal` 也需统一使用 `retryHTTPPost`：
> - `device_state_manager.go`:postInternal（状态变更通知）
> - `protocol_parser.go`:postInternal（遥测数据通知）
> - `alert_consumer.go`:postInternalAlarmRequest（告警转发）

#### 6.1.2 MQTT Stats 原子化

**问题**: `DataReceived++`、`CmdSent++` 等非原子操作在并发下可能丢失计数。

**修复**: 改用 `atomic.Int64` 类型：

```go
type MQTTStats struct {
    // 迁移为 atomic.Int64（并发安全计数器）
    DataReceived    atomic.Int64
    InfoReceived    atomic.Int64
    AlarmReceived   atomic.Int64
    CmdSent         atomic.Int64

    // 保持非原子类型
    LastDataAt      time.Time      // 最后数据到达时间，非计数器
    OnlineClients   int64          // 当前在线客户端数，由 Set 操作维护
}
```

> **注**: 现有 `client.go` 中 MQTTStats 共 6 个字段。`DataReceived`/`InfoReceived`/`AlarmReceived`/`CmdSent` 四个计数器迁移为 `atomic.Int64`；`LastDataAt`（`time.Time` 类型）和 `OnlineClients`（由 online-set 维护的瞬时值）保持原有类型不变。

#### 6.1.3 Redis 错误处理规范化

**问题**: 使用 `err.Error() != "redis: nil"` 字符串比较判断 Redis 错误。

**修复**: 替换为标准 `errors.Is` 判断：

```go
// 修复前（错误方式）
if err.Error() != "redis: nil" {
    log.Errorf("Redis error: %v", err)
}

// 修复后（正确方式）
if !errors.Is(err, redis.Nil) {
    log.Errorf("Redis error: %v", err)
}
```

#### 6.1.4 Redis 断连恢复策略

**问题**: Redis 断连后无自动恢复机制，缓存操作持续失败。

**修复**: 新增 Redis 健康监控协程：

```
启动 → 每 5s Ping 检测
         ├── 成功 → 正常模式
         └── 失败 → 日志告警 + 降级模式
                    ├── 跳过缓存，直接写 DB
                    ├── 记录降级指标
                    └── 持续重试重连
                         └── 成功 → 恢复模式
                              ├── 重建 heartbeat TTL
                              ├── 重建 online-set
                              └── 恢复正常模式
```

#### 6.1.5 Kafka Consumer 优雅关闭

**问题**: Kafka consumer 无优雅关闭，可能导致 in-flight 消息丢失。

**修复**: 添加 `sync.WaitGroup` 管理：

```go
func (c *KafkaConsumer) GracefulShutdown(timeout time.Duration) {
    c.cancel() // 发送关闭信号
    done := make(chan struct{})
    go func() {
        c.wg.Wait() // 等待 in-flight 消息处理完成
        close(done)
    }()
    select {
    case <-done:
        log.Info("All in-flight messages processed")
    case <-time.After(timeout):
        log.Warn("Graceful shutdown timeout, forcing exit")
    }
}
```

### 6.2 可观测性增强

| 新增能力 | 实现方式 |
|---------|---------|
| 暴露 IngestMetrics | 增强 `/metrics` 端点 |
| Kafka 消费延迟 | 新增 lag 和 message age 指标 |
| 命令投递 SLA | 新增命令发送/确认/超时计数 |
| Redis 健康上报 | 每 30s 写入 Redis |
| 增强 `/health` 端点 | 返回结构化 JSON |

**`/metrics` 新增指标**:

> **现有 `/metrics` 输出**（2 个指标）：`inv_device_mqtt_online_clients`, `inv_device_mqtt_cmd_sent`
> **现有 `/health` 输出**：Redis ping 状态 + MQTT broker 连接状态（来自 Redis 键）+ 在线客户端数
> 以下为增量新增字段。

| 指标名 | 类型 | 说明 |
|--------|------|------|
| `ingest_processed_total` | Counter | 成功处理的消息总数 |
| `ingest_retries_total` | Counter | HTTP 重试总次数 |
| `ingest_dlq_total` | Counter | 进入 DLQ 的消息总数 |
| `ingest_permanent_errors_total` | Counter | 永久性错误（进入 DLQ 前最终失败）总数 |
| `ingest_latency_seconds` | Histogram | 消息处理延迟分布 |
| `kafka_consumer_lag` | Gauge | 当前消费 lag（offset 差值） |
| `kafka_message_age_seconds` | Gauge | 消息从产生到处理完成的时间差 |
| `commands_sent_total` | Counter | 命令发送总数 |
| `commands_acked_total` | Counter | 命令确认总数 |
| `commands_expired_total` | Counter | 命令超时总数 |
| `commands_avg_latency_seconds` | Gauge | 命令平均投递延迟 |

**`/health` 响应格式**:

```json
{
  "status": "ok",
  "mqtt": "connected",
  "kafka_lag": 12,
  "redis": "connected",
  "online_devices": 45,
  "dlq_pending": 3,
  "uptime_seconds": 172800
}
```

---

## 7. 模块 3 — device-communication 状态层改造

### 7.1 可靠性修复

#### 7.1.1 统一状态管理

**问题**: Hub 和 DeviceStateManager 各自维护独立的心跳/在线状态管理，可能导致状态不一致。

**修复**: 统一为 DeviceStateManager 作为唯一状态权威：

```
修复前:
  Hub ──── 独立管理 heartbeat/online-set
  DeviceStateManager ──── 独立管理状态

修复后:
  Hub ──── 仅负责 MQTT 消息路由
  DeviceStateManager ──── 唯一状态权威
      ├── 心跳处理
      ├── 在线/离线判定
      ├── 状态转换审计
      └── Redis 状态同步
```

**关键变更**:
- 移除 Hub 中的独立 heartbeat/online-set 管理逻辑
- Hub 仅负责 MQTT 消息路由，所有状态变更通过 DeviceStateManager 的统一 API 进行
- DeviceStateManager 负责所有 Redis 心跳键和在线集合的维护

#### 7.1.2 实现 `hasActiveSevereAlarms()`

**问题**: 当前为空 stub，始终返回 false，导致告警状态不影响设备状态判定。

**修复**: 实现完整逻辑：

```go
func (dsm *DeviceStateManager) hasActiveSevereAlarms(ctx context.Context, deviceSN string) (bool, error) {
    // 1. 从 Redis 获取设备活跃告警列表
    alarms, err := dsm.redisClient.GetActiveAlarms(deviceSN)
    if err != nil {
        return false, fmt.Errorf("failed to get active alarms: %w", err)
    }
    // 2. 检查是否存在严重级别（level >= warning）的告警码
    for _, alarm := range alarms {
        if alarm.Level >= AlarmLevelWarning {
            return true, nil
        }
    }
    return false, nil
}
```

**告警级别常量定义**（需在代码中新增）：

```
- AlarmLevelInfo = 1      // 信息级，不触发故障状态
- AlarmLevelWarning = 2   // 警告级，触发故障状态
- AlarmLevelCritical = 3  // 严重级，触发故障状态
hasActiveSevereAlarms 检查 level >= AlarmLevelWarning (即 >= 2)
```

**数据源**：查询 Redis Set `device:alarm:active:{sn}`（现有告警处理流程中已维护的活跃告警集合）。
若该键不存在，则需新增：在 AlertConsumer 处理告警消息时，将活跃告警码写入此 Set；告警恢复时移除。

#### 7.1.3 状态变更通知重试

**问题**: `postInternal` 状态变更通知无重试，单次失败即丢失。

**修复**: 复用模块 2 中提取的统一 `retryHTTPPost` 帮助函数，确保状态变更通知可靠送达 business-api。

#### 7.1.4 stateCache 无限增长问题

**问题**: `stateCache`（`sync.Map`）无上限，长时间运行可能内存泄漏。

**修复**: 改用 Redis 作为唯一缓存源（Redis 已有 TTL 机制），移除本地 `sync.Map`。好处：
- 自动过期清理，无内存泄漏风险
- 多实例部署时状态一致
- 统一数据源，减少不一致可能

### 7.2 可观测性增强

| 新增能力 | 实现方式 |
|---------|---------|
| 状态转换指标 | 追踪每秒状态变更频率 |
| 状态转换审计日志 | 写入 Redis List，供排查设备连接问题 |
| 去抖事件指标 | 追踪去抖机制的过滤效果 |

**新增指标详情**:

| 指标名 | 类型 | Labels | 说明 |
|--------|------|--------|------|
| `device_state_transitions_total` | Counter | `from_state`, `to_state` | 状态转换计数 |
| `device_debounce_events_total` | Counter | `event_type`, `action` (accepted/rejected) | 去抖事件计数 |

**状态转换审计日志格式**（Redis List 元素）:

```json
{
  "sn": "CS6K2-20260101-001",
  "from": "online",
  "to": "offline",
  "reason": "heartbeat_timeout",
  "timestamp": "2026-07-22T10:30:00Z",
  "active_alarms": 0
}
```

---

## 8. 模块 4 — business-api 聚合层改造

### 8.1 新增 API 端点

| 端点 | 方法 | 功能 | 认证 |
|------|------|------|------|
| `/api/v1/system/pipeline-health` | GET | 聚合管道健康状态 | Admin RBAC |
| `/api/v1/system/pipeline-metrics` | GET | 聚合关键指标 | Admin RBAC |
| `/api/v1/system/dlq` | GET | DLQ 列表查询（分页） | Admin RBAC |
| `/api/v1/system/dlq/:id/retry` | POST | 重试单条 DLQ 消息 | Admin RBAC |
| `/api/v1/system/dlq/:id` | DELETE | 清除单条 DLQ 消息 | Admin RBAC |

> **DLQ 存储方案**：复用现有 Redis List（`kafka:dlq:{consumer_type}`），由 device-communication 的 DLQ 模块维护。
> business-api 通过 Redis 客户端直接读取 DLQ 数据，无需新增 PostgreSQL 表。
> API 实现需新增 Redis 连接配置（复用 device-communication 的 Redis 实例）。

**`GET /api/v1/system/pipeline-health` 响应格式**:

```json
{
  "overall_status": "degraded",
  "services": {
    "bridge": {
      "status": "ok",
      "kafka_connected": true,
      "last_heartbeat": "2026-07-22T10:30:00Z"
    },
    "device-server": {
      "status": "degraded",
      "kafka_lag": 1500,
      "redis": "connected",
      "last_heartbeat": "2026-07-22T10:30:00Z"
    },
    "api": {
      "status": "ok",
      "db_pool_active": 5,
      "last_heartbeat": "2026-07-22T10:30:00Z"
    }
  },
  "summary": {
    "online_devices": 42,
    "total_devices": 50,
    "connection_rate": "84%"
  }
}
```

> `overall_status` 计算规则：全部 `ok` → `ok`；任一 `degraded` → `degraded`；任一 `down` 或心跳超时 → `down`

**`GET /api/v1/system/dlq` 查询参数**:

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `page` | int | 1 | 页码 |
| `page_size` | int | 20 | 每页数量 |
| `consumer_type` | string | - | 按消费者类型过滤 |

**`GET /api/v1/system/dlq` 响应格式**:

```json
{
  "items": [
    {
      "id": "dlq-001",
      "consumer_type": "telemetry",
      "topic": "device-telemetry",
      "payload_summary": "...",
      "error_message": "upstream timeout",
      "retry_count": 3,
      "created_at": "2026-07-22T09:00:00Z"
    }
  ],
  "total": 15,
  "page": 1,
  "page_size": 20
}
```

### 8.2 SSE 与现有接口增强

**SSE 新增事件类型**:

在现有 SSE 通道中新增 `pipeline_health` 事件类型，每 30s 推送聚合健康快照：

```
event: pipeline_health
data: {"overall_status":"ok","online_devices":42,"total_devices":50,"message_rate":125.3,"dlq_pending":3}
```

**增强现有 `/api/v1/system/health`**:

- 补充 Redis 连通性检查（`redis_ping` 字段）
- 补充数据库连接池状态（`db_pool_active`, `db_pool_idle`, `db_pool_max`）

---

## 9. 模块 5 — React 前端增强

### 9.1 系统健康页面增强

在现有 React 管理后台的**系统配置 → 系统健康**页面中新增以下展示区域：

| 区域 | 展示内容 | 数据来源 |
|------|---------|---------|
| 管道状态总览 | 三色指示灯（绿/黄/红）：Bridge、Kafka、Device-Server、API 四个节点的连通状态 | `pipeline-health` API + SSE |
| 设备连接率 | 在线设备数 / 总注册设备数，百分比 + 趋势图（最近 1h） | `pipeline-metrics` API |
| 消息吞吐量 | 实时消息处理速率（条/秒） | SSE `pipeline_health` 事件 |
| DLQ 积压 | 当前 DLQ 中的消息数量 + 最近 10 条预览，支持重试/清除操作 | `dlq` API |
| 消费延迟 | Kafka 消费延迟指标，lag 数值 + 颜色阈值 | `pipeline-metrics` API |
| 命令投递 | 命令发送成功率百分比 + 超时计数 | `pipeline-metrics` API |

### 9.2 颜色阈值规则

| 指标 | 绿色（正常） | 黄色（警告） | 红色（严重） |
|------|------------|------------|------------|
| Kafka Lag | < 100 | 100 - 1000 | > 1000 |
| 设备连接率 | > 90% | 70% - 90% | < 70% |
| 命令投递成功率 | > 95% | 80% - 95% | < 80% |
| DLQ 积压数 | < 10 | 10 - 100 | > 100 |

### 9.3 数据刷新策略

- **SSE 推送**: `pipeline_health` 事件每 30s 自动推送，前端实时更新
- **手动刷新**: 页面提供刷新按钮，调用 REST API 获取最新数据
- **断线重连**: SSE 断线后自动重连，重连期间显示 "数据更新中..." 提示

---

## 10. 测试策略

### 10.1 单元测试

| 测试目标 | 覆盖场景 |
|---------|---------|
| `retryHTTPPost` 帮助函数 | 重试次数正确、指数退避、超时处理、可重试/不可重试状态码区分 |
| Redis 健康监控 | 断连检测、降级模式切换、重连恢复、heartbeat/online-set 重建 |
| 状态转换机 | 所有合法转换路径（online→offline, offline→alarm 等）、非法转换拒绝 |
| `hasActiveSevereAlarms` | 无告警返回 false、低级告警返回 false、warning 及以上返回 true、Redis 错误处理 |
| Prometheus 指标格式 | 验证输出符合 Prometheus  exposition format |
| Bridge 原子计数器 | 并发写入正确性验证 |

### 10.2 集成测试

| 测试目标 | 覆盖场景 |
|---------|---------|
| Bridge `/health` 端点 | Kafka 连通时返回 `ok`、Kafka 断开时返回 `degraded` |
| device-server `/metrics` 端点 | 输出格式正确、指标名合法、数值合理 |
| pipeline-health 聚合 API | 全部 ok 返回 ok、部分 degraded 返回 degraded、心跳超时返回 down |
| DLQ 管理 API | 列表分页、重试操作、清除操作 |

### 10.3 端到端验证（手动）

```
1. 启动所有服务 → 检查各健康端点返回 ok
2. 模拟设备上线 → 确认在线设备数指标变化
3. 发送遥测数据 → 确认 ingest 指标和延迟指标变化
4. 模拟 Redis 断连 → 确认降级日志输出、服务继续运行
5. 恢复 Redis → 确认自动重连、heartbeat 重建
6. 停止 Kafka → 确认 bridge 健康状态变为 degraded
7. 发送无效数据 → 确认 DLQ 积压增加
8. 通过管理后台 DLQ 页面重试/清除消息
```

---

## 11. 错误处理原则

### 11.1 核心原则

1. **所有新增的网络调用**（HTTP、Redis、Kafka）必须有明确的超时和错误处理路径
2. **降级而非崩溃**: Redis 不可用时跳过缓存但继续处理消息，记录降级指标
3. **健康探针的失败**不触发服务重启，只记录日志和更新健康状态
4. **状态变更失败时**记录审计日志但不阻塞消息处理流程

### 11.2 超时配置

| 操作 | 超时时间 | 说明 |
|------|---------|------|
| HTTP POST（含重试） | 30s | 单次请求 5s + 3 次重试 |
| Redis 操作 | 3s | 包含 Ping 探测 |
| Kafka 健康探针 | 5s | 每 10s 执行一次 |
| Kafka Consumer 关闭 | 15s | 等待 in-flight 消息 |

### 11.3 降级策略矩阵

| 故障组件 | 降级行为 | 恢复行为 |
|---------|---------|---------|
| Redis 不可用 | 跳过缓存写入，直接写 DB；心跳通过 DB 兜底 | 自动重连后重建 heartbeat/online-set |
| Kafka 不可用 | Bridge 缓存消息到内存队列（上限 1000 条），超限丢弃并记录 | Kafka 恢复后 flush 缓存队列 |
| business-api 不可用 | 状态变更通知进入本地重试队列 | API 恢复后自动重试 |

---

## 12. 部署顺序

```
Step 1: mqtt-kafka-bridge
  └── 验证: /health 返回含 Kafka 状态的 JSON，/metrics 输出 Prometheus 格式

Step 2: device-communication
  └── 验证: /health 返回结构化状态，/metrics 包含所有新增指标，Redis 断连恢复测试通过

Step 3: business-api
  └── 验证: pipeline-health 聚合 API 正常返回，DLQ API CRUD 正常，SSE 推送正常

Step 4: React Admin
  └── 验证: 系统健康页面展示正确，DLQ 管理功能正常，SSE 实时更新
```

> 每个模块独立部署验证，前一个模块验证通过后再部署下一个。

---

## 13. 关键文件路径

| 文件 | 路径 |
|------|------|
| mqtt-kafka-bridge 主文件 | `mqtt-kafka-bridge/main.go` |
| device-communication 入口 | `device-communication/cmd/main.go` |
| MQTT 客户端 + Hub | `device-communication/internal/mqtt/client.go` |
| 设备状态机 | `device-communication/internal/service/device_state_manager.go` |
| 数据服务 | `device-communication/internal/service/data_service.go` |
| 协议解析器 | `device-communication/internal/service/protocol_parser.go` |
| 告警消费者 | `device-communication/internal/service/alert_consumer.go` |
| Kafka 有序消费者 | `device-communication/internal/service/kafka_consumer.go` |
| 重试 + DLQ | `device-communication/internal/service/retry_consumer.go`, `dlq.go` |
| Ingest 指标 | `device-communication/internal/service/metrics.go` |
| 心跳解析器 | `device-communication/internal/telemetry/heartbeat_v1.go` |
| business-api 设备处理 | `business-api/internal/handler/device_handler.go` |
| business-api 内部处理 | `business-api/internal/handler/internal_handler.go` |
| 系统健康 | `business-api/internal/handler/system_health.go` |
| WebSocket/SSE | `business-api/internal/handler/ws_handler.go` |
| 数据库 Schema | `database/schema.sql` |

---

## 14. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| Redis 键命名冲突 | 与现有键冲突导致数据覆盖 | 使用 `pipeline:` 前缀，与现有 `device:` 前缀隔离 |
| 指标暴露安全风险 | 敏感信息泄露 | `/metrics` 端点仅内网访问，不暴露到公网 |
| 状态统一后回归 bug | Hub 状态丢失 | 渐进式迁移，先双写再切换，保留回滚能力 |
| DLQ 数据量过大 | 查询性能下降 | 设置 DLQ 自动清理策略（默认保留 7 天） |

---

## 15. 验收标准

| 验收项 | 标准 |
|--------|------|
| Bridge 健康探针 | `/health` 正确反映 Kafka 连通性，断连 10s 内状态更新 |
| 统一重试函数 | `data_service.go` 中无重复重试代码，所有 HTTP POST 通过统一函数 |
| Redis 断连恢复 | Redis 断连 30s 内检测到，恢复后 60s 内完成 heartbeat 重建 |
| 状态管理统一 | Hub 中无独立状态管理代码，所有状态变更通过 DeviceStateManager |
| 管道健康聚合 | 3 个服务中任一降级，聚合状态显示 degraded |
| DLQ 管理 | 可通过管理后台查看、重试、清除 DLQ 消息 |
| 前端展示 | 系统健康页面实时展示所有管道指标，SSE 推送延迟 < 5s |
| 测试覆盖 | 单元测试覆盖所有新增函数，集成测试覆盖所有新增 API |
