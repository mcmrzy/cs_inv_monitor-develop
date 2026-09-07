# 储能 BMS 遥测扩展协议设计（ARM/ESP32 侧增加内容）

> 2026-09-07。目标：为 Web/App 储能页面提供数据。依据：《储能BMS页面设计方案.md》《储能BMS参数总表.md》、
> BMS 固件 LUX/Growatt CAN 协议帧（`external/储能bms`）、采集器协议寄存器映射（`collector_protocol_print.html`）、
> 心跳 V2.1 规范（`CS-L10-6K2_MQTT_上报协议设计_V2.1.md`）。
> 约束：**心跳信封 v=2 不变，纯 additive**——新组追加在 `sock` 之后，既有 57 个位置冻结不动，旧固件/旧解析器双向兼容。

---

## 1. 页面需求 → 链路字段追溯总表

| 页面组件 | 字段 | BMS→ARM CAN 来源 | ARM 能否拿到 | 现状 |
|---|---|---|---|---|
| SOC 圆环 | SOC | 0x355 / 0x313 | ✅ | ✅ 已上云 bat[1] |
| 功率/电流卡 | 总压、电流、充/放功率 | 0x356 / 0x313 | ✅ | ✅ 已上云 bat[0/2/3/4] |
| 健康卡 | **SOH** | 0x355(1%) / 0x313(1%) | ✅ | ❌ 需新增 |
| 容量卡 | **剩余容量 / FCC** | LUX 0x359 仅 FCC(1Ah)；Growatt 0x314 剩余容量(0.1Ah) | ✅（LUX 下剩余容量=FCC×SOC 换算） | ❌ 需新增 |
| 寿命卡 | **循环次数** | LUX 0x35C ✅；Growatt 0x314 写死 0（BMS 固件 bug） | ✅（建议走 LUX 0x35C） | ❌ 需新增 |
| 电芯极值卡 | **最高/最低芯压 mV** | 0x355 / 0x319 | ✅ | ❌ 需新增 |
| | **芯压序号** | 仅 Growatt 0x319；LUX 无 | ⚠️ 协议相关 | ❌ |
| | **压差 mV** | LUX 可算(max−min)；Growatt 0x314 直接给 | ✅ | ❌ |
| 温度卡 | **最高/最低芯温 0.1℃** | 0x356 / 0x313 | ✅ | ❌ 需新增 |
| | **温度序号** | 仅 Growatt 0x322 | ⚠️ 协议相关 | ❌ |
| 限值面板 | **请求限充压/限充电流/限放电流/放电截止** | 0x351 | ✅ | ❌ 需新增 |
| 告警面板 | **保护位图 + 告警位图** | 0x359 Byte0/1=保护，Byte2/3=告警（位定义见 §4.1） | ✅ | ❌ 需新增（现 sys[3] 语义不明） |
| 使能状态 | **充/放使能、满充请求** | 0x35C / 0x319 | ✅ | ❌ 需新增 |
| 接入识别 | **BMS 在线 / 厂商** | 在线=0x355/0x356 帧超时判定（逆变器侧新增逻辑）；厂商仅 Growatt 0x320 "BJ" | ✅/⚠️ | ❌ 需新增 |
| 电芯柱状图 | **16 芯电压数组** | 仅 Growatt 0x315~0x318；**LUX 协议不带** | ⚠️ 仅 Growatt | ❌ |
| MOS 状态 | 充/放/预充 MOS ×4 | CAN 协议均不带（仅 SRNE/PACE 485 有） | ❌ CAN 下拿不到 | ❌ 三期 |

> 结论：**一期全部字段在 LUX（默认协议）下即可满足**；电芯数组与序号、MOS 状态受协议限制，列二期/三期。

---

## 2. ARM 侧增加（核心改动）

### 2.1 运行参数区新增寄存器（ESP32 可读）

在运行参数区开辟连续块（建议起始偏移 `+0x0200` 或 ARM 固件实际空闲处，下表偏移为占位）：

