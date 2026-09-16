# App / L10 BLE 端到端实施计划

> 执行人员：使用 subagent-driven-development 或 executing-plans 分任务实施。本文是实施计划，不代表已实现或已验证。不得因本文自动提交、推送或部署；这些动作另需用户授权。

**Goal:** 手机断网时可安全直连 L10、展示真实数据、控制并确认参数、升级通信模块和主控，联网后可靠补传操作审计。

**Architecture:** 设备为测量与执行结果的来源；App 共用认证 BLE 会话并按 SN 路由业务；服务器区分手机报告和设备确认。第一期不通过手机补传遥测。

**Tech Stack:** Flutter/Dart、NimBLE/ESP-IDF/C、Go/Gin/PostgreSQL、SQLite。

## 0. 文件树变更清单

路径根：`R=/mnt/d/cs_app_project/cs_inv_monitor-develop/cs_inv_monitor-develop`；`F=/mnt/d/CS_INV_WIFI/esp32c3_l10_idf`。下表路径相对于对应根，仅为文档缩写，不要求设置环境变量。`[A]` 为拟新增，`[M]` 为拟修改；无删除项。新增路径若实施时已存在，先核对归属再调整计划，不能覆盖已有工作。

| 根 | 标记与路径 | 每个文件的落地改动摘要 | 流程 |
|---|---|---|---|
| R | [A] docs/superpowers/specs/2026-09-15-ble-l10-contract.md | 三端协议、状态、授权及兼容规则 | 1 |
| R | [A] contracts/ble/l10-v2-vectors.json | 双端共享认证、分帧、命令与 OTA 黄金向量，不含真实密钥 | 1 |
| F | [M] components/ble_ct/ble_ct.c | 能力信息、连接态、统一访问门禁 | 2 |
| F | [M] components/ble_ct/ble_ct.h | 会话与能力接口 | 2 |
| F | [M] components/ble_ct/ble_ct_auth.c | 双向认证、挑战生命周期、输入界限与敏感日志移除 | 2 |
| F | [M] components/ble_ct/ble_ct_auth.h | 认证状态及会话查询接口 | 2 |
| F | [M] components/ble_ct/ble_ct_cmd.c | 读返回码、命令去重、异步执行结果、参数语义 | 3 |
| F | [M] components/ble_ct/ble_ct_cmd.h | 执行回调与结果码接口 | 3 |
| F | [M] components/ble_ct/ble_ct_telemetry.c | 独立快照、同步保护、MTU 分帧、鉴权读取 | 4 |
| F | [M] components/ble_ct/ble_ct_telemetry.h | 快照发布及质量信息接口 | 4 |
| F | [M] main/telemetry/cmd_handler.c | 云端/BLE 写仲裁、主控 ACK 与回读关联 | 3 |
| F | [M] main/telemetry/cmd_handler.h | 通道上下文及完成通知接口 | 3 |
| F | [M] main/telemetry/telemetry.c | 字段单位、时间与缺失值、脱离 MQTT 的本地采集 | 4 |
| F | [M] main/app/app_main.c | 注册回调、初始化服务；最后由集成负责人合入 | 2–6 |
| F | [M] components/ble_prov/ble_prov.c | 注册并转发 OTA GATT、保持配网入口兼容 | 6 |
| F | [A] main/ota/ble_ota.c | BLE 控制/数据适配、队列与背压 | 6 |
| F | [A] main/ota/ble_ota.h | 初始化、断连、状态通知接口 | 6 |
| F | [M] main/ota/ota_service.c | 生产验签及安全版本、兼容性、最终确认与结果保留 | 6 |
| F | [M] main/ota/ota_service.h | 安全元数据和任务结果接口 | 6 |
| F | [M] main/CMakeLists.txt | 新 BLE OTA 源文件注册 | 6 |
| F | [A] tests/host/CMakeLists.txt | 无硬件协议测试目标及依赖桩 | 2–6 |
| F | [A] tests/host/test_ble_contract.c | 认证、长度、分片及协议向量 | 2、4 |
| F | [A] tests/host/test_ble_control.c | 返回码、队列、主控 ACK/回读、幂等 | 3 |
| F | [A] tests/host/test_ble_ota.c | OTA 帧、偏移、背压、状态与校验拒绝 | 6 |
| R | [M] inv_app/lib/core/services/ble/ble_adapter.dart | 暴露实际 MTU、连接与订阅就绪状态 | 2、5 |
| R | [M] inv_app/lib/core/services/ble/ble_device_manager.dart | 新认证、会话关联、命令生命周期、结果查询 | 2、5 |
| R | [M] inv_app/lib/core/services/ble/ble_polling_service.dart | 首次立即读、去重轮询、超时与错误可观测性 | 5 |
| R | [A] inv_app/lib/core/services/ble/device_live_snapshot.dart | 来源、时间、序号、有效性及业务数据强类型模型 | 5 |
| R | [A] inv_app/lib/core/services/ble/device_live_data_service.dart | 按 SN 汇聚 BLE/既有云端数据；只管理实时源选择 | 5 |
| R | [M] inv_app/lib/core/services/service_locator.dart | 新服务及生命周期注册 | 5–7 |
| R | [M] inv_app/lib/features/device/domain/repositories/device_repository.dart | 声明本地能力、参数与控制结果接口 | 5 |
| R | [M] inv_app/lib/features/device/data/repositories/device_repository_impl.dart | 复用现有仓库，按显式通道调用；不创建平行控制仓库 | 5 |
| R | [M] inv_app/lib/features/device/presentation/bloc/device_bloc.dart | 订阅统一实时源、操作状态及审计协调 | 5、7 |
| R | [M] inv_app/lib/features/device/presentation/pages/device_realtime_page.dart | 来源与过期提示、缺失值显示 | 5 |
| R | [M] inv_app/lib/features/device/presentation/pages/device_control_page.dart | 移除页面直接云端发送依赖，离线能力和参数读取 | 5 |
| R | [M] inv_app/lib/features/ota/data/datasources/ble_communication_service.dart | 统一协议、认证连接、实际 MTU、ACK 与响应关联 | 6 |
| R | [M] inv_app/lib/features/ota/presentation/pages/local_ota_page.dart | 阶段进度、连接独占、失败恢复及状态查询 | 6 |
| R | [M] inv_app/lib/features/ota/data/datasources/local_ota_result_sync_queue.dart | 按账号/任务保存结果，避免版本覆盖代替审计 | 7 |
| R | [M] inv_app/lib/core/services/offline/offline_op_log_store.dart | SQLite 迁移、账号分区、操作事件状态 | 7 |
| R | [M] inv_app/lib/core/services/offline/offline_log_api.dart | 逐 ID 上传回执及错误分类 | 7 |
| R | [M] inv_app/lib/core/services/offline/offline_log_sync_service.dart | 账号代次隔离、认证等待、逐 ID 确认 | 7 |
| R | [M] inv_app/lib/features/auth/presentation/bloc/auth_bloc.dart | 退出先停同步与 BLE，保留受保护的本账号待同步记录 | 7 |
| R | [M] business-api/internal/model/models.go | 审计请求、回执与查询模型 | 7 |
| R | [M] business-api/internal/handler/offline_log_handler.go | 结构/上限校验、逐条结果、审计查询入口 | 7 |
| R | [M] business-api/internal/service/services.go | 逐设备权限、上传者/操作者分离、结果可信度策略 | 7 |
| R | [M] business-api/internal/repository/repositories.go | 事件幂等、状态更新、分页查询 | 7 |
| R | [M] business-api/cmd/main.go | 审计查询路由，固定路径先于动态 SN 路由 | 7 |
| R | [M] database/schema.sql | 同步最终审计表结构，不存私钥/PIN | 7 |
| R | [A] database/migrations/<next>_ble_audit_v2.up.sql | 新增字段、索引与兼容迁移；执行前分配未占用编号 | 7 |
| R | [A] database/migrations/<next>_ble_audit_v2.down.sql | 对应迁移逆向脚本，执行前说明审计数据影响 | 7 |
| R | [M] inv_app/test/ble/ble_device_session_test.dart | 认证、重试、会话失效与最终结果 | 2、5 |
| R | [M] inv_app/test/ble/ble_polling_service_test.dart | 立即快照、停止/重启及串行读取 | 5 |
| R | [A] inv_app/test/ble/device_live_data_service_test.dart | 云端/BLE 新旧数据及身份隔离 | 5 |
| R | [A] inv_app/test/ble/ble_control_flow_test.dart | 页面/仓库控制与审计集成 | 5、7 |
| R | [A] inv_app/test/ble/ble_ota_transport_test.dart | 分包、快速 ACK、状态重组、中止与断连 | 6 |
| R | [M] inv_app/test/offline/offline_op_log_store_test.dart | 迁移、账号隔离及未同步数据保留 | 7 |
| R | [M] inv_app/test/offline/offline_log_sync_service_test.dart | 逐条结果、401/403、切账号在途请求 | 7 |
| R | [M] business-api/internal/handler/offline_log_handler_test.go | 拒绝无权设备、默认未知、批次部分结果 | 7 |
| R | [M] business-api/tests/integration/offline_logs_test.go | 幂等、事件更新、事务及查询权限 | 7 |

