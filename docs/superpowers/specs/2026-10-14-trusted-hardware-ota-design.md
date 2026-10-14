# 基于可信硬件档案的 OTA 完整方案

日期：2026-10-14。状态：完整性评审通过的设计稿，供用户评审；未实施、未迁移数据库、未部署、未刷写设备。

实施约束补充（2026-10-14）：用户明确系统端没有权限修改 ARM、DSP、BMS 固件。本次不修改这三个目标的应用或 Bootloader。阶段 A 的可信档案、矩阵与系统端校验正常实施；阶段 B 中涉及目标自校验的内容作为未来设备供应方能力边界，不能作为本次系统功能已完成的证据。现有协议不能提供独立板卡 UID/安全恢复的目标保持 registry_verified，云端只在精确审计兼容窗口执行；设备端保护可放入允许修改的通信管理器，但不能把台账写回再读出冒充实物识别。离线升级须由通信管理器实现可信身份、授权和写前校验后开放，系统端不得通过伪造能力位或认证回执绕过。

## 1. 目标、已确认输入与方案选择

同一个销售型号可以包含不同主板、DSP 板、通信板和 BMS。本方案解决硬件身份错误造成的固件误选，并覆盖远程、本地联网、本地离线、回退、重试及售后换板。

用户已确认：有 SN 对应的出厂记录，且记录包含主板、DSP、通信板等模块；本地升级可以提前联网准备，再在无互联网的现场执行。

本设计不假定当前设备具备独立板卡识别、可信时钟、不可回滚计数器、双分区或硬件保护密钥。未通过能力验收的模块不进入对应保护等级。设计中的编号、时限和容量是拟定产品约束，不是现有固件能力声明。

| 方案 | 收益 | 局限 | 选择 |
|---|---|---|---|
| SN 台账与模块档案 + 固件兼容矩阵 + 设备写入前校验 | 利用现有台账，兼顾旧设备与后续设备，能够处理换板 | 需要档案治理、App 和真实固件协同改造 | 推荐，分阶段交付 |
| 仅由管理员维护 SN 与固件白名单 | 服务端改动较少，短期降低误选 | 固件白名单维护量大；设备本地入口和换板识别仍存在缺口 | 作为过渡期人工核实方式 |
| 仅依赖板卡自动识别 | 最终可减少人工维护 | 旧板未必有可读标识，不能用软件中的版本常量代替实物识别 | 作为增强来源，不单独使用 |

核心规则：可信档案决定兼容身份；设备上报是观测信息；独立读取的实际板卡身份用于执行前验证。三者分开保存，禁止相互静默覆盖。

## 2. 当前实现与必须修正的问题

| 证据 | 当前行为 | 设计要求 |
|---|---|---|
| `business-api/internal/handler/internal_handler.go` 的 DeviceInfo upsert | 非空上报更新设备型号、硬件版本 | 仅更新观测信息；不得更新可信型号、模块配置 |
| `business-api/internal/repository/ota_independent_repository.go` 的 queryDeviceInfoForOTA | 上报硬件字符串在目录中存在就标记 HardwareKnown | 改为读取已核实、未冻结的模块档案 |
| `inv_app/lib/features/ota/presentation/models/local_ota_presentation.dart` | 本地 INFO 硬件字符串被作为匹配依据 | 使用核实档案和授权；INFO 原始字符串仅用于比对 |
| `business-api/internal/service/ota_service.go` 的 verifyFirmwareReleaseSignature | V1 只签目标、版本、大小、SHA256、安全版本 | 新版清单同时签入型号和模块硬件兼容范围 |
| `business-api/internal/handler/device_handler.go` 的 Create/Update，及 DeviceService/DeviceRepository 对应参数 | hardwareVersion 传入 firmwareEsp 参数 | 修复独立字段映射；普通设备编辑不成为硬件核实入口 |
| `inv_app/lib/features/ota/presentation/controller/local_ota_controller.dart` | 完成状态可采用 fallbackVersion 展示和同步 | 请求版本不作为安装成功证据 |

保留已有发布、灰度、任务、幂等、模块顺序和历史机制。数据库迁移 129 的目录是已有分类数据，不能据此认定某台设备已经核实。本设计只新增迁移，不修改 129 或已存在的 130；实施时根据最终工作区分配后续编号。

本地检查的 L10 工程 `D:/CS_INV_WIFI/esp32c3_l10_idf/main/telemetry/telemetry.c` 从 ARM 只读区取得 HardwareVersion 后格式化上报。该字段不能自动代表 DSP、通信板或所有目标模块，也不能证明实际部署设备的硬件识别能力。

## 3. 身份、型号与兼容关系

### 3.1 三个独立对象

| 对象 | 含义 | 修改来源 |
|---|---|---|
| 销售型号 model | 用户看到的产品型号，如 CS-L10-6K2 | 台账核实或经审核的型号纠正 |
| 模块硬件类型 board_type | 一类可以共用同一目标固件的板卡，例如某主板修订 | 硬件管理员建立，发布后编码不改 |
| 设备当前模块配置 module assignment | 某 SN 当前装配了哪些板卡类型、板卡 UID | 出厂记录或有凭据的售后换板 |

目标字段保持 `arm`、`dsp`、`esp`、`bms`。硬件类型记录 target_chip、稳定 board_code、板卡修订、说明。主板可能承载多个目标，同一个物理 board_uid 可以出现在不同目标记录中；其关联必须由档案明确建立。

board_code 使用不可复用的 ASCII 编码，长度 1..50，仅 `[A-Z0-9][A-Z0-9._-]*`；显示名称独立。内部可使用数据库 ID，设备协议使用稳定编码。HW-1、V1 和 1 不自动等价。别名映射必须带明确目标、来源、审核记录和生效修订，不能以全局字符串替换实现。

兼容判断的基本单位是 `verified_model + target_chip + board_type`，还应满足签名清单的 Bootloader 最低版本、存储布局标识、必要协议能力和模块依赖。能力未知不推定满足。同一个软件版本可以有不同板卡构建；固件文件身份必须使用 firmware_id、SHA256 和 manifest_digest。

### 3.2 模块差异示例

以下是设计示例，不代表实际生产型号或板卡。

| SN | 主板/ARM | DSP | 通信/ESP | 可选 ARM 文件 | 可选 ESP 文件 |
|---|---|---|---|---|---|
| SN-A | MAIN-A | DSP-A | COMM-A | ARM-A.bin | ESP-A.bin |
| SN-B | MAIN-B | DSP-A | COMM-A | ARM-B.bin | ESP-A.bin |

只有经固件负责人验证兼容性，才允许文件同时覆盖多个 board_type。不能根据相同销售型号、软件版本、文件名或上报字符串判断通用。

### 3.3 核实与执行保护分开表达

`identity_state`：`unverified`、`verified`、`conflict`、`service_pending`、`retired`。按模块记录原因，任何会影响连接身份或跨模块依赖的冲突同时阻断相关升级。

`protection_level`：

- `registry_verified`：台账已核实；服务端和新版 App 能检查，设备写入前保护未验证。
- `device_enrolled`：设备已有与真实 UID 绑定的工厂身份，登记完成；目标模块更新器保护尚未完整验收。
- `device_enforced`：目标模块的所有入口均验证身份、清单、授权和持久计数；已通过对应板卡实机验收。

只有注册记录不构成设备防误刷证据。SN 是业务标识，也不构成密码学设备身份证明。新能力位只能作为观测，必须与登记、固件构建及实机验证记录一致。

