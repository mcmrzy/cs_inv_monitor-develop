# 持续质量检查与修复台账

更新时间：2026-07-16

## 目标

持续检查并修复 Web、Flutter App、后端与部署链路中的显示、业务逻辑和功能问题。每一项问题都记录现象、根因、修复、验证和剩余风险，避免“可以编译”被误认为“可以正常使用”。

## 状态说明

- `待确认`：静态检查发现，需要通过测试或实际业务路径复现。
- `已确认`：已经定位到确定的错误路径。
- `修复中`：代码正在修改，尚未完成回归。
- `已修复`：代码和针对性测试通过。
- `待部署验证`：本地验证通过，需要生产或测试环境确认。

## 当前问题

| 编号 | 优先级 | 模块 | 状态 | 问题与影响 | 根因 | 修复/验证 |
| --- | --- | --- | --- | --- | --- | --- |
| CQ-001 | P0 | API/数据库 | 待部署验证 | 设备、电站列表接口因可空列 Scan 到 Go 非空类型而返回 500 | Repository 未处理数据库 NULL | 已对设备/电站查询增加 NULL 兼容和回归测试；需持续检查其他 Repository |
| CQ-002 | P0 | Web | 已修复 | 查询失败被 `?? []`、空表、空状态或 0 值掩盖 | 多数 React Query 调用只处理 loading/data，未处理 error | 已扫描 109 个查询调用；所有实际页面查询均加入错误状态，涵盖仪表盘、监控、日志、工单、用户、管理、型号、OTA、设备、电站、大屏和详情页。剩余 2 个查询属于无调用方的 `useFieldMetadata` 死代码 |
| CQ-003 | P0 | App | 已修复 | 设备、电站、告警请求 500 时可能继续显示旧数据且未标记缓存 | BLoC 对所有 Failure 使用缓存，只把 NetworkFailure 标记为缓存；已有数据时还会忽略错误 | 仅 NetworkFailure 可降级到缓存且强制标记；服务器错误进入 Error 状态。BLoC 针对性测试通过 |
| CQ-004 | P0 | App | 已修复 | `code == 0` 但 `data` 结构错误时被当成成功空数据 | Repository parser 返回 `Right({})`/`Right([])` | Device/Station/Alarm/Dashboard/OTA 读取接口严格校验结构；写操作仍允许合法空响应。契约测试通过 |
| CQ-005 | P0 | App 仪表盘 | 已修复 | 多个仪表盘接口部分失败时，失败模块显示 0 或空图表 | BLoC 只统计是否至少一个接口成功，没有向 UI 传递部分失败信息 | BLoC 记录失败模块，页面显示部分加载失败和重试入口；10 项仪表盘测试通过 |
| CQ-006 | P1 | Web OTA | 已修复 | 发布弹窗请求失败后主动 `setModelList([])`/`setDeviceList([])` | catch 将异常转换为空数组 | 型号/设备加载失败会显示错误和重试；相关数据失败时禁止发布 |
| CQ-007 | P1 | 多语言 | 持续修复 | 多处中英文混用、硬编码中文及乱码注释/文案 | 文案未统一进入 locale，历史文件编码异常 | 核心 UI 已完成首轮双语化；复扫仍发现 App 通知/BLE 服务消息和 Web OTA 深层弹窗存在硬编码中文，已登记 CQ-024，不能再把该项视为完全结束 |
| CQ-008 | P1 | App 工程质量 | 持续修复 | `flutter analyze` 历史 warning/info 容易掩盖新缺陷 | 历史未使用代码、异步 context、废弃 API、格式规则和调试输出长期累积 | 本轮将 error/warning 清零；当前仍有 760 项 info，主要为 `require_trailing_commas` 等格式规则，后续按目录机械清理并在 CI 中单独阻断 warning/error |
| CQ-009 | P1 | Web API 契约 | 已修复 | HTTP 成功但业务失败或 `data` 结构错误时，queryFn 仍可能变成空数据 | Web 请求层没有处理业务 `code != 0`，也缺少结构契约 | Axios 拦截器统一拒绝业务错误和 GET 缺失 data；核心 API 可声明 object/array/page 契约并严格校验，设备、仪表盘、工单、用户、管理、告警、型号、协议和 OTA 已接入 |
| CQ-010 | P0 | Web 设备控制 | 已修复 | 设备详情“控制模板”读取命令历史接口，模板字段与后端返回完全不匹配，选择/执行控制可能失效或崩溃 | `/devices/:sn/commands` 是历史分页接口，不是控制能力接口 | 模板改读 `/control-capabilities` 并把参数 Schema、风险等级和分类转换为控制表单；历史改读 `/commands/history`，新增 API 契约测试 |
| CQ-011 | P0 | 验证码安全 | 已修复 | 滑块验证码可伪造：请求 JSON 解析失败时后端直接发放 token，正常请求也只检查耗时；前后端日志泄露坐标或 token | 拼图和坐标校验完全在客户端，后端信任 `verified` | 后端生成背景与拼图图片并只在 Redis 保存期望坐标；挑战一次性使用，错误坐标、过期和重放均失败；前端只提交 challengeId/x/duration，不再持有正确坐标或 verified；删除敏感日志及 create-puzzle 依赖 |
| CQ-012 | P1 | API 限流 | 已修复 | 公开验证码图片接口可高频消耗 CPU；触发全局限流时 HTTP 仍返回 200，网关与客户端无法按 429 处理 | 高成本接口仅使用宽松全局桶，限流中间件调用通用业务错误响应 | 验证码生成/校验增加每 IP 2 次/秒、突发 5 次的独立桶；新增真实 HTTP 429 响应并覆盖自定义桶与无效配置测试 |
| CQ-013 | P0 | App 设备控制 | 已修复 | 控制页五组接口失败或返回 HTTP 200 业务错误时，异常被空 `catch` 吞掉，页面仍显示默认 SOC、空计划和空命令记录 | 页面绕过 Repository 直接使用 Dio，未校验响应 code/data，且没有失败状态 | 新增统一 API envelope 解包器；控制字段、实时数据、计划、状态和历史均严格校验对象/数组/分页结构；页面区分全部/部分加载失败并提供重试，首批命令状态和 Tab 文案已双语化 |
| CQ-014 | P0 | App 参数设置 | 已修复 | 参数页通过异步 `get_params` 控制命令读取配置，却把后端返回的 `task_id` 当参数；请求失败后仍渲染默认值，写请求业务失败也会提示成功 | 读取接口选错且直接 Dio 调用未校验 envelope | 改读 `/devices/:sn/control-state`，以 reported 覆盖 desired 形成当前参数；设备状态与控制状态严格校验，失败时警告默认值不可信并可重试；写命令必须返回合法 task_id 才视为已受理 |
| CQ-015 | P0 | App 实时详情 | 已修复 | 云端设备详情失败时，即使 MQTT 从未收到数据，页面也清除错误并用默认字段渲染，看起来像真实空值 | 失败降级没有验证备用数据源是否实际可用 | 设备详情接入严格 envelope 校验；云端和 MQTT 均无数据时显示加载失败；只有实际收到 MQTT 数据才降级，并明确提示云端不可用和备用字段来源 |
| CQ-016 | P1 | App 添加设备 | 已修复 | 从指定电站进入添加设备时，电站名称可能始终为空；选择电站弹窗关闭页面后仍可能访问 context | 页面把后端 `data.station` 错读成 `data` 根字段，且异步选择后缺少 mounted 判断 | 严格解包电站详情并读取嵌套 station；扫描历史及选择电站流程补 mounted 保护；该文件定向 analyze 清零 |
| CQ-017 | P0 | App 能源计划 | 已修复 | 能源计划把后端对象响应当数组读取，保存时只发送 periods，导致读取失败或覆盖其他字段 | App 与后端 schedule envelope/PUT 契约不一致 | 新增 schedule 规范化和替换/删除 helper；读取完整 schedule 对象，保存携带 timezone、enabled、periods 并使用 If-Match revision；7 项 helper/API 测试通过 |
| CQ-018 | P0 | API 能源计划 | 已修复 | 普通用户可通过已知 SN 读取或修改其他用户设备的计划/临时覆盖 | 5 个设备级 handler 未校验设备归属 | Handler 注入 `DeviceRepository.HasDataPermission`；管理员放行，普通用户必须拥有/获共享权限；授权测试覆盖管理员、所有者、非所有者和缺失 checker |
| CQ-019 | P0 | API 电池配置 | 已修复 | 普通用户可读取或绑定其他用户设备的电池配置 | 设备级电池接口缺少归属校验 | GET/PUT battery-config 接入同一设备授权检查，并新增管理员、所有者、非所有者测试 |
| CQ-020 | P0 | 生产部署 | 待外部配置 | 新镜像已构建但不能安全替换当前容器 | `deploy/.env.prod` 缺失，现有 `.env` 仍含占位密码/证书 | 增加 `deploy/docker-up.ps1` 和 Makefile 生产配置校验；缺文件、占位值或 `DB_SSL_MODE != require` 时拒绝部署。待提供真实生产配置后执行重建和 healthy 验证 |
| CQ-021 | P1 | App Wi-Fi | 已修复 | Wi-Fi 扫描依赖 `wifi_iot` 的废弃扫描 API，平台升级后可能失效 | 扫描与连接能力耦合在旧插件 | 新增 `wifi_scan` 适配服务，迁移本地发现、配网页和本地 OTA 的扫描流程；`wifi_iot` 仅保留连接能力 |
| CQ-022 | P1 | App 仪表盘 | 已修复 | 型号动态字段成功加载后仍使用 `widget.fields`，自动加载结果 `_autoFields` 被忽略 | 动态区块分支和渲染函数没有使用 effective fields | 统一使用 `widget.fields ?? _autoFields`，恢复按型号字段元数据动态渲染 |
| CQ-023 | P0 | 合并回归 | 已修复 | cherry-pick 曾覆盖能源计划/电池授权实现，但保留了测试，导致编译失败 | 并发提交的冲突解决只保留部分文件 | 恢复两个 Handler 的授权实现和 main 注入；`go test -p 2 ./...` 全量通过，保留测试防止再次静默回退 |
| CQ-024 | P1 | 多语言 | 待修复 | App 通知标题/BLE 服务错误和 Web OTA 多个弹窗仍硬编码中文，英文模式下会混入中文 | 深层业务组件和无 BuildContext 的服务/BLoC 未使用 locale key | 已完成字符串复扫并锁定文件；下一轮优先把通知模型改为语义 key+参数、BLE 错误映射为本地化 key，并补齐 OTA locale 键与英文模式测试 |