## 1. 假设、范围与已知证据

- 目标固件仅 F，不移植普通 C3 的旧二进制 OTA 协议；第一期支持通信模块及主控，其他模块未声明能力则不允许升级。
- 已授权设备可离线查看/控制；首次绑定、离线凭证有效期及角色权限在流程 1 固定。离线无法立即获知云端撤权，必须明确可接受的撤权延迟，不能声称实时撤权。
- 遥测一期仅设备上云。手机同步控制/参数/OTA 审计，不把记录重放成命令，不增加手机后台常驻网关。
- 保持既有 App 风格、云端及 WiFi AP 功能；仅为三通道共用业务边界调整相关代码，不做无关重构。
- App `ble_device_manager.dart:203` 有遥测流；当前业务页面未接入该流。`device_control_page.dart:340` 直接云端控制。
- F `ble_ct_auth.c:157–227` 返回设备 HMAC 后置认证，缺手机持钥证明；AUTH/COMMAND 固定缓冲缺边界检查。
- F `ble_ct_cmd.c:128` 对读取成功码 0 判断错误；`cmd_handler.c:258` 将排队当完成，未回 BLE 最终结果。
- F `ble_prov.c:148` 有 OTA 特征，但未找到执行回调注册；`ota_service.c:374–438` 允许无签名和零安全版本绕过。此处与普通 C3 不同。
- App 已有 SQLite 日志和上传服务；正常登出清空日志可能丢未同步事件。缺账号归属也不能靠同步时的登录身份补认。
- 行号为规划时快照，实施前重查当前文件；不以旧文档中的完成状态代替代码证据。