## 4. 数据模型与权限

### 4.1 新增和扩展的数据

| 表/对象 | 主要字段 | 约束与职责 |
|---|---|---|
| hardware_board_types | id、target_chip、board_code、revision_label、description、status | `(target_chip, board_code)` 唯一；停用类型保留历史 |
| device_hardware_registry | sn、verified_model、device_uid、identity_state、identity_revision、source、evidence_ref、verified_by、verified_at | SN 唯一；与账号绑定分离；未联网设备也可建档 |
| device_hardware_modules | sn、target_chip、board_type_id、board_uid、module_revision、state、evidence_ref | `(sn,target_chip)` 当前记录唯一；不存在模块显式标记 absent |
| device_hardware_history | sn、前后修订、模块差异、action、reason、actor、evidence_ref、created_at | 只追加；记录出厂核实、纠正、换板、冻结和解冻 |
| device_hardware_observations | sn、observed_device_uid、reported_model、target_chip/scope、reported_board_code、reported_board_uid、bootloader/layout/capabilities、source、reported_at、raw_digest | 保留原始意义；最新观测和有保留期历史；不改注册身份 |
| firmware_board_types | firmware_id、model、target_chip、version、board_type_id | 保证关联目标一致；同型号/目标/软件版本/板卡类型只关联一份固件 |
| hardware_import_batches / hardware_import_rows | 文件摘要、操作者、预览结果、逐行原始值、验证错误、提交状态 | 幂等导入、逐行审计、冲突不覆盖 |
| ota_install_authorizations | authorization_id、sn、target_chip、identity/module/binding_revision、firmware_id、manifest_digest、install_sequence、time_policy、issued_at、expires_at、status | 服务端登记发放和撤销；不是设备实际消费状态的替代品 |
| ota_identity_counters | 稳定 device_uid/SN 锚点、身份修订、模块授权序号 | 独立保留；删除/重建设备不重置序号 |
| devices 扩展展示 | verified_model 摘要、identity_state、reported_hardware_version、reported_model | 旧 hardware_version 仅保留历史/兼容展示；不得继续作为新版 OTA 权威来源 |
| firmware_versions 扩展 | compatibility_schema、manifest_version、manifest_digest、signature_key_id、签名清单、最低能力/布局/Bootloader、依赖要求 | `legacy_system` 与 `module_board` 明确区分；发布后清单不可变 |
| device_upgrades 扩展 | 身份/模块/绑定修订快照、board_type/board_uid、manifest_digest、authorization_id、preflight_reason、verification_level、实际版本/摘要 | 当前档案不反写历史；旧记录保持原样 |

身份和授权序号不依赖 `devices` 表物理生命周期。删除设备、换账号、重新绑定不能恢复旧授权的有效性。跨表唯一性通过明确外键/复合键或事务内约束实现，不能只依靠前端检查。

全局身份修订用于任何档案修改后的云端任务重验。模块修订用于设备本地执行的目标身份和依赖集合核验。账号绑定修订沿用现有机制，身份修订不能与绑定修订混用。

### 4.2 权限

新增独立权限：`hardware:view`、`hardware:import`、`hardware:verify`、`hardware:service`、`hardware:freeze`、`ota:offline-authorize`。权限命名与当前 RBAC 注册方式适配，Gateway 和 API 使用同一授权规则。

初期只有系统管理员拥有档案修改权限；后续可显式授予生产/售后人员，不能因为是安装商就默认允许。终端用户查看本机核实状态并升级，不可修改硬件类型、UID 或审核状态。

核实写入必须包含证据和原因，使用 expected_revision 做乐观锁。导入者能按被授予的权限核实；首版不引入全员双人审批，但已有核实档案的纠正/换板必须走独立审核流程。审计与档案变更同事务提交。

## 5. 台账导入、核实和上报冲突

### 5.1 台账导入

推荐字段：sn、model、arm_board_code、arm_board_uid、dsp_board_code、dsp_board_uid、esp_board_code、esp_board_uid、bms_board_code、bms_board_uid、生产批次、来源编号。缺 UID 不伪造；缺板卡记录不按上报或软件版本补齐。

流程：上传 CSV/XLSX → 解析到 staging → 校验 SN/型号/板卡目标 → 展示新增、相同、重复、冲突、缺字段 → 用户明确选择有效行提交 → 有核实权限者按台账证据确认。

每批最多 10,000 行，提交按不超过 500 行的事务块处理，每行结果可追踪，整批不是原子事务。文件摘要和逐行自然键确保重复提交不产生额外修订。冲突和无效行不得自动落入 verified。已确认记录不同值必须进入纠正/换板流程，不支持“导入覆盖”。

导入只建立硬件档案，不调用普通设备 Create，不创建账号归属、不改 station、不重置 device_key，不把未接入设备标成在线。软删除设备的档案仍保留，是否重新开放升级由设备和档案生命周期共同决定。

### 5.2 上报处理

通信服务写入 observations。Business API 根据已有可信档案计算对比结果和阻断原因。上报接入的 SN 必须以已认证 MQTT/本地会话身份为锚点；payload SN 不一致记身份冲突，不按 payload 任意切换设备。

比对字段必须有 scope。当前整机 hardware_version/ARM 只读值保留 `legacy_system` 或经验证的实际语义，不自动复制到四个模块。目标/板卡明确且来源可信的值才进入模块比对。

| 档案与观测 | 处理 |
|---|---|
| 没有档案，上报有效 | 创建待核实线索，不自动核实，不开放 OTA |
| 已核实，明确目标观测一致 | 保持 verified |
| 已核实，旧设备无对应字段 | 标注 observation_missing；按保护等级处理，不能宣称已实物确认 |
| 明确 UID、型号或模块身份冲突 | 置 conflict，停止新的相关任务/授权，告警并核查 |
| 空值、缺失、解析异常 | 不覆盖、不推断、不清空已核实值 |
| 重复旧包或更早时间戳 | 留存证据；不回退最新身份状态 |

只有冲突审核才能解除 conflict。设备再次报告正确值不自动清除安全冻结。已证实旧固件报告错误时，可登记限定 SN、模块、来源、报告值及固件构建的 exception；它只忽略该特定低可信观测，不更改 board_type，不豁免实际 UID/更新器身份冲突。升级后重新验证，异常登记到期或固件构建改变就失效。

## 6. 固件库与统一升级判定

### 6.1 固件发布

上传选择销售型号、目标模块、明确板卡范围，并提供真实文件摘要与适用 Bootloader/布局/能力/依赖。V2 固件必须带可验证签名，unsigned 仅用于开发隔离环境，不能发布到受保护设备。

草稿可修改范围。发布冻结文件、范围、清单和构建身份；后续修改必须创建新构建记录。芯片 version 是软件版本，现有 main_version 是发布编号，firmware_id/摘要标识真实构建。首版保留同型号/目标/软件版本/板卡类型的唯一约束：不同板卡可拥有同 version 的不同文件；同一板卡需要更换已发布文件时，必须使用新的芯片 version，不能仅增加 main_version 绕过约束。停用和灰度属于发行策略，可变更但不改变签名清单。

现有 hardware_versions/firmware_hardware_versions 保留 legacy_system 语义。历史范围不会自动等价为 module_board。升级到新矩阵前，固件负责人必须核实它对应的实际目标板卡并登记证据；禁止直接把整机 HW1 当成通信板 HW1。