| 偏移 | 寄存器名 | 类型/量纲 | 来源 | 缺数据时填 |
|---|---|---|---|---|
| +0x0200 | `BmsOnline` | u8：0/1 | 收到 0x355 或 0x356 帧→置 1；**超时 5s 未收到→0**（与 BMS 侧 0x305 判逆变器完全对称） | 0 |
| +0x0201 | `BmsVendor` | u16：ASCII 两字符，如 'BJ'；0=未知 | Growatt 0x320；LUX 恒 0 | 0 |
| +0x0202 | `BmsSoh` | u16，1% | 0x355 byte2/3 | 0 |
| +0x0203 | `BmsRemainCap` | u16，0.1Ah | LUX：`FCC(0x359,1Ah)×SOC/100`；Growatt：0x314 直接 | 0 |
| +0x0204 | `BmsFullCap` | u16，0.1Ah | LUX 0x359 容量；Growatt 0x314（注意 BMS 侧 0x314 FCC 未实际写入帧的 bug，需 BMS 固件修复或按上一行换算） | 0 |
| +0x0205 | `BmsCycleCnt` | u16，次 | LUX 0x35C byte2/3 | 0 |
| +0x0206 | `BmsCellVoltMax` | u16，mV | 0x355 byte4/5 | 0 |
| +0x0207 | `BmsCellVoltMin` | u16，mV | 0x355 byte6/7 | 0 |
| +0x0208 | `BmsCellVoltDiff` | u16，mV | ARM 计算 max−min | 0 |
| +0x0209 | `BmsCellVoltMaxIdx` | u16，0 起 | Growatt 0x319；LUX 恒 0xFFFF | 0xFFFF |
| +0x020A | `BmsCellVoltMinIdx` | u16，0 起 | 同上 | 0xFFFF |
| +0x020B | `BmsTempMax` | s16，0.1℃ | 0x356 byte4/5 | 0x7FFF |
| +0x020C | `BmsTempMin` | s16，0.1℃ | 0x356 byte6/7 | 0x7FFF |
| +0x020D | `BmsTempMaxIdx` / `BmsTempMinIdx` | u16 ×2 | Growatt 0x322；LUX 恒 0xFFFF | 0xFFFF |
| +0x020F | `BmsChgLimitVolt` | u16，0.1V | 0x351 byte0/1 | 0 |
| +0x0210 | `BmsChgLimitCurr` | u16，0.1A | 0x351 byte2/3 | 0 |
| +0x0211 | `BmsDsgLimitCurr` | u16，0.1A | 0x351 byte4/5 | 0 |
| +0x0212 | `BmsDsgCutVolt` | u16，0.1V | 0x351 byte6/7 | 0 |
| +0x0213 | `BmsProtection` | u16 位图 | 0x359 Byte0 \| Byte1<<8 | 0 |
| +0x0214 | `BmsAlarm` | u16 位图 | 0x359 Byte2 \| Byte3<<8 | 0 |
| +0x0215 | `BmsChgEnable` / `BmsDsgEnable` | u8 ×2：0/1 | 0x35C Byte0 bit0/bit1 | 0 |
| +0x0217 | `BmsFullChgReq` | u8：0/1 | 0x35C Byte0 bit3 | 0 |
| +0x0218 | `BmsCellVolt[16]` | u16[16]，mV | Growatt 0x315~0x318；LUX 恒 0xFFFF | 0xFFFF |

共 24 项（含数组 16）。全部为**只读运行量**，不涉及控制参数区。

### 2.2 ARM 侧新增逻辑（唯一的行为改动）

1. **BmsOnline 超时判定**：CAN 接收任务里记录最近一次 0x355/0x356 帧到达时间，超 5s 未收到清 `BmsOnline`。这是全方案唯一的"新逻辑"，其余都是搬运已收到的帧字段。
2. **LUX 下剩余容量换算**：`remain = FCC × SOC / 100`（LUX 0x359 只发 FCC）。
3. **LUX 下压差计算**：`diff = max − min`。
4. 序号/数组类寄存器在 LUX 协议下填 `0xFFFF`（=无效），心跳层据此发 `null`。

### 2.3 ARM 明确不需要做的

- 告警 3 级明细、故障 32 位明细、MOS 状态、均衡状态、16 芯温度数组——CAN 协议本身不携带，属三期协议演进，不在本次范围。
- 任何控制类命令（强制 MOS、DO、解锁）。

---

## 3. ESP32 侧增加

### 3.1 心跳新增 `bms` 组（追加在 sock 之后）

