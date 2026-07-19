# 逆变器多级渠道云平台实施计划

> **For Codex:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task.

**Goal:** 将当前平台升级为原厂→代理商→分销商→终端客户四级组织、多角色授权、统一数据范围和完整资产生命周期的平台，并建立可自动阻断发布的商用验收门禁。

**Architecture:** 采用双轨渐进迁移。manufacturer 根组织是租户边界，`organization_closure` 管理组织树；membership、role assignment、permission-scope grant 和对象 grant 正交建模；设备库存、所有权、服务和分享分离。新授权模型在 shadow 阶段作为权威写入，旧字段仅作兼容投影，最终切入 enforce。所有高风险业务使用数据库事务、CAS、幂等响应、不可变审计和事务 outbox。

**Tech Stack:** PostgreSQL/TimescaleDB、Go 1.26、Gin、pgx、Redis、React 18 + TypeScript + Vitest、Flutter/Dart、Docker Compose、GitHub Actions、PowerShell/Bash。

**Approved design:** `docs/superpowers/specs/2026-07-19-commercial-channel-platform-design.md`

---

## 执行纪律与会话拓扑

- 每个任务严格执行 RED → GREEN → REFACTOR；没有先观察到失败测试，不写对应生产代码。
- 一个实现代理一次只处理一个任务。完成后依次进行规格符合性审查、代码质量审查；修复后再进入下一任务。
- 并行代理只承担只读调研、规格/计划/代码审查或互不重叠的验证，避免共享工作树互相覆盖。
- 用户已有改动 `inv-admin-frontend/src/pages/stations/index.tsx` 全程排除在暂存和代理编辑之外；电站新能力优先落到独立组件和 `StationDetailPage.tsx`。
- 每个任务只提交该任务文件。提交前运行 `git diff --cached --check` 并确认未带入用户改动。
- 外部 HIL、生产证书、生产凭据和 production environment 审批不能伪造；实现仓库门禁和证据模板后仍须由真实环境补证。

会话分块：

1. Foundation：任务 1–6，数据库、契约、授权内核、上下文令牌。
2. Organization：任务 7–8，组织/成员/邀请/用户生命周期。
3. Asset：任务 9–13，认领、分享、解绑、转移、电站和统一数据范围。
4. Clients：任务 14–17，管理端和 Flutter。
5. Commercial gate：任务 18–21，E2E、审计运维、发布门禁、全量验收。

## Chunk 1：契约、数据模型与授权基础

### Task 1：建立跨服务契约唯一事实源

**Files:**

- Create: `contracts/openapi/channel-platform-v1.yaml`
- Create: `contracts/events/authorization-cache-invalidated.v1.schema.json`
- Create: `contracts/events/asset-transfer.v1.schema.json`
- Create: `contracts/events/audit-event.v1.schema.json`
- Create: `tools/check_channel_contracts.ps1`
- Modify: `inv_api_server/tests/api_contract_test.go`
- Test: `inv_api_server/tests/api_contract_test.go`

**Steps:**

- [ ] 在 `api_contract_test.go` 增加失败测试，要求上述 OpenAPI/事件文件存在，并至少包含组织上下文、组织、邀请、认领、grant、设备转移和电站转移路径。
- [ ] 运行 `go test -count=1 -run TestChannelPlatformContract ./tests`（目录 `inv_api_server`），确认因契约缺失失败。
- [ ] 编写 OpenAPI V1、稳定错误码、`AuthorizationContextV2`、`allowed_actions` 以及三个事件 schema；明确 `additionalProperties` 和版本字段。
- [ ] 编写 PowerShell 检查器，提供 `legacy|shadow|enforce` 模式：旧路径在 OpenAPI 标记 deprecated，shadow 阶段报告但不阻断尚未迁移的消费者，Task 21 的 enforce 模式禁止未声明路径和危险的不兼容 diff。
- [ ] 增加运行时契约测试骨架，后续 E2E 用 OpenAPI 验证 Gateway 请求/响应，并让缓存失效、资产转移、审计事件的生产者和消费者分别校验 JSON Schema。
- [ ] 再运行定向测试及 `powershell -ExecutionPolicy Bypass -File tools/check_channel_contracts.ps1 -Mode shadow`，确认通过。
- [ ] 提交：`test: 建立渠道平台跨服务契约门禁`。

### Task 2：创建组织、成员、角色和配额迁移

**Files:**

- Create: `database/migrations/059_create_channel_authorization.up.sql`
- Create: `database/migrations/059_create_channel_authorization.down.sql`
- Create: `database/migrations/060_extend_audit_outbox.up.sql`
- Create: `database/migrations/060_extend_audit_outbox.down.sql`
- Create: `database/tests/059_channel_authorization_test.sql`
- Modify: `database/schema.sql`
- Modify: `tests/integration/db_migration_test.go`

**Steps:**

- [ ] 先在迁移集成测试中断言 `organizations`、`organization_closure`、`organization_memberships`、`membership_role_assignments`、`role_permission_grants`、`resource_grants`、`organization_quotas`、`organization_quota_usage`、`invitations` 和隔离表存在且关键约束生效。
- [ ] 先运行 `docker compose -f deploy/docker-compose.test.yml up -d --build --wait --wait-timeout 300`，在 `tests/integration` 设置 `$env:TEST_REQUIRE_SERVICES='true'` 后运行 `go test -v -tags=integration -count=1 -run '^TestFreshDatabaseBaselineAndMigrations$' ./...`，确认新断言真实失败而非 Skip。
- [ ] 编写 059 up/down；加入 root tenant 复合约束、closure depth=0、有效 membership/邀请唯一索引、HMAC 摘要字段、版本和 `ON DELETE RESTRICT`。编写 060 审计 TEXT resource ID、幂等响应和事务 outbox，供后续组织/用户事务使用。
- [ ] 在 SQL 测试中覆盖非法跨租户父子、重复有效 membership、重复 pending invitation 和 closure 自关联缺失。
- [ ] 更新 `schema.sql`，运行数据库迁移测试两次验证幂等，并验证 down 仅用于 enforce 前结构回滚。
- [ ] 提交：`feat(db): 建立多级组织授权模型`。