## Chunk 1：协议、授权与设备结果真实性

## 流程 1：固定共同契约与验收样本

### 涉及文件

文件表中的 contract 文档和黄金向量；只读参考现有 BLE、主控参数及 OTA 接口。

### 修改说明

- [ ] 清点每个现有控制按钮对应的命令名、主控地址、单位、缩放、范围、枚举、可读写性、角色限制；以实际主控协议为依据，不能直接采用可疑别名。
- [ ] 固定 INFO 能力字段：`proto_version`、`model`、`hardware_version`、`parameter_schema_version`、`capabilities`、支持升级模块与最大报文。字段名称需三端共同评审。
- [ ] 固定快照信封：`device_sn`、`boot_id`、`sample_seq`、`sampled_at`、`time_quality`、`schema_version`、`data`、`quality`。手机另外记录 `received_at`、`source`，不可冒充设备采样时间。
- [ ] 固定控制信封：`operation_id`、`command_id`、`session_id`、`sequence`、`action`、`params`。设备返回 `accepted/executing/applied/rejected/failed`；通信超时由 App 标记 `unknown`，并查询而非换通道重发。
- [ ] 固定最终结果字段：同一命令 ID、错误码、实际值、参数 revision、设备结果 ID。规定同 ID 同载荷返回原结果，同 ID 不同载荷拒绝；缓存淘汰后不得承诺永久 exactly-once。
- [ ] 固定 OTA CTRL/DATA/STATUS 分工：控制帧携带版本化完整 manifest；数据帧携带 transfer ID、offset 和 payload；ACK 返回连续接受偏移，STATUS 返回任务阶段和错误。控制 JSON 也必须可分帧，不能假设 manifest 能放一包。
- [ ] 定义生产认证与离线授权方案：优先复用现有持钥机制补双向证明及加密链路；服务端角色能力若需设备强制执行，使用可验证授权凭据而非信任 App 自报角色。禁止自创加密算法。
- [ ] 固定每阶段有效期、重试次数、资源上限与最大队列长度，通过目标硬件 RAM/Flash 预算确定数值。为未知字段、错误单位、重放、半帧、旧版本提供向量。