```json
{ "v": 2, "t": 1783000000, "data": {
    "sys":[11], "pv":[5], "ac":[11], "chr":[3], "bat":[5], "eng":[14],
    "fan":[2], "diag":[3], "sock":[3],
    "bms":[20]          // ← 新增，20 值
}}
```

| 索引 | 字段键 | 量纲（scale） | null 条件 |
|---|---|---|---|
| 0 | `bms_online` | 1（0/1） | — |
| 1 | `battery_soh` | 1（%） | 离线 |
| 2 | `battery_capacity_remain` | 0.1（Ah） | 离线 |
| 3 | `battery_capacity_full` | 0.1（Ah） | 离线 |
| 4 | `battery_cycle_count` | 1（次） | 离线 |
| 5 | `cell_voltage_max` | 1（mV） | 离线 |
| 6 | `cell_voltage_min` | 1（mV） | 离线 |
| 7 | `cell_voltage_diff` | 1（mV） | 离线 |
| 8 | `cell_voltage_max_index` | 1 | 序号无效(0xFFFF) |
| 9 | `cell_voltage_min_index` | 1 | 同上 |
| 10 | `cell_temp_max` | 0.1（℃） | 离线 |
| 11 | `cell_temp_min` | 0.1（℃） | 离线 |
| 12 | `bms_chg_limit_voltage` | 0.1（V） | 离线 |
| 13 | `bms_chg_limit_current` | 0.1（A） | 离线 |
| 14 | `bms_dsg_limit_current` | 0.1（A） | 离线 |
| 15 | `bms_protection` | 1（位图 §4.1） | 离线 |
| 16 | `bms_alarm` | 1（位图 §4.1） | 离线 |
| 17 | `bms_chg_enable` | 1（0/1） | 离线 |
| 18 | `bms_dsg_enable` | 1（0/1） | 离线 |
| 19 | `bms_full_chg_request` | 1（0/1） | 离线 |

> `bms_online=0` 时整组其余 19 值发 `null`（服务器按 QualityPartial 记，前端显示"未接入电池"空态）。
> 现有 `sys[3] bms_warning` **保持不动**（兼容既有前端），新 `bms[16]` 才是语义明确的 0x359 位图；两者并行一个版本后弃用旧值。

### 3.2 电芯电压数组（二期，二选一）

- **方案 A（推荐）：心跳再加一组 `"cvt":[16]`**（cell voltage array，mV，Growatt 协议下发值，LUX 下整组 null）。符合 V2.1"单一快照"哲学，服务器按组长度自适应。代价：心跳从 77 值涨到 93 值。
- 方案 B：独立主题 `cs_inv/{sn}/data/cells`（60s，JSON 数组）。心跳保持小，但违背"不拆分多主题"原则，且要新开解析分支。
- 不论哪种，`device_cell_samples` 表结构已就绪（voltages/temperatures JSONB 列），云端写入链路复用 V1 的落库逻辑。

### 3.3 实现注意

- ESP32 对未知组需容忍（`DisallowUnknownFields` 只在服务端；ESP32 是组包方无此问题）。
- 轮询新寄存器可并入现有 180s 心跳前的一次性读取，不增加 UART 压力（新增 ≤40 个 u16）。
- `schema_hash` 升级为 `heartbeat-v2-csl10-6k2-v2.2-<date>`，信封 v 不变。

---

## 4. 云端配套（device-communication / business-api，简列）

1. `heartbeat_v2.go`：`heartbeatDataV2` 加 `Bms []json.RawMessage` / `Cvt []json.RawMessage`；**bms/cvt 组缺失视为合法**（49/57 值旧固件本来没有，不算 QualityPartial），存在则长度精确（20/16，cvt 容忍未来 32 芯扩展）；`v2Scales` 加 `"bms"`/`"cvt"` 表；`Sample` 加 `BMS`/`CellVolt` 结构。
2. `buildRealtimeV2`：Redis realtime 增加 `bms`/`cvt` 组透传（供前端实时轮询）。
3. 落库：bms 组标量列或 JSONB；cvt[16] 写 `device_cell_samples`（表已存在，V2 链路当前写空数组的兜底逻辑对齐）。
4. 迁移 09x：`telemetry_field_catalog` + `device_protocol_fields`（新组 `bms`/`cvt`，含 display_name_key/unit/scale）+ `schema_hash` 更新 + 前端字段能力（`is_visible`/`show_realtime`/`default_chart`）。
5. 前端：Web `BmsTab`/App 储能页按字段能力动态渲染（方案文档已定义灰显位点亮顺序）。