### Task 3：实现历史数据预检与组织授权回填

**Files:**

- Create: `inv_api_server/internal/migration/channel_backfill.go`
- Create: `inv_api_server/internal/migration/channel_backfill_test.go`
- Create: `inv_api_server/cmd/channel_migrate/main.go`
- Modify: `inv_api_server/internal/migration/migrator.go`

**Steps:**

- [ ] 先写表驱动测试：角色数字冲突不能自动映射；父级循环、孤儿、重复标识、owner 冲突进入隔离；checkpoint 重跑无重复结果。本任务只回填 Task 2 已存在的组织/成员/角色/配额，资产与 tenant ownership 在 Task 9 续跑。
- [ ] 运行 `go test -count=1 ./internal/migration`，确认因 backfill API 不存在失败。
- [ ] 实现 `preflight/backfill-organizations/shadow-report` 子命令，显式读取映射配置；批处理使用 checkpoint 和 `FOR UPDATE SKIP LOCKED`。为后续 `backfill-assets/validate-constraints` 预留显式子命令，但不在本任务写不存在的资产表。
- [ ] 保证 API 启动迁移器只执行结构迁移，不执行大数据回填；回填结果写审计摘要和 shadow diff。
- [ ] 运行定向测试、`go test -race -count=1 ./internal/migration` 和 `go vet ./internal/migration ./cmd/channel_migrate`。
- [ ] 提交：`feat(migration): 增加渠道模型预检与回填`。

### Task 4：实现组织授权模型与数据库集合查询

**Files:**

- Create: `inv_api_server/internal/model/organization.go`
- Create: `inv_api_server/internal/model/authorization.go`
- Create: `inv_api_server/internal/repository/organization_repository.go`
- Create: `inv_api_server/internal/repository/authorization_repository.go`
- Create: `inv_api_server/internal/repository/authorization_repository_test.go`
- Create: `inv_api_server/internal/repository/outbox_repository.go`
- Create: `inv_api_server/internal/service/authorization_service.go`
- Create: `inv_api_server/internal/service/authorization_service_test.go`
- Modify: `inv_api_server/internal/service/data_permission.go`
- Modify: `inv_api_server/internal/service/data_permission_test.go`

**Steps:**

- [ ] 先写授权矩阵失败测试：permission、grant scope、对象关系任一缺失均 deny；多角色不能拼接高权限和大范围；同级/跨租户不可见。
- [ ] 写仓储测试，要求组织/成员列表条件通过 closure/grant 的 `JOIN/EXISTS/CTE` 表达，不展开 ID/SN 参数列表；设备 binding resolver 接口先默认拒绝，具体 JOIN 在资产表完成后的 Task 10/13 实现。
- [ ] 运行 `go test -count=1 ./internal/repository ./internal/service`，确认测试因新类型/服务缺失失败。
- [ ] 实现 `AuthorizationService.Authorize/BuildScope`、deny reason、对象延迟解析接口、组织数据库过滤器及事务内 outbox enqueue；未知 permission/scope 或尚未实现的资产 resolver 默认拒绝。
- [ ] 将旧 `DataPermission` 改为兼容适配器，在 shadow 模式比较结果但永不取 UNION。
- [ ] 运行定向测试、race 和 vet；提交：`feat(authz): 实现统一组织数据范围授权`。

### Task 5：强化 JWT、会话撤销与可信身份头

**Files:**

- Modify: `inv_api_server/pkg/jwt/jwt.go`
- Modify: `inv_api_server/pkg/jwt/jwt_test.go`
- Create: `inv_api_server/internal/middleware/authorization_context.go`
- Create: `inv_api_server/internal/middleware/authorization_context_test.go`
- Modify: `inv_api_server/internal/handler/auth_handler.go`
- Modify: `api-gateway/internal/middleware/jwt.go`
- Modify: `api-gateway/internal/middleware/jwt_test.go`
- Modify: `api-gateway/internal/middleware/rbac.go`
- Modify: `api-gateway/internal/middleware/rbac_test.go`

**Steps:**

- [ ] 先写失败测试：伪造 `X-User-* / X-Organization-ID` 被删除；缺 user/org/token_type/iss/aud/jti/version 返回 401；refresh token 不能访问业务路由；未知算法拒绝。
- [ ] 写父组织停用、membership version、session version 变化后旧 token 立即失效的测试；break-glass audience 不能走普通中间件。
- [ ] 分别运行 API 与网关定向测试，观察失败。
- [ ] 实现严格 access token claims、`POST /auth/context` token 交换、无组织端点白名单和可信内部头注入。
- [ ] 缓存/数据库异常时高风险动作 fail closed；组织子树版本提升触发撤权事件。
- [ ] 运行两个 Go 模块的 middleware/JWT race 测试与 vet；提交：`fix(auth): 绑定活动组织并强化会话撤权`。

### Task 6：路由接入与 legacy/enforce 功能开关

**Files:**

- Modify: `inv_api_server/cmd/main.go`
- Modify: `api-gateway/internal/routes/routes.go`
- Modify: `api-gateway/internal/routes/routes_test.go`
- Modify: `api-gateway/internal/middleware/role_guard.go`
- Create: `inv_api_server/internal/config/channel_authorization.go`
- Modify: `deploy/configs/api-server.yaml`
- Modify: `deploy/configs/gateway.yaml`

