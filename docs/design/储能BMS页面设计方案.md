# 储能 BMS 页面设计方案（Web + App）

> 2026-09-07 调研产出。依据：`external/储能bms` BMS 固件源码（BBM-5K-48P，16 串磷酸铁锂）、
> `device-communication` 遥测链路代码、`inv-admin-frontend` 与 `inv_app` 现有页面模式。
> 前提：用户确认储能字段已通过遥测协议上报（具体字段以实际设备 payload 为准，见 §6 待确认清单）。

---

## 1. 结论摘要

- **页面形态**：Web 端做成设备详情页新 Tab「储能」(`BmsTab`)；App 端做成设备详情页第 5 个 Tab 或独立路由页 `/device/:sn/storage`。不建议新开顶层菜单——储能是设备的属性页，入口跟着设备走。
- **数据现状**：云端链路今天就能拿到 `bat` 组 7 个实时字段 + `sys.bms_warning` + `eng` 组充放电能量统计 + 历史遥测曲线，**P1 页面不依赖任何后端改动**。
- **主要缺口**：电芯级数据（16 芯电压/温度数组，`device_cell_samples` 表有数据）**没有查询 API**，前端两端都从未消费过——电芯柱状图需要新增后端接口（P2）。
- **不建议做**：BMS 参数设置/强制 MOS 控制等控制类功能本期不做（BMS 的 PC 协议虽支持，但遥测链路没有控制通道，需要另行走设备命令链路）。

---

## 2. 数据面盘点

### 2.1 BMS 固件完整数据面（`external/储能bms`，公共数据表 T00~T22）

| 类别 | 字段 | 内部量纲 |
|---|---|---|
| 实时测量 | Pack 总压 / 电流（有符号，充+放-） | 0.1V / 0.1A |
| | SOC / SOH | 0.1% |
| | 充电电流 / 放电电流（分列） | 0.1A |
| 电芯级 | 16 芯电压数组（含每芯均衡标志 bit15） | 1mV |
| | 最高/最低芯压 + 序号、压差 | 1mV |
| | 电芯温度×2、MOS 温度、PCB 温度（raw=℃+40） | 1℃ |
| | 最高/最低芯温 + 序号 | 1℃ |
| | 均衡状态数组（每芯 0/1） | — |
| 容量统计 | 满充容量 FCC / 剩余容量 / 标称容量 | 0.1Ah |
| | 累计充/放电容量（Ah）、累计充/放电能量（Wh） | 1Ah / 1Wh |
| | 循环次数（本固件恒 0，真实计数在参数区满充/满放次数） | 次 |
| | 风扇转速 | rpm |
| 状态 | 电池模式：0 静置/1 充电/2 放电/3 初始化/4 回充 | 枚举 |
| | 系统状态机编号（switch_on/work/chg_protect/dsg_protect/fault/balance…） | 枚举 |
| | 充/放/预充/预放 MOS 状态 ×4、充放电保护标志、电池自锁 | 位 |
| 告警 | 16 类告警 × 3 级（alarm_status 64bit，每类 2bit 等级）：单体过压/欠压、总压过/欠、充/放过流、充/放高温/低温、环境/MOS/PCB 温度、压差、温差 | 位图 |
| 故障 | 28 位故障位图（fault_status 32bit）：短路、反接、NTC/采样线断线、AFE 通信、MOS 故障、风扇、PF、自锁等 | 位图 |
| 请求 | 请求充电电压/电流（发给逆变器的限压限流） | 0.1V / 0.1A |

BMS→逆变器 CAN 协议（Growatt/LUX）里也带全 16 芯电压、极值芯压芯温、SOH、剩余容量、压差、循环数——即**逆变器侧能看到这些数据**，能否上云取决于采集器固件往遥测帧里塞了什么。

### 2.2 云端链路今天实际有的字段（代码可查证）

**实时**（`device-communication/internal/service/protocol_parser.go` `buildRealtimeV2` → Redis `realtime:latest:{sn}` → `GET /devices/by-sn/:sn/realtime`）：

| 组 | 字段 | 说明 |
|---|---|---|
| `bat` | `battery_voltage` `battery_soc` `battery_current` `battery_charge_power` `battery_discharge_power` `power`（派生，放正充负）`battery_overcharge` | V2 心跳 bat 组 5 值 + 派生 |
| `sys` | `bms_warning`（u16 位图）、`work_state`、`fault_code`、`warning`、`battery_overcharge`、各温度 | |
| `eng` | `daily_charge_energy` / `total_charge_energy` / `daily_discharge_energy` / `total_discharge_energy` 等 14 值 | 充放电量统计 |