## 4.1 `bms_protection` / `bms_alarm` 位定义（LUX 0x359，需与 BMS 固件方书面确认）

| Byte | bit | 含义 |
|---|---|---|
| 0（保护） | 1/2/3/4/7 | 总压过压 / 总压欠压 / 高温 / 低温 / 放电过流 |
| 1（保护） | 0 / 3 | 充电过流 / 系统错误 |
| 2（告警） | 1/2/3/4/7 | 电压高 / 电压低 / 温度高 / 温度低 / 放电电流大 |
| 3（告警） | 0 / 3 | 充电电流大 / 内部通信故障 |

> bit0 与 5、6 为 reserve。**此表从 BMS 源码位域反推，落地前务必让固件组出一帧实测核对**。

---

## 5. 分期与工作量估计

| 期 | 范围 | 改动方 | 前置条件 |
|---|---|---|---|
| 一期 | §2 寄存器 24 项（LUX 可用子集，数组/序号填无效值）+ §3.1 心跳 `bms[20]` + 云端 §4 | ARM（逻辑仅 1 处超时判定 + 2 处换算）、ESP32（组包）、云端 | 无，LUX 为默认协议 |
| 二期 | `cvt[16]` 电芯数组 + 极值序号点亮 | 依赖现场逆变器↔BMS 使用 Growatt 协议，或 LUX 协议演进加帧 | 确认现场协议族 |
| 三期 | 身份（`BmsVendor` 点亮）、MOS 状态、告警 3 级明细 | 协议演进（Growatt 0x320 透传 / 自定义帧 / 485 协议） | 协议版本决策 |

## 7. ARM 源码核对结论（2026-09-07 第二版，修正活跃实现后，替代第一版）

> **重大更正**：第一版（基于 `ComBMS/UsartBms.c` 的 Modbus 主机分析）分析的是**未启用的死代码**。
> 真正编译运行的是 `UsartBMS485/UsartBms0.c`，协议也不是标准 Modbus，而是**储能 BMS 的 PC 485 协议（0x7C 帧）**。

### 7.1 实际链路（以任务调度与 Keil 工程编译清单为准）

- 任务调度：`Period100ms()`（`APP/SystemManage.c:63-71`，100ms 周期）→ **`ProcessUsart0Com1()`**；
  旧实现 `ProcessUsart0Com()` 在同处被注释（`//ProcessUsart0Com()`）。
- 门控条件（`UsartBms0.c:315`）：`锂电池模式 && configWord1.RS485Protocol==5(BBJ_BMS_PROTOCOL)`——对应控制参数 `Index_LiBatProtocolType 0x0030`，**协议类型是用户配置项**。
- 命令（`UsartBms0.c:21-32`）：发 `{0x7C, crcL, crcH, 0x80, 0x01, 0x00, 0x00}`——即储能 BMS 固件
  `PC_485_protocol.C` 的"命令 0x01 读电池信息"（帧头 0x7C + 地址 0x80），应答 = 16 芯电压 + 4 路温度 + pack_info 61 字节。
- 在线判定：`ReceiveNewFlag`（收到有效帧置 1，连续 3 次超时清 0，`UsartBms0.c:326-335`）。
  旧实现维护的 `SysParam.BMSDisconnected` 在活跃路径**无人置位**（仅初始化清 0）。

### 7.2 ARM 实际解析并存入 `batterySum1` 的字段（`RcvBMSPacket1`，UsartBms0.c:36-178）

