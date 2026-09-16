# CS-L10 BLE 本地通信 v2 契约

状态：实施前共同契约（App、L10 固件、服务端评审输入）
版本：`2.0`
日期：2026-09-15

本文只定义三端必须一致的线格式和状态语义。它不替代真实硬件参数表、发布签名策略或产品权限审批。没有被现有权威映射或硬件样机确认的数字，必须保持为门禁（`TBD_GATE`），不得由 App 默认补齐。

## 1. 一期边界与编码规则

- BLE 服务仍使用 CSIV-CT：`43534956-4354-1000-8000-00805f9b34fb`。INFO、AUTH、TELEMETRY、COMMAND、CMD_RESULT 的特征 UUID 沿用 `docs/BLE_Local_Communication_Protocol.md` 和 App `BleCtProtocol` 中的值。
- 所有控制消息使用 UTF-8、严格 JSON object；未知字段可忽略但未知 `v`、`type`、必需字段或类型必须拒绝。整数不得用小数表示；数字不得为 NaN/Infinity。
- 二进制字段使用标准 Base64（无换行）；SHA-256 使用小写 64 位十六进制；时间为 Unix 秒 UTC。报文字节数按 UTF-8 编码后计算。
- v2 消息可分帧；任何 JSON（包括 OTA CTRL manifest）都不能假设适合一包。ATT 有效载荷按实际协商 MTU 计算（`MTU - 3`），不得固定假设 MTU 512；当前 L10 实现的 509 字节和 8 帧上限是待硬件预算确认的候选值。
- 一期手机只读取/展示设备产生的 BLE 快照；手机不是遥测中继、缓存补发器或后台网关，不把手机收到的遥测上传云端冒充设备采样。云端遥测仍由设备上云。

## 2. 共同信封与 INFO

所有 v2 应用消息至少包含：

```json
{"v":2,"type":"<message type>","message_id":"<unique id>","session_id":"<connection session>","body":{}}
```

`message_id` 在同一连接内唯一；`session_id` 每次 BLE 连接重新生成。除直接 GATT Read 返回的 INFO 快照外，每个响应还必须包含顶层 `in_reply_to`，值为它所响应请求的 `message_id`；请求不得携带 `in_reply_to`。INFO Read 没有应用层请求信封，因此不携带 `in_reply_to`，App 以当前连接和返回的 `session_id` 关联。App 必须同时校验适用的 `session_id`、`in_reply_to`、响应 `type` 和当前协议阶段，迟到响应不得完成新一轮请求。旧设备只能被显式识别为 v1/不支持安全直连，禁止静默回退到旧认证。

INFO 是只读快照，字段名称固定如下：

```json
{
  "v": 2,
  "type": "info",
  "message_id": "info-001",
  "session_id": "sess-001",
  "body": {
    "device_sn": "H1CNA00135000014",
    "proto_version": 2,
    "model": "CS-L10-6K2",
    "hardware_version": "TBD_GATE",
    "firmware_version": "TBD_GATE",
    "parameter_schema_version": "TBD_GATE",
    "capabilities": ["info", "telemetry", "control", "ota"],
    "supported_upgrade_modules": ["communication_module", "system_controller"],
    "max_report_bytes": "TBD_GATE",
    "bound": true
  }
}
```

`capabilities` 是设备实际启用的能力标识，不代表 App 可绕过认证或权限。`hardware_version`、固件版本、参数 schema、报文上限和模块支持必须由 L10 固件/硬件确认；`TBD_GATE` 不是可发送到生产设备的值。`esp`/`arm` 仅允许在实现映射和发布元数据中出现，不能作为用户显示名称。

## 3. 认证与访问门禁

生产认证必须使用设备绑定的 32 字节 `device_key`（原始字节，不是 Base64 文本），算法仅使用标准 HMAC-SHA256；生产密钥、PIN、签名私钥绝不进入本文或向量文件。v2 要求双方证明持钥，且挑战只消费一次：

1. 手机发送 `auth.init`，含随机 `phone_nonce`。
2. 设备返回 `auth.challenge`，含随机 `device_nonce`、`device_ts`，并以 `in_reply_to` 关联 `auth.init`。
3. 手机发送 `auth.proof`：
   `phone_proof = HMAC-SHA256(K, ASCII("CSIV-CT/v2/app|") || session_id || "|" || phone_nonce || "|" || device_nonce || "|" || decimal(device_ts))`。
4. 设备验证后返回 `auth.result`，以 `in_reply_to` 关联 `auth.proof`，并以同一 transcript 将前缀替换为 `CSIV-CT/v2/device|` 计算 `device_proof`。手机验证成功才进入 `ready`。

Nonce 必须为 16 字节随机数；挑战、session 和证明不得跨连接复用。设备时钟不可信时只能依赖挑战生命周期/单调时钟，不能把可修改的手机时间作为唯一防重放依据。认证前拒绝控制、OTA 和敏感遥测读取；断开即清除认证状态。生产挑战有效期、失败锁定次数/时长、认证报文最大长度由硬件安全评审确认，未确认前标 `TBD_GATE`。

## 4. 遥测快照

TELEMETRY 的 `body` 固定为：

```json
{
  "device_sn": "H1CNA00135000014",
  "boot_id": "boot-test-01",
  "sample_seq": 42,
  "sampled_at": "2026-09-15T08:00:00Z",
  "time_quality": "device_clock",
  "schema_version": "TBD_GATE",
  "data": {"ac": {"voltage": 230.1}},
  "quality": {"flags": 0}
}
```

