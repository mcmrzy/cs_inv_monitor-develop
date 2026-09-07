# ESP32 固件 BLE 直连模式修订实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按设计文档 §5.2 的 12 条修订（含 P0-⑫ PIN 校验机制）改造 ESP32 固件 ble_ct 组件，实现：GATT 无 ENC 标志、事件转发、时钟校准、PIN 双入口校验、幂等/多帧/锁定等可靠性修订；同步修订协议文档 3 处。

**Architecture:** ESP-IDF + ESP32-C3（esp32c3fh4），ble_ct 组件（`ble_ct.c` / `ble_ct_auth.c` / `ble_ct_cmd.c` / 新增 `ble_ct_pin.c`）+ ble_prov 组件（配网，gap_event_cb 事件转发）。PIN 算法：HMAC-SHA256(PRODUCT_SECRET, SN) mod 1e6，设备端本地校验。

**Tech Stack:** ESP-IDF（GATT Server / NVS / mbedtls / eFuse）

**参考设计文档:** `docs/superpowers/specs/2026-08-10-ble-local-mode-design.md` §5（GATT/修订清单/时钟/PIN）、§6（协议修订）、§8.3（联调）

**前提约定:**
- 固件仓库不在当前工作区，文件路径为设计文档 §5 约定的组件相对路径（`components/ble_ct/`、`components/ble_prov/`），执行时在固件仓库内操作
- 修订编号与设计文档 §5.2 一致（①-⑫）
- 构建命令：`idf.py build`（固件仓库根目录）；无单元测试框架时以构建 + 静态检查 + 真机用例为验证手段
- 依赖：mbedtls 已集成于 ESP-IDF；HMAC 使用 `mbedtls_md_hmac`

---

### Task 1: 修订②——GATT 特征不加链路层 ENC 标志（P0）

**Files:**
- Modify: `components/ble_ct/ble_ct.c`（GATT 属性表定义）

**背景**：现有特征若带 `ESP_GATT_PERM_*_ENC_*` 权限，未配对时无法读 INFO / 写 AUTH bind → 绑定死锁。加密靠配对后自动链路加密。

- [ ] **Step 1: 核对现状**

```bash
grep -n "ENC\|PERM" components/ble_ct/ble_ct.c
```

确认是否存在 `ESP_GATT_PERM_READ_ENC_MITM` / `ESP_GATT_PERM_WRITE_ENC_MITM` / 特征属性位 `ESP_GATT_CHAR_PROP_BIT_ENC_*`。

- [ ] **Step 2: 移除 ENC 权限（若存在）**

所有特征权限改为明文读写（AUTH/COMMAND 为 Write，TELEMETRY 为 Read+Notify，CMD_RESULT 为 Notify，INFO 为 Read）：

```c
// 示例：AUTH 特征（Write + Notify，无 ENC 标志）
{ ESP_GATT_PERM_WRITE, ESP_GATT_CHAR_PROP_BIT_WRITE | ESP_GATT_CHAR_PROP_BIT_NOTIFY },
// TELEMETRY（修订① Read + Notify）
{ ESP_GATT_PERM_READ, ESP_GATT_CHAR_PROP_BIT_READ | ESP_GATT_CHAR_PROP_BIT_NOTIFY },
```

- [ ] **Step 3: 验证**

```bash
idf.py build
```

Expected: 编译通过；`grep -n "ENC" components/ble_ct/ble_ct.c` 无输出。
真机：未配对状态下 App 可读 INFO、可写 AUTH（bind 不因链路权限死锁）。

- [ ] **Step 4: 提交**

```bash
git add components/ble_ct/
git commit -m "fix(ble_ct): remove link-layer ENC flags from GATT characteristics"
```

---

### Task 2: 修订③——连接/断开/订阅事件转发（P0）

**Files:**
- Modify: `components/ble_prov/`（gap_event_cb）
- Modify: `components/ble_ct/ble_ct.c`（新增 `ble_ct_on_gap_event()`）

**背景**：ble_prov 已注册 `gap_event_cb`，但 CONNECT/DISCONNECT/SUBSCRIBE/MTU 事件未转发给 ble_ct；断开时鉴权状态未重置。

- [ ] **Step 1: 定义转发接口（ble_ct 侧）**