## 第一轮检查范围

- Web：设备、电站、仪表盘、监控、告警、工单、操作日志、用户、管理、OTA、远程设置、批量设置、型号管理、设备详情、大屏。
- App：Device/Station/Alarm/Dashboard/OTA Repository、BLoC、缓存降级和错误页面。
- 后端：设备/电站 Repository NULL 兼容和统一响应结构。

## 回归原则

1. HTTP 4xx/5xx 不得显示成“暂无数据”。
2. 响应结构不符合契约时必须报格式错误，不得返回成功空数组。
3. 只有明确的离线/网络错误可以读取缓存；所有缓存数据必须有明显标识。
4. 仪表盘部分接口失败时必须标出失败模块，不允许用 0 冒充真实业务值。
5. 空数据、无权限、加载失败和离线缓存必须是四种不同的 UI 状态。

## 验证记录

### 2026-07-16 第一轮

- Flutter 针对性测试：40 项通过，3 项因既有平台通道限制跳过。
- 覆盖范围：Device/Station/Alarm BLoC 缓存降级、五类 Repository 响应契约、写接口合法空响应。
- Web `npm run build:check`：通过。
- Web 全量 Vitest：20 个测试文件、184 项测试全部通过。
- Flutter 仪表盘：10 项测试通过，覆盖部分接口失败提示。
- Flutter analyze：无 error；存在 416 项历史 warning/info，已登记 CQ-008。
- Flutter 全量测试：166 项通过，4 项既有跳过项，无失败。
- 本轮 App 修复后 Flutter 全量测试：169 项通过，4 项既有跳过项，无失败。
- Go API 服务 `go test ./...`：全部通过，覆盖 handler、repository、service、response 和安全测试。
- Web API 契约测试新增：HTTP 200 业务错误、GET 缺失 data、object/array/page 结构错误、合法空写响应。
- Web Mock 契约已按当前 Go 后端修正：固件和升级包列表为数组，任务列表为分页对象。
- 验证码 Handler：覆盖 malformed JSON、缺失挑战、异常轨迹、正确坐标、错误坐标、一次性消费、重放失败和 token 入库，`go test ./internal/handler` 通过。
- 删除 `create-puzzle` 后登录 chunk 从约 37 kB 降至约 22 kB；`npm audit --audit-level=moderate` 为 0 漏洞。
- Web 构建产物已拆分；当前最大 chunk 为 `vendor-antd-choices` 408.67 kB，未出现构建警告。
- 型号/协议治理工作区已清除硬编码中文，覆盖列表、状态、抽屉、迁移预览、表单及操作反馈；Web 构建和 184 项测试再次通过。
- API 限流回归：`go test ./internal/middleware ./internal/handler ./pkg/response` 通过，限流响应为 HTTP/业务码双 429。
- App 设备控制：新增响应解包器 3 项测试，HTTP 200 业务错误、缺失 data 和类型错误均会失败；控制页定向 `flutter analyze` 无问题。
- App 参数设置：纠正异步 `get_params` 误用并接入 control-state；控制页、参数页和响应工具联合定向 `flutter analyze` 无问题。
- App 实时详情：云端/业务错误不再无条件伪装成 MQTT 降级；定向 analyze 无 error/warning，保留该历史文件 34 项格式类 info 待 CQ-008 批量清理。
- App 电站详情：补齐 MQTT 监听和天气请求的 mounted 保护，清理未使用绘图代码、废弃颜色 API 与格式告警；该文件定向 analyze 从 19 项降至 0。
- App 添加设备：修正电站详情响应层级，恢复预选电站名称显示，并清理异步 context 问题；定向 analyze 无问题。