**Steps:**

- [ ] 先写路由测试，只要求 `/auth/context` 和基础授权中间件存在，并证明 role 2/3 不再被 `RequireRole(1)` 提前拒绝；`/authorization/me`、组织/邀请/资产路由由后续对应业务 Task 注册。
- [ ] 写配置测试，非法模式、生产 legacy 模式和 enforce 无迁移标记均启动失败。
- [ ] 运行路由/配置测试观察失败。
- [ ] 接入 `legacy|shadow|enforce|cleanup` 开关；移除普通业务的数字角色全局绕过，保留兼容映射但未知默认拒绝。
- [ ] 运行 API/网关路由测试与 `tools/check_channel_contracts.ps1 -Mode shadow`；全路由严格检查留到 Task 21。
- [ ] 提交：`feat(authz): 接入渠道授权模式与路由`。

## Chunk 2：组织、成员与名下用户

### Task 7：实现组织、配额、移动和邀请事务服务

**Files:**

- Create: `inv_api_server/internal/service/organization_service.go`
- Create: `inv_api_server/internal/service/organization_service_test.go`
- Create: `inv_api_server/internal/service/invitation_service.go`
- Create: `inv_api_server/internal/service/invitation_service_test.go`
- Create: `inv_api_server/internal/handler/organization_handler.go`
- Create: `inv_api_server/internal/handler/organization_handler_test.go`
- Create: `inv_api_server/internal/handler/authorization_handler.go`
- Modify: `inv_api_server/cmd/main.go`

**Steps:**

- [ ] 写失败测试覆盖合法四级父子、非法跳级、环、跨根移动、配额耗尽、并发移动和邀请重放。
- [ ] 写故障注入测试，closure/quota/audit/outbox 任一步失败时组织移动或邀请接受整体回滚。
- [ ] 实现事务级 root advisory lock、CAS version、quota usage 条件更新和一次性邀请 HMAC。
- [ ] 先增加 `/authorization/me` 路由 RED 测试，再实现 `/organizations`、children、members、invitations、eligible-targets 与 `/authorization/me`。
- [ ] 运行 service/handler race 测试和契约检查。
- [ ] 提交：`feat(org): 实现组织成员邀请与安全移动`。

### Task 8：实现名下用户创建、禁用、角色变更和转移

**Files:**

- Modify: `inv_api_server/internal/handler/admin_handler.go`
- Create: `inv_api_server/internal/handler/admin_handler_test.go`
- Modify: `inv_api_server/internal/repository/repositories.go`
- Modify: `inv_api_server/internal/service/services.go`
- Modify: `inv_api_server/cmd/main.go`
- Modify: `inv_api_server/internal/middleware/permission.go`

**Steps:**

- [ ] 先写 POST/DELETE/transfer 路由和服务测试，覆盖直属/隔级管理、同级和跨租户拒绝、禁止自提权、最后 org_admin 保护、并发版本冲突。
- [ ] 写公开注册三分支测试：有效邀请、受限 customer、自身 `pending_claim`；无组织用户不能访问业务 API。
- [ ] 运行定向测试，确认现有缺失 POST/DELETE 路由导致失败。
- [ ] 以 membership/role assignment 为事实源实现创建、邀请、禁用、恢复、转移和软删除；同事务写兼容 `parent_id/role` 投影。
- [ ] 角色降级、禁用、转移后提升版本、撤销 session 并写 outbox/audit。
- [ ] 运行 handler/service/race/契约测试；提交：`feat(user): 完成下级用户生命周期管理`。

## Chunk 3：设备、电站与业务范围

### Task 9：创建资产生命周期、租户归属与延迟校验迁移

**Files:**

- Create: `database/migrations/061_create_asset_lifecycle.up.sql`
- Create: `database/migrations/061_create_asset_lifecycle.down.sql`
- Create: `database/migrations/062_add_tenant_ownership_columns.up.sql`
- Create: `database/migrations/062_add_tenant_ownership_columns.down.sql`
- Create: `database/migrations/063_prepare_channel_constraints.up.sql`
- Create: `database/migrations/063_prepare_channel_constraints.down.sql`
- Create: `database/channel-migrate/validate_channel_constraints.sql`
- Create: `inv_api_server/internal/migration/channel_asset_backfill.go`
- Create: `inv_api_server/internal/migration/channel_asset_backfill_test.go`
- Modify: `database/schema.sql`
- Modify: `tests/integration/db_migration_test.go`

**Steps:**

- [ ] 先扩展迁移测试，要求 inventory、claim credential、device binding、asset grant、transfer、idempotency response、outbox、审计 TEXT resource ID 和 station/device tenant 列存在。
- [ ] 增加约束失败断言：双 owner、双 claim credential、双 pending transfer、跨租户 station/device、级联删除和重复幂等键。
- [ ] 运行 fresh DB 测试观察失败。
- [ ] 实现 061–063；自动启动迁移只增加资产结构、tenant ownership 列和 `NOT VALID` 约束，绝不在旧数据回填前自动 validate。
- [ ] 实现可恢复 `backfill-assets`，补 station/device root tenant、organization、owner/binding；只有隔离业务数据为 0 和 shadow diff 为 0 时，显式 `channel_migrate validate-constraints` 才执行 `database/channel-migrate/validate_channel_constraints.sql`。
- [ ] 运行 fresh DB、历史快照、重复迁移、回填重启和显式 validate SQL 约束测试。
- [ ] 提交：`feat(db): 建立设备资产生命周期与事务事件模型`。

