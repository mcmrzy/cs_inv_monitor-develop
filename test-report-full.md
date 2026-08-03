# cs_inv_monitor 全方面测试报告

- 执行日期：2026-08-02 ~ 2026-08-03
- 测试环境：隔离测试环境 `deploy/docker-compose.test.yml`（项目名 inv-monitor-test），不触碰本地开发与生产数据
- 测试账号：E2E/压测账号（动态注册）、`load2026@test.com`（压测）
- 结论：**6 阶段全部执行完毕，功能/集成/压测/安全各层均达到预期；发现并修复 8 类缺陷（含 2 个 P0、1 个 P1）；剩余 3 项 P2 低风险项与 1 项外部工作流风险已在文末记录**

---

## 1. 测试范围与环境

| 项 | 值 |
|---|---|
| 服务 | inv-api-server(8080→网关18888)、inv-device-server、api-gateway、mqtt-kafka-bridge、PostgreSQL 16+TimescaleDB、Redis 7、EMQX、Kafka |
| 工具链 | Docker 29.5.2、Go 1.26.4（容器 golang:1.26.5-alpine）、Node v24.16.0、k6 v2.1.0、Flutter SDK |
| 测试资产 | 99 个 Go 测试文件、9 个集成测试文件、vitest 26 文件/232 用例、Flutter 约 40 文件、安全套件、k6 脚本、mqtt_simulator.py |

## 2. 阶段 0：环境准备（通过）

- 7 容器全部健康（postgres/redis/emqx/kafka/api-server/device-server/gateway）
- 网关 18888 /health、15432 PG、16379 Redis、11883 EMQX 均就绪
- E2E/压测账号注册完成（Redis 预写验证码 + email-register）

## 3. 阶段 1：单元测试层（通过）

### Go 单元测试（race + coverage）与 vet

| 模块 | 结果 | 关键包覆盖率 |
|---|---|---|
| business-api | 全绿 | pkg/apperr 100%、pkg/timezone 100%、pkg/jwt 75.2%、pkg/sn 87.6%、pkg/response 63.6% |
| device-communication | 全绿 | pkg/timezone 100%、pkg/sn 86.7%、telemetry 81.2%、service 45.4%、pkg/kafka 40.6% |
| api-gateway | 全绿 | routes 95.8%、proxy 85.3%、middleware 68.1% |
| mqtt-kafka-bridge | 全绿 | 32.8% |

- `go vet` 4 模块无告警

### API 契约测试（通过）

- `go test -v -count=1 ./tests/...` 静态路由注册与前端调用兼容性全绿（含 064 契约 SQL 修复）

### 前端（通过）

- `tsc --noEmit` 0 错误；vitest **26 文件 / 232 用例全绿**（修复 vitest 误收集 e2e/ 后重跑）；`vite build` 成功（仅 chunk>500kB 提示，非错误）；项目无 lint 配置（npm run lint 不存在，已在阶段记录）

### Flutter（通过）

- `flutter analyze --no-fatal-infos` 通过；`flutter test --coverage` **271 通过 / 4 跳过**，覆盖率 6.7%

## 4. 阶段 2：集成测试层（通过）

- `cd tests/integration && go test -v -tags=integration` **第 9 轮全绿：ok 52.454s**
- 覆盖：认证生命周期、邮件登录、设备绑定/解绑、未授权访问、跨租户数据隔离、限流、组织/邀请/成员生命周期、设备认领、MQTT 遥测全链路、15 个数据库迁移基线
- 期间修复 4 类测试/环境问题：invitation role_id、手机号唯一冲突、064 契约 role_code、cross_tenant 数组解析（详见缺陷清单）

## 5. 阶段 3：前端 E2E 与业务功能验证（通过）

### Playwright E2E（11/11 通过，28.3s）

登录成功/失败提示、登出、仪表盘、设备列表→详情、告警中心、OTA 页、电站管理、电站监控、未登录重定向 /login、语言切换（中/英）

- 截图证据：`e2e_evidence/e2e-login-success.png`、`e2e-page-dashboard.png`、`e2e-page-devices.png`、`e2e-page-device-detail.png`、`e2e-page-alerts.png`、`e2e-page-ota.png`、`e2e-page-stations.png`、`e2e-page-monitoring.png`、`e2e-redirect-login.png`、`e2e-lang-zh.png`、`e2e-lang-en.png`、`e2e-logout.png`、`e2e-login-failed.png`

### MQTT 业务链路（通过）

