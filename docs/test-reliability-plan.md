# 测试可靠性与商业级稳定计划（test-reliability-plan）

> 制定日期：2026-09-06　基线：develop @ 9d3d41a2d
> 目标：前后端 + 移动端达到商业级稳定可靠——质量门槛自动化、核心业务路径被真实测试覆盖、界面美观稳定有回归防线、所有功能稳定可用有端到端保障。

---

## 一、目标定义（可度量的"商业级"）

| 维度 | 商业级验收标准 |
|---|---|
| 合并门槛 | integration / e2e / 安全扫描 / go vet+test 为 required checks，红灯无法合并 |
| 后端覆盖 | business-api ≥50%（repository ≥40%），且为**真数据库执行**的测试 |
| 前端覆盖 | 主流程页面（dashboard/devices/alerts/ota/monitoring）每页有单测；覆盖率增量门槛 ≥60% |
| 界面稳定 | 主页面截图基线回归（Web 5 页 × 中英 2 语言）；Flutter 核心页 golden 测试（light/dark） |
| E2E 稳定 | storageState 解耦、retries ≥1、无 spec 顺序依赖、CI 连续 20 次全绿 |
| 部署可靠 | 全部容器有 healthcheck；CD 健康检查覆盖所有业务服务；有 staging 验证层 |
| 凭据安全 | 测试凭据不入 CI artifact；生产凭据仅存在于 deploy/.secrets/ |

## 二、现状基线（2026-09-06 实测）

| 子系统 | 测试规模 | 覆盖率 | 主要问题 |
|---|---|---|---|
| business-api | 71 文件 / 349 用例 | **13.2%**（repository 2.7%、service 8.0%） | 大量单测只断言 SQL 字符串不执行 SQL |
| device-communication | 24 文件 / 248 用例 | 37.8%（telemetry 83%） | repository 仅 11.8% |
| api-gateway | 13 文件 / 102 用例 | 70.3% | gzip/role_guard/slash 中间件无测试 |
| mqtt-kafka-bridge | 4 文件 / 36 用例 | 74.5% | 可接受 |
| 管理后台 Web | 33 文件 / 268 用例 + Playwright 11 用例 | 无覆盖率统计 | **13 个页面目录 0 单测**；无视觉回归 |
| Flutter App | 88 文件 / ~490 用例 | 旧数据 8.2% | onboarding 0 测试；无 golden；无 integration_test；11 处 skip |

**已有资产（保留并扩大）**：`deploy/docker-compose.test.yml` 真实栈（TimescaleDB + Redis + EMQX + Kafka + 3 业务容器，全 healthcheck 于基础设施）；`tests/integration/` 110 用例（跨租户/设备认领/组织生命周期/MQTT 流/DB 迁移）；CI 6 job 链路完整；CD SHA 不可变 tag + 失败回滚；Web 端 MSW 85 handler + test-utils 体系；Flutter pumpApp/bloc_test/mocktail 体系。

---

## 三、分阶段计划

### P0 止血与硬门槛（本周，约 2–3 人日）

| # | 事项 | 位置 | 验收标准 |
|---|---|---|---|
| 1 | 分支保护 required checks | GitHub Settings（仓库外） | main/develop 合并前 go-check、integration-test、e2e-test、security-scan、frontend-check、flutter-check 必须绿 |
| 2 | CI 加固 | `.github/workflows/ci.yml` | 每个 job 加 `timeout-minutes`（go 20 / frontend 15 / flutter 20 / integration 30 / e2e 30 / security 15）；顶层 `concurrency`（按 ref 分组，PR cancel-in-progress）；go-check 启用 Go module 缓存 |
| 3 | 消灭软门槛 | ci.yml frontend-check | `npm run test:run --if-present` → 硬性 `npm run test:run`；`api-docs-validation.yml` Go 1.22 → 1.26.6 对齐 |
| 4 | 凭据治理 | ci.yml + `inv-admin-frontend/e2e/` | e2e artifact 上传**剔除** `auth-storage.json`、`e2e-account.json`（只传截图/trace）；`global-setup.ts:104` 与根目录 `_*.mjs` 硬编码密码改为 env（本地默认值保留但集中一处） |
| 5 | healthcheck 补齐 | `deploy/docker-compose.test.yml`、`docker-compose.prod.yml` | inv-api-server / inv-device-server / api-gateway / inv-admin-frontend / nginx 全部加 healthcheck（HTTP /health 或 TCP 探针）；`cd.yml` 健康检查函数补 api-server 与 device-server |
| 6 | 仓库卫生 | 根目录 | 删除 `tests/integration/.gocache-final/`（数十万小文件）、`business-api/tmp_viper_test/`、`_viper_test/`、一次性 `_*.mjs`、遗留 `e2e_*.json`/`*_out.txt`；`.gitignore` 补规则防再犯 |