验收：App、固件、服务器负责人逐项认可同一份契约与向量。尚未确定的凭据、量纲或权限不得通过 UI 默认值“补齐”。该阶段完成后才能并行实现。

## 流程 2：认证与连接访问门禁（P0）

### 涉及文件

F 的 `ble_ct.c/.h`、`ble_ct_auth.c/.h`、`app_main.c`；R 的 `ble_adapter.dart`、`ble_device_manager.dart`；认证与协议测试文件。

### 修改说明

- [ ] 先写失败测试：仅发送 nonce/ts 不得获得控制权限；错误证明、重复证明、过期挑战、换连接复用、未授权遥测读均拒绝。
- [ ] 运行对应测试并保存失败证据，确认失败来自上述漏洞而非缺工具。
- [ ] 实现设备随机挑战、手机证明、设备证明、单次挑战消费；确认手机证明后才进入 ready，校时同样在认证后进行。
- [ ] 按连接保存认证状态，断开清理会话；时钟不可信时使用挑战及单调时间判定，不能以可修改手机时间作为唯一防重放依据。
- [ ] AUTH/COMMAND 限长、类型校验、带长度解析、响应编码安全；移除 AUTH 原文日志中的密钥/PIN，禁止日志泄露凭证。
- [ ] 规定配网/首次绑定可访问的最小特征与安全启动流程，不能简单给所有特征加加密要求导致首次绑定死锁。
- [ ] App 能力探测后只启用匹配协议；旧设备明确显示不支持安全直连控制，不静默回退旧认证。
- [ ] 复测正向绑定/重连及全部拒绝路径。认证通过前，不进入控制和 OTA 联调。

## 流程 3：主控参数执行闭环（P0）

### 涉及文件

F 的 `ble_ct_cmd.c/.h`、`cmd_handler.c/.h`、`app_main.c`、`tests/host/test_ble_control.c`。

### 修改说明