新查询优先使用 module_board；未完成范围核实的历史文件只供查阅，不进入可安装列表。旧接口展示可保留，但不影响服务端新校验。

### 6.2 一个判定入口

引入 OTAEligibilityService，输入操作者、SN、目标、firmware_id、通道、动作和档案修订。服务层调用，Repository 提供事务/锁与数据；不在 Handler、App 页面或 MQTT 层复制不同判定规则。

依次检查：权限与归属 → 生命周期/冻结 → 核实型号及目标模块 → 必要跨模块冲突 → 板卡矩阵 → 当前版本/依赖 → Bootloader/布局/能力 → 文件与签名 → 发布/灰度 → 通道和保护等级 → 档案/绑定修订 → 维护停机能力/忙状态。

适用所有入口：可用固件列表、最新版本、任务创建、立即安装、排队执行、重试、回退、离线授权、旧 push/task 路由。force_reason 只能用于已有许可下的软件版本策略，不能跳过硬件、身份、签名、安全版本或停机条件。

错误原因统一返回：`identity_unverified`、`identity_conflict`、`module_identity_missing`、`module_absent`、`firmware_incompatible`、`firmware_scope_missing`、`identity_changed`、`binding_changed`、`device_protection_required`、`bootloader_unknown`、`layout_mismatch`、`dependency_unsatisfied`、`authorization_expired`、`authorization_replayed`、`authorization_revoked`、`maintenance_not_confirmed`、`verification_pending`。实际数值使用 apperr 注册，遵循统一响应格式。

### 6.3 决策表

| 身份条件 | 云端新版入口 | 本地联网 | 现场离线 |
|---|---|---|---|
| 未核实/冲突/模块缺失/范围缺失 | 拒绝 | 拒绝 | 拒绝 |
| registry_verified 旧设备 | 仅受控兼容窗口，明确剩余风险 | 仅授权售后过程 | 首版拒绝发放离线授权 |
| device_enrolled，目标更新器保护未验收 | 受控迁移，不按完整保护发布 | 受控迁移 | 拒绝 |
| device_enforced + 身份一致 + 清单兼容 | 允许 | 允许 | 有有效授权且具备持久防重放能力才允许 |
| 设备无独立目标身份或不能安全停机 | 目标升级拒绝，进入现场核实/维护路径 | 同左 | 同左 |

兼容窗口默认关闭，由系统管理员按确切 SN、目标、文件摘要、维护工单和有效期开放。它不跳过服务器档案检查，只承认设备端保护尚缺；新 App 明确显示“需售后受控操作”。旧 App 的已缓存离线包无法靠云端彻底撤回，该风险直到设备入口保护完成才收口。

## 7. 云端升级、批量与重试

流程：预检 → 创建任务和快照 → 调度时重新预检 → 签发安装授权 → 设备验证清单/身份/授权 → 维护停止与 ACK → 接收和摘要校验 → 安装 → 重启/模块重新上线 → 版本、构建身份和健康检查 → 结果同步。

同设备多个模块的创建是一个数据库事务；任一模块预检失败，整个设备计划不创建。跨设备批量先返回可升级/拒绝明细，用户可明确选择有效设备提交；不能静默跳过。执行过程中模块不是事务原子升级，可能部分成功，需保留逐模块结果。

默认沿用 BMS → ARM → DSP → ESP，通信模块最后；新方案不得未经设备验收改变顺序。固件依赖与该顺序矛盾时，预检拒绝组合，要求另行分阶段迁移。每一步执行前重查依赖和档案，前一步失败即停止后续。

任务快照保存全局身份修订、目标模块修订、依赖模块修订、绑定修订和真实文件身份。排队期间任一相关修订改变，原任务标记 identity_changed，不自动改用新固件；重新创建计划。Redis 只缓存摘要，最终下发读主库，不能用缓存放行。

设备持久化授权消费和升级日志；数据库锁只负责服务器决策，不能锁住物理换板。清单与授权由设备在开始和进入不可逆写入前分别核验，更新期间对目标模块独占，依赖身份发生变化则停止。

重试复用相同文件身份和恢复会话，重新校验资格。未完成的设备内升级可凭同 authorization_id 恢复日志；已结束的重试需要新的授权序号。超时返回结果未知/待确认，不把 100% 传输、下载完成、ACK 或蜂鸣当成安装成功。

## 8. 提前联网准备与现场离线 OTA

### 8.1 准备包

App 联网选择设备和目标 → 云端预检 → 下载固件及不可变 V2 清单 → 校验 SHA256 和签名 → 领取设备专用 InstallAuthorization → 完整缓存后显示“已准备，可离线执行”。

一个准备包由固件文件、签名清单、设备工厂身份证明/注册摘要、安装授权组成。固件文件可按 SHA256 共享缓存，授权必须按设备与目标隔离。文件缺失、摘要不符、授权缺失、身份修订不符均不可安装。首版离线准备只支持单设备、单目标；多目标需逐目标准备，前一步成功并满足下一步依赖后才能开始下一步，不发放可以跳过顺序检查的通用批量包。云端多模块事务与默认顺序保持第 7 节语义。

安装授权绑定 authorization_id、device_uid、SN、verified_model、target_chip、board_code/board_uid、相关模块修订、binding_revision、firmware_id、manifest_digest、install_sequence、time_policy、issuer/key_id。board_uid 缺失的目标不发放完整保护离线授权。跨模块依赖同时绑定依赖 board_uid 和修订。

每设备/目标首版只允许一个未结束的准备授权，避免多手机离线占用同一序号。服务端事务内分配严格递增序号；设备在验证并接受授权时原子保存 reserved 记录并提高 accepted_sequence 高水位，同 authorization_id 的接收重试不视为新授权。新授权必须大于高水位；终止或封存的授权不可复用。

授权状态必须区分如下：

| 设备状态 | 持久记录与允许操作 | 服务端占用释放 |
|---|---|---|
| 未接收 issued | 设备尚未保存授权；查询瞬间未接收不保证随后不会接收 | 必须先让设备持久封存原授权并取得签名取消证明，查询本身不能释放 |
| reserved / receiving | 保存授权、摘要、相关身份和高水位；可重传同文件；不改变安装目标 | 签名取消结果或可信在线状态证明允许取消；已占用序号不回收 |
| consumed / in_progress | 进入不可逆写入前原子保存消费序号、有效性检查结果和恢复日志 | 不允许新授权替代；必须完成恢复或受控维护终止 |
| sealed | 保存成功、失败或取消的签名终态；原序号保持消费/占用历史 | 幂等同步终态后释放，下一次分配更大序号 |
| unknown | 服务端/手机没有可靠设备状态 | 保持占用，不以超时、撤销按钮或 App 删除包自动释放 |

安装前主动取消会封存该授权，accepted_sequence 不降低。接收失败保留 reserved，可恢复同一任务；需要换包时先取得设备取消证明。即使原授权还未接收，也必须发送签名 CancelAuthorizationV1，由设备原子提交该目标高水位至少为原 install_sequence，并封存原 authorization_id，再返回签名取消结果；这样查询之后另一手机再提交旧包也会被拒绝。已 consumed/in_progress 的任务拒绝取消，先恢复到安全终态。

设备已验证取消但服务端未同步时，可缓存签名结果，联网后释放。更高序号授权不能直接抢占现有 reserved/in_progress；服务端已经登记撤销而设备未确认时，禁止首版签发替代授权。新鲜 not_received 查询只用于诊断，不能作为释放依据。此约束避免旧离线包与新授权在两台手机之间竞争。

