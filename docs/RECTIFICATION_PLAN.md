# 项目整改执行计划

> 基于全方位深度审查结果，按模块拆分为 8 条并行工作线，每条线独立可执行。

---

## 并行工作线总览

```
线程1 [安全加固]     ████████████████████████████████  P0 全部 + P1 安全项
线程2 [认证体系]     ████████████████████████          P0 验证码 + JWT刷新
线程3 [内部API]      ████████████████████              P0 认证 + 全局DB消除
线程4 [设备服务]     ██████████████████                移除repo + 性能优化
线程5 [WebSocket]    ████████████████                  Redis Pub/Sub改造
线程6 [OTA服务]      ████████████████                  并发下发 + 错误处理
线程7 [代码规范]     ██████████████████████            类型安全 + 错误信息 + 死代码
线程8 [数据库]       ████████████████                  迁移统一 + 缓存策略
```

---

## 线程1：安全加固 [负责人: A]

### 1.1 CORS 收敛
- **文件**: `inv_api_server/internal/middleware/auth.go`
- **现状**: `Access-Control-Allow-Origin: *`
- **改造**: 从配置读取 `cors.allowed_origins`，生产环境只允许前端域名
- **验收**: 跨域请求只允许白名单域名

### 1.2 WebSocket 来源校验
- **文件**: `inv_api_server/internal/handler/ws_handler.go`
- **现状**: `CheckOrigin: func(r *http.Request) bool { return true }`
- **改造**: 校验 `Origin` 头是否在允许列表中
- **验收**: 非白名单 Origin 的 WebSocket 握手被拒绝

### 1.3 用户列表权限收窄
- **文件**: `inv_api_server/cmd/main.go` (路由注册)
- **现状**: `/api/v1/users` 只需要登录即可访问
- **改造**: 添加 `RequirePermission(permChecker, "users", "view")`
- **验收**: 普通用户访问 `/api/v1/users` 返回 403

### 1.4 设备序列号格式校验
- **文件**: `inv_api_server/internal/handler/device_handler.go`
- **现状**: 用户提交的 SN 直接使用
- **改造**: 添加正则 `^[A-Z0-9-]{8,64}$` 校验
- **验收**: 不合法格式的 SN 返回 400

### 1.5 数据库连接日志脱敏
- **文件**: `inv_api_server/cmd/main.go`, `inv_device_server/cmd/main.go`
- **现状**: 日志中打印完整连接信息
- **改造**: 日志只打印 host/port/database/user
- **验收**: 日志中不出现密码字段

### 1.6 端口暴露最小化
- **文件**: `deploy/docker-compose.yml`
- **现状**: postgres/redis/kafka 都映射到宿主机端口
- **改造**: 生产 compose 中移除不必要的端口映射，只保留 gateway:80
- **验收**: 生产环境只有 gateway 端口对外

---

## 线程2：认证体系重构 [负责人: B]

### 2.1 SMS 验证码真实发送
- **文件**: `inv_api_server/internal/service/services.go`
- **现状**: `SendCode` 只存 Redis，不调用短信网关
- **改造**:
  1. 新增 `inv_api_server/internal/service/sms_provider.go`
  2. 定义 `SMSProvider` 接口: `Send(phone, code string) error`
  3. 实现 `AliyunSMSProvider` 和 `MockSMSProvider`
  4. `SMSService.SendCode` 中调用 `provider.Send()`
  5. 配置中新增 `sms.provider` / `sms.access_key` / `sms.secret_key`
- **验收**: 调用 `/auth/send-code` 后手机收到验证码

### 2.2 验证码使用 crypto/rand
- **文件**: `inv_api_server/internal/service/services.go`
- **现状**: `math/rand.Intn(10)` 生成验证码
- **改造**: 改用 `crypto/rand.Int(rand.Reader, big.NewInt(10))`
- **验收**: 验证码不可预测