| 内容 | 量纲（实际存储） | 备注 |
|---|---|---|
| 16 芯电压数组 | mV（取 bit12-0） | 极值 max/min 在解析时现算 |
| 温度：环境/PCB/MOS（类型 1/2/3） | ℃（raw−40） | **类型 0 电芯温度未存**；极值温度计算被注释 |
| 电流 | 10mA（0.1A×10） | 有符号 |
| 总压 | 10mV（0.1V×10） | |
| SOC / SOH | **0.1% 原样存**（代码注释"0.1%→%"有误导，未除 10；LCD 显示时 ÷10） | |
| 剩余/满充/额定容量 | 0.1Ah | |
| battery_mode | 0 静置/1 充/2 放/3 初始化/4 回充 | |
| battery_status | 1 字节 MOS 位（充/放/预放/预充） | |
| 循环次数 | 次 | |
| 累计充/放容量 | Ah（u32） | |
| 充电请求电流/电压 | 0.1A / 0.1V | |
| system_mode | 状态机编号 | |
| **未解析（跳过）** | **fault_status 4B、alarm_status 8B**——BMS 告警/故障明细没有进 ARM | `UsartBms0.c:135-141` |

> 量纲基准由 LCD 渲染代码反推确认（`Form/BatteryMonitoringForm.c`：SOC ÷10 显示、电压 ÷100、芯压 ÷1000、容量 ÷10）。

### 7.3 断点实锤：ESP32 链路完全没接 BMS 数据

`batterySum1` 的消费方只有 LCD 界面：`BatteryMonitoringForm.c`（58 处）、`AlarmForm.c`（9 处）、`BatteryForm.c`（1 处）。
**`Collector/Collector.c` 零引用**。因此：

- `ReadRunParam`（Collector.c:395-460）电池字段全是硬编码 50 占位；
- `ReadTestRunParam`（Collector.c:1250+）取的是 `SysParam.VbatA/BatPercent/Ibat`——这些来自 **DSP（USART1 帧，`UsartDsp.c:300`）**，即逆变器功率级自己的采样/估算，不是 BMS；
- 心跳 bat[5] 里的 SOC 是 **DSP 估算值**，与 BMS 真实 SOC 可能不一致。

LCD 电池页（BatteryMonitoringForm）已展示：16 芯电压（最高红/最低蓝+序号）、SOC/SOH、总压、电流、循环次数、压差、剩余/满充容量——**这就是现成的页面需求清单与算法参考**（极值序号 = 遍历 16 芯数组，`BatteryMonitoringForm.c:114-115`）。

### 7.4 ARM 侧改动清单（修正版，文件:行级）

1. `Collector/CollectorParamAddr.h`：`RunParamDef` 尾部追加 bms 组字段（标量 ~20 + `cellVolt[16]`），`RunParamEndIndex` 同步扩大。
2. `Collector/Collector.c ReadRunParam()`：占位 50 块替换为从 `batterySum1` 真实取值（SOC/SOH 记得 ×精度口径统一），新字段一并填充；在线位用 `ReceiveNewFlag`。
3. `UsartBMS485/UsartBms0.c RcvBMSPacket1()`：把跳过的 `fault_status(4B)`/`alarm_status(8B)` 解析进 `batterySum1` 新增字段（前端告警面板数据源）；按需补存电芯温度（类型 0）。
4. 可选：极值芯压/芯温序号照抄 LCD 页算法在 ARM 层算好，或由云端/前端算（16 节数据已在心跳里）。

### 7.5 `bms_warning`（sys[3]）现状

- 位定义本身可参考 `SystemManage.h:473-499`（13 位：bit0 BMS 通讯丢失、bit1/2 单体过压/欠压、bit3/4 过充/过放、bit7/8 放/充过温、bit9 MOS 过温…）。
- **但**：把 BMS warningFlag 位图映射进 `warningCode2Bits` 的代码在活跃路径里被注释（`UsartBms0.c:198-307` 整块注释），即当前 `bms_warning` 基本不反映 BMS 告警。一期方案里告警数据以 §7.4 第 3 条新增的 fault/alarm 位图为准，`bms_warning` 位映射作为可选恢复项。

### 7.6 对前文方案的影响