- [ ] 先测试成功读取返回码 0、不可读参数、主控拒绝、超时和不同通道并发；测试重复命令只执行一次。
- [ ] 将读取判断改为显式成功码比较；读取失败不得返回默认 0 冒充参数实际值。
- [ ] 去掉功率 W 到充电电流 A 的错误别名；每个参数检查 finite、范围、枚举和步进，转换前拒绝 NaN/无穷或溢出值。
- [ ] 引入共享写请求上下文：来源、operation ID、command ID、地址、期望值、截止时间。一次只能有受控数量的主控在途请求。
- [ ] 排队返回 accepted；主控 ACK 失败返回 failed；ACK 成功后触发参数回读，确认值和 revision 后返回 applied。回读未完成保持 executing 或结果未知，不提前成功。
- [ ] 主控协议若无事务 ID，实施串行仲裁；相同地址的迟到 ACK 不能匹配到下一条写请求。
- [ ] 保存有界近期结果供断连查询。跨重启无法证明命令是否执行时返回 unknown，不自动重做危险动作。
- [ ] 回归云端 MQTT 控制，确认共用调度不会破坏原有任务关联和结果回报。

## Chunk 2：遥测与 App 业务接入

## 流程 4：固件遥测快照与传输

### 涉及文件

F 的 `ble_ct_telemetry.c/.h`、`telemetry.c` 和协议测试。

### 修改说明

- [ ] 先测未订阅时仍刷新快照、MTU 23/185/247/512、缺片/重复片、跨快照片段混入、快照并发读取。
- [ ] 从主控采集生成规范化快照，独立于 MQTT 发送与 BLE 订阅；添加锁或双缓冲，禁止半份 JSON 被读取。
- [ ] 分片大小取 `实际 MTU - ATT 开销 - 协议头`，限制消息总长度、片数及重组时间；长 Read 明确定义偏移/分片语义，不依赖偶然可用的整包 JSON。
- [ ] 逐字段对照主控原始值与云端转换，包括电压、频率、正负电流、功率、电量和温度。保留符号，缺失为 null/无效标记，不用固定 offgrid、PF=0 冒充测量值。
- [ ] 推送采用最新值合并及受控频率，避免积压陈旧快照；页面进入主动读取，退出降频；具体周期由协议阶段确定。
- [ ] 复测手机通知关闭、MQTT 断线及 OTA 独占时，采集不被中断。

## 流程 5：App 展示、参数与控制接入

### 涉及文件

R 的 BLE 会话/轮询、新 snapshot/data service、现有 device repository、device bloc、实时/控制页面与 service locator，以及表中 App 数据和控制测试。

### 修改说明

- [ ] 先写数据源竞争测试：当前 BLE 快照不能被迟到云端旧值覆盖；不同 SN、旧账号、旧连接代次的数据不得串入。
- [ ] 复用已有实时实体做字段适配，新增信封层承载来源/质量，不创建第二套独立业务字段模型；所有消费者统一订阅。
- [ ] 首次认证成功立即读快照；通知持续更新、轮询兜底；移除订阅时释放资源。断线保留末值并明确过期。
- [ ] 设备云端在线、手机 BLE 可达、数据新鲜度分别显示和判断；没有采样时间的快照不能伪造“最新”。
- [ ] 控制页经既有 repository 获取能力、参数并发送命令，不在页面直接 Dio POST。缓存参数 schema 必须按型号/版本校验；缓存缺失时禁用不确定控制并解释原因。
- [ ] 发送前锁定通道和稳定命令 ID；超时查询结果，禁止自动跨通道重发；更新 UI 仅依据实际结果。
- [ ] 控制意图先持久化，再允许发送；写日志失败时不可悄悄执行需要审计的操作，应明确告知并按产品策略处理。
- [ ] 补 widget/集成测试：断网打开控制页仍能显示允许参数；主控拒绝、超时和未知状态不显示成功。

## Chunk 3：BLE OTA

## 流程 6：认证传输、设备安装与最终确认

### 涉及文件

F 的新增 `main/ota/ble_ota.c/.h`、`ble_prov.c`、`ota_service.c/.h`、`main/CMakeLists.txt`、`app_main.c`；R 的 BLE OTA service、local OTA page；双端 OTA 测试。

### 修改说明