### P1 核心路径真测试（1–2 周，约 6–8 人日）

| # | 事项 | 位置 | 验收标准 |
|---|---|---|---|
| 7 | business-api 真 DB 测试扩容 | `business-api/tests/integration/`、`internal/repository/` | 优先设备控制 9 步校验链、认证/超管判定、OTA 下发回报、RBAC 矩阵、多租户过滤；repository 从"断言 SQL 字符串"迁到真执行（复用 `TEST_DB_*` test 栈 15432 + testcontainers `SetupTestDB`）；repository ≥40%、service ≥30% |
| 8 | 覆盖率渐进门槛 | ci.yml / vite.config.ts / flutter-check | 三端 CI 产出覆盖率并展示；对 PR **改动包**设 ≥60% 增量门槛（不动存量）；`test-coverage` Makefile 目标改为真实生成报告 |
| 9 | E2E 稳定化 | `inv-admin-frontend/e2e/`、`playwright.config.ts` | 改 Playwright 官方 storageState 模式（setup project + dependencies），消除对 `auth.spec` 落盘文件的顺序耦合；CI `retries: 2`；无 spec 间依赖 |
| 10 | golangci-lint 引入 | `.golangci.yml`（新建）、ci.yml、Makefile | 起步集：errcheck/govet/staticcheck/gosimple/ineffassign/unused/gofmt；存量用 `new-from-rev` 只管增量；CI go-check 加 lint step |
| 11 | schema.sql 重新 squash | `database/` | 基线与 096+ 迁移完全一致；新增"fresh schema == migrated schema"一致性集成测试；移除 `MIGRATION_AUTO_RUN` 兜底依赖 |
| 12 | 契约自动校验 | `contracts/openapi/`、`business-api/tests/api_contract_test.go` | kin-openapi 校验实现路由 vs `channel-platform-v1.yaml`；前端 `api-compatibility.test.ts` 对照同一 yaml；api_contract_test 的 PowerShell 依赖改纯 Go（消除 Skip） |

### P2 界面稳定防线（2–4 周，约 8–10 人日）

| # | 事项 | 位置 | 验收标准 |
|---|---|---|---|
| 13 | Web 视觉回归 | `inv-admin-frontend/e2e/` | dashboard/devices/alerts/ota/monitoring × 中英 2 语言 = 10 张 `toHaveScreenshot` 基线入库；**前置**：e2e 栈固定种子数据 + mock 时间，否则时序页面截图每天变化；更新流程 `--update-snapshots` + PR 审 diff |
| 14 | Flutter golden 测试 | `inv_app/test/` | login/dashboard/device detail/OTA 页 light+dark 基线；`flutter test --update-goldens` 更新流程；**同时移除吞 RenderFlex overflow 的测试包装**（edit_profile_avatar_test 等），让布局问题重新暴露并修复 |
| 15 | Web 主流程页单测 | `inv-admin-frontend/src/pages/` | dashboard（聚合/SSE hook）、devices（过滤/分页）、ota（表单/推送）、monitoring 每页 ≥1 冒烟渲染 + 关键交互；高频组件 StatisticCard/StatusBadge/RegionPicker/UploadAvatar 补测 |
| 16 | Flutter integration_test | `inv_app/integration_test/`（新建） | 登录流程、设备列表、OTA 下载与取消（FirmwareDownloadService 已支持 cancel）；模拟器可跑；真机项（WiFi 配网/BLE/本地 OTA）保留真机验证 |
| 17 | 平台通道 mock 补齐 | `inv_app/test/` | BLE/WiFi/scanner 相关用 `setMockMethodCallHandler` 首批覆盖；清理 11 处 skip（station_bloc Connectivity×3、profile_setup/mock 基础设施×5、Dio.delete×1 等），重构 bloc state mock 基础设施 |