- §1/§2 的"LUX CAN/Growatt 帧来源"分析**作废**（那是 BMS 固件里支持但本产品未启用的逆变器协议）；实际走 PC 485 协议，字段覆盖比原方案更全：16 芯电压、MOS 状态、循环数、容量**一期全有**，不再有"二期依赖协议族"的问题。
- ESP32 心跳 `bms[20]` 组设计（§3.1）不变，字段量纲按 §7.2 调整（SOC/SOH 0.1%、电压 10mV 或统一换算）。
- 云端 `heartbeat_v2.go` 解析、`device_protocol_fields` 注册、前端按 §3/§4 不变。
- 待确认收紧为：①`ReadRunParam` 与 `ReadTestRunParam` 哪个是 ESP32 心跳实际轮询命令（也可能两个都要填真实值）；②告警/故障位图（BMS pack_info 的 alarm_status/fault_status）bit 定义表由 BMS 固件方提供。
### 7.7 ESP32 侧改动规格（2026-09-07 定稿并已实装，取代 §3.1 草案）

ARM 已实装：`RunParamDef` 追加 47 字（94 字节）BMS 扩展组，起始地址 **0x0440**，结束 0x046E
（`RunParamEndIndex` 已改为按 sizeof 自动推导）。ESP32 只需两步：

**① 读寄存器**：READ_RUNPARAM(0x03)，`param1=0x0440, param2=94`（即 47 字），一次读全。
应答为小端 u16 流，u32 字段按 2 字拆分（下表合并为单个 JSON 数值）。

**② 心跳加 additive 组** `"bms":[45]`（追加在 sock 之后，信封 v=2 不变）：

| 索引 | 字段键 | ARM 寄存器 | 量纲(scale) | null 条件 |
|---|---|---|---|---|
| 0 | `bms_online` | 0x0440 | 1 | — (恒发) |
| 1 | `battery_soc`（BMS口径） | 0x0441 | 0.1% | offline |
| 2 | `battery_soh` | 0x0442 | 0.1% | offline |
| 3 | `battery_capacity_remain` | 0x0443 | 0.1Ah | offline |
| 4 | `battery_capacity_full` | 0x0444 | 0.1Ah | offline |
| 5 | `battery_design_capacity` | 0x0445 | 0.1Ah | offline |
| 6 | `battery_cycle_count` | 0x0446 | 1 次 | offline |
| 7 | `cell_voltage_max` | 0x0447 | 1 mV | offline |
| 8 | `cell_voltage_min` | 0x0448 | 1 mV | offline |
| 9 | `cell_voltage_diff` | 0x0449 | 1 mV | offline |
| 10 | `cell_voltage_max_index` | 0x044A | 1(0起) | offline |
| 11 | `cell_voltage_min_index` | 0x044B | 1(0起) | offline |
| 12 | `cell_temp_max` | 0x044C | 1 ℃ | offline |
| 13 | `cell_temp_min` | 0x044D | 1 ℃ | offline |
| 14 | `bms_mos_temp` | 0x044E | 1 ℃ | offline |
| 15 | `bms_env_temp` | 0x044F | 1 ℃ | offline |
| 16 | `bms_pcb_temp` | 0x0450 | 1 ℃ | offline |
| 17 | `battery_work_mode` | 0x0451 | 枚举0静置/1充/2放/3初始化/4回充 | offline |
| 18 | `bms_mos_status` | 0x0452 | 位 bit0充MOS bit1放MOS bit2预放 bit3预充 | offline |
| 19 | `bms_system_mode` | 0x0453 | 1 | offline |
| 20 | `bms_chg_request_current` | 0x0454 | 0.1A | offline |
| 21 | `bms_chg_request_voltage` | 0x0455 | 0.1V | offline |
| 22 | `bms_fault_status` | 0x0456+0x0457 | 位图(u32 合为单值) | offline |
| 23 | `bms_alarm_w0` | 0x0458 | 告警0~7等级(每类2bit) | offline |
| 24 | `bms_alarm_w1` | 0x0459 | 告警8~15等级 | offline |
| 25 | `bms_alarm_w2` | 0x045A | 告警16~19等级 | offline |
| 26 | `battery_total_chg_capacity` | 0x045B+0x045C | Ah(u32 合为单值) | offline |
| 27 | `battery_total_dsg_capacity` | 0x045D+0x045E | Ah(u32 合为单值) | offline |
| 28~43 | `cell_voltage[0..15]` | 0x045F~0x046E | 1 mV(bit15=均衡) | offline |
| 44 | `bms_balance_bitmap` | 由 cell_voltage bit15 拆出或 ARM 后续透出 | 位 | offline |

