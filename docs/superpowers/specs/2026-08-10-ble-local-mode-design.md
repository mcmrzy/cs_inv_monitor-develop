# BLE 直连设备（本地模式）设计文档

> 日期：2026-08-10
> 状态：待评审
> 关联协议：《BLE_Local_Communication_Protocol.md V1.0》（本文档含 2 处协议修订）
> 关联固件计划：《BLE 本地模式实现方案（修订版 V2）》（含本文档 §5 的 11 条修订）

---

## 1. 背景与目标

### 1.1 需求

用户希望：

1. 设备（CS-L10-6K2 逆变器）通过蓝牙绑定到用户账号
2. 手机 App 在离网状态下（本地模式）获取设备信息和控制设备
3. 本地操作信息保存到手机
4. 手机联网后把操作日志同步到服务器

### 1.2 确认的需求决策

| # | 决策点 | 结论 |
|---|--------|------|
| 1 | 通信通道 | BLE 直连为主；控制命令 **HTTP 优先、BLE 仅离线兜底** |
| 2 | 离线身份 | 离网未登录也可操作，但必须通过 device_key 应用层鉴权（防任意手机控制） |
| 3 | 日志范围 | 绑定/解绑、控制命令、写参数（set_param）、OTA 升级；**读参数不记录** |
| 4 | 日志同步 | 自动同步 + 指数退避重试；网络恢复/App 启动时触发 |
| 5 | 入口形态 | **不做"本地模式页"**；设置项"通过 BLE 直连设备"开关，与 HTTP 并存 |
| 6 | 绑定时机 | 场景 A：配网成功后**全自动绑定**（零操作）；场景 B：扫描发现未绑定设备**一键确认绑定**（防抢绑） |
| 7 | 轮询周期 | 180s（可配 60s/180s/300s） |
| 8 | 控制页 | 不新建独立 BLE 控制页；现有设备控制页数据源/命令通道透明切换 |
| 9 | 日志入口 | 设备详情页 |
| 10 | 解绑 | 云端解绑 + 清除本地 device_key；设备端 key 由固件"重绑窗口"机制覆盖（App 引导，无需用户手动恢复出厂） |

### 1.3 现状基础（复用不重复建设）

- App 端 BLE 协议层已实现：[ble_adapter.dart](inv_app/lib/core/services/ble/ble_adapter.dart)、[ble_device_manager.dart](inv_app/lib/core/services/ble/ble_device_manager.dart)（状态机 / HMAC-SHA256 鉴权 / 命令队列 / 1 字节控制头分帧重组 / 指数退避重连 / 多设备管理 / 自动连接扫描）
- device_key 存储：`flutter_secure_storage`（key 形如 `ble_device_key_<SN>`），[SecureStorageBleDeviceKeyStore](inv_app/lib/core/services/ble/ble_device_manager.dart) 已实现
- 配网服务：`ble_provisioning_service.dart`（CSIV-PR）已接入 WiFi 配网页
- 遥测实体：`InverterRealtime.fromJson` 可复用（协议 §6.1 遥测结构与 MQTT 对齐）
- 后端：`POST /devices/bind` 已存在（但**不返回 device_key**）；`audit_logs`、`device_cmd_logs` 表已存在
- 网络状态：`NetworkStatusService`（离线判定）可复用为日志同步触发器

---

## 2. 总体架构