- [x] 先用协议向量验证 manifest 分帧、快速 ACK、丢 ACK、重复偏移、错误偏移、缓冲满、错误 transfer ID 和取消。
- [x] 固件注册 OTA 特征回调。GATT 回调仅校验并入有界队列，worker 通过现有 `ota_service_start_local` 接收流；禁止阻塞 BLE host 等待烧写。
- [x] App 共用或明确独占已认证连接；暂停普通控制和轮询，保证退出/失败后恢复，不与配网抢适配器。
- [ ] 传递 task ID、目标、版本、大小、SHA256、签名、安全版本、超时和兼容性信息；新增兼容性字段若需签名覆盖，连同发布元数据契约一起更新，不能只做未签名型号判断。
- [ ] 生产路径必须拒绝空签名、错误签名、零/回退安全版本、超大/错型号固件。开发例外不得默认进入生产构建。
- [x] App 先注册按 task/request ID 的响应等待，再写入；按完整消息重组并分派 ACK/状态，不能首通知即完成或清空早到 ACK。
- [x] 仅按设备已接受的连续偏移推进传输；写入成功不是设备已持久接收。设备缓冲满时背压，超时重试沿用传输身份。
- [ ] 首版断连后清理或查询任务；仅在设备明确支持恢复偏移时续传，否则安全重新开始。禁止宣称已经提供断点续传。
- [ ] 分开接收、校验、烧写、重启、确认阶段；通信模块沿用健康检查与回滚，主控复用现有升级协议并重启回读版本。
- [x] 安装开始后按 ota_service 可取消性约束 UI；手机退出不得误认为设备已停止安装。再次进入可查询已保留的最终任务结果。
- [ ] 联调单模块通过后再验证升级包顺序；不支持或未连接模块应标跳过/不可用，不能默认所有模块可升级。

验收：手机传完 100% 后设备校验失败仍显示失败；主控烧写失败可识别；重启后目标版本或健康确认不足时显示待确认，而非成功。

> 2026-09-15 App 侧 BLE OTA 传输已接线：`BleCommunicationService` 复用已鉴权 `BleDeviceSession` + `BleOtaLease` 独占，覆盖 ota.ctrl/data/query、连续 offset ACK、状态映射与租约释放；`ble_ota_transport_test.dart` 5 例 + BLE/OTA 回归 68 例通过。真机安装/回滚与断连续传验收仍未做。
> 2026-09-16 固件侧 `tests/host/test_ble_ota.c` 已补齐：鉴权门禁、v2 信封、空签名/零安全版本/非法 target、session/transfer/连续 offset、剩余长度溢出、队列背压、query/cancel/status 读、以及 `ota_service_start_local` 实际消费字节；`ctest` 6/6 通过。

## Chunk 4：审计同步与端到端验收

## 流程 7：账号隔离、逐事件同步与云端查询

### 涉及文件

文件表中 App offline/auth/OTA queue、Go model/handler/service/repository/routes、schema/新迁移和离线日志测试。

### 修改说明