### Task 10：实现库存导入和安全设备认领

**Files:**

- Create: `inv_api_server/internal/model/asset_lifecycle.go`
- Create: `inv_api_server/internal/repository/asset_lifecycle_repository.go`
- Create: `inv_api_server/internal/service/asset_lifecycle_service.go`
- Create: `inv_api_server/internal/service/asset_lifecycle_service_test.go`
- Create: `inv_api_server/internal/handler/asset_lifecycle_handler.go`
- Create: `inv_api_server/internal/handler/asset_lifecycle_handler_test.go`
- Modify: `inv_api_server/internal/handler/device_handler.go`
- Modify: `tests/integration/api_e2e_test.go`

**Steps:**

- [ ] 先写认领 RED 测试：未知 SN、错误/过期/重放 code、错误库存、越权电站失败；相同幂等键重放原响应；两个并发认领仅一个成功。
- [ ] 将旧“随机 SN 自动创建成功”集成用例改为预置库存和 claim credential，先确认旧实现不满足。
- [ ] 实现受信内部库存导入，终端 bind 路径彻底移除 `EnsureDevice`；claim code 仅比较 key_id + HMAC digest。
- [ ] 按规定锁顺序原子写 owner、inventory、station、legacy projection、audit、outbox、idempotency response。
- [ ] 运行 service race、handler、integration claim 测试。
- [ ] 提交：`feat(device): 实现库存校验与并发安全认领`。

### Task 11：实现对象 grant、分享、解绑和设备转移

**Files:**

- Modify: `inv_api_server/internal/repository/asset_lifecycle_repository.go`
- Modify: `inv_api_server/internal/service/asset_lifecycle_service.go`
- Modify: `inv_api_server/internal/handler/asset_lifecycle_handler.go`
- Modify: `inv_api_server/internal/repository/repositories.go`
- Modify: `inv_api_server/internal/handler/device_handler.go`
- Create: `inv_api_server/internal/service/asset_transfer_service_test.go`
- Create: `tests/integration/commercial_channel_concurrency_test.go`

**Steps:**

- [ ] 写 grant 权限测试：owner/admin 可 share，viewer 不能再分享/解绑/转移/OTA；view/control 过期和撤销即时失效。
- [ ] 写解绑/转移事务测试：申请状态、eligible target、CAS、旧 grant 撤销、唯一 owner、审计/outbox；任一步故障整体回滚。
- [ ] 先运行测试，并复现现有“申请已批准但设备更新失败仍成功”的缺陷。
- [ ] 用新事务服务替换旧 `ApproveUnbind` 分步写入；实现 grants、revoke、transfer request/approve/reject/cancel。
- [ ] 验证旧 owner 在列表、详情和所有高风险动作立即失权。
- [ ] 运行 race、integration、契约测试；提交：`feat(device): 完成分享解绑与所有权转移闭环`。

### Task 12：实现电站归属、转移和站内设备一致性

**Files:**

- Modify: `inv_api_server/internal/model/models.go`
- Modify: `inv_api_server/internal/repository/repositories.go`
- Modify: `inv_api_server/internal/service/services.go`
- Modify: `inv_api_server/internal/handler/station_handler.go`
- Create: `inv_api_server/internal/service/station_transfer_service_test.go`
- Modify: `inv_api_server/internal/handler/device_handler.go`

**Steps:**

- [ ] 写失败测试：设备不能加入越权/跨租户电站；电站转移必须带全部站内设备或按策略拒绝；中途失败整体回滚。
- [ ] 写转移后 owner、operation grant、告警订阅、统计归属和旧缓存同时切换的断言。
- [ ] 运行 station/device 定向测试观察失败。
- [ ] 实现 station organization/owner 读写、eligible targets、事务转移和版本冲突处理。
- [ ] 返回对象级 `allowed_actions`；避免修改用户已有的 `pages/stations/index.tsx`。
- [ ] 运行 service/handler race 测试；提交：`feat(station): 实现电站归属与安全转移`。

### Task 13：统一设备、电站、告警、统计、控制、OTA、工单、通知和导出范围

**Files:**

- Modify: `inv_api_server/internal/handler/device_handler.go`
- Modify: `inv_api_server/internal/handler/station_handler.go`
- Modify: `inv_api_server/internal/handler/alarm_handler.go`
- Modify: `inv_api_server/internal/handler/dashboard_handler.go`
- Modify: `inv_api_server/internal/handler/ota_handler.go`
- Modify: `inv_api_server/internal/handler/work_order_handler.go`
- Modify: `inv_api_server/internal/handler/notification_handler.go`
- Modify: `inv_api_server/internal/repository/ota_repository.go`
- Create: `inv_api_server/internal/service/channel_scope_consistency_test.go`

**Steps:**

- [ ] 先写 `CC-SCOPE-001` 表驱动测试，对每个资源执行列表、详情、count/聚合和动作，要求相同 scope 且跨租户无侧漏。
- [ ] 单独覆盖控制、批量控制、OTA 和导出 fail closed；分页 total 与空/403 行为不泄漏对象存在性。
- [ ] 运行定向测试，记录现有各 handler 分散授权导致的失败。
- [ ] 统一接入 `AuthorizationService` 的 query filter/object checker；移除 role/owner 的重复分支。
- [ ] 导出改为有配额、过期下载和字段白名单的异步任务；危险批量操作限制批次并记录审批。
- [ ] 运行全 API service/handler race 测试；提交：`refactor(authz): 统一全业务数据可见范围`。

## Chunk 4：管理端与 Flutter 工作流

### Task 14：管理端统一授权上下文和权限路由