### P3 持续治理（1–2 月）

| # | 事项 | 说明 |
|---|---|---|
| 18 | staging 环境 | 复用 test compose 拓扑部署独立 staging；cd.yml 改为 staging → E2E 对 staging → 人工确认 → 生产 |
| 19 | flaky 治理 | 16 处 `time.Sleep` → `testify.Eventually` 条件等待；条件 Skip 在 CI 一律 fail（推广 `TEST_REQUIRE_SERVICES=true` 语义到 member_lifecycle 等前置） |
| 20 | 版本化发布 | CHANGELOG.md + git tag（semver）；release-android.yml 接入 |
| 21 | 真机验证矩阵 | WiFi 配网 / BLE / 本地 OTA 真设备验证（backlog 最后剩余项，需真设备到位） |
| 22 | 月度审计 | 覆盖率 review、skip 清零、flaky 记录与修复 |

---

## 四、度量仪表盘（阶段验收）

| 指标 | 现状 | P1 后 | P3 后 |
|---|---|---|---|
| business-api 覆盖率 | 13.2% | ≥25%（repository ≥40%） | ≥50% |
| Web 主流程页单测 | 0/13 页 | dashboard/devices/ota 有 | 全覆盖 |
| 视觉回归基线 | 0 | 0 | 5 页 × 2 语言 |
| Flutter golden | 0 | 0 | 核心页 light/dark |
| E2E | retries 0 + 顺序耦合 | storageState + retry 2 | 并行 + 多浏览器 |
| 覆盖率门槛 | 无 | 增量 ≥60% | 存量爬坡 |
| healthcheck | 4/9 服务 | 9/9（test+prod） | 9/9 |
| 测试凭据入 artifact | 是 | 否 | 否 |

## 五、风险与依赖

- **种子数据固定**是视觉回归的前置条件——时序页面（dashboard/monitoring）截图会随数据漂移，P2-13 必须先做数据固化，否则基线维护成本不可接受。
- **存储/时间成本**：Flutter integration CI 需 macOS runner（贵），可先本地跑、CI 后补；多浏览器矩阵同理。
- **存量 lint 债**：golangci-lint 全量开必爆，坚持 `new-from-rev` 增量策略。
- **schema squash** 涉及 `database/` 敏感区：按 AGENTS.md 要求迁移文件只增不改，squash 产物走新增目录并配回滚说明。
- 分支保护（P0-1）是 GitHub 仓库设置，代码侧无法自证，需要仓库管理员在 Settings → Branches 落地。

---

## 六、执行进度（随批次更新）

### 批次 1（77319e020）：P0 全部 + P1-8/9/10
详见提交说明。前端 298 用例全绿；CI timeout/concurrency/golangci-lint/三端覆盖率 artifact/healthcheck/E2E storageState 解耦落地；修复存量红色用例 App.test.tsx。

### 批次 2（da422c5fc）：P1-7 首批
新增 10 个真库集成测试（设备控制 9 步链 ×6、OTA 生命周期 ×2、超管会话上下文 ×2）；修复 3 个早已失效的存量集成测试（authorization / registration_identity——CI integration-test job 实际为红的根因）。repository+service 集成覆盖率 7.8% → 12.0%。

### 批次 3（本批）：P1-11 核心 + P1-12 校准
- **新增 `TestActiveMigrationsReplayOnSquashBaseline`**（tests/integration）：把"squash 基线(0..95) + 活跃迁移(096..110) 启动回放"的架构契约变成显式测试——基线不得提前登记 096+、回放必须全部成功、尾部签名对象（config_domain/app_versions/device_key_hash/member_transfer_requests）逐项断言。不再依赖容器启动副作用来暴露基线/迁移冲突。
- **schema.sql 死代码清理**：移除 device_model_commands 的第二处重复定义（IF NOT EXISTS 永不生效，误导维护者），留注释指向正式定义与能力列来源。基线加载由新增契约测试守护。
- **P1-12 校准**：渠道契约套件（含 PowerShell 检查器 3 个测试）本地验证全绿；CI 的 ubuntu-latest runner 预装 pwsh，实际不存在 Skip 问题。Go 重写检查器（508 行）性价比低，**降级为 P3 备选**；kin-openapi 全量路由校验保留在 P1-12 待办中。
- 本地全量验证：root integration 模块、business-api 集成+单测、契约套件全部通过。