- **null 语义**：`bms_online=0` 时，索引 1~44 全部发 `null`（ARM 已统一填 0xFFFF/-1000 无效值，ESP32 也可原样透传、由服务端按无效值转 null——二选一，建议 ESP32 判 BmsOnline 后统一发 null 更干净）。
- 16 芯电压直接并入 bms 组（ARM 寄存器已含），**无需独立 cvt 组**（§3.2 方案A作废）。
- 服务端配套：`heartbeat_v2.go` 加 `bms` 组解析（45 值自适应，缺组=旧固件合法）；`bms_alarm_w*` 每告警 2bit 等级解码表：0 单体过压 1 总压过高 2 充电过流 3 充电高温 4 充电低温 5 单体欠压 6 总压过低 7 放电过流 8 放电高温 9 放电低温 10 SOC过低 11~16 环境过/欠温、PCB过/欠温、MOS过/欠温 17 压差 18 温差 19 SOC过低(重复位,以BMS枚举为准)。
- `schema_hash` 升级，前端按字段能力注册新键（web/app 页面字段即上表键名）。

### 7.8 ESP32 已完成改动清单（2026-09-07 实装，`external/通讯esp`）

| 文件 | 改动 |
|---|---|
| `main/telemetry/arm_param.h` | `RunParamDef` 镜像扩展至 270 字节（BMS 组 176~269 偏移逐字段对齐 ARM）；`RUN_PARAM_SIZE=270`、`RUN_PARAM_END_INDEX=0x046E`；新增 `_Static_assert(sizeof==270)` |
| `main/telemetry/arm_poll.c` | 调试字段表补 47 个 BMS 字段；轮询/应答校验均由 RUN_PARAM_SIZE 宏驱动自动适配（应答长度校验、memcpy 均无需改） |
| `main/telemetry/telemetry.c` | `publish_heartbeat` 追加 `"bms":[45]` 组：在线发 45 值（16 芯值=bit12-0，均衡位拆到组尾 balance_bitmap），离线发 `[0,null×44]`；新增 `hb_append()` 边界安全追加（vsnprintf 越界防护）；缓冲 768→1536 |

校验：gcc 布局断言通过（legacy 176 字节布局未动、BMS 锚点 176/200/230/238、总 270）；bms 组 45 值拼装逻辑独立脚本验证通过。

### 7.9 ARM 已完成改动清单（2026-09-07 实装）

| 文件 | 改动 |
|---|---|
| `BMS/BMS.h` | `batterySum_t` 追加 `maxCellVoltageIdx/minCellVoltageIdx/faultStatus(u32)/alarmStatus(u64)` |
| `UsartBMS485/UsartBms0.c` | ①温度改按类型码解析((raw>>13)&3, 修正原固定下标错位); ②电芯温度(type0)入库+极值计算; ③均衡位图→balanceStatus; ④fault_status/alarm_status 解析(原跳过); ⑤芯压极值序号记录 |
| `Collector/CollectorParamAddr.h` | `RunParamDef` 追加 47 字 BMS 扩展组(0x0440~0x046E); `RunParamEndIndex` 改为 sizeof 自推导 |
| `Collector/Collector.c` | `ReadRunParam()`: ①追加 BMS 扩展组填充(ReceiveNewFlag 门控, 离线填无效值); ②两处 malloc(256)→512(结构体已270字节, 原256会溢出) |

> 注：`ReadRunParam` 的既有电池字段（BatVolt/BatterySOC 等）已由用户侧改为 DSP 来源（SysParam），本次未动；
> BMS 口径数据全部走新增扩展组，两套口径并行（心跳 bat[1]=DSP估算，bms[1]=BMS真实）。

## 8. 待办确认（历史清单，部分已被 §7 解决）

1. §4.1 位图定义与 BMS 固件方核对（源码位域有 reserve 位，语义需书面确认）。
2. Growatt 0x314 帧 FCC 未写入的 BMS 固件 bug（`Growatt_can_protocol.c:150-152` 重复写 remain_cap）——若走 Growatt 协议需 BMS 侧修复。
3. ESP32 心跳组包缓冲上限（93 值 JSON 约 <1KB，UART 帧上限 1088 字节，预估可容纳，需 ESP 固件侧确认）。
4. 现场逆变器↔BMS 实际运行协议族（决定二期电芯数组是否可行）。
