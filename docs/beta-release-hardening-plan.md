# Beta 发布稳固完善高性能整改计划

> 文档创建日期: 2026-07-15
> 目标: 将系统从当前开发状态推进至可发布 Beta 版本，确保稳固、完善、高性能

---

## 一、当前状态评估

### 1.1 构建状态

| 组件 | 状态 | 关键问题 |
|------|------|---------|
| api-gateway | ⚠️ 可构建，测试部分失败 | RBAC 路由测试 5 个子测试失败（403 替代 200） |
| inv_api_server | ❌ 编译失败 | `DeviceRepository` struct 定义缺失，被引用 15 次但从未声明 |
| inv_device_server | ❌ 编译失败 | 6 个 Kafka 辅助符号未定义（`kafkaMessageReader`、`ingestErrorStore`、`runOrderedKafkaConsumer`、`permanentMessage`、`downstreamHTTPError`、`asPermanentMessage`） |
| mqtt-kafka-bridge | ✅ 构建通过，测试通过 | 无问题 |
| React 前端 | ⚠️ 需 npm install | worktree 中无 node_modules，CI 环境可构建 |
| Flutter 应用 | ⚠️ 分析有警告 | 非阻断性问题 |

### 1.2 核心阻断项

| # | 问题 | 严重度 | 影响 |
|---|------|--------|------|
| B1 | inv_api_server 编译失败（DeviceRepository 缺失） | 阻断 | API 服务完全不可用 |
| B2 | inv_device_server 编译失败（6 个符号缺失） | 阻断 | 设备服务完全不可用 |
| B3 | api-gateway RBAC 测试失败（5 个子测试） | 阻断 | 权限校验逻辑回归 |
| B4 | authStore 角色 1 权限绕过（2 个测试失败） | 严重 | 代理商获得管理员权限 |
| B5 | 数据库迁移 039-047 未提交 | 阻断 | schema 与代码不匹配 |
| B6 | 并机/三相/告警写入接口 HTTP 500 | 阻断 | 核心协议功能不可用 |
| B7 | Device Server MQTT 证书 pin 不匹配 | 阻断 | 设备服务不健康 |

### 1.3 功能完成度

| 模块 | 完成度 | 主要差距 |
|------|--------|---------|
| 设备接入与遥测 | 75% | Device Server 不健康；三相 DTO 不一致 |
| 告警管理与推送 | 60% | 告警事件 SQL 列不匹配；索引退化 |
| OTA 固件升级 | 80% | 并发下发、HTTP 超时未确认 |
| 设备型号管理 | 70% | Flutter 端硬编码；Protocol UI 未确认 |
| 电站管理与可视化 | 75% | WebSocket 仍轮询；N+1 请求；UI 不统一 |
| 用户权限管理 | 80% | authStore 权限绕过；角色语义不一致 |
| Flutter 移动端 | 70% | 实体硬编码；控制页未动态化 |
| React 管理后台 | 75% | Bundle 3.33MB；2 种 Card/5 种统计卡片 |

---

## 二、P0 — 阻断项修复（必须完成）

### P0-1: 修复 inv_api_server 编译 [B1]

**问题**: `repositories.go` 第 757 行起引用 `DeviceRepository` 类型 15 次，但 struct 定义不存在。

**修复方案**:
- 在 `repositories.go` 中添加 `DeviceRepository` struct 定义
- 包含正确的 `db *sql.DB` 或 `*pgxpool.Pool` 字段
- 确保所有 15 处引用的方法接收者类型一致
- 运行 `go build ./...` 验证编译通过
- 运行 `go test ./...` 验证测试通过

**验收标准**: `go build ./...` 和 `go test ./...` 在 inv_api_server 目录均通过

### P0-2: 修复 inv_device_server 编译 [B2]

**问题**: `alert_consumer.go` 和 `protocol_parser.go` 引用 6 个未定义符号。

**修复方案**:
- 创建 `internal/service/kafka_helpers.go`（或 `ingest_types.go`）
- 定义 `kafkaMessageReader` interface（参考 `pkg/kafka/kafka.go` 中的 `messageReader`）
- 定义 `ingestErrorStore` interface
- 定义 `downstreamHTTPError` struct
- 实现 `runOrderedKafkaConsumer`、`permanentMessage`、`asPermanentMessage` 函数
- 确保与最近提交 `32493cc0` 的"系统稳定性优化"逻辑一致
- 运行 `go build ./...` 和 `go test ./...` 验证