**Files:**

- Modify: `inv-admin-frontend/src/types/index.ts`
- Modify: `inv-admin-frontend/src/stores/authStore.ts`
- Modify: `inv-admin-frontend/src/stores/authStore.test.ts`
- Create: `inv-admin-frontend/src/services/authorizationApi.ts`
- Create: `inv-admin-frontend/src/services/authorizationApi.test.ts`
- Modify: `inv-admin-frontend/src/services/api.ts`
- Modify: `inv-admin-frontend/src/pages/login/index.tsx`
- Modify: `inv-admin-frontend/src/pages/login/LoginPage.test.tsx`
- Modify: `inv-admin-frontend/src/utils/queryKeys.ts`
- Create: `inv-admin-frontend/src/pages/auth/SelectOrganizationPage.tsx`
- Create: `inv-admin-frontend/src/pages/auth/SelectOrganizationPage.test.tsx`
- Modify: `inv-admin-frontend/src/components/ProtectedRoute.tsx`
- Modify: `inv-admin-frontend/src/components/ProtectedRoute.test.tsx`
- Modify: `inv-admin-frontend/src/App.tsx`
- Modify: `inv-admin-frontend/src/layouts/MainLayout.tsx`

**Steps:**

- [ ] 先写测试：未知 legacy role 不得成为管理员；路由要求 permission；切换组织取消请求、清空组织缓存并交换 access token；refresh 后重取上下文。
- [ ] 运行 `npm run test:run -- src/stores/authStore.test.ts src/components/ProtectedRoute.test.tsx src/services/authorizationApi.test.ts`，确认失败。
- [ ] 实现 `AuthorizationContextV2`、内存 access token、Cookie refresh、组织选择器和集中 legacy mapping。
- [ ] React Query key 全部包含 active organization/authorization version；菜单和路由使用 permission，动作使用 `allowed_actions`。
- [ ] 运行定向测试、`npm run build:check`。
- [ ] 提交：`feat(web): 统一活动组织与权限路由`。

### Task 15：管理端组织、成员、邀请和下级用户页面

**Files:**

- Create: `inv-admin-frontend/src/services/organizationApi.ts`
- Create: `inv-admin-frontend/src/services/invitationApi.ts`
- Create: `inv-admin-frontend/src/pages/organizations/index.tsx`
- Create: `inv-admin-frontend/src/pages/organizations/OrganizationsPage.test.tsx`
- Create: `inv-admin-frontend/src/pages/invitations/AcceptInvitationPage.tsx`
- Create: `inv-admin-frontend/src/pages/invitations/AcceptInvitationPage.test.tsx`
- Modify: `inv-admin-frontend/src/services/userApi.ts`
- Modify: `inv-admin-frontend/src/services/userApi.test.ts`
- Modify: `inv-admin-frontend/src/pages/users/index.tsx`
- Modify: `inv-admin-frontend/src/pages/users/UsersPage.test.tsx`
- Modify: `inv-admin-frontend/src/locales/users.ts`
- Modify: `inv-admin-frontend/src/locales/layout.ts`

**Steps:**

- [ ] 写页面/API RED 测试，覆盖组织树、成员职责、邀请状态、邀请深链接受/过期/撤销/重新登录、直属/隔级用户、禁用/恢复/转移、eligible targets、403/409/410/422。
- [ ] 证明 mock 不再提供后端不存在的 POST/DELETE 成功路径。
- [ ] 实现组织页、邀请流和 membership 驱动的用户页；未知状态默认禁止操作。
- [ ] 高风险动作使用 expected_version/idempotency key 并以服务端结果为准。
- [ ] 运行定向与全量 Vitest、build check。
- [ ] 提交：`feat(web): 实现组织成员和下级用户管理`。

### Task 16：管理端设备认领、分享、解绑、转移和电站转移

**Files:**

- Modify: `inv-admin-frontend/src/services/deviceApi.ts`
- Modify: `inv-admin-frontend/src/services/deviceApi.test.ts`
- Modify: `inv-admin-frontend/src/pages/devices/index.tsx`
- Modify: `inv-admin-frontend/src/pages/device-detail/index.tsx`
- Create: `inv-admin-frontend/src/pages/device-detail/AssetGrantPanel.tsx`
- Create: `inv-admin-frontend/src/pages/device-detail/AssetGrantPanel.test.tsx`
- Create: `inv-admin-frontend/src/pages/device-detail/AssetTransferPanel.tsx`
- Create: `inv-admin-frontend/src/pages/device-detail/AssetTransferPanel.test.tsx`
- Modify: `inv-admin-frontend/src/pages/stations/StationDetailPage.tsx`
- Create: `inv-admin-frontend/src/pages/stations/StationTransferPanel.tsx`
- Create: `inv-admin-frontend/src/pages/stations/StationTransferPanel.test.tsx`

**Steps:**

- [ ] 写 API/组件失败测试，覆盖 claim code、idempotency、grant 状态、审批状态、冲突重载和 `allowed_actions` 隐藏。
- [ ] 运行定向测试观察旧接口缺失/错误状态失败。
- [ ] 实现设备 lifecycle 工作区与独立电站转移组件，不编辑 `pages/stations/index.tsx`。
- [ ] 目标只能来自 eligible targets；所有高风险提交等待服务端完成。
- [ ] 运行相关 Vitest、全量 Vitest 和 build check。
- [ ] 提交：`feat(web): 完成设备与电站资产工作流`。

### Task 17：Flutter 统一授权、认领、分享和本地安全

**Files:**