**历史**：`GET /devices/by-sn/:sn/telemetry?startTime&endTime&granularity`（TimescaleDB，按 3 分钟槽合并各组）——`battery_soc/voltage/current/charge_power/discharge_power` 均可画历史曲线。

**前端已有消费**：web `energyUtils.ts` 的 `extractEnergyMetrics` 已解析全部 bat 字段；Flutter `BatteryData` 实体字段齐全（soc/soh/capacityRemain/cycleCount/cellVoltageMax/Min/Diff/protectStatus/bmsFaultCode…）。

### 2.3 缺口（需要后端/协议配合才能上页面）

1. **电芯数组**：`device_cell_samples` 表存了 voltages/temperatures JSON，但 business-api 无查询接口、两端前端零消费 → P2 新增 `GET /devices/by-sn/:sn/cells`。
2. **SOH / 容量 / 循环数 / MOS 状态 / 告警故障明细位图**：当前遥测帧没有这些组。若采集器固件已扩展（如 chr 第 4 值、fan 第 3 值或新 `bms` 组），需在 `heartbeat_v2.go` 加解析 + `device_protocol_fields` 注册 + `buildRealtimeV2` 透出，前端才有数据（V2.2+ 解析器目前只容忍未知扩展位、按 scale=1 透传但不落库）。
3. **3 级告警矩阵**：`bms_warning` 是 16bit 聚合位图，详细等级需固件扩展。

---

## 3. Web 端方案（inv-admin-frontend）

### 3.1 入口与注册点

详情页已是全屏独立路由 `/devices/:sn/detail` + antd Tabs，**新 Tab 零路由改动**：

| 改动 | 文件 |
|---|---|
| 新建 `src/pages/device-detail/BmsTab.tsx` | props `{ sn: string }` |
| Tabs items 加一项 `{ key: 'bms', label: t('deviceDetail.tab.bms'), children: <BmsTab sn={sn}/> }` | `src/pages/device-detail/index.tsx:52-67` |
| 词条 `deviceDetail.tab.bms`（zh/en） | `src/locales/deviceDetail.ts`（记得在 `locales/index.ts` 已聚合，无需动） |

### 3.2 页面布局（自上而下）

```
┌────────────────────────────────────────────────────────────┐
│ 状态行: 工作状态Tag(充电/放电/静置/故障·按battery_current方向+work_state) │
│         在线状态 · 数据时间(freshRealtime 新鲜度)              │
├──────────────┬─────────────────────────────────────────────┤
│ SOC 大圆环    │  指标卡×4: 总压(V) · 电流(A,带符号) ·          │
│ (Progress    │  充电功率(kW) · 放电功率(kW)                  │
│  circle,复用  │                                             │
│  EnergyCenter│  次级行: SOH% · 剩余/满充容量(Ah)* · 今日充/放电量  │
│  Tab 样式)    │  (eng组 daily_charge/discharge_energy)        │
├──────────────┴─────────────────────────────────────────────┤
│ BMS 告警面板: bms_warning 位图解码网格(仿 SysStatusBitsPanel)   │
│  + 最近告警列表(复用 alarms API)                               │
├────────────────────────────────────────────────────────────┤
│ 历史曲线: 指标切换(SOC%/电压V/电流A/充放功率kW)                 │
│  getTelemetry + lib/echarts 折线(仿 EnergyStatsTab)          │
├────────────────────────────────────────────────────────────┤
│ (P2) 电芯电压柱状图: 16 芯 bar, 最高红/最低蓝标色,              │
│      压差+极值位置标注; 电芯温度条形图                          │
└────────────────────────────────────────────────────────────┘
```

带 `*` 的字段（SOH/容量）视遥测帧扩展情况灰显"暂无数据"，不阻塞 P1。

### 3.3 复用清单（不要重写）

- `energyUtils.ts`：`toRtEnvelope` / `freshRealtime`（离线防陈旧值）/ `extractEnergyMetrics`（已给 battSoc/battVoltage/battCurrent/chargePower/dischargePower）/ `formatSignedPower` / `getBattState`
- react-query 轮询模式：`queryKeys.devices.realtime(sn)` + `refetchInterval: document.visible ? 10_000 : false`（仿 `EnergyCenterTab.tsx:56-60`）
- SOC 圆环样式：`EnergyCenterTab.tsx:149-160`
- 位图面板模式：`SysStatusBitsPanel.tsx`（12 位网格 → 改造为 bms_warning 位定义表）
- 历史曲线：`deviceApi.getTelemetry` + `src/lib/echarts`（仿 `EnergyStatsTab.tsx:116-144`）
- 字段能力：若把储能字段注册进 `device_protocol_fields`（group_code `bat` 或新 `bms` 组），「全部参数」动态渲染可直接复用 StatusTab 的 `getFieldCapabilities` 模式
- 告警列表：`GetAlarms` 已有