```
┌────────────────────────────── App（Flutter）──────────────────────────────┐
│ 设置项「通过 BLE 直连设备」开关                                              │
│   ├─ BleDiscoveryService  扫描/识别逆变器（CSIV-CT UUID）                    │
│   ├─ BleBindingService    自动绑定编排（场景A/B）                           │
│   ├─ BlePollingService    180s 定时轮询遥测（TELEMETRY Read）               │
│   ├─ 复用 BleDeviceManager（连接/鉴权/命令/notify 推送）                     │
│   ├─ OfflineOpLogStore    sqflite 本地日志                                  │
│   └─ OfflineLogSyncService 网络恢复自动同步（指数退避）                       │
└──────────────┬──────────────────────────────┬──────────────────────────────┘
               │ HTTPS                          │ BLE（CSIV-CT）
┌──────────────▼──────────────┐  ┌──────────────▼──────────────────────────────┐
│ 后端 business-api            │  │ 固件 ESP32（ble_ct 组件，V2 计划+11条修订）   │
│ ├─ bind 扩展返回 device_key  │  │ ├─ AUTH（bind/auth + 时钟校准）              │
│ ├─ POST /devices/offline-logs│  │ ├─ TELEMETRY（Read+Notify，分帧）            │
│ └─ device_offline_op_logs 表 │  │ ├─ COMMAND/CMD_RESULT（幂等）                │
│                              │  │ └─ INFO（bound/proto_ver）                  │
└──────────────────────────────┘  └────────────────────────────────────────────┘
```

---

## 3. App 端设计

### 3.1 设置项「通过 BLE 直连设备」

位置：设置 → 设备与连接 → 「通过 BLE 直连设备」开关（默认关）。

**打开时**：
1. 请求蓝牙权限（denied → 引导系统设置）
2. 启动 BLE 扫描（CSIV-CT 服务 UUID）
3. 识别结果分三类：
   - **已绑定设备**（本地有 device_key）：后台自动连接 + 鉴权，进入轮询
   - **未绑定设备**（bound=false 且绑定窗口内）：列表提示"可绑定"
   - **其他蓝牙设备**：忽略
4. 已绑定设备在 BLE 范围内时，设备列表/详情页数据源切换为本地轮询，显示「BLE」徽标

**关闭时**：断开所有 BLE 会话、停止轮询，恢复纯 HTTP 数据源。

**开关状态持久化**：`StorageService`（key: `ble_direct_enabled`）。

### 3.2 自动绑定

#### 场景 A：配网成功后全自动绑定（零操作）

WiFi 配网流程结束时（BLE 连接仍存活），自动执行：

```
读 SN（CSIV-PR SN 特征，回退 INFO）
→ 读 INFO 检查 bound
   ├─ bound=true → 跳过（已有绑定）
   └─ bound=false → 检查登录态
       ├─ 未登录 → 配网成功页提示"登录后自动绑定"，登录后补绑（设备仍在窗口期则自动执行）
       └─ 已登录 → POST /devices/bind（后端返回 device_key）
          → 写 AUTH {"mode":"bind","device_key":...,"issued_at":...}
          → 设备 notify {"mode":"bind","result":"ok"}
          → 存 flutter_secure_storage
          → 记录绑定日志（action=bind）
          → 配网成功页追加一行提示"设备已绑定到您的账号"
```

失败处理：绑定失败不阻塞配网成功流程，仅提示；用户可在设备详情页手动补绑（绑定窗口内）。

#### 场景 B：扫描发现未绑定设备（一键确认，防抢绑）

打开开关扫描到 bound=false 的设备时，弹轻量确认对话框：

> "发现附近设备 CS-XXXX（未绑定），是否绑定？"

- 确认 → 走场景 A 的 ④~⑧（需已登录；未登录先引导登录）
- 取消 → 设备从列表隐藏（本次会话内）

**不自动绑定的原因**：绑定建立"账号-设备"信任关系，任意已登录用户靠近即可抢绑未保护设备；绑定窗口机制（§协议 4.3）的防护意义正在于此。场景 A 之所以自动，是因为用户正处于自己设备的配网流程中。

### 3.3 数据轮询（180s）

- 触发条件：设置开关开 + 设备已绑定 + BLE 会话 ready（已鉴权）
- 周期：默认 180s（设置项可配 60s/180s/300s）
- 方式：`read(TELEMETRY)` 获取最新遥测快照（协议修订①：TELEMETRY 权限改为 Read+Notify）
- 数据落地：解析为 `InverterRealtime`，驱动设备列表/详情页数据；**遥测数据不写操作日志**（仅展示）
- 与 notify 推送并存：设备 80s 节拍推送 + 数据突变推送仍实时刷新；轮询作为兜底与主动拉取手段