**验收标准**: `go build ./...` 和 `go test ./...` 在 inv_device_server 目录均通过

### P0-3: 修复 api-gateway RBAC 路由测试 [B3]

**问题**: 设备协议读取路由（alarm-events、parallel-state、three-phase）返回 403 而非 200。

**修复方案**:
- 检查 `internal/routes/` 中的路由注册和权限配置
- 确认 RBAC 中间件对 device protocol 读取路由的权限策略
- 修复权限校验逻辑使其与测试期望一致
- 确保不削弱安全性（不应简单跳过权限检查）
- 运行 `go test ./internal/routes/... -run TestDeviceProtocol` 验证

**验收标准**: api-gateway 所有测试通过

### P0-4: 修复前端 authStore 权限绕过 [B4]

**问题**: 角色 1（代理商）在前端被当作全权限，与后端 RBAC 不一致。

**修复方案**:
- 检查 `inv-admin-frontend/src/` 中 authStore 的角色判断逻辑
- 修复角色 1 的权限范围，使其与后端 RBAC 一致
- 确保代理商只能看到自己权限范围内的功能和数据
- 运行前端测试验证 160/160 通过

**验收标准**: 前端所有测试通过（含原有 2 个失败用例）

### P0-5: 完成数据库迁移提交与验证 [B5]

**问题**: 迁移 039-047 为未跟踪文件，schema.sql 已修改但未提交。

**修复方案**:
- 审查迁移 039-047 的 SQL 内容
- 确保迁移文件命名规范一致（时间戳前缀）
- 验证空库 fresh install 路径（从 001 顺序执行到最新）
- 验证存量库升级路径（从 038 升级到 047）
- 修复迁移 036 down 脚本的 PL/pgSQL 语法错误
- 确保 `schema.sql` 与最终迁移结果一致

**验收标准**: 两条迁移路径均成功执行，schema.sql 一致

### P0-6: 修复核心写入接口 HTTP 500 [B6]

**问题**: 并机状态、三相遥测、设备告警上报接口返回 500。

**修复方案**:
- 修复 `device_parallel_state.updated_at` 列不存在问题
- 统一三相遥测 DTO 与数据库 SQL
- 修复 `alarms.type/level/message` 列不存在问题
- 确保所有写入接口返回 2xx
- 添加端到端测试覆盖三个接口

**验收标准**: 三个写入接口均返回 200/201，端到端测试通过
**依赖**: P0-1、P0-5

### P0-7: 修复 Device Server MQTT 健康 [B7]

**问题**: MQTT 证书 pin 为全零占位值，Device Server 持续 unhealthy。

**修复方案**:
- 检查 Device Server 的 MQTT TLS 证书 pin 配置
- 配置正确的证书摘要值或改为开发环境跳过验证
- 确保 Device Server 健康检查通过
- 验证 MQTT 连接和消息接收正常

**验收标准**: Device Server 健康状态为 healthy
**依赖**: P0-2

---

## 三、P1 — 稳定性提升

### P1-1: Kafka/HTTP 重试与数据防丢

**问题**: 批处理重试耗尽后直接丢数据，无死信队列。

**方案**:
- 实现死信队列（DLQ）存储永久失败的消息
- 添加重试计数和指数退避策略
- 添加监控指标（重试次数、DLQ 积压量）
- 确保消息至少被处理一次（at-least-once 语义）

**依赖**: P0-2

### P1-2: WebSocket 轮询改 Redis Pub/Sub

**问题**: WebSocket 实时推送仍用轮询，延迟高、资源浪费。

**方案**:
- 替换轮询为 Redis Pub/Sub 订阅模式
- 优化连接管理（心跳、重连、超时清理）
- 添加连接数监控指标

**依赖**: P0-1

### P1-3: 设备状态管理集中化

**问题**: 状态管理逻辑分散在 4 个文件 2 个服务中，LWT 竞态未集中处理。

**方案**:
- 完成 DeviceStateManager 阶段二至四
- 从 protocol_parser.go、internal_handler.go 迁移防抖逻辑
- 集中化 LWT（Last Will Testament）竞态处理
- 添加状态转换测试

**依赖**: P0-2、P0-6

### P1-4: 前端 UI 一致性整改

**问题**: 2 种 Card 样式、5 种统计卡片、3 种表格 size、6 个页面缺标题。