- mqtt_simulator.py 52 台设备遥测：设备状态在线、遥测写入测试库、告警 5 条落库、Redis 在线状态确认
- 数据链路：MQTT→EMQX→relay→Kafka→device-server→Redis+DB 全链路验证

## 6. 阶段 4：压力测试（通过）

### Go Benchmark（22.7s 全 PASS）

| 基准 | 结果 |
|---|---|
| JWT 生成 | 6980 ns/op（7867 B/op，83 allocs/op） |
| JWT 解析 | 6784 ns/op |
| SN 生成 / 校验 / 解析 | 314 / 207 / 129 ns/op |
| 时区加载 | 12.3 ns/op（0 alloc） |
| SQL 注入检测 / XSS / 路径遍历 | 67µs / 18.8µs / 9.5µs |

### k6 API 压测（修复限流后）

| 场景 | 请求数 | 延迟 | 错误 |
|---|---|---|---|
| 20 VU 阶梯（修复后 rerun） | 2002 | avg 3.33ms，p95 11.5ms | 0 |
| 100 VU | 19667（72.3 req/s） | p95 16.0ms | 429 全部为网关预期限流防护 |

- 修复前 20VU p95 曾达 174.99ms（P1 限流击穿，见缺陷清单）

### MQTT 负载（mqtt-load）

- 200 clients / 60s：11800 条消息，0 错误，p95 71.6ms

### 万级设备模拟（mqtt_simulator 10000 台 × 双模式）

第二轮补测（2026-08-03）：先注册 10000 台 MASS-TEST 设备（devices 表），再跑双模式各 10000 台。

| 模式 | 结果 |
|---|---|
| Kafka 模式（39092 listener） | 10000/10000 发送成功（51.21s，195.26 msg/s）；device_telemetry_3min 10000 行（topic=heartbeat）、device_cell_samples 10000 行、last_online_at 10000/10000 台、0 ingest 错误 |
| MQTT 模式（relay 异步化修复后） | 10000/10000 全转发 Kafka（relay relayed=10000/errors=0）；Kafka consumer lag 0；last_online_at 10000 台刷新；realtime:latest 70000 字段 key（10000×7）+ device:state 10000+；0 ingest 错误 |

说明：第一轮 5000 台（25.39s/196.89 msg/s）曾受两处测试环境配置影响——① Kafka 模式默认 19092 端口（PLAINTEXT listener advertised 为容器主机名 kafka:9092，宿主不可达）导致消息 0 落库，改用 PLAINTEXT_HOST 39092 端口后链路恢复；② 压测后清理时 MASS-TEST 设备被删，需先重新注册设备才能验证 last_online_at 全量更新。

### 压测期间资源监控（docker stats 采样）

postgres CPU 1.54%/216.9MiB、kafka 0.87%/358.4MiB、redis 1.29%/42.8MiB、emqx 0.32%/69.3MiB、device-server 0.27%/20.4MiB、api-server 0%/17.9MiB、gateway 0%/10.8MiB —— 全部资源占用极低

### 压测后清理（完成）

- 删除调试文件 3 个（_check_kafka_mass.py、_test_kafka_producer.py、_rec.json）
- Redis：MASS-TEST/RELAY-CHECK/WILL-TEST 三类 key 全部清零（约 6.9 万 key）
- DB：devices/telemetry/cell_samples/ingest_errors/alarms 压测数据全部为 0

## 7. 阶段 5：安全测试（通过）

### 安全套件（全绿，ok 0.375s）

- CORS 白名单（允许/阻断/前缀攻击/空列表默认拒绝/Preflight）
- 认证暴力破解防护（登录失败限次）、缺失/伪造 Bearer Token 401、错误响应不泄露堆栈、Cookie HttpOnly、超大 RequestBody 限制
- 输入验证：SQL 注入 9 类 payload、XSS、路径遍历、SN 格式、密码强度、整数溢出、超大 JSON body
- JWT：弱密钥检测、篡改拒绝、过期拒绝、None 算法攻击拒绝、角色值不可篡改、空 token 拒绝

### 依赖漏洞扫描（govulncheck，4 模块）

| 漏洞 | 模块 | 状态 |
|---|---|---|
| GO-2026-6061 grpc v1.81.1（xDS RBAC/HTTP2） | business-api | **已修复**：升级 grpc v1.82.1，go build 通过，重扫消失 |
| GO-2026-5856 crypto/tls ECH 隐私泄露（标准库 1.26.4） | 4 模块 | 容器 golang:1.26.5-alpine 已覆盖；本地工具链需升级 1.26.5（P2） |
| GO-2026-4970 os 符号链接 root escape（标准库 1.26.4） | 4 模块 | 同上 |