### 2026-07-16 第二轮

**Phase 0 — Docker Healthcheck 修复**：
- 为 `deploy/docker-compose.yml` 和 `deploy/docker-compose.prod.yml` 中的 `inv-api-server`、`api-gateway`、`inv-device-server` 三个服务添加 healthcheck 配置。

**Phase 1 — Flutter '正常' 硬编码替换**：
- 5 个文件 6 处硬编码 `'正常'` 替换为 `l10n.normal`。

**Phase 2 — Flutter print() 清理**：
- 5 个文件 41 处 `print()` 替换为 `debugPrint()`。

**Phase 3 — use_build_context_synchronously 修复**：
- 4 个文件添加 mounted guard，消除异步 context 风险。

**Phase 4 — Web 前端 CQ-007 剩余项**：
- 4A: OTA 状态映射国际化（8+6 个状态键）。
- 4B: 管理页租户表单国际化（12 个新键）。
- 4C: 告警页事件类型标签国际化。
- 4D: 大屏页规范化。
- 4E: 型号管理页字段表国际化（25 个新键，29 处替换）。

**Phase 5 — Flutter 页面 i18n**：
- 5A: status_grid_widget 语义参数修复（`isOnline` 替代 `label=='在线'`）。
- 5B: OTA 页面国际化（15+ 处）。
- 5C: BLE 配网状态文案（13 状态 + 15+ UI 文案）。
- 5D: 设备实时数据页（保留 chineseMap 兼容层）。
- 5E: 仪表盘 Widget 国际化（7 处）。
- 5F: 协议页面国际化（20+ 处）。
- l10n 三文件新增约 55 个 i18n 键值对。

