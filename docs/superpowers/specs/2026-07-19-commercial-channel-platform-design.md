# 逆变器多级渠道云平台商用改造设计

## 1. 目标

在不破坏现有遥测、告警、控制、OTA 和客户端主流程的前提下，将当前以 `users.role + users.parent_id + devices.user_id` 为核心的权限雏形，升级为可验证的多租户组织、成员、数据范围和资产生命周期平台。

本设计覆盖：

- 原厂 → 代理商 → 分销商 → 终端客户四级组织链。
- 安装商、售后、运营、只读、财务、API 服务账号等非渠道层级角色。
- 名下组织和用户的创建、邀请、启停、转移和权限回收。
- 电站和设备的库存、认领、绑定、分享、解绑、转移、退役及审计。
- 列表、详情、统计、告警、控制、OTA、导出使用同一数据范围。
- 网关、API、管理端和 Flutter 的统一角色与权限契约。
- 双租户四级业务 E2E、并发、事务、安全、灾备和发布门禁。

真实逆变器 HIL、生产证书、应用商店账号和生产凭据不在本地生成；仓库必须提供强制门禁、脚本和验收记录模板，未取得外部证据时不得标记为商用发布通过。

## 2. 方案比较

### 方案 A：继续强化旧字段

保留数字角色代表渠道层级，通过递归 `parent_id` 查询和更多条件分支补齐功能。

- 优点：改动小，短期接口兼容最好。
- 缺点：组织层级、员工职责和资产范围继续混在一个数字里；多组织成员、服务商、临时授权、跨组织转移难以正确表达。
- 结论：不采用。适合作为临时补丁，不适合作为商用权限基础。

### 方案 B：一次性替换全部身份和资产接口

删除旧角色和归属字段，全部客户端同时切换新模型。

- 优点：最终模型最干净。
- 缺点：现有 Go 服务、管理端、Flutter、集成测试和运维脚本同时失效，回归面过大，难以分阶段验证。
- 结论：不采用。

### 方案 C：双轨渐进迁移（采用）

新增组织、成员、作用域和资产关系模型，以其作为新的授权事实源；保留旧字段作为兼容投影，在每个业务切片完成后逐步迁移读写路径。

- 优点：每个阶段都可独立测试和回滚；支持现有客户端过渡；能建立正式租户边界。
- 代价：迁移期存在新旧模型同步代码，需要明确唯一事实源和停用时间。

## 3. 核心原则

### 3.1 三个正交维度

授权结果必须同时满足：

```text
操作权限 permission
  ∩ 组织数据范围 organization scope
  ∩ 对象关系 object relationship
```

- 组织类型回答“主体处于哪一层”。
- 成员角色回答“主体能做什么”。
- 数据范围回答“主体能对哪些对象做”。

禁止继续使用 `currentRole < targetRole` 作为完整授权判断。

### 3.2 默认拒绝

- 无组织、无成员关系、无明确权限或无对象关系时拒绝。
- 网关缺少关键身份声明时返回 401，不放行到后端。
- API 查询必须显式携带授权上下文，不能依赖前端隐藏菜单。

### 3.3 原厂根组织是租户边界，用户不是租户

每个 manufacturer 根组织定义一个独立租户，`root_tenant_id` 指向该根组织；其下 agent、distributor、customer 和 service_partner 是租户内业务组织。所有业务数据必须同时携带 `root_tenant_id` 和直接负责的 `organization_id`。

一个用户可以属于多个组织，甚至受邀加入不同根租户，但每个请求必须选择明确的活动组织且 token 只能绑定一个根租户；组织停用后，其成员访问立即失效。

### 3.4 库存、所有权、服务关系、分享关系分离

- 渠道库存：当前由哪个组织保管或可销售。
- 终端所有权：当前客户组织/用户拥有哪个设备和电站。
- 服务关系：哪个安装商或售后组织被分配服务。
- 分享关系：谁在什么期限内拥有查看或控制权。

这些关系不得再压缩进 `devices.user_id` 和 `installer_id` 两列。

## 4. 组织与成员模型

### 4.1 organizations

建议字段：

- `id`
- `root_tenant_id`
- `parent_id`
- `org_type`: `manufacturer | agent | distributor | customer | service_partner`
- `name/code/status`
- `depth`（冗余校验字段）；层级事实统一存储在 `organization_closure`
- `created_by/created_at/updated_at/deleted_at/version`