```c
// ble_ct.h
typedef enum {
    BLE_CT_EVT_CONNECT,
    BLE_CT_EVT_DISCONNECT,
    BLE_CT_EVT_SUBSCRIBE,
    BLE_CT_EVT_MTU_UPDATED,
} ble_ct_gap_evt_t;

void ble_ct_on_gap_event(ble_ct_gap_evt_t evt, const uint8_t *remote_mac, uint16_t mtu);
```

- [ ] **Step 2: 转发逻辑（ble_prov gap_event_cb 内）**

- `ESP_GATTS_CONNECT_EVT` → `ble_ct_on_gap_event(BLE_CT_EVT_CONNECT, ...)`；**单中心守卫**：已有连接时 `esp_ble_gap_disconnect` 拒绝新连接
- `ESP_GATTS_DISCONNECT_EVT` → 转发 DISCONNECT
- `ESP_GATTS_READ_EVT` / `ESP_GATTS_WRITE_EVT`（含 `ESP_GATT_WRITE_TYPE`）→ 按句柄分发给 ble_ct 对应处理函数
- `ESP_GATTS_MTU_EVT` → 转发 MTU_UPDATED（更新 ble_ct 分帧 mtu 上下文）
- `ESP_GATTS_REG_FOR_NOTIFY_EVT` / 订阅相关 → 转发 SUBSCRIBE

- [ ] **Step 3: 断开重置（ble_ct 侧）**

`BLE_CT_EVT_DISCONNECT` 时：`authenticated = false`、清空命令队列、重置 AUTH 等待态、**保留 PIN/鉴权锁定计数**（防断开重连绕过锁定）；遥测推送上下文重置。

- [ ] **Step 4: 验证**

```bash
idf.py build
```

真机：连接后断开，再连接需重新鉴权；第二台手机连接时被拒（单中心）。

- [ ] **Step 5: 提交**

```bash
git add components/ble_prov/ components/ble_ct/
git commit -m "feat(ble_ct): forward gap events, reset auth on disconnect, single central guard"
```

---

### Task 3: 修订①+§5.3——时钟校准模块（P0）

**Files:**
- Modify: `components/ble_ct/ble_ct_auth.c`（新增时钟模块，约 30 行）
- Modify: `components/ble_ct/ble_ct_auth.h`

**方案**：设备虚拟时钟 `device_now = s_time_base + (uptime_now - s_base_uptime)`；校准源优先级：NTP > 鉴权 ts > bind issued_at；仅鉴权/绑定成功触发。

- [ ] **Step 1: 时钟模块实现**

```c
// ble_ct_auth.c
static int64_t  s_time_base;      // 校准 Unix 时间戳（ms）
static uint32_t s_base_uptime;    // 校准时 uptime（ms，esp_timer_get_time()/1000）
static bool     s_clock_valid;

int64_t ble_ct_now(void) {
    if (!s_clock_valid) return 0;
    uint32_t up = (uint32_t)(esp_timer_get_time() / 1000);
    // 重启保护：uptime 从 0 重计，若小于基准则视基准 uptime 为 0（误差=上次开机时长，可接受）
    uint32_t base_up = (up < s_base_uptime) ? 0 : s_base_uptime;
    return s_time_base + (up - base_up);
}

void ble_ct_calibrate(int64_t ts) {
    s_time_base = ts;
    s_base_uptime = (uint32_t)(esp_timer_get_time() / 1000);
    s_clock_valid = true;
    // NVS 持久化：nvs_set_i64("ble_time_base") / nvs_set_u32("ble_base_uptime")
}
```

- [ ] **Step 2: 校准触发点接入**

- 鉴权成功（auth 校验通过）→ `ble_ct_calibrate(msg.ts)`
- 绑定成功（bind result ok）→ `ble_ct_calibrate(msg.issued_at)`
- 配网后 NTP 成功（已有在线逻辑）→ 优先 NTP 校准（同一函数）

- [ ] **Step 3: 鉴权时间戳校验改造**

AUTH `{mode:auth, nonce, ts}` 处理：`|ble_ct_now() - ts| > 300000`（300s）→ 拒绝 `{result:"rejected", reason:"ts_out_of_range"}`。

- [ ] **Step 4: 启动恢复**

`ble_ct_auth_init()` 读 NVS：存在 `ble_time_base` → 恢复 `s_time_base`/`s_base_uptime`/`s_clock_valid=true`。