**Phase 6 — 英文模式测试**：
- test-utils.tsx 扩展支持 `lang` 选项。
- 新建 ModelRegistryWorkspace.test.tsx（9 个测试）。

**Phase 7 — 全量验证**：
- Web 构建：通过。
- Web 全量 Vitest：21 个测试文件、193 项测试全部通过。
- Flutter analyze：0 error / 28 warning / 341 info（共 369 项，较第一轮 416 项降低 47 项）。
- Flutter 全量测试：169 项通过，4 项既有跳过项，无失败。
- Go API 服务 `go test ./...`：13 packages 全部通过。
- Go Gateway 服务 `go test ./...`：修复 RBAC 中间件 `hasPermission` 方法（增加 JWT role 回退逻辑）后全部通过。

**Phase 8 — 端到端缺口分析**：
- 设备控制：32 个 handler 方法，0 测试覆盖（P0）。
- 告警处理（API 侧）：9 个方法，0 测试覆盖（P1）；Device Server 侧 12 个测试已覆盖。
- 工单流转：9 个方法，0 测试覆盖（P1）。
- OTA 发布：34 个方法，0 测试覆盖（P0）。
- 总计 84 个 handler 方法零测试覆盖，列入下一轮检查重点。

**额外修复**：
- Go Gateway RBAC 中间件 `hasPermission` 增加 JWT role 回退逻辑，解决权限校验遗漏。