合法主链：

```text
manufacturer → agent → distributor → customer
```

`service_partner` 可挂在原厂、代理商或分销商下，但不占用客户层级。

数据库和服务层都要校验：

- 同一 `root_tenant_id` 内才允许普通重挂。
- 禁止自引用和挂到子孙节点。
- 禁止非法组织类型跳转，跨租户转移必须走平台级审批流程。
- 停用组织时授权立即失效，但历史业务数据不物理删除。

`organization_closure(root_tenant_id, ancestor_id, descendant_id, depth)` 固定作为组织树实现，包含每个组织到自身的 depth=0 行。禁止在实现阶段切换为字符串 path；移动组织时必须事务重写闭包行，并以 `(root_tenant_id, ancestor_id, depth, descendant_id)` 和 `(root_tenant_id, descendant_id, ancestor_id)` 索引支持后代/祖先查询。

### 4.2 organization_memberships

membership 只表达成员身份，不直接拼接单一角色或范围。建议字段：

- `organization_id/user_id`
- `status`
- `invited_by/accepted_at/expires_at`
- `created_at/updated_at/version`

`membership_role_assignments` 允许一个 membership 拥有多个功能角色；`role_permission_grants` 将 `permission_code` 与 `data_scope` 绑定到同一条角色授予，避免从一个角色取得高权限、从另一个角色拼接大范围。`resource_grants` 表达显式对象授权及过期时间。

内置功能角色：

- `org_admin`
- `channel_manager`
- `operator`
- `installer`
- `after_sales`
- `viewer`
- `finance`
- `api_client`

角色可以按组织类型配置允许的权限集合；不得把安装商、运营和终端客户继续写成同一层级枚举。

有效 membership 在同一 organization/user 上唯一。角色合并按“每个 permission 分别计算其 grant scope”执行，绝不能先合并全部 permissions 再取最大 scope。

### 4.3 数据范围

首期固定支持：

- `self`
- `organization`
- `organization_and_descendants`
- `assigned_resources`
- `explicit_resources`

区域只能作为业务过滤条件，不能作为唯一授权边界。

### 4.4 组织配额

`organization_quotas` 至少支持有效成员、直属子组织、后代组织、库存/已认领设备、电站、待处理邀请、并发导出任务和 API 速率。配额可由父组织下发更严格覆盖值，但子组织不能自行放宽根租户上限。

创建成员/组织、分配库存、接受邀请和批量转移时，在同一数据库事务内锁定对应 quota usage 行并条件递增；失败或回滚不得消耗配额。现有 `users.user_limit/device_limit` 只作为迁移输入，不能继续作为事实源。

## 5. 授权服务

在 API 服务中建立统一 `AuthorizationService`，输入：

- actor user ID
- active organization ID
- resource
- action
- object identity（可选）

输出：

- allow/deny
- scope organization IDs
- scope user IDs
- scope station IDs/device SNs（按需延迟解析）
- deny reason

列表接口使用作用域过滤器，详情/控制接口使用对象检查器。集合授权必须通过 closure、binding、grant 的 `JOIN/EXISTS/CTE` 下推到数据库，禁止把全部可见设备 SN 展开成 SQL 参数。设备、电站、告警、统计、控制、OTA、工单、通知和导出不得自行实现不同版本的归属判断。

数据库层使用 `root_tenant_id/organization_id` 索引和外键；高风险表可增加 PostgreSQL RLS 作为纵深防御，但应用授权仍是主要接口。

## 6. 用户与组织业务流程

### 6.1 创建与邀请

1. 操作者必须是目标父组织的 `org_admin/channel_manager`。
2. 校验允许创建的子组织类型和配额。
3. 创建组织或生成成员邀请。
4. 邀请使用一次性、过期、可撤销令牌；接受后创建 membership。
5. 写入审计事件并发送通知。

兼容阶段的直接创建用户 API 仍可存在，但必须在同一事务中创建 membership，并限制为操作者作用域内的下级角色。

公开注册只能选择三种安全结果之一：接受有效邀请加入已有组织、创建权限和配额均受限的 `customer` 组织，或进入无业务 API 权限的 `pending_claim` 状态。公开注册绝不能自动加入 manufacturer/agent/distributor，也不能让无组织用户访问电站、设备、告警、控制、OTA 或导出接口。