### 3.4 控制命令通道选择

```
用户发起控制（开/关机、功率、写参数）
├─ HTTP 可达（在线）→ 走云端 API（现有逻辑，云端审计 + device_cmd_logs）
└─ HTTP 不可达（离线）→ 若 BLE 会话 ready → 走 BLE COMMAND
    └─ 两者都不可达 → 提示"设备离线，无法控制"
```

- BLE 命令信封：`{"command_id","action","params","ts"}`（协议 §7.1），`action` 复用协议 §7.3 命令清单
- 命令结果：`{"command_id","status","data/error"}`（协议 §7.2）
- 每次控制操作（无论通道）**都写本地操作日志**（action / params / result / 时间），在线通道的操作在日志同步时与服务端已记录数据不冲突（日志含通道标识）

### 3.5 操作日志（本地存储 + 自动同步）

#### 数据模型（sqflite 表 `local_op_logs`）

| 字段 | 类型 | 说明 |
|------|------|------|
| `log_id` | TEXT PK | 本地 UUID，**同步幂等键** |
| `device_sn` | TEXT | 设备 SN |
| `action` | TEXT | `bind` / `unbind` / `power_on` / `power_off` / `set_power` / `set_param` / `ota` |
| `params` | TEXT | JSON 参数（命令参数 / 固件版本等） |
| `result` | TEXT | `ok` / `error:<code>` |
| `channel` | TEXT | `cloud` / `ble`（操作通道标识） |
| `op_time` | TEXT | 本地操作时间 ISO8601 |
| `sync_status` | TEXT | `pending` / `syncing` / `synced` / `failed` |
| `sync_attempts` | INT | 重试次数（默认 0） |

容量上限：**500 条 / 30 天**，超限滚动清理（优先清 `synced`）。

#### 同步服务 OfflineLogSyncService

- 触发时机：`NetworkStatusService` 网络恢复事件 / App 启动 / 手动按钮
- 流程：取 `sync_status != synced` 日志（≤50 条/批）→ `POST /devices/offline-logs`（需登录 JWT）→ 成功标记 `synced`，失败按指数退避重试（30s / 1min / 5min / 15min / 60min 封顶）
- `sync_attempts > 5` → 标记 `failed`，保留本地等待手动重试
- 未登录时：日志照常记录（`operator` 归属在同步时取当前用户），登录后自动补传
- 后台执行不阻塞 UI（串行队列）

#### 日志页面（入口：设备详情页）

- 顶部：待同步数量统计 + 「立即同步」按钮
- 列表：时间 / 设备 SN / 操作（本地化文案）/ 结果 / 同步状态（待同步/已同步/失败可重试）
- 筛选：按设备 SN / 操作类型 / 同步状态

### 3.6 页面改动汇总

| 页面 | 改动 |
|------|------|
| 设置页 | 新增「通过 BLE 直连设备」开关 + 轮询周期选项（60/180/300s） |
| 配网成功页 | 自动绑定结果提示（"设备已绑定到您的账号" / "登录后自动绑定"） |
| 设备列表/详情页 | BLE 可用时显示「BLE」数据源徽标；数据混合展示（本地轮询优先，HTTP 兜底）；详情页新增日志入口 |
| 设备控制页 | 命令通道透明切换（HTTP 优先 / BLE 兜底），无需新页面 |
| 操作日志页（新） | 见 §3.5 |
| 绑定确认对话框（新） | 场景 B 一键确认 |

### 3.7 解绑流程

```
用户在设备详情页发起解绑
→ 调后端 POST /devices/:sn/unbind（云端解除绑定关系，审计落 audit_logs）
→ 清除本地 device_key（SecureStorageBleDeviceKeyStore.delete）
→ 断开 BLE 会话
→ 记录解绑日志（action=unbind）
→ 提示："设备已解绑；如需重新绑定到其他账号，请让设备进入重新绑定状态（设备按键 / 恢复出厂设置）"
```