---

## 4. App 端方案（inv_app）

### 4.1 入口与注册点

推荐**轻量路线**（跟随 `device_realtime_page.dart` 现状，页面直接用 `getIt<RealtimeDataService>()`，零新 Bloc）：

| 改动 | 文件 |
|---|---|
| 新建 `lib/features/device/presentation/pages/device_storage_page.dart` | 储能页本体 |
| 详情页入口：AppBar 动作或 `RealtimeDataTab` 电池卡点击跳转；或 TabController 加第 5 个 Tab | `device_realtime_page.dart:520-535` |
| 路由 `GoRoute('/device/:sn/storage')`（注意声明顺序陷阱 `app_router.dart:264-266`） | `core/router/app_router.dart` |
| 词条 | `l10n/app_zh.dart` + `app_en.dart` 各加一节 |

### 4.2 页面布局（移动端竖排）

```
┌──────────────────────────┐
│ SOC 大圆环 + 工作状态 Tag    │  ← 仿电站详情 _energyNodeBatt 的 SOC 展示
├──────────────────────────┤
│ 2×2 指标格: 电压/电流/今日充电/今日放电 │  ← 仿 energy_statistics_tab 四宫格
├──────────────────────────┤
│ 明细卡: SOH · 剩余容量 · 循环次数* · 温度   │
│ (ListTile 行式, 仿 RealtimeDataTab 分组卡) │
├──────────────────────────┤
│ BMS 告警卡: bms_warning 解码 Chips          │
├──────────────────────────┤
│ (P2) 16 芯电压柱状图 (fl_chart BarChart)    │
├──────────────────────────┤
│ 历史曲线入口 → 复用 history_chart_page 模式  │
│ 加 soc 指标 FilterChip + LineChart          │
└──────────────────────────┘
```

### 4.3 复用清单

- 实体：`core/entities/inverter_data.dart` 的 `BatteryData`（字段已齐全，缺的 SOH/容量解析补进 `realtime_data_service.dart` 的 V2 展平解析分支即可）
- 数据流：`RealtimeDataService`（60s 轮询 `/devices/by-sn/:sn/realtime`，broadcast 流）；本地直连模式已有 3s 轮询可复用
- 图表：`fl_chart`（`history_chart_page.dart` 为模板）
- 能量流小部件：电站详情 `_flowArea`/`_energyNodeBatt`（`station_detail_page.dart:558,776`）可抽出来放 SOC+流向
- 权限/角色：无需动 `RoleService.getNavItems`（不进底部 Tab）

---

## 5. 分期落地

| 期 | 内容 | 依赖 |
|---|---|---|
| **P1 页面骨架** | Web `BmsTab` + App 储存页：SOC 环、指标卡、bms_warning 面板、历史曲线（soc/voltage/current/power） | 无后端改动，纯前端 |
| **P2 电芯级** | 后端新增 `GET /devices/by-sn/:sn/cells`（读 `device_cell_samples`，注意 V2 设备该表为空数组需 404/空处理）；两端电芯柱状图 + 温度条 | 新 API |
| **P3 字段扩展** | 采集器固件把 SOH/容量/循环数/MOS 状态/告警明细加进遥测组 → `heartbeat_v2.go` 解析 + `device_protocol_fields` 注册 + realtime 透出 → 前端灰显位点亮；`bms_warning` 位定义表落地 | 固件 + 协议文档 |
| **P4（可选）控制类** | 强制充放 MOS、DO、解锁自锁——需另走设备命令链路（`cs_inv/{sn}/command`），本期不做 | 命令链路设计 |

---

## 6. 数据链路（BMS → ARM → ESP32 → 云端）

```
BMS(BBM-5K-48P)          逆变器 ARM(GD32)              ESP32 采集器              云端
─────────────            ────────────────              ────────────              ─────
CAN@1s 周期广播    ──►   解析 CAN 帧 → 内部变量表  ◄──►  UART 轮询地址映射寄存器
LUX 协议:                BatVolt/BatterySOC/            (PPP 0x7E 帧 + TEA-CBC
 0x355 SOC/SOH+极值芯压   BatChgCurr/BatDischgCurr/      双层加密 + CRC32)
 0x356 总压/电流/极值温    BatChrWatt/BatDisChrWatt/      │
 0x359 保护告警位图+容量   BmsWarning/BatOverCharge…      ▼
 0x351 限压限流                                          MQTT cs_inv/{sn}/heartbeat
 0x35C 使能/循环数                                       信封 v=2，180s 周期
 (收 0x305 判逆变器在线)                                  bat[5] + sys[3]=bms_warning
```