撤销或新发授权会关闭旧授权的服务端状态，但离线设备尚未收到更新时仍可能接受旧授权。App 再次联网立即刷新并删除撤销包。服务端不得把离线撤销标成“设备已撤销”。

### 8.2 授权期限的两种语义

默认首版使用 `counter_once`：设备校验签名、设备/板卡 UID、修订和单次授权序号；App 提前联网准备的可执行窗口为 72 小时。App 使用签名服务端时间和本机单调时钟检查年龄，重启或时钟锚点失效后要求重新联网核实，不仅依靠用户可调的系统时间。

counter_once 设备若没有可信时间，不能强制验证 72 小时期限；这是一项明确限制。旧包尚未被消费、设备也未收到新修订/序号时，设备端可能仍接受它。只有接受这一离线限制的板卡发行策略才允许该模式，后台显示“单次授权；设备无法独立验证时限”。

若产品要求严格设备端过期，采用 `strict_time`：只有具备经验证、重启后不回退的可信时间能力的设备可以领取；设备在接收授权和开始不可逆安装前校验 expires_at。无可信时间返回 offline_expiry_unsupported，不能降级为仅 App 检查。严格时间仍不能即时收到云端撤销，只能保证期限和联网刷新边界。

期限约束的是开始不可逆安装的时刻。已经在有效期内完成 consumed 持久提交的安装，可以在过期后恢复同一授权、UID、修订和摘要，或完成预先验证的安全回退；这不是新安装授权。仅 reserved/receiving 尚未消费的包过期后禁止开始安装，应安全取消并封存。掉电后可信时间失效但消费日志完整时允许只恢复原安装；消费日志/身份/计数损坏进入 recovery_required，不能利用时间失效接收新文件。

离线风险窗口内不承诺云端紧急停用立即生效。存在紧急安全风险的固件/设备由发行策略禁发 counter_once，要求联网执行或 strict_time。时间要求与单调序号的区别参考 RFC 9124 §4.3.1/§4.3.3。

### 8.3 现场连接与安装

1. 用户选择已准备设备，建立已鉴权 BLE/WiFi 会话。广播名、热点名和用户选择的 SN 不能证明设备身份。
2. App 对设备发送 32 字节随机挑战；设备用登记密钥签名挑战、会话上下文、UID、目标板卡集合和修订。App 验证工厂身份证明和挑战响应，拒绝复制 INFO 或仅同名 SN。
3. 验证连接设备 UID、目标板卡 UID、修订、绑定状态和授权一致；设备也独立执行相同绑定检查。
4. 将清单和授权送入公共 OTA 管理器，设备返回 preflight 结果，成功后才传文件。
5. 进入维护状态并等待可验证停机 ACK。文件只写安全暂存区域，完整摘要校验后才进行目标安装。
6. 设备持久化消费序号和恢复日志，再进入目标擦除/安装；掉电后只能恢复同一授权和摘要，不能借恢复状态安装另一文件。
7. 安装后读取真实目标版本和构建摘要/ID，执行健康检查，生成设备签名结果。App 本地显示完成状态并保存待同步结果。

WiFi 本地入口复用设备绑定鉴权，不能保留任意热点连接即可升级的开放写入路由。BLE 的现有 device_key 和 OTA 独占机制继续使用；绑定鉴权与工厂身份挑战各有职责。

恢复网络后 App 上报 authorization_id、设备签名结果、实际版本/摘要、消费序号及修订。服务端幂等存储结果，拒绝把当前归属或当前型号代入历史授权。绑定变更后仍可接收可信历史结果用于审计，但不允许该用户重新执行升级或获得新权限。

## 9. V2 清单、授权与设备工厂身份

### 9.1 签名对象与设备持久状态

| 对象 | 签名者 | 绑定内容 | 用途 |
|---|---|---|---|
| FirmwareManifestV2 | 固件发布签名者 | 型号、目标、版本、板卡范围、大小/摘要、安全版本、Bootloader/布局/能力/依赖 | 证明文件真实且适用于该类板卡 |
| InstallAuthorizationV1 | OTA 授权签名者 | 具体设备/目标/修订、清单摘要、操作类型、授权序号和时间策略 | 证明这台设备获得本次安装许可 |
| FactoryIdentityV1 / 更新证书 | 工厂/售后身份签名者 | 真实 device_uid、SN、型号、模块 board_uid/board_code、身份修订、公钥 | 把业务档案与具体硬件连接起来 |
| BindingStateV1 | 绑定管理签名者 | device_uid、SN、binding_revision、绑定状态、凭据版本 | 可信地更新设备当前账号绑定修订 |
| CancelAuthorizationV1 | OTA 授权签名者 | 原授权 ID、device_uid、SN、目标、原清单摘要和授权序号 | 设备持久封存未安装授权，防止撤销查询后的竞争 |
| IdentityChallengeV1 / InstallResultV1 | 登记设备密钥 | 随机挑战及会话身份，或授权与实际安装证据 | 连接身份证明、授权状态确认与历史结果 |

各对象使用独立用途标签、key_id 和信任权限。优先沿用已用 Ed25519 算法，发布、身份和授权密钥分别管理；私钥不进入 App、普通配置、仓库或日志。绑定签名能力适配现有绑定机制，仍使用独立用途域。服务端通过受控签名接口取得签名，事务登记授权后才能交付；失败不重复分配相同序号。

| 设备持久状态 | 可信写入来源 | 单调性与存储 |
|---|---|---|
| SN、model、device_uid、identity_revision、模块身份与 module_revision、公钥 | 工厂/售后签名 FactoryIdentityV1；UID 必须等于实际设备 UID | 独立身份区双记录提交；新身份修订严格增加；未变模块可保留模块修订，变更模块必须增加 |
| binding_revision、绑定状态、凭据版本 | BindingStateV1；验证绑定用途信任钥及 UID/SN | 独立持久状态；新修订严格增加；相同摘要同修订幂等，其余拒绝 |
| accepted_sequence、consumed_sequence、授权日志 | 通过签名、身份和策略校验的 InstallAuthorizationV1，由公共更新器写入 | 原子双记录/事务日志；只增不减；恢复出厂和普通 OTA 不清零 |
| 最低协议策略、最低安全版本 | 已认证、符合平台安全机制的受保护策略更新/Bootloader 状态 | 不允许普通安装授权降低；能力报告不写此值 |

身份更新必须绑定 expected_identity_revision，防止跨修订覆盖。普通运行期间仅接受不改变实际板卡集合的核实更新；板卡/型号/UID 变更进入物理维护会话，由售后权限和工单签发更新。相同身份修订且完全相同摘要可幂等，其余同修订或更低修订拒绝。存在 consumed/in_progress 时禁止修改身份或绑定，先恢复到安全终态；无法恢复则进入有线维护，不以修改修订绕过日志。

BindingStateV1 不携带明文用户密钥；关联凭据沿现有安全配网/绑定通道更新，只有凭据版本和绑定修订原子一致后才开放升级。解除绑定、设备转移和重新绑定由可信绑定服务签发，旧 App 的普通 INFO 不能写修订。设备未收到新绑定状态时适用第 8 节离线撤销限制。

V2 和受保护授权强制验签。V1 只能进入明确的迁移窗口，不能被解释成 V2。设备按本地持久策略要求最低协议版本，旧客户端请求 V1 时拒绝，能力报告丢失不能使策略回退。

### 9.2 规范编码与容量