### 6.2 启停与撤权

- 停用用户或 membership 后，旧 access/refresh token 立即失效。
- 停用组织后，组织及子树不能进行新业务操作；平台管理员可进入只读处置模式。
- 密码修改、角色降级、组织迁移、退出登录都增加 session version 或撤销 jti。

### 6.3 组织和用户转移

- 普通转移仅允许同根租户。
- 校验操作者同时具有源组织和目标组织权限。
- 校验无环、目标类型合法、目标配额足够。
- 事务更新层级、成员关系和必要资产关系。
- 提交后失效授权缓存和旧会话，记录 before/after 审计。

## 7. 设备与电站生命周期

### 7.1 设备库存和认领

库存生命周期状态机：

```text
manufactured → in_stock → allocated → installed → retired
```

`claimed/transferred/unbound` 是所有权事件，不是库存持久状态；在线/离线/故障是连接状态。所有权、保管权、服务关系和临时分享分别由 binding/grant 有效区间表达，禁止用一个复合枚举混合这些维度。

设备只能由原厂生产导入或受信内部设备服务创建。终端绑定不再调用 `EnsureDevice` 自动创建未知 SN。

认领请求必须包含：

- 已存在且可认领的 SN。
- 一次性 claim code/二维码密钥的哈希校验。
- 目标电站属于当前授权范围。
- 渠道库存允许交付到当前客户。
- 幂等键。

对设备行加锁，两个并发认领只能一个成功。

### 7.2 绑定关系

`device_bindings` 表表达：

- `owner`
- `operator`
- `installer`
- `viewer`
- `controller`

包含主体类型、主体 ID、生效时间、过期时间、状态、权限集合和创建者。同一设备最多一个有效 owner。

设备认领凭证单独建模，每台设备最多一个有效凭证；只保存包含 `key_id` 的 HMAC 摘要，不保存 claim code 明文。

### 7.3 分享

- 使用正式授权 API，不发送 MQTT `share` 控制命令。
- 仅 owner 或拥有 share 权限的管理员可创建。
- 区分 view/control，支持过期、撤销和列表。
- 分享用户不能转移、解绑、OTA 或再次分享，除非显式授权。

### 7.4 解绑和转移

- 直接解绑仅适用于平台管理员或满足策略的 owner 自助场景。
- 安装商/服务商默认提交申请，由所属客户或有权渠道审批。
- 审批状态更新、所有权变更、分享撤销、缓存失效和审计必须在同一事务或事务 + outbox 中完成。
- 设备/电站转移使用 `transfer_requests`，记录源、目标、审批人、版本和幂等键。
- 转移完成后旧主体立即失去详情、列表、控制、OTA、告警和导出权限；历史遥测和审计归档不被改写。

### 7.5 电站归属

电站增加 `organization_id` 和明确 owner。设备只能加入当前授权范围内的电站。转移电站时，事务处理站内设备 owner/operation 关系、告警订阅和统计归属；失败整体回滚。

## 8. API 与跨端契约

API 分组建议：

- `/organizations`
- `/organizations/:id/children`
- `/organizations/:id/members`
- `/invitations`
- `/authorization/me`
- `/auth/context`
- `/devices/claims`
- `/devices/:sn/grants`
- `/devices/:sn/transfers`
- `/stations/:id/transfers`

所有分页响应、错误码、字段命名统一。管理端和 Flutter 通过共享的角色/权限常量或生成契约使用相同编号和字符串。

管理端路由守卫必须同时校验登录与 permission；菜单隐藏仅用于体验。Flutter 角色服务改为权限驱动，不再用 0–3 的旧枚举决定能力。

### 8.1 活动组织上下文

- 登录和刷新返回当前用户可用 memberships 摘要，但不接受客户端自行声明的权限。
- `POST /auth/context` 接收 `organization_id`，校验有效 membership 后签发绑定 `organization_id/root_tenant_id/membership_version/session_version` 的短期 access token；refresh token 只绑定用户会话，不能直接访问业务 API。
- `GET /authorization/me` 返回当前 access token 的 active organization、组织路径、有效 permission codes、data scope 和可切换 memberships；响应含 `authorization_version` 用于缓存分区与失效。
- 网关必须删除客户端传入的 `X-Organization-ID/X-Tenant-ID/X-User-*`，再从 access token 注入可信身份头。组织切换、membership 变化或刷新后，客户端清空旧组织的 query/page/offline cache 并重新获取授权上下文。
- Web、Flutter 和网关遇到未知角色、权限码、组织状态或 scope 时一律无权限；兼容数字角色只能通过一个集中、可测试的 legacy mapping 转换，禁止把缺失/未知角色默认为管理员。
- Web 的 refresh token 只能存放在 `HttpOnly + Secure + SameSite` Cookie，短期 access token 仅保存在内存；Flutter 使用系统安全存储且不得保存原始密码。组织切换和退出登录必须旋转或撤销 refresh session，并清除旧 access token。