- [ ] **Step 5: 验证**

```bash
idf.py build
```

真机：绑定后 App 查询设备时间误差 <5s；设备重启后时钟基准仍有效（NVS）；ts 偏差 >300s 鉴权被拒。

- [ ] **Step 6: 提交**

```bash
git add components/ble_ct/
git commit -m "feat(ble_ct): virtual clock with auth/bind timestamp calibration & NVS persistence"
```

---

### Task 4: 修订⑫+§5.4——PIN 校验机制（P0，新增）

**Files:**
- Create: `components/ble_ct/ble_ct_pin.c` / `ble_ct_pin.h`
- Modify: `components/ble_ct/ble_ct_auth.c`（AUTH 消息处理：pin_check / bind 带 pin）
- Modify: `components/ble_ct/CMakeLists.txt`（源文件注册）

**方案**：PIN = HMAC-SHA256(PRODUCT_SECRET, SN) 取前 3 字节 mod 1e6；设备端本地校验；配网/绑定双入口；按 MAC 失败计数 5 次锁 30 分钟。

- [ ] **Step 1: 先写测试向量（纯函数，编译期验证）**

```c
// ble_ct_pin_test.c（或在 main 中临时自检；无单测框架时用 idf.py build + 启动日志断言）
#include "ble_ct_pin.h"
// 向量：SN="CS-L10-6K2-TEST0001" 时 compute_pin 输出应与工厂工具一致
// 工厂工具先行生成 3 组 (SN → PIN) 向量，固件自检比对
```

- [ ] **Step 2: PIN 模块实现**

```c
// ble_ct_pin.h
uint32_t ble_ct_compute_pin(const char *sn);
bool     ble_ct_pin_verify(const char *sn, uint32_t pin, const uint8_t *remote_mac);
bool     ble_ct_pin_locked(const uint8_t *remote_mac);
void     ble_ct_pin_reset(const uint8_t *remote_mac);   // 成功后清零
```

```c
// ble_ct_pin.c
// 编译时嵌入（产品线共享，保密；Secure Boot + Flash Encryption 缓解提取）
static const char PRODUCT_SECRET[] = "CS_INV_L10_2026_SECRET";

uint32_t ble_ct_compute_pin(const char *sn) {
    uint8_t digest[32];
    mbedtls_md_hmac(MBEDTLS_MD_SHA256,
                    (const uint8_t *)PRODUCT_SECRET, sizeof(PRODUCT_SECRET) - 1,
                    (const uint8_t *)sn, strlen(sn), digest);
    return ((digest[0] << 16) | (digest[1] << 8) | digest[2]) % 1000000;
}
```

- [ ] **Step 3: 锁定机制（按 MAC）**

```c
// 失败计数表：最多 8 个 MAC 槽，LRU 淘汰
typedef struct { uint8_t mac[6]; uint8_t fails; int64_t locked_until; } pin_lock_entry_t;
// 校验失败：fails+1；fails >= 5 → locked_until = ble_ct_now() + 30*60*1000
// 锁定期间返回 rejected:locked；成功 → fails=0
```

（RAM 状态，断电解除；与鉴权锁定 ⑧ 分离计数。）

- [ ] **Step 4: AUTH 消息接入**

- `mode == "pin_check"`（配网入口，写 WiFi 凭据前）：
  - 设备未绑定或绑定窗口内 → `ble_ct_pin_verify(sn, pin, mac)` → notify `{result:"ok"}` / `{result:"rejected", reason:"invalid_pin"}` / `{result:"rejected", reason:"locked"}`
  - 已绑定 → `{result:"rejected", reason:"already_bound"}`（修订⑪协同）
- `mode == "bind"` 且消息含 `pin` 字段（场景 B）→ 先 PIN 校验，失败不写 key；成功 → NVS 持久化 device_key → notify `{result:"ok"}`
- `mode == "bind"` 且无 pin（场景 A，配网已验）→ 维持原逻辑（bound=false 才允许）

- [ ] **Step 5: 安全加固**

- `PRODUCT_SECRET` 不落单一明文字符串：按偏移分片拼接 + 编译期混淆（至少拆 3 段）——提高反编译提取门槛
- 建议固件工程启用 `CONFIG_SECURE_BOOT` + `CONFIG_SECURE_FLASH_ENC_ENABLED`