设备端 device_key 保留在 NVS；固件「重绑窗口」机制（配网后 10 分钟 / 按键授权）允许覆盖。**用户无需手动恢复出厂**——由 App 在重新绑定时引导（进入绑定窗口后自动覆盖）。

---

## 4. 后端扩展（business-api）

### 4.1 绑定接口扩展（返回 device_key）

`POST /api/v1/devices/bind`（现有 `DeviceHandler.Bind`）：

- 响应增加 `device_key`（32 字节随机数 Base64）与 `expires`（过期时间，用于提示绑定窗口）
- 生成：`crypto/rand` 32 字节 → Base64
- 落库：`devices` 表新增列 `device_key`（加密存储或哈希存储，**禁止明文**；与 SN 一对一）——建议存 device_key 的 SHA-256 摘要用于校验，原始 key 仅下发一次（与协议 §4.1"云端可吊销并重发"一致：重新绑定时重新生成覆盖）
- 迁移：新增 migration（devices 表加列 + 索引）

### 4.2 新表 `device_offline_op_logs`

```sql
CREATE TABLE device_offline_op_logs (
    id BIGSERIAL PRIMARY KEY,
    log_id VARCHAR(64) NOT NULL UNIQUE,      -- App 本地 UUID，幂等键
    user_id BIGINT NOT NULL,                  -- 同步时归属用户
    device_sn VARCHAR(50) NOT NULL,
    action VARCHAR(50) NOT NULL,              -- bind/unbind/power_on/power_off/set_power/set_param/ota
    params JSONB DEFAULT '{}',
    result VARCHAR(50) DEFAULT 'ok',
    channel VARCHAR(10) DEFAULT 'ble',        -- cloud/ble
    op_time TIMESTAMPTZ NOT NULL,             -- 本地操作时间（App 上报）
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, log_id)
);
CREATE INDEX idx_offline_logs_user_time ON device_offline_op_logs(user_id, op_time DESC);
CREATE INDEX idx_offline_logs_sn ON device_offline_op_logs(device_sn);
```

- `log_id` 唯一约束实现幂等（重复上报 `ON CONFLICT DO NOTHING`）

### 4.3 上报接口

`POST /api/v1/devices/offline-logs`（需登录）：

```json
{
  "logs": [
    { "log_id": "uuid", "device_sn": "H1CNA...", "action": "set_power",
      "params": {"power_w": 3000}, "result": "ok", "channel": "ble",
      "op_time": "2026-08-10T08:00:00Z" }
  ]
}
```

- 响应：`{"accepted": 45, "duplicates": 2}`（accepted=新写入，duplicates=幂等跳过）
- 单批上限 50 条；`action` 白名单校验；`log_id` 格式校验（UUID）
- 写入 `device_offline_op_logs`；同时**不重复写** `audit_logs`（离线日志独立审计域）

### 4.4 管理后台（可选，本期不做）

管理后台查询离线日志（按用户/设备/时间）——列为后续扩展，本期仅落库。

---

## 5. 固件对齐要求（ESP32 端）

固件按《BLE 本地模式实现方案（修订版 V2）》实施，并应用以下修订：

### 5.1 GATT 定义（已对齐，确认）

| 名称 | UUID | 权限（修订后） |
|------|------|----------------|
| CSIV-CT 服务 | `43534956-4354-1000-8000-00805f9b34fb` | — |
| AUTH | `43534956-4155-1000-8000-00805f9b34fb` | Write + Notify |
| TELEMETRY | `43534956-544c-1000-8000-00805f9b34fb` | **Read + Notify（修订①：加 Read，支撑 180s 轮询）** |
| COMMAND | `43534956-434d-1000-8000-00805f9b34fb` | Write |
| CMD_RESULT | `43534956-4352-1000-8000-00805f9b34fb` | Notify |
| INFO | `43534956-494e-1000-8000-00805f9b34fb` | Read |