### 8.1.1 对象级允许动作

- 设备和电站详情以及需要呈现动作入口的列表项由服务端返回 `allowed_actions`，至少支持 `view/control/share/unbind/transfer/ota/edit/delete`。
- `allowed_actions` 是当前 actor、active organization、对象关系和对象状态的即时投影，不是新的授权事实源；客户端只用它控制交互展示，服务端在每次动作时仍重新执行完整授权。
- 对象版本、owner/grant/transfer 状态或 authorization version 变化时，旧 `allowed_actions` 立即失效；未知动作默认隐藏和拒绝。

### 8.2 交互状态与错误契约

- 组织、邀请、认领、分享、解绑和转移接口返回稳定业务错误码，至少覆盖 `ORG_SCOPE_DENIED`、`MEMBERSHIP_INACTIVE`、`CLAIM_INVALID`、`CLAIM_REPLAYED`、`ASSET_CONFLICT`、`TRANSFER_PENDING`、`VERSION_CONFLICT` 和 `APPROVAL_REQUIRED`。
- 管理端和 Flutter 明确展示 pending/approved/rejected/expired/revoked/conflict 状态；重复提交使用幂等键，409 冲突必须重新加载对象版本后由用户确认。
- 前端乐观更新仅用于低风险展示字段；组织迁移、角色变更、认领、解绑、转移、控制和 OTA 必须以服务端确认结果为准。

### 8.3 本地直连安全边界

- Flutter 的本地 HTTP/BLE/Wi-Fi 控制和本地 OTA 不得依赖 App 内数字角色，也不得因云端不可达自动获得更高权限。
- 本地高风险动作要求设备现场证明和短期 capability：在线时由云端签发绑定 user、organization、device、actions、nonce 和过期时间的 capability token；离线时使用设备安全元件/出厂密钥验证的配对证明，能力范围不得超过最后一次有效授权。
- capability 必须防重放、绑定设备会话并通过设备侧时钟/单调计数器过期；解除 owner、禁用 membership 或恢复联网时同步撤销列表。
- 本地 OTA 包必须校验厂商签名、型号、版本策略和防回滚计数器；远程/本地控制都必须由设备固件执行相同安全包络，App 不能绕过功率、电压、电流和并网保护限制。
- 扫码得到的 claim code/PIN 必须进入 `/devices/claims`，日志、崩溃报告和本地持久化不得保存明文；现有 MQTT `cmdType=share` 路径必须删除并改用 grants API。

## 9. 兼容与迁移

### 9.1 四阶段切换

迁移固定分为：

1. `legacy`：只读旧数据，执行预检和新表回填，不扩大任何旧权限。
2. `shadow`：新模型为权威写入，旧字段仅作为同事务兼容投影；新旧授权分别计算并记录差异，禁止取二者并集。
3. `enforce`：只根据新模型授权；继续监控兼容投影和旧调用，但旧结果不影响授权。
4. `cleanup`：停止旧字段写入并移除旧数字角色分支；至少稳定运行一个发布周期后才删除旧列。

切入 `enforce` 前必须同时满足：shadow diff 为 0、outbox/兼容投影无积压、没有仍处于隔离状态的有效业务数据。正式切换并产生新业务数据后只允许前向修复，`down.sql` 仅保证切换前的结构回滚，不承诺新业务数据的无损降级。

### 9.2 历史数据回填

历史数字角色在 schema、迁移、网关和处理器中含义冲突，禁止仅按 `users.role` 数字直接回填。回填器先综合 parent 链、现有 permission、用户行为类型、设备/电站归属和显式映射配置生成预检报告。

预检必须识别父级循环、孤儿用户、重复手机号/邮箱、冲突的设备 owner、非法角色和缺失租户。无法确定归属的数据进入隔离表并默认拒绝业务访问，必须由有审计的修复命令处置。