### 2.3 JWT 缩短有效期 + Refresh Token
- **文件**: `inv_api_server/pkg/jwt/jwt.go`, `inv_api_server/internal/handler/auth_handler.go`
- **现状**: Access Token 168h，无刷新机制
- **改造**:
  1. Access Token 有效期改为 2h
  2. 新增 `RefreshToken` 生成方法（有效期 7d，存 Redis）
  3. 新增 `/auth/refresh` 接口
  4. 登录时同时返回 access_token + refresh_token
  5. 新增 `/auth/logout` 撤销 refresh_token
- **验收**: Token 2h 过期后可用 refresh_token 续期

### 2.4 Token 黑名单
- **文件**: `inv_api_server/internal/middleware/auth.go`
- **改造**: 登出时将 token JTI 存入 Redis 黑名单（TTL = token 剩余有效期）
- **验收**: 登出后 token 立即失效

---

## 线程3：内部 API 与依赖注入 [负责人: C]

### 3.1 内部 API 认证
- **文件**: `inv_api_server/internal/middleware/internal_auth.go` (新建)
- **现状**: `/api/v1/internal/*` 无任何认证
- **改造**:
  1. 新增 `InternalAuthMiddleware(sharedSecret string)`
  2. 校验请求头 `X-Internal-Key` 是否匹配共享密钥
  3. 密钥从环境变量 `INTERNAL_API_SECRET` 读取
  4. 设备服务发请求时附带该 header
- **验收**: 无 key 的请求返回 401

### 3.2 消除全局 DB 变量
- **文件**: `inv_api_server/internal/handler/common.go`, `internal_handler.go`
- **现状**: `var db *pgxpool.Pool` 全局变量
- **改造**:
  1. 新增 `InternalHandler` 结构体，通过构造函数注入 `*pgxpool.Pool`
  2. 将 `InternalDeviceStatus` 等 5 个函数改为 `InternalHandler` 的方法
  3. 删除 `SetDB` / `GetDB` / `bgCtx` 全局函数
  4. 所有 context 改为显式创建 + defer cancel
- **验收**: `handler` 包内无全局 DB 变量

### 3.3 AdminHandler 移除原始 SQL
- **文件**: `inv_api_server/internal/handler/admin_handler.go`
- **现状**: `ListAllModels` 直接写 SQL
- **改造**: SQL 移到 `ModelRepository.ListAllWithDeviceCount()`，handler 只调用 repo
- **验收**: handler 层无 SQL 字符串

### 3.4 setupRouter 参数结构化
- **文件**: `inv_api_server/cmd/main.go`
- **现状**: `setupRouter` 有 11 个参数
- **改造**: 定义 `RouterDeps` 结构体，将所有 handler/service 打包传入
- **验收**: `setupRouter` 参数不超过 3 个

---

## 线程4：设备服务瘦身 [负责人: D]

### 4.1 彻底移除 repo 依赖
- **文件**: `inv_device_server/internal/service/data_service.go`
- **现状**: `DataService` 仍持有 `repo` 字段，`GetRealtimeFromDB` 直接查库
- **改造**:
  1. `GetRealtimeFromDB` 改为调用 `GET /api/v1/devices/:sn/realtime`（通过 API 服务）
  2. 移除 `DataService.repo` 字段
  3. 设备服务的 `DeviceRepository` 只保留元数据查询方法
- **验收**: 设备服务无任何业务表写入和直接查询

### 4.2 内存 Map 改为 Redis Sorted Set
- **文件**: `inv_device_server/internal/mqtt/client.go`
- **现状**: `snToLastSeen map[string]time.Time` 内存存储
- **改造**:
  1. 移除 `snToLastSeen` map 和 `snMux`
  2. `MarkDeviceOnline` 只写 Redis `ZADD device:online {timestamp} {sn}`
  3. `IsDeviceOnline` 改用 `ZSCORE`
  4. `GetOnlineDeviceSNs` 改用 `ZRANGEBYSCORE`
- **验收**: 设备在线状态完全基于 Redis，支持多实例部署