### 5.2 修订清单（V2 计划需修改项）

| 级别 | 修订 | 说明 |
|------|------|------|
| P0 | ① 时钟校准机制 | 见 §5.3；协议 §5.1 同步修订（修订②） |
| P0 | ② 特征不加链路层 ENC 标志 | 否则未配对时无法读 INFO / 写 AUTH bind，绑定死锁；加密靠配对后自动链路加密 |
| P0 | ③ 连接/断开/订阅事件转发 | ble_prov 的 gap_event_cb 转发 CONNECT/DISCONNECT/SUBSCRIBE/MTU 给 ble_ct；断开时重置鉴权状态（协议 §5"断开即失效"）；单中心连接（已有连接时拒绝新连接） |
| P1 | ④ 跨文件句柄导出 | `ble_ct_get_telemetry_handle()` / `ble_ct_get_result_handle()`（现引用 ble_ct.c 内部变量，编译失败） |
| P1 | ⑤ 幂等缓存归位 | 移到 ble_ct_cmd.c；加过期策略（10 分钟）；`timestamp_ms` 生效 |
| P1 | ⑥ 统一用 mbedtls | `mbedtls_base64_encode/decode` + `mbedtls_md_hmac`（HMAC-SHA256），去掉 monocypher 依赖与 TODO |
| P1 | ⑦ 多帧上限处理 | 遥测 JSON 超过 8 帧（4072B）时**拒绝推送并告警**，禁止静默截断 |
| P1 | ⑧ 锁定按 MAC | 鉴权失败计数按对端 MAC 记录（协议 §5.2） |
| P2 | ⑨ action 映射核对 | `power_on/power_off/set_power/set_param/get_param` 与 cmd_handler 46 命令名逐一核对，禁止臆造映射 |
| P2 | ⑩ 遥测裁剪核心子集 | BLE 通道推送 §6.1 核心子集（6 组字段），降低分帧与带宽 |
| P2 | ⑪ 绑定窗口守卫 | 已绑定设备上 `open_bind_window()` 无效（防配网成功后误开重绑窗口） |

### 5.3 时钟校准机制（P0-① 方案定稿）

设备无 RTC，离线无 NTP。采用**"BLE 鉴权消息时间戳校准 + uptime 推算"**：

```
设备虚拟时钟：device_now = s_time_base + (uptime_now - s_base_uptime)
校准源优先级：
  ① 配网后 NTP（在线时，存 NVS：s_time_base + 校准时 uptime）
  ② 每次成功鉴权（auth）时的 ts（App Unix 时间戳）——离线兜底
  ③ 绑定（bind）消息的 issued_at
```

- 时序：App write AUTH `{mode:auth, nonce, ts}` → 设备用当前 device_now 校验 `|device_now - ts| ≤ 300s` → 计算 HMAC 返回 → **成功后校准** `s_time_base = ts`，NVS 持久化（重启有效）
- 安全：仅鉴权/绑定成功触发校准，而成功前提是持有 device_key → 只有合法绑定方能校准；恶意伪造 ts 无法通过 HMAC，不会污染时钟
- 实现：ble_ct_auth.c 增加时钟模块（`ble_ct_now()` / `ble_ct_calibrate(ts)`，约 30 行）

---

## 6. 协议文档修订（BLE_Local_Communication_Protocol.md）

| # | 位置 | 修订内容 |
|---|------|----------|
| 修订① | §2.2 TELEMETRY 行 | 权限从"通知"改为"**读 + 通知**"：Read 返回最近一次遥测快照（App 轮询用）；数据突变仍即时 Notify |
| 修订② | §5.1 | 增加时间校准约定：*"设备无 RTC 时，以最近一次成功鉴权（auth/bind）消息中的 `ts` 作为时间基准，配合 uptime 推算本地时钟；NVS 持久化基准值；NTP 可用时优先 NTP。只有鉴权/绑定成功才触发校准。"* |

---

## 7. 数据流时序

### 7.1 自动绑定（场景 A，配网成功后）