大数据回填使用独立可恢复命令 `inv_api_server/cmd/channel_migrate`，按 checkpoint 分批并使用 `SKIP LOCKED`；禁止放入 API 启动时的单事务迁移器。每批写入可重放结果和 shadow compare 指标。

结构与业务切片顺序：

1. 建立组织、成员、闭包、配额、授权范围、库存和绑定表。
2. 从现有 role/parent_id/user_id/installer_id 回填默认组织和关系。
3. 引入兼容读取，比较新旧结果并记录差异指标。
4. 按用户、电站、设备、告警/统计、控制/OTA 顺序切换新授权。
5. 新模型稳定后停止旧字段写入；旧列保留一个发布周期再移除。

每个迁移都要有 up/down、幂等验证、升级数据校验和回滚说明。

### 9.3 数据库强约束

- 父子组织必须通过复合外键/约束触发器保证属于同一 `root_tenant_id`；组织 code 在租户内使用有效行部分唯一索引。
- 同一用户在同一组织最多一个有效 membership；同一组织和标准化接收方最多一个 pending invitation。
- 邀请令牌与 claim code 只保存带 `key_id` 的 HMAC 摘要；同一设备最多一个有效 claim credential、一个有效 owner、一个 pending transfer/unbind。
- 幂等键唯一范围为 `(root_tenant_id, actor_id, endpoint, idempotency_key)`，服务端保存并重放首次成功响应。
- 电站、设备、binding/grant 通过复合外键或约束触发器保证同租户；所有权、组织、审计使用 `ON DELETE RESTRICT`，不得级联删除。
- 审计 `resource_id` 使用 `TEXT`，覆盖设备 SN 等非数字标识。

### 9.4 事务、锁与 outbox

- 设备认领在一个事务中依次锁设备、库存、claim credential、目标电站和 quota usage；条件消费凭证，写 owner/库存/电站、兼容投影、审计、outbox 和幂等响应。
- 解绑/转移审批锁申请、资产和当前有效关系，按 `expected_version` CAS 更新；撤销旧 grant，写新关系、兼容投影、审计和 outbox。任何一步失败全部回滚。
- 邀请接受锁邀请并条件改状态，然后创建/复用用户、membership 与 role assignments；重放返回原结果。
- 组织移动按 root tenant 获取事务级 advisory lock，再锁源子树、目标节点和 quota usage；校验无环后原子重写 closure、版本、审计和 outbox。
- Redis 失效和消息发布由事务内 outbox 异步驱动并幂等重放，不能参与数据库事务；高风险操作的审计或 outbox 写入失败必须回滚。

## 10. 安全与运维

- 网关先删除客户端传入的 `X-User-*`，再从严格校验的 access token 注入身份。
- JWT 校验算法、`exp/iss/aud/jti/token_type/session_version`。
- access token 只接受配置的非 `none` 签名算法，固定校验 issuer/audience、`token_type=access`、jti、session version、membership version、组织状态版本和有效期；这些版本以数据库/Redis 的可撤销状态为准，缓存异常对高风险请求默认拒绝。
- 禁用父组织时提升子树授权版本，使所有后代上下文失效。无活动组织的 token 只能访问登录、刷新、公开注册、邀请接受和组织上下文选择端点。
- break-glass 使用独立 audience、短有效期、工单与批准声明及专用中间件；不得复用 `role=0` 或任何全局角色绕过。
- RBAC 缓存失效事件跨服务传播；缓存/数据库异常默认拒绝高风险操作。
- 审计记录 actor、active organization、tenant、request ID、IP、资源、before/after、结果和失败原因。
- 远程控制、批量控制、OTA 和大规模导出支持审批、批次限制和紧急停止。
- 生产发布使用受保护 environment 和人工批准；staging 与生产使用相同镜像 digest。
- 建立 PITR、跨故障域备份、恢复演练和告警演练门禁。

### 10.1 平台运营与租户边界

- 平台运营账号不属于任何客户租户，默认不能读取租户业务数据。
- 跨租户处置必须使用限时 break-glass 授权，要求工单号、双人批准和明确的资源范围；首期仅允许只读诊断，写操作必须使用单独审批动作。
- break-glass 的申请、批准、使用、到期和拒绝全部进入不可变审计；不能用原厂组织管理员代替平台运营身份。

