# CS INV 逆变器 WiFi 模块 — BLE 本地通信协议规范（控制与遥测）

> 版本：V1.0（草案，待固件团队评审）  
> 日期：2026-08-06  
> 适用设备：ESP32-C3 / ESP32-C2 WiFi 通讯模块  
> 关联文档：《BLE_Provisioning_Protocol.md》（配网服务 CSIV-PR）

---

## 1. 概述

在现有 BLE 配网服务（CSIV-PR）之外，新增 **BLE 本地控制服务（CSIV-CT）**，使 App 在设备未联网或云端不可达时，仍可通过蓝牙直连完成设备管理。

**五大能力**：

| 能力 | 说明 | GATT 特征 |
|------|------|-----------|
| 设备绑定 | 首次使用将设备与账号绑定，云端下发 device_key | 复用配网服务 + 云端 API |
| 鉴权 | challenge-response 双向验证，防重放 | `AUTH` |
| 自动连接 | 后台低功耗扫描，命中已绑定设备自动连接鉴权 | —（连接层行为） |
| 本地遥测 | 设备经 BLE 推送运行数据，复用 MQTT 遥测 JSON | `TELEMETRY` |
| 下发控制 | 开/关机、功率设置、参数读写 | `COMMAND` / `CMD_RESULT` |

**设计原则**：

- 与 CSIV-PR 共存：配网服务不受影响，两服务可同时被发现与使用
- 数据格式统一：遥测与控制均使用 UTF-8 JSON，遥测结构与 MQTT 上报协议对齐，App 端同一套实体（`InverterRealtime`）解析
- 单连接约束：BLE 为单中心连接，App 连接期间设备的本地通信由此 App 独占；鉴权失败或非绑定设备不得使用控制与遥测能力

---

## 2. GATT 服务定义

### 2.1 服务 UUID

```
43534956-4354-1000-8000-00805f9b34fb
```

UUID 编码说明：`43534956` = ASCII "CSIV"，`4354` = ASCII "CT"（Control & Telemetry）。

### 2.2 特征列表

| 名称 | UUID | 权限 | 数据格式 | 说明 |
|------|------|------|----------|------|
| AUTH | `43534956-4155-1000-8000-00805f9b34fb` | 写 + 通知 | JSON（见 §5） | challenge-response 鉴权 |
| TELEMETRY | `43534956-544c-1000-8000-00805f9b34fb` | 通知 | JSON（见 §6） | 遥测推送，对齐 80s 心跳 |
| COMMAND | `43534956-434d-1000-8000-00805f9b34fb` | 写 | JSON（见 §7） | 控制命令下发 |
| CMD_RESULT | `43534956-4352-1000-8000-00805f9b34fb` | 通知 | JSON（见 §7） | 命令执行回报 |
| INFO | `43534956-494e-1000-8000-00805f9b34fb` | 只读 | JSON（见 §8） | 设备信息快照 |

UUID 简写对照表（第 3 段标识）：

| 特征 | 第3段 | 记忆 |
|------|-------|------|
| AUTH | `4155` | "AU" |
| TELEMETRY | `544c` | "TL" |
| COMMAND | `434d` | "CM" |
| CMD_RESULT | `4352` | "CR" |
| INFO | `494e` | "IN" |

> 设备 SN / 固件版本 / MAC 仍可从配网服务（CSIV-PR）的只读特征读取，CSIV-CT 不重复定义；`INFO` 提供聚合快照便于一次读取。

---

## 3. 连接参数与 MTU 协商

| 参数 | 值 | 说明 |
|------|-----|------|
| MTU | **512** | 连接建立后由 App 发起协商；遥测 JSON 通常 300~800 字节，MTU 512 可单帧或双帧传输 |
| 连接间隔 | 15~30 ms | 固件可接受的推荐范围 |
| 数据长度扩展 (DLE) | 开启 | BLE 4.2+ 必需，否则 MTU 512 无意义 |
| 超长帧处理 | 应用层分帧 | 单帧放不下的 JSON 按 §6.3 分帧协议传输 |

**连接建立顺序**（App 侧实现，固件无需处理）：

```
连接 → 协商 MTU=512 → 发现服务 → 订阅 CMD_RESULT/TELEMETRY/AUTH 通知 → 鉴权 → ready
```