签名负载采用固定字段顺序的 UTF-8 ASCII 行格式，LF 换行，严格长度，十进制整数，无前导零，摘要小写十六进制。标量只能用对应字段白名单；拒绝 CR、换行注入、重复字段、未知字段、非标准 Base64、空必填字段。数组排序、去重，以逗号分隔，元素不允许逗号。

用途标签分别为 `CS_INV_OTA_V2`、`CS_INV_INSTALL_AUTH_V1`、`CS_INV_FACTORY_ID_V1`、`CS_INV_BINDING_STATE_V1`、`CS_INV_CANCEL_AUTH_V1`、`CS_INV_IDENTITY_CHALLENGE_V1`、`CS_INV_INSTALL_RESULT_V1`。不对 JSON 序列化结果直接签名。JSON 是展示/HTTP 外层，验签以明确 canonical_payload 字节为准，外层重复字段必须与负载一致或拒绝。标签占第一行，后续每行 `key=value`，末尾保留 LF；签名作为外层字段，不进入自身负载。

下表顺序即签名字段顺序。每个列出的字段必须出现；只有注明可空的字段允许空值。签名者根据 key_id 选择已登记的用途公钥；key_id 不改变用途权限。

| 对象 | 字段顺序 |
|---|---|
| FirmwareManifestV2 | manifest_version、key_id、model、target、version、build_number、board_codes、size、sha256、security_version、min_bootloader、storage_layout、required_capabilities、dependency_requirements |
| InstallAuthorizationV1 | authorization_version、key_id、authorization_id、operation、device_uid、sn、model、target、board_code、board_uid、identity_revision、module_revision、dependency_identities、binding_revision、firmware_id、manifest_digest、install_sequence、time_policy、issued_at、expires_at |
| FactoryIdentityV1 | identity_version、key_id、device_uid、sn、model、expected_identity_revision、identity_revision、modules、device_public_key、device_key_id |
| BindingStateV1 | binding_version、key_id、device_uid、sn、binding_revision、binding_state、credential_revision |
| CancelAuthorizationV1 | cancel_version、key_id、cancel_id、authorization_id、device_uid、sn、target、manifest_digest、install_sequence、reason |
| IdentityChallengeV1 | challenge_version、device_key_id、challenge、session_context、device_uid、sn、model、identity_revision、modules、binding_revision、target、board_uid、module_revision、accepted_sequence、active_authorization_id、active_state、result_digest |
| InstallResultV1 | result_version、device_key_id、authorization_id、operation、device_uid、sn、target、board_uid、identity_revision、module_revision、binding_revision、manifest_digest、install_sequence、state、observed_version、observed_build_number、observed_sha256、health_result、reason |

版本/修订/序号/大小/构建编号为无符号十进制整数：协议版本和安全/构建编号 uint32，修订/序号/文件大小 uint64；身份修订从 1 开始，工厂首次登记 expected_identity_revision=0。UID 是规范小写十六进制 16..64 字符，真实芯片 ID 按固定编码转换；未具备相应长度的旧 ID 需经生产登记建立稳定 UID，不能简单填零。公钥是 32 字节小写十六进制，挑战/会话上下文为 32 字节小写十六进制，摘要为 32 字节小写十六进制；签名为 64 字节规范 Base64。文本标识遵循固定 ASCII 白名单并设长度，外层不接受任意 JSON 对象代替记录。

modules 与 dependency_identities 是按目标排序的记录数组，记录格式 `target:board_code:board_uid:module_revision`，记录用逗号分隔，内部冒号不允许出现在字段值中；每目标最多一条。modules 至少含通信板和实际升级目标，最多四条；dependency_identities 可空，必须精确覆盖清单中依赖目标的当前身份。不存在模块不写入 modules，不能用伪造 UID 占位。

dependency_requirements 是按目标排序的数组，记录格式 `target:board_code:min_build_number:min_protocol_revision`，每依赖目标一条，最多四条，可空。最小构建号是针对明确板卡类型的功能兼容序号，不与安全版本或安装授权序号混用；同板卡发布构建号严格增加。新固件必带 build_number，目标实际读回并有构建身份映射；旧模块没有这些属性时先走受控能力迁移。首版采用精确依赖 board_code，不引入复杂 OR 表达式；不同依赖板卡组合签发不同不可变清单。

board_codes、required_capabilities 使用排序去重的 ASCII token 数组，后者可空；board_codes 不可空。target/数组排序固定 arm、bms、dsp、esp，仅用于规范编码，执行顺序仍是第 7 节顺序。min_bootloader 使用已登记的 uint32 可比较编号，storage_layout 使用准确 ASCII 布局 ID。软件 version 仅为显示/唯一性标签，跨模块最低依赖用 build_number/protocol_revision 判断，不按自由文本排序。

operation 为 install 或 rollback；time_policy 为 counter_once 或 strict_time。issued_at、expires_at 为 UTC Unix 秒；strict_time 两者必须为正且 expires_at>issued_at，counter_once 的 expires_at 仍表达 App 的准备窗口，设备不具备可信时间时不声称能执行该时间限制。observed_version/observed_sha256 在未验证/拒绝/取消结果可空，observed_build_number 未知编码 0；健康结果为 pass、fail、unknown，未知值不能冒充成功。active_authorization_id 无活动授权时可空，active_state 为 idle、reserved、receiving、in_progress 或 recovery_required，idle 的 accepted_sequence 仍保留高水位。

会话上下文由当前已鉴权通道的握手 transcript 摘要生成，挑战一次使用，签名响应必须含收到的挑战/上下文，禁止跨连接重用。accepted_sequence、active_authorization_id 和 active_state 均指响应 target，不把 ARM 高水位当成 ESP 的高水位。普通身份查询 result_digest 可空；为查询某授权状态，设备返回 InstallResultV1，本次 IdentityChallengeV1 的 result_digest 必须为该结果 canonical_payload 的 SHA256，不能用旧取消结果证明另一个新授权尚未执行。state=not_received 只表达查询瞬间，服务端不得据此释放占用；释放需要封存的 succeeded/failed/cancelled 结果。

CancelAuthorizationV1 必须绑定真实 device_uid/SN 和原授权 target/id/序号/摘要，验证 OTA 授权用途签名；设备在未接收/接收但未消费时原子封存并提高高水位，已封存同一对象幂等，不能降低高水位，也不能取消另一活动任务。取消未接收授权时，消息必须同时提供完整原签名 InstallAuthorizationV1，设备验签并逐项核对取消对象，由原授权保存板卡 UID、各修订和 operation 快照，不能凭空重建结果。取消对象不授权写固件，不受原安装期限限制。安装中拒绝取消；重复取消只能返回同一封存结果，绝不解除 consumed 日志。设备取消结果保留原授权身份快照和摘要，实际构建证据可空，避免把取消冒充安装成功。

一致性比较：授权 manifest_digest 等于收到清单 canonical_payload 的 SHA256；清单 model/target/board_codes 匹配核实身份和授权；授权 board_uid/module_revision 匹配工厂证明及现场独立读取；依赖记录匹配清单所需类型和真实目标读回版本；identity_revision/binding_revision 与设备持久状态完全相等；firmware_id 由服务端绑定文件，但设备最终以清单 SHA256 验证真实文件。任一不一致拒绝，不能以外层值覆盖已验签负载。

每清单最多 16 个 board_code、每编码最多 50 字节；超过范围拆为多份不可变清单，共用文件但分别签名。单个签名对象含签名总长不超过 4096 字节；工厂证明按本机实际模块最多四个记录，不发送全目录。依赖最多四目标，所有字段有固定上限，超限在发布/签发阶段拒绝。