### 4.3 MQTT 命令通道扩容
- **文件**: `inv_device_server/internal/mqtt/client.go`
- **现状**: `cmdChan` 固定 200 容量
- **改造**: 改为 1000 容量 + 非阻塞写入（select + default 返回错误）
- **验收**: 大规模下发不阻塞

### 4.4 启动时 initSchema 移除
- **文件**: `inv_device_server/cmd/main.go`
- **现状**: 启动时 `initSchema()` 创建表
- **改造**: 删除 `initSchema()`，所有表定义统一在 `database/schema.sql`
- **验收**: 设备服务启动不执行任何 DDL

---

## 线程5：WebSocket 实时推送改造 [负责人: E]

### 5.1 Redis Pub/Sub 替代轮询
- **文件**: `inv_api_server/internal/handler/ws_handler.go`
- **现状**: 每 2 秒轮询 Redis GET
- **改造**:
  1. 创建 WebSocket 时订阅 `realtime:data:{sn}` 频道
  2. 设备服务推送数据时同时 `PUBLISH` 到该频道
  3. 收到消息后推送给前端
  4. 移除 `pollTicker`
- **验收**: 无数据更新时 WebSocket 连接零 Redis 查询

### 5.2 连接管理优化
- **改造**:
  1. 添加连接数限制（每用户最多 5 个 WebSocket）
  2. 添加心跳检测（30 秒 ping/pong）
  3. 连接关闭时自动退订
- **验收**: 连接泄漏自动回收

---

## 线程6：OTA 服务改造 [负责人: F]

### 6.1 并发下发
- **文件**: `inv_api_server/internal/service/ota_service.go`
- **现状**: 串行 HTTP 调用
- **改造**:
  1. 使用 `errgroup.Group` + 令牌桶限制并发数（默认 10）
  2. 每个设备下发结果异步写入 task_device 表
  3. 下发完成后更新 task 状态
- **验收**: 100 台设备 OTA 下发耗时从 ~100s 降到 ~10s

### 6.2 HTTP Client 超时
- **文件**: `inv_api_server/internal/service/ota_service.go`
- **现状**: `httpClient: &http.Client{}` 无超时
- **改造**: `&http.Client{Timeout: 30 * time.Second}`
- **验收**: 下发超时不阻塞

### 6.3 OTA 命令走 MQTT 通道
- **现状**: OTA 命令通过 HTTP 发到设备服务的 internal 端口
- **改造**: OTA 命令直接通过 MQTT 发布到设备 topic
- **验收**: 减少一跳 HTTP 调用

---

## 线程7：代码规范统一 [负责人: G]

### 7.1 类型断言安全化
- **文件**: `inv_api_server/internal/middleware/auth.go`
- **改造清单**:
  ```go
  // Before
  func GetUserID(c *gin.Context) int64 {
      userID, _ := c.Get("user_id")
      return userID.(int64)
  }
  // After
  func GetUserID(c *gin.Context) int64 {
      v, exists := c.Get("user_id")
      if !exists { return 0 }
      id, ok := v.(int64)
      if !ok { return 0 }
      return id
  }
  ```
- **验收**: 所有 `c.Get()` 返回值做 comma-ok 断言

### 7.2 错误信息统一
- **改造**: 全项目统一为英文 error code + 可选中文 message
- **错误码体系**:
  - `AUTH_001` ~ `AUTH_099`: 认证相关
  - `DEV_001` ~ `DEV_099`: 设备相关
  - `STA_001` ~ `STA_099`: 电站相关
  - `SYS_001` ~ `SYS_099`: 系统错误
- **验收**: 同一模块错误码连续，语言一致

### 7.3 删除死代码
- **清理清单**:
  - `inv_api_server/cmd/main.go`: 删除 `_ = dataPerm`
  - `inv_api_server/cmd/main.go`: 删除未使用的 `cancel`
  - `inv_api_server/cmd/main.go`: 删除注释掉的 admin 路由块（约 40 行）
  - `inv_device_server/internal/repository/device_repository.go`: 确认无遗漏