- Modify: `inv_app/lib/features/auth/domain/entities/user.dart`
- Create: `inv_app/lib/core/entities/authorization_context.dart`
- Create: `inv_app/lib/core/services/authorization_service.dart`
- Modify: `inv_app/lib/core/services/role_service.dart`
- Modify: `inv_app/lib/core/services/storage_service.dart`
- Modify: `inv_app/lib/core/services/service_locator.dart`
- Modify: `inv_app/lib/core/router/guards/auth_guard.dart`
- Modify: `inv_app/lib/core/router/app_router.dart`
- Modify: `inv_app/lib/features/auth/data/datasources/auth_remote_data_source.dart`
- Modify: `inv_app/lib/features/auth/data/repositories/auth_repository_impl.dart`
- Modify: `inv_app/lib/features/auth/presentation/bloc/auth_bloc.dart`
- Modify: `inv_app/lib/features/auth/presentation/bloc/auth_event.dart`
- Modify: `inv_app/lib/features/auth/presentation/bloc/auth_state.dart`
- Create: `inv_app/lib/features/auth/presentation/pages/select_organization_page.dart`
- Create: `inv_app/lib/features/auth/presentation/pages/accept_invitation_page.dart`
- Modify: `inv_app/lib/features/device/domain/repositories/device_repository.dart`
- Modify: `inv_app/lib/features/device/data/datasources/device_remote_data_source.dart`
- Modify: `inv_app/lib/features/device/data/repositories/device_repository_impl.dart`
- Modify: `inv_app/lib/features/device/presentation/bloc/device_bloc.dart`
- Modify: `inv_app/lib/features/device/presentation/bloc/device_event.dart`
- Modify: `inv_app/lib/features/device/presentation/bloc/device_state.dart`
- Modify: `inv_app/lib/features/device/presentation/pages/add_device_page.dart`
- Modify: `inv_app/lib/features/profile/presentation/pages/device_share_page.dart`
- Modify: `inv_app/lib/features/station/data/datasources/station_remote_data_source.dart`
- Modify: `inv_app/lib/features/station/data/repositories/station_repository_impl.dart`
- Modify: `inv_app/lib/features/station/domain/repositories/station_repository.dart`
- Modify: `inv_app/lib/features/station/presentation/bloc/station_bloc.dart`
- Modify: `inv_app/lib/features/station/presentation/bloc/station_event.dart`
- Modify: `inv_app/lib/features/station/presentation/bloc/station_state.dart`
- Create: `inv_app/lib/features/station/presentation/pages/station_transfer_page.dart`
- Modify: `inv_app/lib/core/services/local_communication_service.dart`
- Modify: `inv_app/lib/core/services/local_firmware_service.dart`
- Create: `inv_app/test/core/services/authorization_service_test.dart`
- Create: `inv_app/test/core/router/auth_guard_test.dart`
- Create: `inv_app/test/features/device/device_claim_test.dart`
- Create: `inv_app/test/features/device/device_grant_transfer_test.dart`
- Create: `inv_app/test/features/station/station_transfer_test.dart`
- Create: `inv_app/test/core/services/local_capability_test.dart`

**Steps:**

- [ ] 先写测试：缺失/未知 role 默认无权限；路由按 permission/allowed_actions；扫码 PIN 进入 claim API；分享不再发送 MQTT control。
- [ ] 写本地控制/OTA 测试，缺现场证明或短期 capability 必须阻断；OTA 包缺签名/型号/防回滚信息必须拒绝。
- [ ] 运行 `flutter test test/core/services/authorization_service_test.dart test/core/router/auth_guard_test.dart`，确认活动组织/路由 RED；再运行 device/station/capability 五个定向测试，确认工作流 RED。
- [ ] 实现安全存储、活动组织切换与缓存清理、claim/grant/transfer 数据流；删除 `cmdType=share` 路径。
- [ ] 对当前仓库无法实现的固件端验签，客户端 fail closed，并将固件验证绑定 HIL 门禁。
- [ ] 运行 `dart format --output=none --set-exit-if-changed lib test`、`flutter analyze`、`flutter test`；提交：`feat(app): 统一渠道授权与资产安全流程`。

## Chunk 5：商用 E2E、审计运维与发布门禁

### Task 18：建立双租户四级业务 E2E 与并发测试

**Files:**

- Create: `tests/fixtures/commercial-channel/two_tenant_four_level.yaml`
- Create: `tests/integration/commercial_channel_fixture.go`
- Create: `tests/integration/commercial_channel_e2e_test.go`
- Create: `tests/integration/commercial_channel_revocation_test.go`
- Modify: `tests/integration/commercial_channel_concurrency_test.go`
- Create: `tests/integration/commercial_channel_contract_test.go`
- Create: `tests/integration/commercial_channel_migration_test.go`

**Steps:**

- [ ] 先写稳定夹具加载测试，建立 A/B 两棵树、同级旁支、服务商、库存、owner、有效/过期 grant；夹具只负责 bootstrap，邀请、认领、禁用、转移、导出等业务动作必须经过生产等价 Gateway。
- [ ] 实现 `CC-AUTH/E2E/SESSION/ASSET/SCOPE/MIG` 测试；列表、详情、count、聚合和动作都断言 200/401/403/409 及零侧漏。`CC-AUDIT` 在 Task 19 的 dispatcher 完成后加入。
- [ ] 使用 OpenAPI 中间验证器检查 Gateway 实际请求/响应；同时验证直连 API 缺可信内部身份或对象授权时不能绕过 Gateway。
- [ ] 对缓存失效、资产转移事件运行 producer/consumer JSON Schema 测试，不只比较路径字符串。
- [ ] 加入并发 claim、移动、邀请、解绑/转移与故障注入回滚。
- [ ] 使用 `go test -json -race -v -tags=integration -count=1 -run '^TestCommercialChannel' ./...` 生成结果，并由 gate 验证 manifest 中本阶段所有 `CC-*` 均出现、通过且 0 Skip；逐项修复生产代码，不放宽断言。
- [ ] 再运行所有 integration 测试，确认旧随机 SN 行为已被安全模型替换。
- [ ] 提交：`test: 覆盖双租户四级渠道业务闭环`。