未完成鉴权的连接，设备应拒绝 `COMMAND` 写入（返回 `Insufficient Authentication`），`TELEMETRY` 不应推送。

---

## 4. 设备绑定流程

绑定目标是让设备与 App/账号建立信任关系，核心是 **device_key 的生成与下发**。

### 4.1 device_key 约定

| 项 | 约定 |
|----|------|
| 长度 | 32 字节（256 bit），Base64 编码传输 |
| 生成方 | 云端（绑定接口返回），**不在 App 或设备端生成** |
| 设备存储 | 固件持久化（NVS/Flash），与 SN 一对一 |
| App 存储 | `flutter_secure_storage`，key 形如 `ble_device_key_<SN>` |
| 更换 | 仅允许通过"重新绑定"流程覆盖；设备恢复出厂时清除 |

### 4.2 绑定时序

```
    手机 App                ESP32 设备                云端
      │                        │                       │
      │ ① 扫描（CSIV-PR/CSIV-CT 服务 UUID）            │
      │ ─────────────────────→ │  广播中                │
      │ ② 连接 + 读 SN（CSIV-PR SN 特征）              │
      │ ─────────────────────→ │                       │
      │ ③ 查询绑定状态          │                       │
      │ ────────────────────────────────────────────→ │
      │ ←──────── { bound: false } ────────────────── │
      │                        │                       │
      │ ④ 调用绑定接口（SN + 设备验证码/配网成功凭据）    │
      │ ────────────────────────────────────────────→ │
      │ ←──────── { device_key, expires } ─────────── │
      │                        │                       │
      │ ⑤ 写入 device_key（见 §4.3）                   │
      │ ───── write(BIND) ───→ │  持久化 device_key     │
      │ ←── notify("bound") ── │                       │
      │ ⑥ App 存 secure_storage                        │
      │                        │                       │
      │ ── 已绑定设备日常使用：跳过 ③④⑤，直接走 §5 鉴权 ── │
```

### 4.3 BIND 特征（复用 AUTH 通道的绑定模式）

device_key 的写入通过 `AUTH` 特征以 `mode="bind"` 消息完成（设备仅在接受绑定的窗口期内响应——配网成功后 10 分钟内，或设备按键/已有绑定方授权后）：

```json
// App → 设备（write AUTH）
{ "mode": "bind", "device_key": "<Base64 32B>", "issued_at": 1786000000 }

// 设备 → App（notify AUTH）
{ "mode": "bind", "result": "ok" }
```

> **安全约束**：`bind` 模式仅在"绑定窗口"内可用。设备已绑定且窗口关闭时，写入返回 `{ "result": "rejected", "reason": "already_bound" }`。强制重新绑定需先恢复出厂或由原绑定方在云端解绑。

---

## 5. 鉴权协议（challenge-response）

### 5.1 目的与算法

- 验证 App 持有该设备的 device_key，防止任意手机连接控制设备
- 防重放：每次挑战使用随机 nonce + 时间戳
- 算法：**HMAC-SHA256**，密钥为 device_key（原始 32 字节，非 Base64 文本）

```
digest = HMAC-SHA256(key=device_key, message=nonce_bytes || ":" || timestamp_ascii)
```

- `nonce`：App 生成的 16 字节随机数，Base64 传输
- `timestamp`：Unix 秒级时间戳；设备校验与本地时钟偏差 ≤ 300s（设备无 RTC 时以启动后秒数对齐，容忍偏差由固件定义）
- `digest`：HMAC 结果 32 字节，Base64 传输

### 5.2 鉴权时序

```
    手机 App                          ESP32 设备
      │                                    │
      │ ① write(AUTH)                      │
      │ ──── { "mode":"auth",             ─→  校验时间戳窗口
      │        "nonce":"<B64 16B>",        │  计算 HMAC-SHA256
      │        "ts":1786000123 }           │
      │                                    │
      │ ←── notify(AUTH) ─────────────────│
      │     { "mode":"auth",               │  设备应答：
      │       "digest":"<B64 32B>",        │  HMAC(nonce:ts)
      │       "device_ts":1786000124 }     │
      │                                    │
      │ ② App 本地重算 digest 比对           │
      │    一致 → 状态进入 ready             │
      │    不一致 → 断开，记一次失败          │
```

- 连续 **3 次** 鉴权失败，设备应断开连接并在 **60s** 内拒绝该 MAC 的 AUTH 写入（防爆破）
- 鉴权有效期与连接绑定：断开即失效，重连须重新鉴权