- **BMS → ARM**（`external/储能bms/App/app/LUX_can_protocol.C`，`CAN_TASK_PERIOD=1000`）：默认 LUX CAN 协议，1 秒周期广播；收到逆变器 0x305 标准帧判在线才开始发。备选 Growatt CAN（0x311~0x330，含全 16 芯电压 0x315~0x318）与 RS485 Modbus 族（LUX/SRNE/PACE/XinDun，`host.C` 按节点优先级自动切换）。多包堆叠时 BMS 作为主机先经 `host_slave_can_protocol.c` 聚合从包再转发。
- **ARM → ESP32**（`docs/collector_protocol_print.html` 寄存器映射）：ARM 在变量表里暴露电池相关寄存器——`BatVolt@+62`(0.01V)、`BatterySOC@+64`(1%)、`BatDisChrWatt@+66`、`BatChrWatt@+70`(0.1W)、`BatChgCurr@+74`、`BatDischgCurr@+76`(0.1A)、`BatOverCharge@+78`、`BmsWarning@+92`(u16)。ESP32 经 USART（PPP 帧 + 双层 TEA-CBC + CRC32）按地址读写。
- **ESP32 → 云端**（`docs/CS-L10-6K2_MQTT_上报协议设计_V2.1.md`）：180s 心跳 `cs_inv/{sn}/heartbeat`，信封 v=2，57 值定长数组；`bat[5]`=battery_voltage/battery_soc/battery_current(±)/battery_charge_power/battery_discharge_power，`sys[3]`=bms_warning。服务器 `heartbeat_v2.go` 解析 → Redis realtime + TimescaleDB。
- **旧一代链路并存**（`docs/ARM_ESP32_UART_Protocol.md` v3.0，CS-I10-6k2）：ARM 用 CMD_PUBLISH 透传分主题 JSON——`data/battery`（5s，字段很全：soh/capacity/cycle_count/cell_volt_max/min/diff/protect_status）、`data/cells`（30s，16 芯数组）；心跳 V1 的 `bat[23]`+`cells[2]` 也带全量。device-communication 两代解析器都在。
- **关键瓶颈**：BMS 给 ARM 的 CAN 帧里 SOH、极值芯压、容量、循环数都有（0x355/0x359），但**现行 ARM→ESP 寄存器映射表只暴露 5 个电池量 + BmsWarning**——储能页面要的数据在 BMS→ARM 这一段没丢，丢在 ARM 寄存器表没映射。补数据的扩展点在 ARM 固件寄存器表 + 心跳加 additive 组（如 `bms[n]`），BMS 固件与云端解析器（V2.2+ 已容忍扩展位）基本现成。

## 7. 电池接入与身份识别（现状：云端无显式信号）

- **"有没有接电池"只能推断**：采集器寄存器表（ARM↔ESP32）没有"电池在线/BMS 在线"位；`info.battery_type` 是逆变器控制参数 0x0004 的**用户配置**（0=LiFePO4/1=NCM/2=LeadAcid，未读取前默认 LiFePO4），不是检测结果。可行启发式：`battery_voltage` 持续高于阈值（如 >30V）且 SOC 合法 → 判定"已接入电池"；否则储能页展示"未接入电池"空态。
- **"是不是辰烁协议电池"协议上基本不可区分**：默认 LUX CAN 只有 0x351/0x355/0x356/0x359/0x35C 五个数据帧，**无 ID/SN/厂商帧**，任何遵守该协议的电池发同样帧。唯一身份信号在 Growatt 协议族 0x320（厂商 ASCII "BJ" + 硬/软件版本）；BMS 自身 SN/型号（BBM-5K-48P）仅本地 PC 485/CAN 命令 0x08 可读，不经逆变器上云。
- **要可靠识别需要**：ARM 寄存器表增加 `BmsOnline`（如 0x355 帧超时判定，对称于 BMS 侧 0x305 判逆变器）/`BmsVendor`（Growatt 0x320）→ 心跳 additive 组透出 → 云端显式展示。零固件改动的过渡方案即上述启发式。

## 8. 待确认清单（动工前对照实际设备 payload）

1. 储能设备实际心跳帧里 `bat` 组是否仍为 5 值？SOH/容量/循环数是否已在扩展位里（V2.2+ 解析器会透传但不落库，抓一条真实 MQTT payload 即可确认）？
2. 电芯数据走哪条链路：旧 `cs_inv/{sn}/data/cells` topic，还是新帧扩展组？决定 P2 的 API 读哪张表。
3. `bms_warning` 各 bit 语义表由谁提供（逆变器侧 ARM 定义 vs BMS 16 类告警映射）——决定告警面板的位定义文案。
4. 储能设备在 `devices` 表的 `device_type`/型号注册方式：若新 device_type，设备列表筛选与 field capabilities 组要同步注册。