- [ ] 先测试旧数据迁移、登出未同步事件、A→B 切号、在途请求、部分拒绝、响应丢失重试、重复事件及匿名事件。
- [ ] 事件最小字段：event ID、operation ID、command/OTA task ID、采集账号/租户（可空）、上传用户、SN、channel、动作、请求值、实际值、状态、设备结果 ID、事件时间/时间质量、服务端接收时间。
- [ ] 服务端不信任客户端操作者字段；上传者来自 JWT，采集账号只是声明，只有可验证授权/设备证据才能提升可信度。共享设备密钥不能独立证明某个云用户身份。
- [ ] 默认结果 unknown；手机报告与设备确认分开存储。不得仅凭 App 日志覆盖权威参数、固件版本、云端在线或 OTA 成功状态。
- [ ] 操作产生时确定账号分区；匿名保持匿名。旧记录无法确定归属则进入待确认隔离区，不按下一次登录者自动归属。
- [ ] 退出先停止新同步/扫描并失效旧账号代次；未同步审计采用受保护存储且对其他账号不可见。明确保留期、容量告警和用户删除策略，不为了清理容量静默删除待同步审计。
- [ ] 新版 API 返回逐 event ID 的 accepted/duplicate/rejected；401 等待认证、403 隔离并提示、网络错误重试。兼容旧客户端的数量响应，新增显式版本字段或版本化端点，不无提示破坏旧契约。
- [ ] 逐设备/组织校验权限，设备转移/撤权后的旧审计采取隔离审核或拒绝策略，不继续授予控制权限。权限检查在 Service 层，Repository 仅处理存储。
- [ ] 幂等键不只按上传账号，operation ID 跨手机和设备结果关联；同 ID 不同设备/载荷冲突拒绝。初始意图与最终结果以事件 revision 更新或追加状态事件，不能被原有 DO NOTHING 吞掉最终结果。
- [ ] 增加分页审计查询，统一既有操作记录展示；对账号、租户、SN 过滤施加服务器权限，敏感参数脱敏。
- [ ] 新增数据库迁移并同步 schema；执行前分配 `<next>` 编号，旧迁移只读。对既有日志标记 legacy/reporter-only，不虚构历史设备证明。
- [ ] OTA 保留每次 task 的历史和确认依据；“最后已报告版本”可继续单独合并，但不能覆盖历史审计。

## 流程 8：整体验证与交付门禁

### 涉及文件

全部测试文件与流程 1 的验收向量；运行环境与真机日志不写入业务源码，不提交凭证或设备密钥。

### 修改说明

- [ ] 每个任务遵循：补失败用例 → 验证预期失败 → 最小实现 → 通过相关用例 → scoped diff 检查；记录命令和输出，不以编译代替行为证明。
- [ ] 双端协议向量必须同时通过；主控单位用真实样本核对，不由 App 和固件两边各自猜相同错误值得到“测试通过”。
- [ ] 模拟单测后执行 IDF 构建，再做 App 断网真机；真实设备烧录、危险控制和生产迁移需对应授权与安全测试条件。
- [ ] 检查既有云端/WiFi AP/配网回归；不能为 BLE 修改全局联网状态导致其他通道失效。
- [ ] 最终按“静态/单测、固件编译、真机、服务器集成”四层报告，明确未验证项。未获提交/推送/部署授权则停在本地交付。

## 2. 并行分工与合流顺序

| 工作包 | 负责人 | 前置 | 可并行范围 | 退出条件 |
|---|---|---|---|---|
| C0 协议 | 主代理统筹三端评审 | 无 | 只读核对 | 契约、向量和授权边界确认 |
| F1 固件安全/参数/遥测 | 固件代理 | C0 | 与 A1、S1 并行 | 流程 2–4 单测及构建通过 |
| A1 App 数据/控制 | App 代理 | C0 | 用固定协议 fake 与 F1 并行 | 数据及控制测试通过 |
| S1 审计服务与存储 | 同步代理 | C0 | 与 F1、A1 并行 | 逐事件 API/权限/迁移测试通过 |
| O1 OTA | App/固件分路径 | F1 安全门禁 | 两端 OTA 文件独占分工 | 流程 6 双端协议与安装确认通过 |
| I1 集成 | 主代理 | A1、F1、S1、O1 | 不并发修改共享入口 | 全部端到端验收 |

`app_main.c`、`service_locator.dart`、认证退出与日志接线属于共享集成文件，由指定负责人独占；其他代理只提补丁建议，不同时写。合流检查契约版本、字段单位、状态含义、权限、路径所有权和测试准备，任何不一致先修正再联调。

## 3. 测试与验收命令

以下为实施时命令，本次未运行。新增测试文件及 CMake 目标须先按文件表建立。Flutter 使用项目锁定版本；Go 工具链、PostgreSQL 测试库和 IDF 环境必须就绪，缺环境记录阻塞，不绕过失败。