现有旧控制帧不能容纳这些对象。新版 capability `ota_manifest_v2_chunked` 声明固定 4096 字节对象接收上限和实际分片上限。BLE 使用新对象上传阶段，单帧不得超过当前协议和 MTU 允许值；HTTP 使用有总长上限的请求；MQTT 可携带小对象或使用摘要绑定的 HTTPS 对象地址。完整重组、校验长度/摘要/签名后才进入升级 preflight，绝不向旧 512 字节缓冲塞长数组。

Go、Dart、C 和签名工具共享契约及正反测试向量。测试包括排序、大小写、重复字段、超长、换行、签名错误、不同对象域签名替换和 V1/V2 混淆。

### 9.3 工厂身份与实际目标

通信模块的工厂信息保存在独立分区，普通 OTA、恢复出厂设置、WiFi 配网不得重写。应用只读访问不等于能抵抗任意恶意固件；如果要求抗篡改，需要安全启动、写保护和密钥保护配合。首版目标是防操作误刷和未授权入口，不宣称阻止物理克隆或任意硬件攻击。

出厂登记：读取实际芯片 UID/板卡 UID → 按台账组装身份 → 签发工厂证明 → 写入独立身份区 → 回读及重启核验 → 服务端登记一致证据。身份凭证不随普通固件复制，同一设备私钥不能批量克隆。

每个升级目标必须有独立可核验 board_uid/board_code。可使用不可随应用升级改变的 Bootloader 身份、生产写入受保护标识或经验证的板卡读取机制。运行应用中的固定字符串和从云端下发再读回的字符串不能作为实际板卡识别。

DSP/ARM/BMS 如无法独立验签，可由经验证的通信管理器在独占维护会话中读取目标受保护身份并校验，再执行安装；目标 Bootloader 至少保证身份稳定、写入完整性和安全恢复。若只能读当前应用的可变标识，仍停留在 registry_verified/device_enrolled，不允许完整保护离线升级。

模块独占开始后，安装前重新验证实际目标 UID；物理拆换、断链、目标重启或会话变化使本次 preflight 失效。通信模块自身升级在重启后恢复计数和日志，不能依赖 App 保持授权消费状态。

授权防重放计数和恢复日志独立持久化，不随恢复出厂清零。设备数据库记录删除不重置计数。若整个 Flash 被擦除，设备进入未登记维护状态，重新按实际 UID 核实并提高身份修订，不能自动恢复到最低序号。如何抵抗恢复旧 Flash 快照属于额外抗篡改保护边界，未配置对应能力时不宣称密码学防回滚。

### 9.4 密钥轮换

设备可信公钥槽记录用途、key_id、启用/退役状态。轮换先用当前受信根授权新增公钥，再确认覆盖率，再停止旧钥新签发。旧钥退役策略与已准备离线授权共同审核；离线设备尚未收到退役不能声称已拒绝旧钥。设备根身份与 OTA 发布钥分离，普通 OTA 授权不能更换工厂身份。

## 10. 换板、档案纠正与解绑

换板流程：建立维护工单 → 标记 service_pending → 冻结相关新任务和授权 → 记录旧 UID 与实际新板照片/生产记录/读取证据 → 校验板卡组合与依赖 → 提交新模块档案及修订 → 更新设备工厂证明 → 回读、重启和身份挑战核验 → 恢复 verified 并重新预检。

若只是修正台账笔误，走 correction 流程，仍增加修订并记录依据；不得假装发生物理换板。模板、编码和型号映射纠正也会使相关旧任务失效。

设备离线换板后，旧授权应因新实际 board_uid 不匹配被拒绝。若维修仅改云端、没有同步设备身份，则设备不能成为新版可升级状态；不得把云端 verified 误当作设备已登记。

更换通信板意味着新的 device_uid 和密钥，旧授权不能转移。授权占用按 device_uid/target 管理；旧通信板不可取得取消证明时，保留原授权未确认状态，并记录 retired_device_uid，不能虚报旧板已撤销。新通信板完成有线维护登记、提高 SN 身份修订并验证新 UID 后，使用新的 UID 授权空间；旧包不能在新板执行。更换主板/DSP/BMS 后增加目标和依赖修订；旧授权的单次序号不能在新板重新从零有效。不可恢复的在途日志由有线维护流程安全恢复/封存后再重新登记，不能由普通 OTA 或云端编辑清除。

解绑/转移增加 binding_revision，在线任务和授权重验，设备收到签名绑定更新后拒绝旧修订授权。未收到更新的离线设备存在撤销延迟，按第 8 节边界处理。恢复出厂只清普通用户配置，不清硬件身份和防重放状态。

## 11. 回退、掉电和成功判定

### 11.1 回退

回退按当前实际模块身份重验，不按历史字符串放行。选择旧 firmware_id/摘要，重新签发更大的 install_sequence；安装序号不能随软件版本降低。硬件范围、Bootloader/布局和依赖仍须满足。

security_version 使用目标安全机制的独立语义，授权不能降低设备已固定的最低安全版本。普通安全回退只能回到仍满足安全下限的已验证镜像；不满足时返回 rollback_security_blocked，转现场恢复路径。

ESP 双分区可在 Bootloader 机制支持下进行试启动/健康确认。ARM/DSP/BMS 必须逐目标确认双槽、恢复 Bootloader、暂存及重试能力。没有安全恢复能力时，不承诺自动回退，也不能进入普通无人值守发布范围；允许的维护升级必须具备现场恢复方案。

### 11.2 设备状态机

`idle → preflight → maintenance_confirmed → receiving → verified → installing → rebooting → validating → succeeded`。预检后进入维护并确认停止，再接收文件；通过完整摘要校验后才允许目标安装。

拒绝发生在 preflight；接收失败可安全重传；进入不可逆写入前持久化授权序号和日志。掉电恢复只匹配同 authorization_id、target、SHA256、UID 和修订；计数或日志不一致进入 recovery_required。未完成授权保持 in_progress，不能同时签发第二个目标任务覆盖它。

现场离线超时不自动重新擦写，App 可重新连接查询日志并恢复同一任务。strict_time 在消费前到期禁止安装，在有效期内已消费的同任务可依持久日志恢复，第 8.2 节规则优先于重新开始时限。自动回退由设备自己的已验证恢复机制决定，不依赖手机持续连接。

### 11.3 成功证据

| 证据级别 | 展示与数据库语义 |
|---|---|
| 上传或传输 100% | 已传输，仍待安装确认 |
| 设备安装完成消息但未重新读取目标 | 安装已报告，verification_pending |
| 读取目标版本，且版本唯一对应构建 | version_confirmed；旧设备限定证据 |
| 目标实际运行摘要/受保护构建 ID 对应文件，健康检查通过 | build_confirmed；新版成功验收 |

同版本多硬件构建场景，版本字符串不足以证明文件身份。摘要必须来自实际运行/已写入镜像或受保护的构建标识，不能从请求清单复制。fallbackVersion 仅用于“目标版本”展示，禁止作为实际安装版本同步。

健康检查按模块明确：重新上线、UART/MQTT 通信稳定、目标版本/构建读取成功、关键功能初始化及无新的致命故障。不同板卡须在发布验证中确定具体超时和观察周期，未提供健康策略的板卡不能开放 device_enforced 发布。软件测试、CI/CD 或传输比例不代替实机验收。