---

## 6. 遥测推送（TELEMETRY）

### 6.1 数据格式

复用 MQTT 遥测 JSON 结构（与云端 Redis 缓存结构一致），App 端直接以 `InverterRealtime.fromJson` 解析。设备可按 BLE 带宽裁剪为**核心子集**：

```json
{
  "device_sn": "H1CNA00135000014",
  "ac":   { "voltage": 230.1, "current": 2.4, "power": 552, "frequency": 50.02, "load_percent": 9.2, "pf": 0.99 },
  "battery": { "soc": 86.5, "voltage": 52.3, "current": -3.2, "power": -167, "charge_state": "discharging" },
  "pv":   { "voltage": 182.0, "current": 6.8, "power": 1238 },
  "sys_status": { "work_mode": "offgrid", "fault_code": 0, "temperature": 38.5 },
  "energy": { "today_generation": 12.4, "today_consumption": 8.1 },
  "load_power": 552,
  "updated_at": "2026-08-06T10:20:30Z"
}
```

**与 MQTT 的差异**（固件需实现）：

| 项 | MQTT 通道 | BLE 通道 |
|----|----------|----------|
| 字段集 | 全量（含 cells/meter/device_info） | 核心子集（上表 6 组）即可，可逐步扩展 |
| 推送节奏 | 云端心跳 80s 对齐 | 对齐设备 80s 遥测节拍；数据突变（功率变化 >20% 或故障）可立即推送 |
| 时间戳 | UTC ISO8601 | 同上；无网络时以设备本地时钟为准，App 侧标注"本地时钟" |

### 6.2 订阅行为

- App 完成鉴权后订阅 `TELEMETRY`；设备从下一节拍开始推送
- 连续推送不携带 device_sn 之外的路由信息（连接本身已标识设备）
- App 退后台或断开即停止推送，不缓存补发

### 6.3 应用层分帧

单帧 ATT 有效载荷 = MTU − 3 = 509 字节。为消除“单帧 JSON 与后续帧无法区分”的歧义，**TELEMETRY 通知统一携带 1 字节控制头**（含单帧场景）：

| 位 | 含义 |
|----|------|
| bit7 | 1=首帧 |
| bit6 | 1=末帧 |
| bit[5:0] | 帧序号（首帧为 0，递增） |

- 单帧传输：控制头 = `0xC0`（首帧+末帧同时置位），后跟完整 JSON
- 多帧传输：首帧 `0x80`，中间帧 `0x01..`，末帧 `0x40|序号`

接收方从首帧开始拼接，收到末帧后整体解析 JSON；超过 8 帧（约 4KB）或未收到首帧而收到后续帧，视为异常丢弃并等待下一首帧。

---

## 7. 命令下发与回报（COMMAND / CMD_RESULT）

### 7.1 命令格式（App → 设备，write COMMAND）

```json
{
  "command_id": "a1b2c3d4",
  "action": "set_power",
  "params": { "power_w": 3000 },
  "ts": 1786000200
}
```

| 字段 | 说明 |
|------|------|
| `command_id` | 8 位十六进制字符串（App 生成，连接内唯一），用于回报配对 |
| `action` | 命令名，见 §7.3 |
| `params` | 命令参数对象，可为空 `{}` |
| `ts` | Unix 时间戳，设备校验窗口 ±300s |

### 7.2 回报格式（设备 → App，notify CMD_RESULT）

```json
{
  "command_id": "a1b2c3d4",
  "status": "ok",
  "data": { "applied_power_w": 3000 }
}
```

失败时：

```json
{
  "command_id": "a1b2c3d4",
  "status": "error",
  "error": { "code": "OUT_OF_RANGE", "message": "power_w must be 0..6000" }
}
```

**配对与超时**（App 侧实现）：

- `command_id` 匹配；收到回报前不视为完成
- 超时 **5s**；超时后自动重发，最多 **2 次重试**；重试沿用原 `command_id`，设备需对相同 `command_id` 做幂等处理（重复执行返回首次结果）
- 同一连接上命令**串行执行**（App 侧队列保证，防止 GATT 并发冲突）

### 7.3 命令清单（初版）