### 2026-07-16 第三轮

- 收口并验证并发 cherry-pick 冲突，源码中无冲突标记，恢复被覆盖的能源计划/电池设备归属授权。
- Web 全量 Vitest：21 个测试文件、193 项测试全部通过；生产构建通过，最大 chunk 为 `vendor-antd-choices` 408.67 kB，无 chunk-size 警告。
- Flutter 全量测试：173 项通过、4 项既有跳过、0 失败。
- Flutter analyze：0 error、0 warning；760 项 info 以 trailing comma 等格式规则为主。
- Go API：`go test -p 2 ./...` 全部通过。高并发并行回归曾触发 Windows Go GC/Vitest worker 异常，改为低并发串行后稳定通过，判定为本机资源竞争而非测试断言失败。
- Wi-Fi 扫描迁移至 `wifi_scan 0.4.1+2`，依赖锁文件已更新。
- 修复 Dashboard 自动型号字段加载后未参与渲染的问题；清理 App 26 个未使用代码/无效判断 warning。
- 多语言复扫确认源码文件本身为 UTF-8；PowerShell 默认读取显示的“乱码”不是文件损坏。另发现 App 通知/BLE 和 Web OTA 深层硬编码，登记 CQ-024。
- Docker 新镜像此前已构建；现运行的 API、Device、Gateway、Postgres、Redis healthy，039–055 迁移已应用，数据库连接全部使用 SSL。前端仍是旧容器且无 health，因缺少真实 `deploy/.env.prod` 未冒险重建。

## 下一步规划

1. **端到端测试补全（P0）**：针对 Phase 8 缺口分析，优先为设备控制（32 handler）和 OTA 发布（34 handler）补充单元/集成测试。
2. **端到端测试补全（P1）**：告警处理 API 侧（9 handler）和工单流转（9 handler）补充测试覆盖。
3. **CQ-024 多语言收尾**：优先修复 App 通知/BLE 服务消息和 Web OTA 深层弹窗硬编码，并为英文模式补回归测试；随后处理 china_regions.dart、alarm_code_mapping.dart 和 fieldNameMap 数据层兼容。
4. **CQ-008 持续降噪**：按目录机械清理 760 项格式类 info；CI 立即把 error/warning 设为阻断，info 单独统计。
5. **Docker 部署验证**：取得真实 `deploy/.env.prod` 后通过安全脚本重建，重点确认前端 healthcheck 和全部服务 healthy；禁止使用占位配置覆盖当前健康容器。
6. **英文模式回归**：持续扩展英文模式组件测试，覆盖 OTA 状态映射、告警事件类型和型号管理字段表等新增国际化键值。