- **验收**: `go vet ./...` 无警告

### 7.4 goroutine 错误处理
- **文件**: `inv_api_server/internal/handler/auth_handler.go`
- **现状**: `go h.userService.UpdateLoginInfo(bgCtx(), ...)` 无错误处理
- **改造**: 使用带日志的 worker 函数:
  ```go
  go func() {
      ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
      defer cancel()
      if err := h.userService.UpdateLoginInfo(ctx, user.ID, c.ClientIP()); err != nil {
          logger.Warn("UpdateLoginInfo failed", zap.Error(err))
      }
  }()
  ```
- **验收**: 所有异步操作有错误日志

### 7.5 中间件 RequireRole 类型安全
- **文件**: `inv_api_server/internal/middleware/auth.go`
- **现状**: `userRole := role.(int)` 无安全断言
- **改造**: 使用 `role, ok := c.Get("role"); if !ok { ... }`

---

## 线程8：数据库治理 [负责人: H]

### 8.1 统一 migration 入口
- **文件**: `database/schema.sql`, `database/migration_*.sql`
- **改造**:
  1. 创建 `database/migrations/` 目录
  2. 按时间戳命名: `001_init_schema.up.sql`, `002_add_indexes.up.sql`
  3. 使用 `golang-migrate` 或 `goose` 管理版本
  4. Docker 启动时自动执行 migration
- **验收**: 每次部署只执行增量 migration，不重复创建表

### 8.2 缓存失效策略
- **文件**: `inv_api_server/internal/repository/repositories.go`
- **改造**:
  1. 设备状态更新时 `DEL realtime:latest:{sn}`
  2. 用户权限变更时 `DEL rbac:user:{uid}`
  3. 电站数据更新时 `DEL station:summary:{id}`
- **验收**: 数据库更新后缓存自动失效

### 8.3 查询索引审计
- **改造**: 为高频查询添加缺失索引:
  - `devices(user_id, station_id, deleted_at)` — 设备列表查询
  - `device_alarms(device_sn, created_at DESC)` — 告警查询
  - `stations(user_id, deleted_at)` — 电站列表查询
- **验收**: 慢查询日志无超过 100ms 的查询

### 8.4 TimescaleDB 压缩策略
- **文件**: `database/migration_timescaledb_tuning.sql` (已创建)
- **验收**: 7 天以上的 chunk 自动压缩

---

## 执行时间线

```
Week 1:
  线程1 [安全加固]     ████████ 完成
  线程2 [认证体系]     ████████ 完成
  线程3 [内部API]      ████████ 完成
  线程7 [代码规范]     ████████ 完成

Week 2:
  线程4 [设备服务]     ████████ 完成
  线程5 [WebSocket]    ████████ 完成
  线程6 [OTA服务]      ████████ 完成
  线程8 [数据库]       ████████ 完成

Week 3:
  集成测试 + 压力测试 + 灰度部署
```

---

## 依赖关系

```
线程2 ──依赖──> 线程1 (JWT 改造需要 CORS 先收敛)
线程3 ──依赖──> 线程2 (内部 API key 需要认证体系)
线程4 ──依赖──> 线程3 (设备服务移除 repo 需要内部 API 先稳定)
线程5 ──依赖──> 线程4 (Pub/Sub 需要设备服务先支持 publish)
线程6 ──无依赖── 可独立执行
线程7 ──无依赖── 可独立执行
线程8 ──无依赖── 可独立执行
```

**可同时启动的线程**: 1, 6, 7, 8（无相互依赖）

---

## 验收检查清单

每条线完成后执行:
- [ ] `go vet ./...` 无警告
- [ ] `go build ./...` 编译通过
- [ ] 已有测试 `go test ./...` 通过
- [ ] 新增代码有对应测试
- [ ] 配置文件已更新 `.env.example`
- [ ] Docker compose 启动正常