**方案**:
- 统一 Card 组件使用标准 ProCard
- 统一统计卡片为 StatisticCard 组件
- 统一表格 size 为 middle
- 补充所有页面标题
- 统一数据获取模式（React Query）
- 消除重复工具函数

**依赖**: P0-4

### P1-5: 前端 Bundle 优化

**问题**: Bundle 3.33MB（gzip 1.04MB），首次加载慢。

**方案**:
- 路由级代码分割（React.lazy + Suspense）
- 第三方库按需引入（echarts、antd）
- 配置 Vite manualChunks 优化分包
- 目标：gzip < 500KB

**依赖**: P0-4

---

## 四、P2 — 性能优化

### P2-1: 数据库查询优化

- 审计慢查询，添加缺失索引（尤其 alarms 表业务索引）
- 优化 N+1 查询（实时数据批量获取）
- 添加查询缓存（Redis）对高频低变数据
- TimescaleDB 连续聚合调优

### P2-2: API 响应优化

- 添加 Gzip 压缩中间件
- 实现分页游标优化（大数据量场景）
- 并发查询优化（errgroup 批量获取）

### P2-3: Redis 缓存策略完善

- 实现多级缓存（本地缓存 + Redis）
- 添加缓存预热和失效策略
- 缓存击穿/雪崩防护（singleflight + 随机 TTL）

---

## 五、P2 — 安全加固

### P2-4: 传输安全

- 启用 MQTT TLS 证书验证（移除 `MQTT_TLS_INSECURE=true`）
- Nginx 配置 HTTPS（Let's Encrypt 或自签证书）
- 数据库连接启用 SSL

### P2-5: 密钥管理

- 邮箱密码改为环境变量注入
- EMQX 认证密码移除硬编码
- 统一密钥管理方案（Docker Secrets 或 Vault）

### P2-6: 权限审计

- 修复新查询端点的设备 SN 对象级归属校验
- 审计所有 API 端点的跨租户数据隔离
- 添加权限测试覆盖

---

## 六、并行执行计划

### Phase 1 — 阻断项修复（5 个并行任务，无依赖）

| 任务 | 范围 | 预计工时 |
|------|------|---------|
| T1: 修复 inv_api_server 编译 | DeviceRepository struct | 1-2h |
| T2: 修复 inv_device_server 编译 | 6 个 Kafka 辅助符号 | 2-3h |
| T3: 修复 api-gateway RBAC 测试 | 权限校验逻辑 | 1-2h |
| T4: 修复前端 authStore 权限 | 角色 1 权限范围 | 1-2h |
| T5: 完成数据库迁移 | 迁移 039-047 验证提交 | 1-2h |

### Phase 2 — 核心功能修复（4 个并行任务，依赖 Phase 1）

| 任务 | 范围 | 依赖 |
|------|------|------|
| T6: 修复核心写入接口 500 | 并机/三相/告警 | T1, T5 |
| T7: 修复 Device Server MQTT 健康 | 证书 pin | T2 |
| T8: Kafka 重试与数据防丢 | DLQ + 退避 | T2 |
| T9: 前端 UI 一致性 + Bundle 优化 | 组件统一 + 分包 | T4 |

### Phase 3 — 加固与优化（3 个并行任务，依赖 Phase 2）

| 任务 | 范围 | 依赖 |
|------|------|------|
| T10: 安全加固 | TLS/HTTPS/密钥 | T6, T7, T8 |
| T11: 性能优化 | 索引/缓存/查询 | T6, T8 |
| T12: 设备状态管理集中化 | 状态机整合 | T6, T7 |

---

## 七、Beta 发布验收标准

### 必须满足（全部通过）

- [ ] 4 个 Go 服务全部 `go build ./...` 通过
- [ ] 4 个 Go 服务全部 `go test ./...` 通过
- [ ] React 前端 `npm run build` 通过
- [ ] React 前端所有测试通过（160/160）
- [ ] Flutter `flutter analyze` 无错误
- [ ] 数据库迁移空库 + 升级两条路径验证通过
- [ ] 并机/三相/告警写入接口返回 2xx
- [ ] Device Server 健康状态 healthy
- [ ] authStore 权限与后端 RBAC 一致
- [ ] 端到端 MQTT 数据链路通畅

### 建议满足（提升质量）

- [ ] Kafka 死信队列实现
- [ ] WebSocket 改为 Pub/Sub
- [ ] 前端 Bundle gzip < 500KB
- [ ] 前端 UI 组件统一
- [ ] 慢查询索引优化
- [ ] HTTPS 配置就绪