### 批次 4（本批）：P1-7 增量 + P2 视觉防线上线
- **P1-7 续（2f2f5585d）**：设备核心生命周期真库测试（Create 幂等/Bind 时区继承/权限三分支/可见集并集/Unbind 失权/软删复活）；`setupCommandTestDB` 补齐 096+ 尾部回放——此前业务集成测试全部跑在缺列的纯基线库上，现与生产库形态收敛。覆盖率 12.0% → 12.7%。
- **P2 视觉防线上线**：
  - `visual` Playwright 项目（1440×900 视口）+ `e2e/visual.spec.ts` 六页面基线（仪表盘/设备列表/告警中心/OTA/电站管理/电站监控），`maxDiffPixelRatio 0.02` 吸收 antd 表格 ±1px 列宽抖动，dashboard 对 canvas 图表与日期选择器做定位器级 mask（豁免日期驱动画布，卡片框架仍受保护）。
  - **e2e 种子固化**：global-setup 开头 TRUNCATE 业务表（此前测试库累积 14+ 台历史设备导致列表高度漂移）、设备 SN 固定为 E2E-SN-001/002、账号昵称固定 e2e-admin。
  - 基线按平台分文件（`*-win32.png` 入库走 LFS）；**CI 只跑 setup+chromium 功能项目**（截图含平台字体渲染，Linux 基线种子待专门任务），本地连续 3 次运行全绿验证。
  - 顺带修复：storageState 路径错位（setup 写仓库根、项目读 frontend 子目录，会炸 CI）；"未登录重定向"用例在项目级登录态下需显式空会话。

### 批次 5（本批）：安全甄别 + 真实 bug 修复 + 剩余待办清理
- **安全发现甄结**：mimosa 标记的 ota_handler 各"注入入口"逐一查证均为参数化查询（污点误报）；唯一危险模式是 `UpdateUpgradePackage` 以 map key 拼列名——当前调用方 key 硬编码不可利用，已在 repo 边界加列白名单并配注入形态 key 的回归测试。
- **真实生产 bug 修复（迁移 111）**：`device_cmd_logs.result` 是 VARCHAR(20) 短结果码列，`UpdateCommandLogStatus` 却写入长文本消息，超长 22001 被 `_ =` 吞掉——离线排队/失败路径的审计状态静默停在 pending。result 放宽为 TEXT（只写不读，零兼容风险）。
- **backfill 工具规则对齐**：`legalOrganizationEdge` 还是 082 之前的层级规则，与数据库约束失配（会把 distributor→customer 放进库、把合法 installer 链误隔离），已对齐 082 触发器。
- **新增 SendPreparedCommand 真库回归 ×3**（httptest 假设备服务器）：双审计表状态机 + 期望控制态落库 + X-Internal-Key/V2 协议体断言 + 排队/失败路径。
- **e2e_evidence 去跟踪**：84 个易变证据文件（截图/日志/临时脚本）解除跟踪消除运行噪音，保留被 test-report-full.md 引用的 5 个 k6 结果。
- **Linux 基线种子工作流**：`visual-baseline.yml`（手动触发）在 ubuntu runner 生成 `*-linux.png` artifact，入库后 CI 可启用视觉比对。
- 覆盖率（repository+service+migration，含集成）18.5%。

### 架构事实记录（防再误判）
- schema.sql = 迁移 0..95 的 squash 基线 + schema_migrations 登记（77 为历史空号）；`database/migrations/` 活跃目录 = 096..110 真正回放尾部 + 001/018/074..095 已登记死重文件；001..095 历史文件在 `database/migrations.archive/`。
- 权限码双格式：命令 `permission_code` 用下划线（`devices_control`，按最后一个下划线拆 resource/action），RBAC 授权码用冒号（`devices:control`）。