- [ ] **Step 6: 验证**

```bash
idf.py build
```

真机用例（§8.3）：PIN 正确绑定成功；PIN 错误 rejected:invalid_pin；连续 5 次错误 → rejected:locked（30 分钟）；重启后锁定解除；无 PIN 写 WiFi 凭据被拒。

- [ ] **Step 7: 提交**

```bash
git add components/ble_ct/
git commit -m "feat(ble_ct): PIN verification (HMAC(secret,SN) mod 1e6) with per-MAC lockout"
```

---

### Task 5: 修订④——跨文件句柄导出（P1）

**Files:**
- Modify: `components/ble_ct/ble_ct.c` / `ble_ct.h`

- [ ] **Step 1: 导出接口**

```c
// ble_ct.h
uint16_t ble_ct_get_telemetry_handle(void);
uint16_t ble_ct_get_result_handle(void);
```

实现返回 ble_ct.c 内部注册句柄（现有跨文件引用编译失败点）。

- [ ] **Step 2: 替换外部直接引用**

`grep -rn "telemetry_handle\|result_handle" components/` 找出引用处，改为调用导出函数。

- [ ] **Step 3: 验证 + 提交**

```bash
idf.py build
git add components/ble_ct/ && git commit -m "refactor(ble_ct): export GATT handle accessors"
```

---

### Task 6: 修订⑤——幂等缓存归位 + 过期策略（P1）

**Files:**
- Modify: `components/ble_ct/ble_ct_cmd.c`

- [ ] **Step 1: 幂等缓存迁移**

将幂等缓存（现散落在其他文件）集中到 `ble_ct_cmd.c`：

```c
#define CMD_IDEMPOTENT_TTL_MS (10 * 60 * 1000)   // 10 分钟过期
typedef struct { char command_id[37]; char result[512]; int64_t ts; } cmd_cache_entry_t;
```

- [ ] **Step 2: `timestamp_ms` 生效**

COMMAND 消息 `{command_id, action, params, ts}`：设备端校验 `|ble_ct_now() - ts| ≤ 阈值`（建议 30s 窗口，与时钟校准联动），超窗拒绝 `{status:"error", reason:"ts_out_of_range"}`（防重放）。

- [ ] **Step 3: 命中/过期行为**

- 命中且未过期 → 返回首次结果（不重复执行）
- 过期 → 执行并覆盖缓存
- 缓存上限 32 条，满则淘汰最旧

- [ ] **Step 4: 验证 + 提交**

```bash
idf.py build
git add components/ble_ct/ && git commit -m "refactor(ble_ct): centralize command idempotent cache with TTL"
```

---

### Task 7: 修订⑥——统一 mbedtls（P1）

**Files:**
- Modify: `components/ble_ct/ble_ct_auth.c` 等（替换 monocypher）

- [ ] **Step 1: 替换加密原语**

- Base64：`mbedtls_base64_encode / mbedtls_base64_decode`
- HMAC-SHA256：`mbedtls_md_hmac(MBEDTLS_MD_SHA256, ...)`
- 删除 monocypher 依赖（`crypto_monocypher*` 引用、CMakeLists 链接、TODO 注释）

- [ ] **Step 2: 验证 + 提交**

```bash
idf.py build
grep -rn "monocypher" components/ble_ct/   # 应无输出
git add components/ble_ct/ && git commit -m "refactor(ble_ct): unify on mbedtls crypto, drop monocypher"
```

---

### Task 8: 修订⑦——多帧上限处理（P1）

**Files:**
- Modify: `components/ble_ct/ble_ct.c`（分帧推送逻辑）

- [ ] **Step 1: 上限守卫**

分帧格式：1 字节控制头 + 最多 508B 数据（BLE MTU 512 减去开销）。遥测 JSON 超过 **8 帧（4072B）** → 拒绝推送并 `ESP_LOGW` 告警（含长度统计），**禁止静默截断**。

```c
#define TELEMETRY_MAX_FRAMES 8
#define TELEMETRY_MAX_BYTES  (TELEMETRY_MAX_FRAMES * 508)
if (json_len > TELEMETRY_MAX_BYTES) {
    ESP_LOGW(TAG, "telemetry too large: %d bytes > %d, drop notify", json_len, TELEMETRY_MAX_BYTES);
    return ESP_ERR_INVALID_SIZE;
}
```