### 前端依赖审计（npm audit --omit=dev）

| 漏洞 | 严重级 | 状态 |
|---|---|---|
| path-to-regexp 8.0.0-8.3.0 ReDoS ×2（经 pro-layout） | high | **已修复**：package.json overrides 强制 8.4.2，tsc/vitest/build 回归全绿 |
| react-router ≤7.17.0（open redirect / deserializeErrors） | moderate ×2 | v6 无修复版（修复仅 v7，breaking）；SPA 场景实际不可利用（deserializeErrors 仅 SSR、open redirect 需用户输入反斜杠），记录 P2 建议升级 v7 |

### 敏感信息检查（通过）

- 仓库无 RSA/EC/OpenSSH 私钥、无 keystore/.pem/.key 被 git 跟踪
- git 仅跟踪 `.env.example` / `.env.prod.example`（示例）；`.env`、`deploy/.env`、`deploy/.secrets/` 均被 .gitignore 忽略
- Go 源码无硬编码凭据（仅 _test.go 测试已知用例）；生产配置（deploy/configs/gateway.yaml）使用 `${ENV}` 占位符
- 开发配置文件（config.docker.yaml）为本地开发默认值，注释标明可被环境变量覆盖

### 限流与 RBAC 越权验证（通过，网关 18888 实测）

| 场景 | 结果 |
|---|---|
| 普通用户 load2026 访问 /api/v1/admin/users | **403**（权限不足） |
| 无 token 访问 /api/v1/admin/users | **401** |
| 普通用户访问 /api/v1/auth/profile、/api/v1/devices | **200**（正常） |

## 8. 缺陷清单

| 级别 | 缺陷 | 状态 |
|---|---|---|
| P0 | repositories.go 引用已删列（role/parent_id）导致集成测试编译失败 | 已修复并重跑全绿 |
| P0 | admin_handler.go SystemMonitor 接口与前端联动断裂 | 已修复并验证 |
| P1 | api-server 组级限流 10/20 req 击穿正常流量（k6 p95 175ms） | 已修复（auth 接口单独限流），重建容器后 k6 p95 11.5ms、集成回归全绿 |
| P1 | mqtt2kafka_relay 同步发送在高流量下阻塞导致消息丢失（1830/5000） | 已修复（异步 send + flush），5000/5000 全转发 |
| P1 | Kafka 模式消息 0 落库（advertised listener 不可达 + consumer group offset 失效） | 已定位为测试环境配置问题并解决（39092 listener + reset-offsets），5000 台完整落库 |
| P2 | 集成测试 4 项（invitation role_id、手机号唯一、064 契约 role_code、cross_tenant 解析） | 已修复，第 9 轮全绿 |
| P2 | react-router 2 个 moderate 漏洞（v6 无修复版） | 记录，建议后续升级 react-router v7（breaking） |
| P2 | 本地 Go 工具链 1.26.4（标准库 2 漏洞） | 记录，建议升级 1.26.5；容器已用 1.26.5 无影响 |
| P2 | 前端 build chunk >500kB 警告 | 记录，建议按需代码分割 |

## 9. 风险与后续建议

1. **外部工作流风险**：报告生成时，工作区存在"权限体系迁移（成员身份=组织类型模型）"未提交改动（92 文件），`business-api` 处于编译中间态（如 model.User 移除 Role 字段后 testutil 未同步、admin_handler 多余 import 等）。该迁移不属于本次测试计划，**建议迁移完成后重跑阶段 1/2 回归**（本报告各阶段结果基于迁移前的已验证快照）。
2. 本地 Go 工具链升级至 1.26.5。
3. react-router 升级 v7 前评估 SPA 路由 API 兼容性。
4. 前端构建产物按路由拆分（manualChunks 已生效，剩余 vendor-antd 大块可进一步拆）。

## 10. 证据文件索引（e2e_evidence/）

- 集成测试：integration-test-9-final.txt（ok 52.454s）
- E2E：playwright-results.json、e2e-final.txt、*.png 截图 12 张
- k6：k6-api-lite-rerun-summary.json（p95 11.5ms）、k6-api-100vu-after-fix.json
- Flutter：flutter-final.txt（+271 ~4）、flutter-analyze.txt
- MQTT 链路：mqtt-e2e-result.json、mqtt-e2e-db-check.json、docker-stats-samples.txt