## 12. API、契约与界面

### 12.1 新增 API 草案

全部以 `/api/v1` 为前缀，遵循 code/message/data 和标准分页；具体数值错误码通过 apperr 注册。以下是设计接口，不是已经存在的接口。

| 方法与路径 | 功能 | 权限/关键约束 |
|---|---|---|
| GET /hardware/board-types | 查询板卡目录 | hardware:view |
| POST /hardware/board-types | 建立类型 | 硬件管理权限；稳定编码不能复用 |
| POST /hardware/imports | 导入预览 | hardware:import；staging |
| POST /hardware/imports/:id/commit | 提交指定有效行 | 幂等键；不得覆盖核实记录 |
| GET /hardware/devices/:sn | 当前档案和观测摘要 | 范围访问控制；普通用户只读本机 |
| POST /hardware/devices/:sn/verify | 台账核实 | hardware:verify；证据、expected_revision |
| POST /hardware/devices/:sn/corrections | 纠正档案 | 核实权限；前后差异与原因 |
| POST /hardware/devices/:sn/service-changes | 售后换板 | hardware:service；expected_revision |
| POST /hardware/devices/:sn/freeze | 冻结/解除冻结 | hardware:freeze；解除必须有核查结论 |
| GET /hardware/devices/:sn/history | 历史 | 分页与范围控制 |
| POST /ota/preflight | 单机/多模块预检 | 当前 OTA 操作权限；返回逐模块原因 |
| POST /ota/offline-authorizations | 创建准备授权 | ota:offline-authorize + 设备操作权限 |
| POST /ota/offline-authorizations/:id/revoke | 申请撤销 | 标明服务端撤销/设备已确认的差别 |
| POST /ota/local-results | 幂等同步签名结果 | 授权与历史结果规则；无权改档案 |
| PUT /ota/firmware/:id/board-types | 草稿/历史首次核实范围 | 固件管理权限；发布清单不可变 |

现有 firmware-overview/resources/trigger/history/task 接口扩展 identity_state、protection_level、逐模块 board_code、兼容原因、证据级别；保持旧字段供旧客户端展示，旧字段不得影响新版权威判断。所有现存旧写入口调用同一服务端资格检查。

新增 `contracts/openapi/hardware-ota-v2.yaml` 和 `contracts/ota/manifest-v2-vectors.json`，记录规范编码、长度、字段规则、错误原因与状态映射。内部观测接口明确 reported_scope 和认证身份，避免只增加四个不明来源硬件字符串。

设备协议提供 identity.challenge、identity.read、ota.object.begin/chunk/commit、ota.preflight、ota.start、ota.query、ota.result；具体 opcode 分配在真实协议契约中集中维护，不在 App 与固件各自猜测。旧协议 opcodes 保持不变，新能力未启用不能向旧设备发送新对象。

### 12.2 后台

在设备详情增加“硬件档案”页签，呈现型号、模块板卡、UID、核实来源/时间、最新上报及差异。新增台账导入预览、待核实/冲突列表、换板工单入口；沿用现有设备权限与布局，不另建整个管理系统。

固件上传按目标筛选板卡范围，发布确认显示文件摘要和实际兼容板卡。批量升级预检先显示可升级数、拒绝数和原因，逐设备结果可追踪。

升级历史同时显示当时身份和当前身份，不把当前配置写回历史。显示“已传输/待设备确认/已验证完成/需现场恢复”，避免把 100% 当成功。

### 12.3 App

普通用户看到模块当前版本、可用版本和清晰阻断说明；不出现可以覆盖硬件的选择框。管理员/售后只在授权界面核实，不能在升级弹窗临时改硬件。

新增“准备离线升级”：选择已核实设备 → 预检 → 下载与验签 → 准备完成。显示设备、目标、文件版本、准备窗口、单次授权和离线限制。现场连接自动验证，用户无需自己比较硬件版本。

旧缓存无板卡清单或授权不可执行，保留删除和联网重新准备。结果待同步单独显示，不把云端同步失败改成设备安装失败。换板、UID不一致、授权已消费时给出具体操作指引。

## 13. 实施边界、顺序与上线控制

### 阶段 A：可信档案与云端闭环

新增数据模型/权限/导入/核实；上报与档案分离；修复普通接口字段映射；统一资格判断；现有任务快照与重验；后台档案/冲突界面；固件范围逐份核实。

交付标准：新旧云端写入口均不能用上报覆盖身份或绕过兼容；未知/冲突设备拒绝；台账导入不改变账号归属。此阶段不宣传设备已防误刷，也不发新版离线授权。

### 阶段 B：真实固件登记和更新器保护

逐硬件族确认源码、目标芯片、分区和恢复路径；实现工厂身份、目标板卡读取、V2 对象传输、公共校验、防重放持久状态和结果证据。先对一类已确认板卡完成全链实机验证，再扩大范围。

旧设备首次升级使用经台账与现场证据确认的迁移固件，不允许“随便刷一个通用版本再识别”。没有可靠身份/暂存/恢复路径的模块先走有线维护登记，不能靠 OTA 自动补造身份。通信 App OTA 不迁移分区；若缺独立身份或日志空间，需要受控有线分区迁移并保留设备身份。

### 阶段 C：新版 App 与现场离线

新增准备包和授权，接入工厂挑战和 V2 通道；准备/连接/安装/证据/同步完整回归。只有 B 阶段通过验收的设备/目标启用离线。默认 counter_once 适用性由发行策略明确批准；strict_time 需额外可信时间验证。

### 阶段 D：扩大范围与收紧旧入口

按板卡族扩大，再逐步关闭兼容窗口。设备本地策略要求 V2 和授权，旧 App 不能退回 V1。旧硬件没有对应保护能力时继续显示受控维护状态，不能用云端“全量开启”隐去能力缺口。

拟定分阶段开关：可信档案校验、按板卡族启用 V2、按 SN/目标开启兼容窗口、离线授权允许列表、strict_time 要求。开关不可用于跳过未知身份/冲突。

服务回退保留新表/档案/计数，不执行破坏性 down migration。回退到仍读取可信档案的兼容版本；若无法保证则暂停 OTA 写入口，不能恢复到信任上报的旧判断。设备持久 V2 策略不随服务回退关闭。

### 涉及代码与文档的边界

| 范围 | 改动方向 |
|---|---|
| database/schema.sql、后续新增 migrations | 只增加新表/字段/约束；保护历史、130 等并行改动 |
| business-api/internal/model、repository、service、handler | 身份模块、资格判定、授权、任务证据；Handler → Service → Repository |
| business-api/cmd/main.go、api-gateway 权限路由 | 接入依赖、注册新权限/接口 |
| device-communication/internal/service、mqtt | 认证 SN 锚点、模块观测、V2 对象和状态转发；不自行核实硬件 |
| inv-admin-frontend/src/pages/devices、pages/ota、services、types、locales | 档案、导入、冲突、范围与任务证据 |
| inv_app/lib/features/ota、core/services、core/errors、l10n | 准备包、签名/身份验证、授权缓存、离线恢复与真实结果 |
| contracts/openapi、contracts/ota | 接口与规范测试向量 |
| 真实 ESP/ARM/DSP/BMS 工程 | 公共更新器、工厂身份、实际板卡读取和恢复；先确认真实源码，不修改外部副本冒充部署 |
| docs | 实施分阶段计划、操作手册、现场验收和恢复手册 |