| action | params | 说明 | 权限 |
|--------|--------|------|------|
| `power_on` | `{}` | 开机（逆变输出开启） | 已鉴权 |
| `power_off` | `{}` | 关机（逆变输出关闭） | 已鉴权 |
| `set_power` | `{ "power_w": 0..6000 }` | 设置输出功率上限 | 已鉴权 |
| `set_param` | `{ "param_id": "...", "value": ... }` | 写控制参数（对齐《48V离网逆变器控制参数与三级权限设计》参数表） | 已鉴权 + 参数权限级 |
| `get_param` | `{ "param_id": "..." }` | 读控制参数，值经 `data` 返回 | 已鉴权 |

> 三级权限（用户/安装商/厂商）参数经 `set_param` 写入时，固件按当前鉴权会话对应的权限级校验，越权返回 `FORBIDDEN`。

### 7.4 错误码

| code | 含义 |
|------|------|
| `UNAUTHENTICATED` | 未鉴权或会话失效 |
| `FORBIDDEN` | 权限不足（参数权限级） |
| `OUT_OF_RANGE` | 参数取值越界 |
| `UNKNOWN_ACTION` | 未识别的 action |
| `BUSY` | 设备忙（如 OTA 中），稍后重试 |
| `INTERNAL` | 设备内部错误 |

---

## 8. INFO 特征（只读快照）

一次读取设备关键信息，JSON：

```json
{
  "sn": "H1CNA00135000014",
  "model": "CS-L10-6K2",
  "firmware": "V1.3.0.20260701",
  "mac": "08:92:72:BD:A6:B0",
  "bound": true,
  "proto_ver": 1
}
```

| 字段 | 说明 |
|------|------|
| `bound` | 设备是否已完成绑定（App 据此决定走绑定还是鉴权分支） |
| `proto_ver` | 本协议版本号，初版为 `1`；后续不兼容变更时递增 |

---

## 9. 安全设计汇总

| 威胁 | 缓解 |
|------|------|
| 任意手机连接控制 | challenge-response 鉴权，device_key 不出安全存储 |
| 重放攻击 | nonce + 时间戳窗口（±300s） |
| 爆破 device_key | 3 次失败锁定 60s；HMAC-SHA256 + 256bit 密钥空间 |
| 绑定劫持 | 绑定窗口期限制（配网后 10min / 按键授权）；已绑定拒绝重写 |
| 窃听 | BLE 链路层配对加密（建议固件对 CSIV-CT 特征要求加密连接，LESC）；应用层 HMAC 不加密内容但防伪造 |
| 密钥泄露 | device_key 按设备隔离；云端可吊销并重发（重新绑定） |

---

## 10. 固件实现要求清单

- [ ] 广播同时携带 CSIV-PR 与 CSIV-CT 服务 UUID（或 Scan Response 分放）
- [ ] CSIV-CT 服务与 5 个特征注册，权限按 §2.2
- [ ] MTU 协商接受 512；DLE 开启
- [ ] 未鉴权拒绝 COMMAND 写入、不推送 TELEMETRY
- [ ] AUTH：`bind`/`auth` 两模式；时间戳窗口校验；3 次失败锁定 60s
- [ ] device_key NVS 持久化；恢复出厂清除
- [ ] TELEMETRY：80s 节拍对齐，突变立即推送；分帧发送
- [ ] COMMAND/CMD_RESULT：command_id 幂等；5s 内回报
- [ ] INFO：`bound`/`proto_ver` 字段
- [ ] （建议）CSIV-CT 特征要求加密连接（LESC bonding）

---

## 11. App 端实现对应

| 协议要素 | App 端位置 |
|----------|-----------|
| BLE 栈抽象（扫描/连接/GATT/MTU） | `lib/core/services/ble/ble_adapter.dart` |
| 多设备管理、状态机、命令队列、自动连接、退避重连 | `lib/core/services/ble/ble_device_manager.dart` |
| 遥测解析 | `lib/core/entities/inverter_data.dart`（`InverterRealtime.fromJson`，复用） |
| device_key 存储 | `flutter_secure_storage`（key: `ble_device_key_<SN>`） |
| 配网（既有） | `lib/core/services/ble_provisioning_service.dart` |

> **当前状态**：本文档为评审草案。TELEMETRY/COMMAND 等特征需固件实现后方可真机联调；App 端架构代码已先行交付（可单元测试，命令队列/重连/配对逻辑不依赖真机）。