```
App(BLE配网连接中) ──read SN──▶ 设备
App ──read INFO──▶ 设备 → {bound:false}
App ──POST /devices/bind──▶ 后端 → {device_key, expires}
App ──write AUTH{bind,device_key,issued_at}──▶ 设备 → NVS 持久化
设备 ──notify AUTH──▶ App {result:"ok"}
App 存 secure_storage → 记日志(bind, cloud) → 配网成功页提示
```

### 7.2 轮询（设置开 + 已绑定 + ready）

```
App 每 180s ──read TELEMETRY──▶ 设备 → 最新遥测快照
App 解析 InverterRealtime → 刷新设备列表/详情页（「BLE」徽标）
设备 80s 节拍/数据突变 ──notify TELEMETRY──▶ App 实时刷新（并存）
```

### 7.3 控制（离线兜底）

```
用户操作 → HTTP 不可达
App ──write COMMAND{command_id,action,params,ts}──▶ 设备（幂等缓存）
设备 ──notify CMD_RESULT──▶ App {command_id,status,data/error}
App 记日志(action, params, result, channel=ble) → UI 反馈
```

### 7.4 日志同步

```
本地操作 → 写 local_op_logs(pending)
网络恢复 / App 启动 / 手动
App ──POST /devices/offline-logs(≤50条)──▶ 后端（log_id 幂等）
成功 → 标记 synced；失败 → 指数退避重试（30s~60min 封顶，5 次后 failed 待手动）
```

---

## 8. 测试计划

### 8.1 App 单元测试

- `OfflineOpLogStore`：CRUD、容量滚动清理（500 条/30 天）、状态机迁移（pending→syncing→synced/failed）
- `OfflineLogSyncService`：批处理（≤50）、退避时序（mock 时间）、幂等（重复 log_id 不再上传）、未登录跳过
- `BleBindingService`：编排状态机（读 SN 失败 / bound=true 跳过 / 未登录分支 / bind 写入失败重试）
- `BlePollingService`：周期调度、READ 失败降级（不影响 HTTP 数据源）

### 8.2 后端集成测试

- `POST /devices/bind`：返回 device_key 格式（Base64 32B）；重复绑定 5002
- `POST /devices/offline-logs`：幂等（同 log_id 重复上报 duplicates 计数）；action 白名单；未登录 401；批量 >50 拒绝

### 8.3 真机联调（固件 + App）

- 绑定：配网后自动绑定（bound false→true）；未绑定设备随时可绑（窗口对未绑定设备始终开放）；**已绑定设备重绑被拒**（already_bound，需恢复出厂/重绑窗口）
- 鉴权：成功 / 3 次失败锁定 60s / 时间戳偏差 >300s 拒绝
- 轮询：180s 读快照；设备重启后 NVS 时钟基准仍有效
- 控制：命令执行 + 幂等（同 command_id 重发返回首次结果）
- 日志：离线操作 10 条 → 断网重启 → 联网自动同步 → 服务端落库且无重复
- 解绑：云端解绑 + 本地 key 清除 + 重新绑定引导

---

## 9. 假设与约束

1. 固件按 V2 计划 + §5.2 修订实现 CSIV-CT（含 TELEMETRY Read）
2. 绑定必须联网且已登录（device_key 云端生成，协议硬约束）
3. BLE 单中心连接（协议 §1），App 连接期间设备本地通信由该 App 独占
4. 手机需授予蓝牙权限（Android 13+ 为 Nearby Devices 权限）
5. 设备端时钟校准依赖 App ts，App 时间异常（用户篡改）仅影响自身会话，无安全影响
6. 管理后台离线日志查询页为后续扩展，本期仅落库

---

## 10. 交付边界（本期不做）

- BLE OTA（OTA 继续走 WiFi HTTP 本地 OTA）
- 后台低功耗自动连接（协议 §1 提及，后续版本）
- 三级权限分级（用户/安装商/厂商，协议 §7.3，后续版本）
- 管理后台离线日志查询 UI