### 10.2 审计、隐私与可观测性

- 审计表由独立数据库角色追加写，应用角色无 `UPDATE/DELETE` 权限；审计事件同时进入事务 outbox，外送失败时告警并可幂等重放。
- 高风险写操作在审计/outbox 不能持久化时整体失败；只读拒绝事件允许本地缓冲，但必须带 request ID 并在恢复后补送。
- 审计时间使用数据库 UTC 时间，保留 actor、active organization、root tenant、request ID、来源 IP、资源、before/after、结果、失败原因和事件 schema version。
- 普通管理员只能查询本组织范围内的业务审计；平台审计员使用独立只读角色。审计默认保留 365 天，具体地区的更长期限通过策略配置并记录法律依据。
- 导出采用异步任务、字段白名单和敏感字段脱敏；下载令牌一次性且最长 24 小时失效。注销/删除采用可审计的匿名化或策略保留，不允许物理删除法定审计记录。
- 必须暴露并告警：授权拒绝率、跨租户拒绝次数、缓存失效延迟、待处理转移、审计/outbox 失败、最近成功备份年龄和恢复演练状态。

### 10.3 灾备目标与恢复验证

- 初始商用目标为 PostgreSQL `RPO <= 15 分钟`、平台核心 API `RTO <= 120 分钟`；若合同要求更严格，以租户策略覆盖且门禁使用更严格值。
- 备份必须加密、跨故障域保存并定期验证校验和；生产启用 WAL 归档，支持恢复到指定时间点。
- `deploy/scripts/restore_verify.sh` 必须在隔离环境恢复指定 SHA/schema 的备份，验证迁移版本、租户隔离约束、owner 唯一约束、审计连续性和关键行数，并在恢复完成前冻结远程控制与 OTA。
- 恢复演练至少每 90 天一次；报告记录备份 URI 摘要、目标时间、实际 RPO/RTO、镜像 digest、数据库 schema、校验结果、失败项和双人签字。

### 10.4 不可绕过的发布证据

- 唯一生产环境名为 `production`，使用受保护 environment；发布人和批准人必须分离。
- staging 验收与 production 提升必须引用同一不可变镜像 digest。`workflow_dispatch` 只能重新验证已有 digest，不能跳过任何 gate。
- `docs/cs6k2-system-support/commercial-channel-test-manifest.json` 是机器可读证据清单，将每个 MUST 关联到测试 ID、CI job、Git SHA、镜像 digest、schema version 及 HIL/DR/安全证据。
- P0/P1 缺陷必须为 0；P2 必须有负责人、期限和经签字的风险接受。HIL 证据绑定当前硬件/固件基线和镜像 digest，DR 证据最长有效 90 天，安全审查证据最长有效 30 天。
- `tools/verify_release_evidence.ps1` 校验证据完整性、时效、摘要和签字角色；任一必需证据缺失或不匹配时 CI/CD 失败。

## 11. 测试设计

### 11.1 单元与属性测试

- 合法/非法组织父子组合。
- 防环、跨租户、角色和范围组合。
- 状态机所有允许和禁止转换。
- scope 解析必须默认拒绝。

### 11.2 数据库与并发测试

- 两个并发认领只能一个成功。
- 转移、解绑审批任一步失败时整体回滚。
- 闭包/路径和配额在并发迁移后保持一致。
- 升级旧数据后新旧授权结果按预期收敛。

### 11.3 契约测试

- `contracts/openapi/channel-platform-v1.yaml` 是 HTTP 路径、方法、DTO、错误码、权限码和身份上下文的唯一事实源；不兼容变更必须发布新的主版本。
- `contracts/events/*.v1.schema.json` 是缓存失效、资产转移和审计 outbox 的事件契约；消费者至少兼容当前和前一小版本。
- 管理端/Flutter 调用的每个方法必须在契约、网关和 API 中存在，生成式检查验证请求/响应字段，禁止 mock 提供后端不存在的成功路径。
- `tools/check_channel_contracts.ps1` 同时检查 OpenAPI、事件 schema、Web/Flutter 调用路径与网关路由；契约 diff 出现删除、收窄枚举或必填字段新增时失败。

### 11.4 双租户四级业务 E2E