当前工作区有其他未提交工作。实施时使用限定文件清单和独立验证目录，不清理/覆盖既有改动。生产迁移、发布和设备刷写在评审通过后的实施任务中按明确授权执行。

## 14. 验证、验收与交付物

### 14.1 必须覆盖的行为

| 场景 | 预期 |
|---|---|
| 同型号不同主板，相同 DSP/通信板 | ARM 各得其文件，已验证共用模块可共用文件 |
| A 板误报为目录中的 B 板 | 不改核实档案；明确目标冲突阻断 |
| 整机/ARM 只读值不明含义 | 不复制为 DSP/ESP/BMS 身份 |
| 仅软件版本/文件名相同 | 不据此合并文件身份或标成兼容 |
| 导入重复、并发核实、冲突行 | 无重复修订、无静默覆盖、无归属变更 |
| 空报、旧包、重复包 | 不清档案、不回退状态、不伪造零/缺失值 |
| 定时任务排队期间换板/解绑 | 原任务失效，重新预检；旧快照保留 |
| 强制、重试、回退、旧 push/task 接口 | 无硬件/签名/身份绕过 |
| 未知 Bootloader/布局/目标能力 | 拒绝对应保护升级 |
| 本地连接同 SN 的不同 UID、伪造 INFO | 挑战/UID/证书或目标检查拒绝 |
| WiFi/BLE/MQTT 任一旧写入口 | 设备公共校验阻止绕过 |
| 离线包换目标、换设备、改清单、错摘要 | 设备拒绝，目标分区不擦除 |
| 重复授权、两手机同时执行 | 独占与持久计数拒绝重复执行 |
| 接收/计数提交/擦写/重启期间掉电 | 恢复同任务或进入可恢复维护状态，不安装另一文件 |
| counter_once 手机时钟倒退/重启 | App 要求重新核时；设备端时限能力限制明确展示 |
| strict_time 无可信时钟/时钟回退 | 拒绝，不降级 |
| strict_time 安装前到期/安装中到期并掉电 | 未消费拒绝；已在有效期消费的同任务可恢复，不接收新文件 |
| 接收失败、取消、结果未知、签发替代授权 | 高水位不退；同文件可恢复；取消须设备确认；未知结果不释放占用 |
| 未接收查询后另一手机提交旧包 | 查询不能释放占用；持久取消后旧包拒绝，才可签发替代授权 |
| 工厂/绑定更新重放、修订降低、在安装中更新 | 拒绝；同摘要同修订幂等；安装先恢复安全终态 |
| 云端撤销时设备离线 | 展示服务端撤销但未到达设备，不虚报已失效 |
| 服务/设备恢复出厂、删除重建 | 档案与序号不复位，旧授权不重新获得有效性 |
| 同版本不同文件安装 | 需要实际构建/摘要证据，不能靠版本字符串确认 |
| 100% 后掉线、仅有 done/fallbackVersion | 待确认，不写入未经验证的实际版本 |
| 低于安全版本回退 | 拒绝；不能用新授权绕过安全下限 |
| 部分模块成功、下一模块失败 | 保存已成功结果，停止后续，按验证过的恢复流程处理 |

### 14.2 执行顺序与命令

实施后先运行规范编码向量和判定单元测试，再做独立本地 PostgreSQL 并发/事务/迁移测试，再做客户端与服务联调，最后实机测试。不得使用生产数据库跑集成测试。

仓库根目录最低检查：`make build-go`、`make test-go`、`make vet-go`、`make type-check`、`make analyze-app`。按变化再运行 `make build-web`、`make test-app`。现有 make test-go 只覆盖 API 与 Device；Gateway/Bridge 涉及改动时在各自目录补 `go test ./... -count=1`。

现有硬件兼容集成回归在 business-api 目录运行 `go test -tags integration ./internal/repository -run '^TestOTAHardware' -count=1 -v`，只使用独立本地 TEST_OTA_HARDWARE_DSN。新模块身份与授权数据库测试应采用同一隔离方式。

真实设备必须至少包含同型号两个不同板卡配置、一个旧设备、一次通信板/目标板换板、一个离线案例。每个允许升级的 target 都需验证准确身份、正常升级、错误板卡拒绝、断链、掉电、重启读回和恢复；DSP/BMS 最终 ACK、CRC、版本/构建读回不能由 ESP 发送比例代替。

交付物：核实台账及冲突处理记录、固件板卡矩阵证据、规范与测试向量、后端/Web/App 版本与摘要、实际固件构建与摘要、按板卡/目标的实机日志、设备登记记录、现场准备/操作/恢复手册和逐阶段放行清单。

## 15. 架构风险检查与发布门槛

| 领域 | 等级 | 发布门槛 |
|---|---|---|
| 身份/数据一致性 | Critical | 上报不覆盖档案；目录存在不代表核实；换板修订闭环 |
| 兼容/签名 | Critical | 范围含明确模块板卡；V2 签入范围；所有入口共用校验 |
| 设备可靠性/恢复 | Critical | 目标独立身份、停机、写入完整性与恢复机制实机通过 |
| 离线授权/权限 | Critical | 绑定真实 UID/修订/单次序号；无设备保护不发完整离线包 |
| 协议容量 | Critical | 4096 字节有界对象、分片/重组/长度拒绝在实际缓冲验证 |
| 成功证据 | Important | fallback/传输比例不冒充实际安装，版本/构建/健康证据分级 |
| 时间/撤销 | Important | counter_once 与 strict_time 明确区分；不声称离线即时撤销 |
| 运维/发布回退 | Important | 服务回退仍守可信档案；保留计数与身份，不降级到上报判断 |
| 可观测性 | Important | 可追溯冲突、拒绝原因、授权状态、证据层级和逐模块失败 |
| 成本/扩展 | Suggestion | 利用现有服务与台账，首版不新增独立微服务或全员双审系统 |

阶段 A 可以独立发布，必须通过身份/数据门槛；B/C/D 在前置门槛未满足时不得开放对应设备功能。发布数量、灰度比例和生产停机窗口由每阶段实施计划结合实际设备数量确定，不在本设计中猜测。

## 16. 评审记录与参考依据

完整性评审已完成：补齐绑定/身份修订的可信持久来源、签名字段与复合记录规范、接收/消费/封存状态、严格期限下的掉电恢复，以及未接收授权取消与替代的竞争窗口。最终结论：可进入分阶段实施计划。该结论只针对设计一致性，不代表代码、部署或实机验收通过。

- 当前仓库：`docs/superpowers/specs/2026-10-12-hardware-compatible-ota-design.md`、`docs/hardware-compatible-ota-rollout.md`、`database/migrations/129_hardware_compatible_ota.up.sql` 与第 2 节代码触点。
- [RFC 9124 §3.4：以 Class ID 区分固件适用设备类别](https://www.rfc-editor.org/rfc/rfc9124.html#section-3.4)。本设计采用模块板卡编码，不要求引入整套 SUIT 协议。
- [RFC 9124 §4.3.10：兼容标识需要认证](https://www.rfc-editor.org/rfc/rfc9124.html#section-4.3.10)，支持将兼容范围纳入签名。
- [RFC 9124 §4.3.1/§4.3.3：序号、回退与可信时间](https://www.rfc-editor.org/rfc/rfc9124.html#section-4.3.1)，用于区分授权消费和时间过期。
- [Espressif 分区文档：独立只读工厂 NVS](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/partition-tables.html)。只读 API 不等于任意固件不可篡改，实际保护按芯片与部署条件验证。