### Task 19：实现审计、outbox、指标与规模基线

**Files:**

- Modify: `inv_api_server/internal/repository/outbox_repository.go`
- Create: `inv_api_server/internal/service/outbox_dispatcher.go`
- Create: `inv_api_server/internal/service/outbox_dispatcher_test.go`
- Modify: `inv_api_server/internal/repository/repositories.go`
- Modify: `inv_api_server/internal/handler/system_health.go`
- Modify: `deploy/prometheus/alerts.yml`
- Modify: `deploy/prometheus/prometheus.yml`
- Create: `tests/performance/channel_scope_load_test.js`
- Create: `tests/performance/channel_scope_thresholds.json`
- Create: `tests/performance/reference-runner.json`
- Create: `tests/integration/commercial_channel_audit_test.go`
- Create: `docs/runbooks/COMMERCIAL_CHANNEL_AUTHORIZATION.md`

**Steps:**

- [ ] 写 `CC-AUDIT-001` 失败测试：应用角色不能修改/删除审计；成功/失败/403 均有 UTC、schema version、before/after；查询受租户 scope 限制且敏感字段脱敏；outbox 重放幂等；高风险审计失败回滚；外送篡改/失败产生告警。
- [ ] 实现 dispatcher lease、重试、dead-letter 指标和 authorization cache invalidation 消费。
- [ ] 暴露授权拒绝、跨租户拒绝、失效延迟、转移积压、审计失败、备份年龄指标并配置告警。
- [ ] 建立 10,000 组织/100,000 设备生成器与机器可读参考 runner；k6 固定 60 秒预热、300 秒测量、32 VU、每类操作至少 10,000 样本，验证授权对象检查 P95<50ms、分页/count P95<500ms。
- [ ] 运行 `k6 run --summary-export artifacts/channel-scope-performance.json tests/performance/channel_scope_load_test.js`；gate 校验 runner manifest、样本量和阈值并上传原始结果。
- [ ] 用 `go test -json -race -v -tags=integration -count=1 -run '^TestCommercialChannelAudit' ./...` 生成并校验 `CC-AUDIT-001` 零 Skip；运行 dispatcher race、基准和告警配置测试。
- [ ] 提交：`feat(ops): 完善审计事件与渠道平台可观测性`。

### Task 20：实现灾备、隐私、HIL 和发布证据门禁

**Files:**

- Create: `deploy/scripts/restore_verify.sh`
- Create: `deploy/docker-compose.dr-test.yml`
- Create: `tests/dr/restore_verify_test.ps1`
- Create: `tools/commercial_channel_gate.ps1`
- Create: `tools/verify_release_evidence.ps1`
- Create: `tools/security_supply_chain_gate.ps1`
- Create: `contracts/evidence/commercial-hil-evidence.v1.schema.json`
- Create: `contracts/evidence/commercial-dr-evidence.v1.schema.json`
- Create: `contracts/evidence/commercial-security-evidence.v1.schema.json`
- Create: `docs/cs6k2-system-support/commercial-channel-test-manifest.json`
- Create: `docs/runbooks/POSTGRES_PITR_RESTORE.md`
- Create: `docs/privacy/DATA_CLASSIFICATION_RETENTION_ERASURE.md`
- Create: `docs/templates/COMMERCIAL_CHANNEL_HIL_RECORD.md`
- Create: `docs/templates/COMMERCIAL_RELEASE_EVIDENCE.md`
- Create: `.github/workflows/commercial-channel-gate.yml`
- Create: `tests/workflows/commercial_release_policy_test.ps1`
- Create: `tests/release/evidence_verifier_test.ps1`
- Modify: `.github/workflows/cd.yml`
- Modify: `deploy/docker-compose.prod.yml`

**Steps:**

- [ ] 先写证据验证器负向测试：缺 HIL/DR/安全证据、SHA/digest/schema 不匹配、过期、摘要不符、错误 OIDC issuer/repository/ref、P0/P1 非零、同人发布批准时均失败。
- [ ] 定义三类机器可读 evidence schema。manifest 只引用带保留策略/只追加能力的制品 URI、SHA-256 与 Sigstore/OIDC 或企业设备证书签名；纯手填 Markdown 永远不能作为唯一证据。
- [ ] 验证器校验证书链/OIDC issuer、repository、ref、SHA、镜像 digest、schema、签发时间和签发主体；GitHub `production` environment reviewer 由平台强制，仓库 JSON 不能模拟批准。
- [ ] 写工作流策略测试，断言 production job 使用 `environment: production`、`needs: commercial-release-gate`，输入只取 gate 输出 digest，禁止 `latest`/生产重建；`workflow_dispatch` 只接受 digest 且仍走完整 release gate。
- [ ] 实现 WAL/PITR 配置和隔离拓扑。DR 测试实际创建备份、写入恢复点前后哨兵、执行 `restore_verify.sh`，验证目标时间、RPO<=15min、RTO<=120min、租户/owner/审计约束及恢复期间控制冻结，并保存原始日志、runner 身份和时间戳。
- [ ] HIL evidence 必须含测试 ID、原始日志/抓包/测量文件摘要、仪器与校准编号、设备/固件/协议版本、开始结束时间、操作者和独立复核者签名；离线实验室使用受信企业设备证书签名，CI 使用受限 OIDC attestation。
- [ ] 编写隐私留存、异步导出、擦除/法律保留 runbook；实现 secret、依赖漏洞、SBOM、许可证、容器和 IaC 扫描聚合脚本。
- [ ] 运行 `tests/release/evidence_verifier_test.ps1`、`tests/workflows/commercial_release_policy_test.ps1` 和隔离 DR 演练；没有真实外部 HIL/生产审批时 release profile 必须保持失败，不能填充假通过记录。
- [ ] 提交：`ci: 建立商用渠道平台发布证据门禁`。