`tests/fixtures/commercial-channel/two_tenant_four_level.yaml` 固定建立 A/B 两棵独立组织树。每棵树包含原厂、两个同级代理、每个代理下两个分销商、客户、服务商、成员、库存设备、已认领设备、电站、有效/过期分享；所有身份和对象使用稳定测试 ID。

测试对本人、直属下级、隔级下级、同级旁支、跨根租户和过期授权六种关系逐一执行列表、详情、count/聚合与写操作断言：

- 原厂看到本租户全部子树。
- 代理商看到自己的分销商和客户，看不到同级代理商。
- 分销商管理自己的客户、安装商和库存，看不到其他分销商。
- 客户仅看到自身电站、设备和有效分享。
- 服务商只看到被分配对象且访问按期失效。
- 停用、角色降级、组织转移后旧 token 和缓存权限立即撤销。
- 设备、电站转移后所有列表、详情、告警、统计、控制、OTA 和导出同时切换。

对应自动化 ID 和入口：

- `CC-AUTH-001`：permission、scope、object relationship 任一缺失均返回 403；非法父子、环和跨根普通重挂均拒绝。
- `CC-E2E-001`：上述六种主体关系无列表、count、聚合或错误信息侧漏。
- `CC-SESSION-001`：用户/membership/组织停用、改密、降级、转移和 logout 后，旧 access/refresh token 立即返回 401/403。
- `CC-ASSET-001`：未知 SN、错误或重放 claim code、越权电站、库存不匹配均拒绝，并发认领只有一个成功。
- `CC-ASSET-002`：解绑/转移的审批、owner 唯一、分享撤销、缓存失效、outbox 和审计原子完成，故障注入后全部回滚。
- `CC-SCOPE-001`：电站、设备、告警、统计、控制、OTA、工单、通知和导出使用相同授权结果。
- `CC-MIG-001`：空库、历史快照、幂等重跑、shadow compare、切换和回滚均通过；切换前差异必须为 0，双写失败通过 outbox 重放收敛。
- `CC-AUDIT-001`：成功、失败、403、审批和撤权均有不可修改审计，外送中断产生告警。

集成入口固定为 `go test -race -v -tags=integration -count=1 -run '^TestCommercialChannel' ./...`（在 `tests/integration` 执行）。

### 11.5 规模、性能与滥用防护

- 基线容量夹具至少包含 10,000 个组织节点、100,000 个设备和单代理 20,000 个后代对象；组织主链最大深度固定为 4，服务关系不增加主链深度。
- 在 CI 记录的参考硬件上，缓存命中的授权对象检查 P95 小于 50 ms，普通分页/count P95 小于 500 ms；指标超限即失败，参考硬件变化必须保留前后基线。
- 验证大树分页、聚合、批量转移、缓存失效风暴和每租户/用户/设备/导出任务限流；任何单租户压力不得造成跨租户数据泄漏或绕过高风险动作限流。

### 11.6 HIL 与发布门禁

- `docs/templates/COMMERCIAL_CHANNEL_HIL_RECORD.md` 固定记录逆变器序列号/硬件版本、ARM/DSP/ESP/BMS 固件、协议版本、App/Web/API SHA、镜像 digest、schema 版本、操作者和复核者。
- 真机逐项验证配网、认领、遥测、告警、控制安全包络、OTA 中断恢复和断网重连；测量容差取设备模型/协议声明值，缺少声明值本身即为阻断项。
- 故障注入覆盖掉电、弱网、重复消息、乱序、升级包校验失败和控制超界；危险控制必须由独立安全人员复核并使用受控测试负载。
- 审计、告警、备份、PITR 和降级演练生成独立证据。无 HIL 双签、恢复报告、安全审查和生产安全配置时，CD 不得进入 production。

## 12. 验收标准

仓库内完成标准：

- 数据模型、迁移、后端、网关、管理端、Flutter 和文档实现一致。
- 新行为均有先失败后通过的自动测试证据。
- 双租户四级 E2E 覆盖正向、平级隔离、跨租户拒绝、禁用和转移。
- 全量 Go、前端和 Flutter 测试、构建、静态检查通过。
- 关键并发、事务和迁移测试通过。
- 安全与代码质量双评审无未解决 Critical/Important。

商用发布完成标准：

- 仓库内完成标准全部满足。
- 外部 HIL、生产凭据轮换、证书、SBOM/许可证、备份恢复和告警演练证据齐全。
- 受保护生产环境获得人工批准。
