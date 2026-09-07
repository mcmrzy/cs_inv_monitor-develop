# CS-L10-6K2 逆变器 ESP32→云端 MQTT 上报协议设计

> **文档版本**: v1.0
> **适用产品**: CS-L10-6K2 48V 离网逆变器（GD32F30x 系统）
> **适用对象**: ESP32 固件开发、云端（device-communication / business-api / 管理后台）开发
> **最后更新**: 2026-08-02
> **上游协议**: `collector_protocol_print.html`（辰烁采集器通信协议规范 v1.0，ARM↔ESP32 UART）
> **相关文档**: `ARM_ESP32_UART_Protocol.md`（旧型号 CS-I10-6k2）、`MQTT接口文档.md`、`system_params.html`

---

## 目录

1. [概述](#1-概述)
2. [采集器协议摘要（UART 层）](#2-采集器协议摘要uart-层)
3. [主题与上报频率](#3-主题与上报频率)
4. [V2 心跳 Payload 定义](#4-v2-心跳-payload-定义)
5. [字段优化对照表](#5-字段优化对照表)
6. [服务器解析链路](#6-服务器解析链路)
7. [控制命令设计](#7-控制命令设计)
8. [数据库型号配置](#8-数据库型号配置)
9. [数据显示与控制页面改造预研](#9-数据显示与控制页面改造预研)
10. [实施清单与验证](#10-实施清单与验证)

---

## 1. 概述

CS-L10-6K2 是辰烁科技 48V 单相离网逆变器，ARM 主控（GD32F30x）通过 USART 与 ESP32 采集器通信（PPP 帧 + TEA 双重加密 + CRC32，地址映射式读写）。ESP32 负责将 ARM 数据经 MQTT 上报云端，并转发云端控制命令。

本协议设计在**精简字段**的前提下，将 CS-L10-6K2 采集器协议中约 70 个运行参数收敛为 **50 个位置数组值**（V2 心跳），并与服务器现有 V1 心跳协议（`device-communication/internal/telemetry/heartbeat_v1.go`）保持同一套「位置数组 + 版本号」模式，服务器新增 V2 解析分支即可接入，存储/缓存/展示链路完全复用。

### 1.1 设计原则

| 原则 | 说明 |
|------|------|
| 精简 | 服务器可推导的字段不上报（Ppv、work_state、battery_power） |
| 分组对齐 | 组结构与现有 `device_protocol_fields`（group_code + field_index）体系一致 |
| 版本化 | `v` 字段区分协议版本，V1 设备不受影响 |
| 元数据驱动 | 字段定义、显示配置、控制命令全部走数据库配置，不改代码 |

---

## 2. 采集器协议摘要（UART 层）

### 2.1 物理层与帧格式

| 项 | 值 |
|----|----|
| 接口 | USART 串口，115200 bps / 8N1，无流控 |
| 帧定界 | PPP 封装 `0x7E ... 0x7E`（0x7E→0x7D 0x5E，0x7D→0x7D 0x5D） |
| 加密 | TEA 双重加密（FrameKey + 动态 TempKey），128 位密钥 |
| 校验 | CRC32（帧尾 4B） |
| 字节序 | 小端序，最大帧长 1088 字节 |

帧结构：`Header(0xAA) + CmdLen(2B, 4 的倍数) + CMD(1B) + Param1(2B 起始地址) + Param2(2B 数据长度) + Data[] + CRC32(4B)`

### 2.2 命令集

| 码 | 名称 | 用途 |
|----|------|------|
| 0x01 | READ_CTRLPARAM | 读控制参数（0x0000-0x0053） |
| 0x02 | WRITE_CTRLPARAM | 写控制参数 |
| 0x03 | READ_RUNPARAM | 读运行参数（0x03E8-0x0442） |
| 0x04 / 0x05 | READ/WRITE_R_W_DATA | 读写可读写数据（0x00C8-0x00CB：UTC 时间等） |
| 0x06 | READ_R_DATA | 读只读数据（0x0190-0x01A5：版本/SN/额定值） |
| 0x07 | CTRLCMD | 控制命令（预留） |
| 0x14 | READ_TEST | 读测试参数（单位与运行参数不同） |

### 2.3 参数地址空间

| 区域 | 地址 | 数量 | 说明 |
|------|------|------|------|
| 控制参数 | 0x0000-0x0053 | ~60 | 输出优先级、充电电流、电池容量/类型、电压频率、主从、SOC 阈值、均衡、发电机、时间等 |
| 可读写 | 0x00C8-0x00CB | 4 | 控制参数修改时间、UTC 时间（32 位，写入自动校时） |
| 运行参数 | 0x03E8-0x0442 | ~70 | 见第 5 节字段优化对照表 |
| 只读 | 0x0190-0x01A5 | ~20 | ARM/DSP 版本、模块号、SN(BCD)、硬件版本、额定参数、Bootloader 版本 |
| 测试参数 | 0x14 命令 | — | 与运行参数结构类似，电压单位为 1V |

### 2.4 系统状态位（SysStatus，运行参数 +0）

| 位 | 名称 | 位 | 名称 |
|----|------|----|------|
| 0 | StandBy 待机 | 6 | GenCharging 发电机充电 |
| 1 | Fault 故障 | 7 | ACBypass AC 旁路 |
| 2 | Charge 充电 | 8 | ToLoad 输出负载 |
| 3 | Discharging 放电 | 9 | Pvinput PV 输入 |
| 4 | PVCharging PV 充电 | 10 | AcInput AC 输入 |
| 5 | ACCharging AC 充电 | 11 | GeInput 发电机输入 |

---

## 3. 主题与上报频率

沿用现有 `cs_inv/{sn}/...` 主题体系，仅上行遥测主题使用 V2 payload：

| 主题 | QoS | Retain | 频率 | 来源 | 说明 |
|------|-----|--------|------|------|------|
| `cs_inv/{sn}/status` | 1 | true | 60s | ESP32 自动 | 在线状态 + RSSI + IP（沿用） |
| `cs_inv/{sn}/info` | 1 | false | 连接时 | ARM | 设备信息 + 只读额定参数（沿用，见 3.1） |
| `cs_inv/{sn}/data/telemetry` | 0 | false | 5s | ARM | **V2 心跳（本协议核心）** |
| `cs_inv/{sn}/data/alarm` | 1 | false | 事件 | ARM | 告警/故障事件（沿用） |
| `cs_inv/{sn}/cmd` | 1 | — | 按需 | 云端→ESP32 | 控制命令下行（沿用格式） |
| `cs_inv/{sn}/cmd_result` | 1 | false | 按需 | ESP32 | 命令执行结果上行（沿用） |
| `cs_inv/{sn}/ota/cmd`、`ota/status` | 1 | — | 按需 | — | OTA（沿用） |

> **时间戳**：所有上行数据由 ESP32 添加 Unix 秒级时间戳（NTP 同步），与现有 V1 一致。

### 3.1 info 主题（设备信息 + 只读参数）

连接时上报一次，沿用现有字段并扩展只读额定参数（对应协议 0x0190-0x01A5）：

```json
{
  "sn": "CSL1062K00000001",
  "model": "CS-L10-6K2",
  "manufacturer": "辰烁科技",
  "firmware_arm": "V1.0.0",
  "firmware_esp": "V1.0.0",
  "firmware_dsp": "V1.0.0",
  "type": "off_grid",
  "phase": "single",
  "rated_power": 6200,
  "rated_voltage": 220,
  "rated_freq": 50,
  "battery_voltage": 48,
  "battery_types": ["LiFePO4", "NCM", "LeadAcid"],
  "inverter_module": "CS-L10-6K2",
  "hardware_version": "V1.0",
  "device_type_code": 0,
  "rated_va": 6200,
  "nominal_grid_voltage": 220,
  "nominal_grid_freq": 50,
  "nominal_bat_voltage": 48,
  "nominal_pv_current": 30,
  "nominal_ac_charge_current": 60,
  "bootloader_version": "V1.0"
}
```

服务器解析 info 后更新 `devices` 表（model_id 自动绑定 CS-L10-6K2）。

---

## 4. V2 心跳 Payload 定义

### 4.1 总览

```json
{
  "v": 2,
  "t": 1783000000,
  "data": {
    "sys": [11],
    "pv":  [5],
    "ac":  [11],
    "chr": [3],
    "bat": [6],
    "eng": [14]
  }
}
```

- `v`: 协议版本，固定 `2`。
- `t`: ESP32 Unix 秒级时间戳。
- 各分组为**定长位置数组**，元素必须是数值或 `null`（`null` 表示该字段本次无数据，服务器标记 QualityPartial）。
- 与 V1 不同，V2 **不含 cells 组**（采集器协议无电芯数据），不含 mos/ambient 温度（协议无）。

### 4.2 组字段顺序定义（服务器解析依据）

#### sys（11 个）— 系统状态

| 索引 | 字段键 | 说明 | 单位 | 范围 |
|------|--------|------|------|------|
| 0 | `sys_status` | 系统状态位（12 位 bitmask） | - | 0-4095 |
| 1 | `fault_code` | 故障码（FaultValue） | - | 0-2^32 |
| 2 | `warning` | 告警位（64 位） | - | 0-2^64 |
| 3 | `bms_warning` | BMS 告警 | - | 0-2^32 |
| 4 | `inverter_temperature` | 逆变温度 | 0.1°C | -40-100 |
| 5 | `boost_temperature` | Boost 温度 | 0.1°C | -40-120 |
| 6 | `transformer_temperature` | 变压器温度 | 0.1°C | -40-120 |
| 7 | `pv_temperature` | PV 温度 | 0.1°C | -40-120 |
| 8 | `dc_bus_voltage` | 母线电压 | 0.01V | 0-500 |
| 9 | `load_percent` | 负载百分比 | 0.1% | 0-120 |
| 10 | `battery_overcharge` | 过充标志 | - | 0-1 |

#### pv（5 个）— 光伏

| 索引 | 字段键 | 说明 | 单位 | 范围 |
|------|--------|------|------|------|
| 0 | `pv1_voltage` | PV1 电压 | 0.1V | 0-150 |
| 1 | `buck1_current` | Buck1 电流 | 0.1A | 0-30 |
| 2 | `pv2_voltage` | PV2 电压 | 0.1V | 0-150 |
| 3 | `buck2_current` | Buck2 电流 | 0.1A | 0-30 |
| 4 | `pv_total_power` | PV 总功率 | 0.1W | 0-7500 |

> `Ppv` 协议直接给出，上报后服务器同时推导 `pv1_power = f(Vpv1, Buck1Curr)` 备用于展示（可选）。

#### ac（11 个）— 交流

| 索引 | 字段键 | 说明 | 单位 | 范围 |
|------|--------|------|------|------|
| 0 | `ac_output_voltage` | AC 输出电压 | 0.1V | 0-250 |
| 1 | `ac_output_frequency` | AC 输出频率 | 0.01Hz | 0-55 |
| 2 | `output_power` | 输出有功功率 | 0.1W | 0-7500 |
| 3 | `output_apparent_power` | 输出视在功率 | 0.1VA | 0-7500 |
| 4 | `output_current` | 输出电流 | 0.1A | 0-100 |
| 5 | `grid_voltage` | 电网电压 | 0.1V | 0-300 |
| 6 | `grid_frequency` | 电网频率 | 0.01Hz | 0-55 |
| 7 | `ac_input_power` | AC 输入功率 | 0.1W | 0-7500 |
| 8 | `ac_input_apparent_power` | AC 输入视在功率 | 0.1VA | 0-7500 |
| 9 | `ac_bypass_power` | AC 旁路放电功率 | 0.1W | 0-7500 |
| 10 | `ac_bypass_apparent_power` | AC 旁路放电视在 | 0.1VA | 0-7500 |

> **单位勘误**：采集器协议文档中 `ACDisChrWatt` 单位标注为 `0.1kWh`，实为功率字段，应为 `0.1W`（与 ACDisChrVA 0.1VA 对应）。本协议按 `0.1W` 处理。

#### chr（3 个）— AC 充电

| 索引 | 字段键 | 说明 | 单位 | 范围 |
|------|--------|------|------|------|
| 0 | `ac_charge_power` | AC 充电功率 | 0.1W | 0-7500 |
| 1 | `ac_charge_apparent_power` | AC 充电视在功率 | 0.1VA | 0-7500 |
| 2 | `ac_charge_current` | AC 充电电流 | 0.1A | 0-150 |

#### bat（6 个）— 电池

| 索引 | 字段键 | 说明 | 单位 | 范围 |
|------|--------|------|------|------|
| 0 | `battery_voltage` | 电池电压 | 0.01V | 0-70 |
| 1 | `battery_soc` | 电池 SOC | 0.1% | 0-100 |
| 2 | `battery_current` | 电池电流（充正放负） | 0.1A | -150-150 |
| 3 | `battery_charge_power` | 电池充电功率 | 0.1W | 0-7500 |
| 4 | `battery_discharge_power` | 电池放电功率 | 0.1W | 0-7500 |
| 5 | `battery_overcharge` | 过充标志（与 sys[10] 同源，可省略） | - | 0-1 |

> bat[5] 与 sys[10] 冗余，协议中 `BatOverCharge` 在运行参数表出现一次；**实际组包时可省略 bat[5] 置 null**，服务器取 sys[10]。

#### eng（14 个）— 能量统计

| 索引 | 字段键 | 说明 | 单位 | 范围 |
|------|--------|------|------|------|
| 0 | `gen_energy_daily` | 发电机今日发电 | 0.1kWh | 0-1e6 |
| 1 | `gen_energy_total` | 发电机总发电 | 0.1kWh | 0-1e12 |
| 2 | `pv_energy_daily` | PV 今日发电 | 0.1kWh | 0-1e6 |
| 3 | `pv_energy_total` | PV 总发电 | 0.1kWh | 0-1e12 |
| 4 | `ac_charge_energy_daily` | AC 今日充电 | 0.1kWh | 0-1e6 |
| 5 | `ac_charge_energy_total` | AC 总充电 | 0.1kWh | 0-1e12 |
| 6 | `battery_discharge_energy_daily` | 电池今日放电 | 0.1kWh | 0-1e6 |
| 7 | `battery_discharge_energy_total` | 电池总放电 | 0.1kWh | 0-1e12 |
| 8 | `battery_charge_energy_daily` | 电池今日充电 | 0.1kWh | 0-1e6 |
| 9 | `battery_charge_energy_total` | 电池总充电 | 0.1kWh | 0-1e12 |
| 10 | `ac_bypass_energy_daily` | AC 旁路今日放电 | 0.1kWh | 0-1e6 |
| 11 | `ac_bypass_energy_total` | AC 旁路总放电 | 0.1kWh | 0-1e12 |
| 12 | `output_energy_daily` | 输出今日放电 | 0.1kWh | 0-1e6 |
| 13 | `output_energy_total` | 输出总放电 | 0.1kWh | 0-1e12 |

### 4.3 完整示例

```json
{
  "v": 2,
  "t": 1783000000,
  "data": {
    "sys": [2050, 0, 0, 0, 282, 450, 431, 300, 5120, 624, 0],
    "pv": [1450, 82, 0, 0, 12400],
    "ac": [2205, 5002, 18703, 18756, 852, 0, 0, 0, 0, 0, 0],
    "chr": [0, 0, 0],
    "bat": [5120, 785, -255, 0, 13056, 0],
    "eng": [0, 0, 1250, 45678, 0, 0, 1305, 23456, 0, 0, 0, 0, 1870, 98765]
  }
}
```

> 数值均为协议原始量纲（已含 0.1 缩放），服务器按字段定义还原。

---

## 5. 字段优化对照表

采集器协议 70 个运行参数 → V2 心跳 50 个位置值，优化明细：

### 5.1 直接复用（25 个，映射到现有字段）

| 协议字段 | V2 位置 | 复用字段键 |
|----------|---------|-----------|
| Vpv1 | pv[0] | `pv1_voltage` |
| Vpv2 | pv[2] | `pv2_voltage` |
| OutputWatt | ac[2] | `output_power` |
| OutputVA | ac[3] | `output_apparent_power` |
| OutputCurr | ac[4] | `output_current` |
| ACOutputVolt | ac[0] | `ac_output_voltage` |
| ACOutputFreq | ac[1] | `ac_output_frequency` |
| BatVolt | bat[0] | `battery_voltage` |
| BatterySOC | bat[1] | `battery_soc` |
| BatChgCurr / BatDischgCurr | bat[2] | `battery_current`（符号合并） |
| BusVolt | sys[8] | `dc_bus_voltage` |
| LoadPercent | sys[9] | `load_percent` |
| InvertTemp | sys[4] | `inverter_temperature` |
| Epv_today / Epv_total | eng[2] / eng[3] | `pv_energy_daily` / `pv_energy_total` |
| Ebat_dischrToday / Total | eng[6] / eng[7] | `battery_discharge_energy_daily` / `_total` |
| Ebat_chrToday / Total | eng[8] / eng[9] | `battery_charge_energy_daily` / `_total` |

### 5.2 服务器推导（3 个，不上报）

| 推导字段 | 公式 | 说明 |
|----------|------|------|
| `pv_total_power` 拆分 | pv1_power / pv2_power = f(Vpv×BuckCurr) | 可选，展示用 |
| `work_state` | sys_status 位组合：Fault→1、Charge→2、Discharging→3、ACBypass→4、StandBy→0 | 与旧型号枚举兼容 |
| `battery_power` | = discharge - charge（放电为正） | 与现有 realtime 结构兼容 |

### 5.3 剔除 / 合并

| 处理 | 协议字段 | 原因 |
|------|----------|------|
| 剔除 | cells（电芯电压/温度） | 采集器协议无电芯数据 |
| 剔除 | mos_temperature / ambient_temperature / fan_speed / runtime_hours | 协议无对应地址 |
| 合并 | BatChgCurr + BatDischgCurr → battery_current（带符号） | 同一母线电流 |
| 合并 | BatOverCharge → sys[10] | 去重 |
| 合并 | Ppv → pv[4] 直接上报 | 协议已给总功率 |

### 5.4 新增字段目录（24 个，迁移 091 写入 telemetry_field_catalog）

| 分组 | 字段键 |
|------|--------|
| system | `sys_status`、`warning`、`bms_warning`、`boost_temperature`、`transformer_temperature`、`pv_temperature`、`battery_overcharge` |
| pv | `buck1_current`、`buck2_current` |
| ac | `grid_voltage`、`grid_frequency`、`ac_input_power`、`ac_input_apparent_power`、`ac_charge_power`、`ac_charge_apparent_power`、`ac_charge_current`、`ac_bypass_power`、`ac_bypass_apparent_power` |
| battery | `battery_charge_power`、`battery_discharge_power` |
| energy | `gen_energy_daily`、`gen_energy_total`、`ac_charge_energy_daily`、`ac_charge_energy_total`、`ac_bypass_energy_daily`、`ac_bypass_energy_total`、`output_energy_daily`、`output_energy_total` |

（system 7 + pv 2 + ac 8 + battery 2 + energy 8 = 27 项，其中 `battery_overcharge` 与 sys 重复归并后实际新增 26 个唯一键，见迁移脚本。）

---

## 6. 服务器解析链路

```
ESP32 --MQTT--> EMQX --webhook--> mqtt-kafka-bridge --Kafka(inv-telemetry)--> ProtocolParser
    → 按 v 分派 → ParseHeartbeatV2 → SaveTelemetryV2（device_telemetry_3min 新列）
    → Redis realtime:latest:{sn}（前端实时展示）
    → 状态机（在线/故障检测）
```

### 6.1 解析要点

- `ProtocolParser.handleHeartbeat` 先读 payload 的 `v` 字段：`v==1` 走 `ParseHeartbeat`，`v==2` 走 `ParseHeartbeatV2`。
- V2 解析器复用 V1 的校验模式：组长度精确匹配、数值/null 校验、范围 bounded、QualityFlags（NullValue/OutOfRange/ClockInvalid）。
- `work_state` 由 `sys_status` 推导写入 `device_telemetry_3min.work_state` 列（与旧型号枚举兼容）。
- `battery_power = discharge - charge` 写入 `battery_power` 列。
- 新增 27 列写入 `device_telemetry_3min` 与 `device_latest_state`（迁移 091）。
- Redis `realtime:latest:{sn}` 扩展结构：

```json
{
  "sys": {"data": {"sys_status": 2050, "fault_code": 0, "warning": 0, "bms_warning": 0,
                   "inverter_temperature": 28.2, "boost_temperature": 45.0, "transformer_temperature": 43.1,
                   "pv_temperature": 30.0, "dc_bus_voltage": 51.2, "load_percent": 62.4,
                   "battery_overcharge": 0, "work_state": 3}, "timestamp": 1783000000},
  "pv": {"data": {"pv1_voltage": 145.0, "buck1_current": 8.2, "pv2_voltage": 0, "buck2_current": 0,
                  "total_power": 1240.0}, "timestamp": 1783000000},
  "ac": {"data": {"output_voltage": 220.5, "output_frequency": 50.02, "output_power": 1870.3,
                  "output_apparent_power": 1875.6, "output_current": 85.2, "grid_voltage": 0,
                  "grid_frequency": 0, "input_power": 0, "input_apparent_power": 0,
                  "bypass_power": 0, "bypass_apparent_power": 0}, "timestamp": 1783000000},
  "chr": {"data": {"power": 0, "apparent_power": 0, "current": 0}, "timestamp": 1783000000},
  "bat": {"data": {"voltage": 51.2, "soc": 78.5, "current": -25.5, "charge_power": 0,
                   "discharge_power": 1305.6, "overcharge": 0}, "timestamp": 1783000000},
  "eng": {"data": {"gen_daily": 0, "gen_total": 0, "pv_daily": 125.0, "pv_total": 4567.8,
                   "ac_chr_daily": 0, "ac_chr_total": 0, "bat_dis_daily": 130.5, "bat_dis_total": 2345.6,
                   "bat_chr_daily": 0, "bat_chr_total": 0, "ac_byp_daily": 0, "ac_byp_total": 0,
                   "out_dis_daily": 187.0, "out_dis_total": 9876.5}, "timestamp": 1783000000},
  "_sn": "CSL1062K00000001", "_msg_type": "heartbeat", "_updated_at": "...", "_timestamp": 1783000000
}
```

### 6.2 只读参数处理

只读参数（版本/SN/额定值）通过 `info` 主题上报（见 3.1），服务器更新 `devices` 表；心跳不含只读字段，避免重复传输。

---

## 7. 控制命令设计

### 7.1 下行链路

```
管理后台 → POST /api/v1/devices/by-sn/{sn}/control {cmd, params, task_id}
    → API Server → device-communication（HTTP 内部调用）
    → MQTT 发布 cs_inv/{sn}/cmd {cmd, params, task_id}
    → ESP32 解析 → UART WRITE_CTRLPARAM(0x02, 地址, 长度, 值) → ARM 执行
    → ARM 返回 → ESP32 发布 cs_inv/{sn}/cmd_result {task_id, cmd, success, message}
    → device-communication → API Server 更新命令日志
```

### 7.2 命令 → 参数地址映射（device_model_commands 配置）

| command_code | 地址 | 参数 | 说明 |
|--------------|------|------|------|
| `set_output_priority` | 0x0000 | priority:int | 输出优先级 |
| `set_max_charge_current` | 0x0001 | current_a:float(0.1A) | 最大充电电流 |
| `set_battery_capacity` | 0x0003 | capacity_ah:int | 电池容量 |
| `set_battery_type` | 0x0004 | battery_type:int | 电池类型 |
| `set_output_voltage` | 0x0007 | voltage_v:int | 输出电压 |
| `set_output_frequency` | 0x0008 | freq_hz:int | 输出频率 |
| `set_master_slave` | 0x0009 | mode:int | 主从模式 |
| `set_ac_charge_current` | 0x000A | current_a:float(0.1A) | 市电充电电流 |
| `set_ac_output_mode` | 0x0016 | mode:int | AC 输出模式 |
| `set_charge_priority` | 0x000D | priority:int | 充电优先级 |
| `set_low_volt_return_utl` | 0x000B | voltage_v:float | 低压转市电 |
| `set_high_volt_return_bat` | 0x000C | voltage_v:float | 高压转电池 |
| `set_soc_cutoff` | 0x0028 | soc:int(%) | 低电量截止 |
| `set_charge_cutoff` | 0x0052/0x0053 | soc:int / voltage_v:float | 市电充电截止 |
| `set_equalize_enable` | 0x001A | enable:bool | 均衡使能 |
| `set_equalize_voltage` | 0x001B | voltage_v:float | 均衡电压 |
| `set_equalize_time` | 0x001C | time_min:int | 均衡时间 |
| `set_gen_start_voltage` | 0x0022 | voltage_v:float | 低压启动发电机 |
| `set_gen_stop_voltage` | 0x0023 | voltage_v:float | 高压关闭发电机 |
| `set_soc_back_utl` | 0x0024 | soc:int(%) | 低电量转市电 |
| `set_soc_back_bat` | 0x0025 | soc:int(%) | 高电量转电池 |
| `set_soc_back_gen` | 0x0026 | soc:int(%) | 低电量启动发电机 |
| `set_soc_close_gen` | 0x0027 | soc:int(%) | 高电量关闭发电机 |
| `set_gen_rate_watt` | 0x0031 | watt:int | 发电机额定功率 |
| `set_alarm_control` | 0x000E | alarm_ctrl:int | 告警控制 |
| `set_buzzer` | 0x0029 | enable:bool | 蜂鸣器使能 |
| `set_utc_time` | 0x00CA/0x00CB | utc:int(秒) | UTC 时间同步（写 32 位，差值>4s 校时） |

> 控制参数读取：云端下发 `query` 命令（沿用现有）或通过 `READ_CTRLPARAM` 按地址段读取；前端控制面板先写后读确认。

---

## 8. 数据库型号配置

迁移脚本 `database/migrations/091_add_model_csl10_6k2.up.sql` 完成：

1. `telemetry_field_catalog` 新增 26 个字段（见 5.4）。
2. `device_protocol_versions` 新增 `heartbeat` v2（schema_hash `heartbeat-v2-csl10-6k2-20260802`）。
3. `device_protocol_fields` 按第 4 节顺序写入 50 个字段定义（wire_type 全部 float32，能量字段 float64）。
4. `device_models` 插入 `CS-L10-6K2`（辰烁科技 / inverter / 6.2kW）。
5. `device_model_fields` 配置显示：分组（PV/AC/充电/电池/系统/能量）、sort_order、show_realtime、show_history。
6. `device_model_commands` 写入第 7.2 节命令清单（parameter_schema 驱动前端表单）。
7. `device_telemetry_3min` + `device_latest_state` 新增 27 列。

---

## 9. 数据显示与控制页面改造预研

### 9.1 现状

| 页面 | 现状 | 问题 |
|------|------|------|
| 设备详情 StatusTab | 硬编码 4 个 Statistic（输出/输入/负载功率、SOC）+ desired/reported 快照表 | 新字段（boost 温度、AC 充电、发电机能量）无法展示 |
| 远程设置 remote-settings | 8 个静态 Section，`handleSet` 仅 message.success 模拟 | 未接真实命令 API；新命令无法配置 |
| 电站能量流图 | PV→电池→负载 3 节点 | 无发电机 / AC 旁路路径 |
| 型号注册工作台 | 型号/字段/命令/协议版本 CRUD 完整 | 无需改代码 |

### 9.2 改造方案

#### A. 设备详情实时数据（StatusTab）— 数据驱动

- 读取设备 `model_id` → `GET /models/{id}/field-capabilities`（`show_realtime=true`、`group_code`、`display_name_key`、`display_unit`）。
- 按 `group_code` 分组渲染卡片：PV 组（pv1/pv2 电压、buck 电流、总功率）、AC 组（输出/电网/旁路）、充电组（AC 充电）、电池组（电压/SOC/电流/充放功率）、系统组（温度×4、状态位、故障码）、能量组（14 个电量）。
- 数据源：`GET /devices/by-sn/{sn}/realtime`（Redis realtime:latest），字段名与 V2 组结构对齐。
- 兼容：CS-I10-6k2（V1）无新字段时自动隐藏空组。

#### B. 远程设置（remote-settings）— 命令数据驱动

- 选择设备后读取 `model_id` → `GET /models/{id}/commands-v2`。
- 新增 `ModelCommandsSection`：按 `parameter_schema` 动态渲染表单（InputNumber/Select/Switch），分组展示（通用/充放电/均衡/发电机策略/其他）。
- 点击设置调用 `POST /devices/by-sn/{sn}/control {cmd, params, task_id}`，随后轮询 `GET /devices/by-sn/{sn}/commands` 获取 `cmd_result` 反馈。
- 兼容：CS-I10-6k2 继续显示现有 8 个静态 Section（model_code 判断）；CS-L10-6K2 显示动态命令面板。

#### C. 能量流图（EnergyFlowDiagram）

- 增加发电机节点：数据源 `eng.gen_daily`/`gen_total` > 0 时显示「发电机 → 充电」路径。
- 增加 AC 旁路路径：`ac.bypass_power` > 0 时显示「市电 → 负载」直通。
- 保持现有 PV/电池/负载逻辑不变。

### 9.3 实施顺序

1. 迁移 091（型号配置）→ 2. Go V2 解析器 → 3. 文档 → 4. 前端 remote-settings 动态面板 → 5. StatusTab 数据驱动 → 6. 能量流图发电机路径。

---

## 10. 实施清单与验证

| # | 项 | 文件 | 状态 |
|---|----|------|------|
| 1 | 协议设计文档 | `docs/CS-L10-6K2_MQTT_上报协议设计.md` | 本文档 |
| 2 | 数据库迁移 | `database/migrations/091_add_model_csl10_6k2.up.sql` / `.down.sql` | 待执行 |
| 3 | V2 解析器 | `device-communication/internal/telemetry/heartbeat_v2.go` | 待实施 |
| 4 | Sample 扩展 | `device-communication/internal/telemetry/model.go` | 待实施 |
| 5 | 解析分支 | `device-communication/internal/service/protocol_parser.go` | 待实施 |
| 6 | 落库扩展 | `device-communication/internal/repository/telemetry_repository.go` | 待实施 |
| 7 | 单元测试 | `device-communication/internal/telemetry/heartbeat_v2_test.go` | 待实施 |
| 8 | 控制面板 | `inv-admin-frontend/src/pages/remote-settings/` | 待实施 |
| 9 | 实时展示 | `inv-admin-frontend/src/pages/device-detail/StatusTab.tsx` | 待实施 |
| 10 | 能量流图 | `inv-admin-frontend/src/pages/stations/components/EnergyFlowDiagram.tsx` | 待实施 |

验证命令：

```bash
make build-device && go test ./device-communication/internal/telemetry/... && make vet-go
# 迁移脚本测试库执行：psql -f 091_add_model_csl10_6k2.up.sql
# 前端：make type-check
```

---

## 附录 A：ESP32 组包伪代码（参考）

```c
// ARM 运行参数帧（0x03E8-0x0442，小端 u16/u32）解析后组装 V2 心跳
// 数据来自 READ_RUNPARAM 响应解密解帧后的 Data[] 区
payload_t build_heartbeat_v2(const run_params_t *rp, uint32_t utc) {
    return (payload_t){
        .v = 2,
        .t = utc,
        .data = {
            .sys = {rp->sys_status, rp->fault_value, rp->warning_lo, rp->bms_warning,
                    rp->invert_temp, rp->boost_temp, 0, 0,
                    rp->bus_volt, rp->load_percent, rp->bat_overcharge},
            .pv = {rp->vpv1, rp->buck1_curr, rp->vpv2, rp->buck2_curr, rp->ppv},
            .ac = {rp->ac_out_volt, rp->ac_out_freq, rp->out_watt, rp->out_va, rp->out_curr,
                   rp->grid_volt, rp->grid_freq, rp->ac_in_watt, rp->ac_in_va,
                   rp->ac_dis_watt, rp->ac_dis_va},
            .chr = {rp->ac_chr_watt, rp->ac_chr_va, rp->ac_chr_curr},
            .bat = {rp->bat_volt, rp->bat_soc, rp->bat_curr_signed,
                    rp->bat_chr_watt, rp->bat_dis_watt, rp->bat_overcharge},
            .eng = {rp->egen_today, rp->egen_total, rp->epv_today, rp->epv_total,
                    rp->eac_chr_today, rp->eac_chr_total,
                    rp->ebat_dis_today, rp->ebat_dis_total,
                    rp->ebat_chr_today, rp->ebat_chr_total,
                    rp->eac_dis_today, rp->eac_dis_total,
                    rp->eop_dis_today, rp->eop_dis_total}
        }
    };
}
// 主题：cs_inv/{sn}/data/telemetry，QoS 0，5s 周期
```