- [ ] **Step 2: 验证 + 提交**

```bash
idf.py build
git add components/ble_ct/ && git commit -m "fix(ble_ct): reject oversized telemetry frames instead of truncating"
```

---

### Task 9: 修订⑧——锁定按 MAC（P1）

**Files:**
- Modify: `components/ble_ct/ble_ct_auth.c`

- [ ] **Step 1: 鉴权失败计数按 MAC**

现有鉴权失败计数（3 次锁定 60s）改为**按对端 MAC 记录**（与 PIN 锁定表结构一致，可共用 LRU 槽位机制）：不同设备（MAC）失败计数互不影响。

- [ ] **Step 2: 验证 + 提交**

```bash
idf.py build
git add components/ble_ct/ && git commit -m "fix(ble_ct): track auth failures per remote MAC"
```

---

### Task 10: 修订⑨——action 映射核对（P2）

**Files:**
- Modify: `components/ble_ct/ble_ct_cmd.c`（命令映射表）

- [ ] **Step 1: 核对映射**

`power_on / power_off / set_power / set_param / get_param` 与 cmd_handler 现有 46 个命令名**逐一核对**（生成对照表，禁止臆造映射）；不一致的命令名以 cmd_handler 权威实现为准修正。

- [ ] **Step 2: 产出对照表**

在 ble_ct_cmd.c 顶部注释维护 `/* BLE action → cmd_handler 命令对照表（核对日期）*/`，覆盖全部映射。

- [ ] **Step 3: 验证 + 提交**

```bash
idf.py build
git add components/ble_ct/ && git commit -m "docs(ble_ct): align BLE action map with cmd_handler commands"
```

---

### Task 11: 修订⑩——遥测裁剪核心子集（P2）

**Files:**
- Modify: `components/ble_ct/ble_ct.c`（推送/Read 快照内容）

- [ ] **Step 1: 定义核心子集（6 组字段）**

BLE 通道推送 §6.1 核心子集（6 组，与 App `InverterRealtime` 对齐）：

```c
// 示例：总功率 / 三相电压 / 三相电流 / 直流输入 / 温度 / 状态
// 字段清单以协议 §6.1 为准，由固件 team 与 App team 联合确认
```

- [ ] **Step 2: 推送与 Read 快照统一走子集**

80s 节拍推送、突变推送、Read 快照均输出核心子集 JSON（而非全量遥测），降低分帧数与带宽。

- [ ] **Step 3: 验证 + 提交**

```bash
idf.py build
git add components/ble_ct/ && git commit -m "feat(ble_ct): push telemetry core subset over BLE"
```

---

### Task 12: 修订⑪——绑定窗口守卫（P2）

**Files:**
- Modify: `components/ble_ct/`（绑定窗口状态机）

- [ ] **Step 1: 守卫逻辑**

```c
// open_bind_window(): 已绑定（NVS 存在 device_key）→ 拒绝并告警，不进入窗口
bool open_bind_window(void) {
    if (ble_ct_is_bound()) {
        ESP_LOGW(TAG, "bind window rejected: device already bound");
        return false;
    }
    bind_window_open = true;      // 配网后 10 分钟 / 按键授权
    bind_window_expire = ble_ct_now() + 10 * 60 * 1000;
    return true;
}
```

- [ ] **Step 2: 配网入口联动**

已绑定设备：配网流程（CSIV-PR 写凭据）与 pin_check 均返回 already_bound（与 Task 4 联动）。

- [ ] **Step 3: 验证 + 提交**

```bash
idf.py build
git add components/ble_ct/ && git commit -m "fix(ble_ct): guard bind window when already bound"
```

---

### Task 13: 协议文档修订（§6 三处）

**Files:**
- Modify: `docs/BLE_Local_Communication_Protocol.md`（固件仓库内）

- [ ] **Step 1: 修订①（§2.2 TELEMETRY 行）**

权限从"通知"改为"**读 + 通知**"：Read 返回最近一次遥测快照（App 轮询用）；数据突变仍即时 Notify。

- [ ] **Step 2: 修订②（§5.1）**

增加时间校准约定（设计文档 §6 修订②原文）。

- [ ] **Step 3: 修订③（§5.x 新增）**

增加 PIN 校验约定（设计文档 §6 修订③原文：双入口、算法、锁定、PRODUCT_SECRET 约定）。