### Task 21：全量验证、双重评审和交付

**Files:**

- Modify only if failures require scoped fixes.
- Create: `docs/COMMERCIAL_CHANNEL_IMPLEMENTATION_REPORT.md`
- Update: `docs/COMMERCIAL_RELEASE_CHECKLIST.md`
- Update: `docs/cs6k2-system-support/09-需求追踪矩阵.md`

**Steps:**

- [ ] 运行 `git diff --check`，确认用户的 `stations/index.tsx` 改动未被覆盖或暂存。
- [ ] 运行 `git diff --cached --quiet -- inv-admin-frontend/src/pages/stations/index.tsx` 和 `git status --short -- inv-admin-frontend/src/pages/stations/index.tsx`，明确证明该用户文件未进入任何任务提交。
- [ ] API：`go test -race -count=1 ./...`、`go vet ./...`（目录 `inv_api_server`）。
- [ ] Gateway：`go test -race -count=1 ./...`、`go vet ./...`（目录 `api-gateway`）。
- [ ] 其他 Go 模块分别运行 `go test -race -count=1 ./...`。
- [ ] Web：`npm run test:run`、`npm run build:check`。
- [ ] Flutter：格式检查、`flutter analyze`、`flutter test`。
- [ ] 数据库/集成：启动 test compose，运行完整 `go test -json -race -v -tags=integration -count=1 ./...`；gate 逐项校验 manifest 的 CC ID 零 Skip。
- [ ] DR：启动 `deploy/docker-compose.dr-test.yml`，实际执行备份、PITR 和 `tests/dr/restore_verify_test.ps1`，保存原始证据；HIL 仍必须由真实实验室签名证据满足。
- [ ] 安全供应链：运行 secret、依赖漏洞、SBOM、许可证、容器和 IaC 扫描，Critical/High 按发布策略阻断。
- [ ] 派发独立规格审查和代码质量/安全审查；修复全部 Critical/Important 后重复受影响测试及全量门禁。
- [ ] 报告清晰区分“仓库实现完成”和“外部 HIL/生产证据未完成”；未补外部证据前不得写“可直接商用发布”。
- [ ] 提交：`docs: 完成多级渠道平台实施验收报告`。

## 最终验收命令

```powershell
# API
Push-Location inv_api_server
go test -race -count=1 ./...
go vet ./...
Pop-Location

# Gateway
Push-Location api-gateway
go test -race -count=1 ./...
go vet ./...
Pop-Location

# Device server and MQTT bridge
Push-Location inv_device_server
go test -race -count=1 ./...
go vet ./...
Pop-Location
Push-Location mqtt-kafka-bridge
go test -race -count=1 ./...
go vet ./...
Pop-Location

# Web
Push-Location inv-admin-frontend
npm run test:run
npm run build:check
Pop-Location

# Flutter
Push-Location inv_app
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
Pop-Location

# Database and complete integration suite
docker compose -f deploy/docker-compose.test.yml up -d --build --wait --wait-timeout 300
New-Item -ItemType Directory -Force artifacts | Out-Null
Push-Location tests/integration
$env:TEST_REQUIRE_SERVICES = 'true'
$integrationOutput = go test -json -race -v -tags=integration -count=1 ./...
$integrationExitCode = $LASTEXITCODE
$integrationOutput | Tee-Object ../../artifacts/commercial-channel-integration.jsonl
Pop-Location
if ($integrationExitCode -ne 0) { exit $integrationExitCode }

# Runtime/static contracts, performance and repository-side release gate
powershell -ExecutionPolicy Bypass -File tools/check_channel_contracts.ps1 -Mode enforce
k6 run --summary-export artifacts/channel-scope-performance.json tests/performance/channel_scope_load_test.js
powershell -ExecutionPolicy Bypass -File tools/commercial_channel_gate.ps1 -Profile repository -OutputDirectory artifacts/commercial-channel
powershell -ExecutionPolicy Bypass -File tools/security_supply_chain_gate.ps1 -OutputDirectory artifacts/security-supply-chain

# Real isolated backup/PITR exercise (repository DR gate)
docker compose -f deploy/docker-compose.dr-test.yml up -d --build --wait --wait-timeout 300
powershell -ExecutionPolicy Bypass -File tests/dr/restore_verify_test.ps1 -OutputDirectory artifacts/commercial-release/dr

# Workflow and evidence policy negative/positive fixtures
powershell -ExecutionPolicy Bypass -File tests/workflows/commercial_release_policy_test.ps1
powershell -ExecutionPolicy Bypass -File tests/release/evidence_verifier_test.ps1
```

生产 `release` profile 只有在真实 HIL、DR、安全和审批证据齐全时才允许通过：

```powershell
powershell -ExecutionPolicy Bypass -File tools/verify_release_evidence.ps1 -Manifest "artifacts/commercial-release/$env:GITHUB_SHA/manifest.json" -RequireTrustedAttestations
powershell -ExecutionPolicy Bypass -File tools/commercial_channel_gate.ps1 -Profile release -OutputDirectory artifacts/commercial-channel
```