`device_sn`、`boot_id`、`sample_seq`、`sampled_at`、`time_quality`、`schema_version`、`data`、`quality` 均必需。`sampled_at` 是设备采样时间；App 可另记本地 `received_at` 和 `source="ble"`，不得改写或冒充采样时间。缺失值必须为 `null` 并设置质量标志，不能以 0/offgrid/PF=0 冒充测量值。质量位沿用 App `telemetry_quality.dart`：`0x01 missing`、`0x02 out_of_range`、`0x04 time_drift`、`0x08 out_of_order/backfill`、`0x10 counter_reset`、`0x20 comm_fault`；未知位保留并报告。

通知分帧头为 1 字节：bit7 首帧、bit6 末帧、bit[5:0] 从 0 开始的序号；单帧为 `0xC0`。缺首帧、序号跳变、跨快照混入、超出经评审的最大长度都丢弃整组。推送/轮询读取的是同一最近快照；手机退出或断连不要求设备缓存补发。

## 5. 控制、结果与幂等

请求 `body` 固定字段：`operation_id`、`command_id`、`session_id`、`sequence`、`action`、`params`。`operation_id` 跨手机/通道用于审计关联，`command_id` 是设备执行幂等键；超时的 App 状态为 `unknown`，必须查询同一 ID 的结果，禁止自动换通道重发。

设备结果至少包含：`operation_id`、`command_id`、`status`、`result_id`、`error`（无错误时为 null）、`actual`、`parameter_revision`。`status` 只允许 `accepted`、`executing`、`applied`、`rejected`、`failed`；排队不是完成，只有设备 ACK 与回读确认后才是 `applied`。

同一 `command_id` 加同一 canonical 请求载荷必须返回第一次结果且不得再次执行；同一 ID 不同载荷必须返回 `rejected`/`IDEMPOTENCY_CONFLICT`。缓存淘汰、重启或无法证明主控是否执行时，不承诺永久 exactly-once，结果必须为 `unknown` 或可解释拒绝。缓存容量、保留时间、并发队列和各阶段超时均为 `TBD_GATE`；当前固件 8 条/10 分钟仅是迁移参考。

参数 action 使用现有主控权威映射（例如 `set_power_limit`、`set_soc_window`、`bms_set_charge_current` 等）和 `parameter_schema`；不得把 `set_power` 误映射成充电电流。每个参数的单位、缩放、范围、步进、枚举、读写性和角色权限必须从实际型号 schema 提供。本文不冻结 L10 未确认的范围；缺 schema 或权限能力时设备返回 `rejected`，App 禁用该控件。

## 6. OTA CTRL / DATA / STATUS

OTA 仅对 INFO 声明支持且已授权的模块开放，一次仅一个 `transfer_id`。三类消息职责固定：

- `ota.ctrl`：携带完整、版本化 manifest，可分帧；至少含 `transfer_id`、`task_id`、`target`、`model`、`version`、`size`、`sha256`、`signature`、`security_version`、`manifest_version`。生产必须拒绝空/错签名、错型号、降级安全版本和超大文件；签名覆盖 manifest 全部字段。
- `ota.data`：携带 `transfer_id`、绝对 `offset`、`payload`（Base64）和 `payload_sha256`。设备只接受下一个连续 offset，重复 offset 返回当前连续接受偏移，错误 offset/transfer ID 拒绝或返回背压。
- `ota.status`：携带 `transfer_id`、`stage`、`accepted_offset`、`progress`、`result_code`、`message`。阶段至少为 `accepted`、`receiving`、`verifying`、`installing`、`rebooting`、`succeeded`、`failed`、`rolled_back`、`cancelled`；传输 100% 不等于安装成功。

目标模块使用 `communication_module`/`system_controller` 等功能名；与现有 `esp`/`arm` 的映射由发布元数据确认。主控升级须经过重启、健康检查和版本回读；断连后只有设备明确支持恢复偏移才允许续传，否则重新开始。签名算法、最高文件尺寸、分片 payload 上限、背压窗口、超时和可取消阶段是发布/硬件门禁，未确认不得写默认值。

## 7. 审计与兼容规则

手机在发送控制、绑定和 OTA 意图前先持久化审计事件，至少包含账号归属（或明确匿名绑定状态）、设备 SN、`operation_id`、通道、canonical 请求摘要、创建时间和本地状态。最终结果追加/更新同一 operation 的状态，不把结果重放成命令。登出不得删除未同步事件；同步按事件逐条幂等，服务器按设备/组织重新授权，不能信任上传账号自报权限。

v2 兼容：同一 `v` 内仅允许向后兼容新增可忽略字段；改变必需字段、算法、单位、状态或分帧语义必须递增 `proto_version`。INFO 能力探测失败、版本不支持、schema 缺失、未知模块或未确认门禁均为不可用，不静默降级到 v1 或云端重发。所有向量中的密钥、签名和设备标识均为测试值。

## 8. 实施前门禁清单

硬件/固件负责人必须确认：设备 nonce/时钟策略、认证有效期和失败锁定、最大报文/分片/队列、INFO 实际字段、L10 参数 schema 与单位缩放、角色凭据格式、OTA 签名公钥与算法、模块映射、最大镜像尺寸、恢复偏移与重启健康判定。服务端负责人必须确认：角色授权凭据是否由服务端签发、审计事件 schema、设备撤权延迟。未完成确认前，本契约与黄金向量只能用于解析/拒绝路径测试，不能宣称生产安全或真机通过。