- [ ] **Step 4: 提交**

```bash
git add docs/BLE_Local_Communication_Protocol.md
git commit -m "docs(protocol): telemetry read permission, time calibration, PIN verification"
```

---

### Task 14: 全量构建 + 真机联调验证（§8.3）

- [ ] **Step 1: 全量构建 + 静态检查**

```bash
idf.py fullclean && idf.py build
# 若工程有 lint/静态检查目标一并执行
```

Expected: 0 error；`grep -rn "TODO\|FIXME" components/ble_ct/` 仅剩计划内项。

- [ ] **Step 2: 真机联调（需 App 联调机 + 后端测试环境）**

| 用例 | 预期 |
|------|------|
| 配网：无 PIN 写 WiFi 凭据 | 被拒（pin_check 拦截） |
| 配网：PIN 正确 | 配网成功 → 自动绑定（bound false→true，离线） |
| 绑定：场景 B 错误 PIN ×5 | rejected:locked，30 分钟内拒绝 |
| 绑定：已绑定设备重绑 | already_bound（守卫 ⑪ + PIN 守卫） |
| 鉴权：3 次失败 | 按 MAC 锁定 60s |
| 鉴权：ts 偏差 >300s | rejected:ts_out_of_range |
| 时钟：绑定后 App 读设备时间 | 误差 <5s；重启后 NVS 基准仍有效 |
| 轮询：180s Read 快照 | 返回核心子集 JSON；>4072B 遥测拒绝不截断 |
| 控制：同 command_id 重发 | 返回首次结果（幂等缓存，10 分钟 TTL） |
| 遥测：80s 节拍 + 突变 Notify | App 实时刷新（与轮询并存） |
| 事件：断开重连 | 需重新鉴权；锁定状态保留 |
| 单中心：第二台手机连接 | 被拒 |

- [ ] **Step 3: 联调问题回归**

联调中发现的问题按 `systematic-debugging` 处理；涉及协议字段的变更需回写设计文档 §5/§6 并同步 App/后端计划附录。

---

## 自审记录（plan 完成时填写）

### Spec 覆盖核对

| 设计文档章节 | 计划 Task | 状态 |
|---|---|---|
| §5.2-① 时钟校准（含 §5.3 定稿） | Task 3 | ✅ |
| §5.2-② 无 ENC 标志 | Task 1 | ✅ |
| §5.2-③ 事件转发 | Task 2 | ✅ |
| §5.2-④ 句柄导出 | Task 5 | ✅ |
| §5.2-⑤ 幂等缓存归位 | Task 6 | ✅ |
| §5.2-⑥ mbedtls 统一 | Task 7 | ✅ |
| §5.2-⑦ 多帧上限 | Task 8 | ✅ |
| §5.2-⑧ 锁定按 MAC | Task 9 | ✅ |
| §5.2-⑨ action 映射核对 | Task 10 | ✅ |
| §5.2-⑩ 遥测裁剪 | Task 11 | ✅ |
| §5.2-⑪ 绑定窗口守卫 | Task 12 | ✅ |
| §5.2-⑫ PIN 校验（含 §5.4 定稿） | Task 4 | ✅ |
| §6 协议修订①②③ | Task 13 | ✅ |
| §8.3 真机联调 | Task 14 | ✅ |

### 依赖与接口一致性

- PIN 算法：固件 `ble_ct_compute_pin` 与工厂工具同算法（测试向量先行，Task 4 Step 1）✅
- 锁定计数：PIN 锁定（5 次/30 分钟）与鉴权锁定（3 次/60s）分离，互不干扰 ✅
- 时钟：`ble_ct_now()` 供鉴权 ts 校验（Task 3）、命令 ts 窗口（Task 6）、绑定窗口过期（Task 12）共用 ✅
- 协议修订③（PIN）依赖 Task 4 实现先落地，文档修订（Task 13）后置 ✅

### 范围说明

- 固件仓库不在当前工作区：Task 文件路径为组件相对路径，执行时在固件仓库内落地
- 工厂工具（PC 端 PIN 打印）为独立交付物：固件计划只定义算法与测试向量，工具由工厂侧实现（持 PRODUCT_SECRET）
- Secure Boot / Flash Encryption 为固件工程配置项（Task 4 Step 5 建议），是否启用由固件团队按量产策略决定