### App 定向验证

```bash
cd /mnt/d/cs_app_project/cs_inv_monitor-develop/cs_inv_monitor-develop/inv_app
flutter pub get
flutter test test/ble test/offline test/ble_frame_reassembler_test.dart
flutter test test/features/ota/presentation/controller/local_ota_controller_test.dart
flutter test test/features/ota/presentation/pages/local_upgrade_page_test.dart
flutter analyze
```

预期：新测试及受影响既有测试全部通过；analyze 新增问题为零，已有问题单独记录，不把定向测试当全 App 通过。

### 固件主机与 IDF 验证

```bash
cd /mnt/d/CS_INV_WIFI/esp32c3_l10_idf
cmake -S tests/host -B build/ble-host-tests
cmake --build build/ble-host-tests
ctest --test-dir build/ble-host-tests --output-on-failure
idf.py build
```

预期：CMake 通过纯逻辑模块和 mock 运行 BLE 测试；IDF 编译目标为该 L10 工程既有配置，不擅自 set-target 或改 Flash 分区。主机测试不能证明射频、BLE 栈或实际烧写可靠性。

### 后端定向与仓库提交前验证

```bash
cd /mnt/d/cs_app_project/cs_inv_monitor-develop/cs_inv_monitor-develop/business-api
go test ./internal/handler -run Offline -count=1
go test ./tests/integration -run OfflineLogs -count=1
cd /mnt/d/cs_app_project/cs_inv_monitor-develop/cs_inv_monitor-develop
make build-go
make test-go
make vet-go
make analyze-app
```

集成测试先检查测试文件要求的连接变量、build tags 和测试库 schema；只允许隔离测试数据库。输出为 SKIP 不算通过。若新增测试命名不同，同步修正文档的 `-run` 过滤，确保实际执行目标用例。

### 真机验收矩阵

| 场景 | 必须观察到的结果 |
|---|---|
| 手机无互联网、设备无 MQTT | 已授权设备仍可读实时数据和允许参数 |
| 非授权手机/重放旧认证 | 敏感读取、控制、OTA 全拒绝 |
| 云端旧数据迟到 | 不覆盖当前 BLE 新快照 |
| 小 MTU、丢片、重复片 | 不截断 JSON，不串包；可诊断超时 |
| 主控拒绝/迟到 ACK/回读不一致 | 不显示已生效，不错误匹配下一命令 |
| 控制结果丢失后重试 | 同 ID 不重复执行；未知结果不偷偷云端重发 |
| OTA 错签名/错型号/降级 | 烧写前拒绝，保留可解释错误 |
| 升级中断连/手机被杀 | 重进可查询；不把传完当成功 |
| 主控升级与通信模块重启 | 实际版本/健康确认满足后才成功 |
| 日志接收成功但 ACK 丢失 | 重传幂等，最终事件状态不丢 |
| A 登出 B 登录、匿名操作 | 不泄露、不冒认、不跨账号自动上传 |
| 设备转移/撤权、重复事件冲突 | 权限与冲突明确返回，不混入他人审计 |

## 4. 范围外与实施前确认项

- 手机遥测中继、完整历史搬运、多手机网关、高频后台常驻不在一期；如后续增加，必须先有设备采样唯一 ID、持久化确认与来源可信度策略。
- 离线授权有效期及撤权延迟是产品/安全选择；流程 1 需确认，不默认永久有效，也不在完全离线时承诺即时撤权。
- 确认生产签名发布链、目标型号/硬件元数据来源和测试设备 Boot 能力。若需要修改签名服务或主控固件，另列明确文件与任务后再实施，不隐式扩大边界。
- 本计划中新增文件与字段为拟定设计；执行前与当前工作区、子目录指令和真实工具链核对。任何业务实施、烧录、提交或发布不属于本次计划编制的完成声明。
