# 辰烁 48V 单相离网逆变器 — MQTT 协议文档

**版本**: V2.0\
**更新时间**: 2026-05-20\
**适用设备**: CS-I10-6k2 48V 单相离网逆变器（ESP32-C3 WiFi 通讯模块）\
**相关文档**: `系统参数规范_48V离网逆变器.md`、`ARM_ESP32_Communication_Protocol.md`、`BMS_ARM_Communication_Protocol.md`

***

## 目录

1. [系统架构](#一系统架构)
2. [UART 帧协议（ARM ↔ ESP32）](#二uart-帧协议arm--esp32)
3. [MQTT 连接参数](#三mqtt-连接参数)
4. [主题格式](#四主题格式)
5. [数据上行（设备 → 云端）](#五数据上行设备--云端)
6. [数据下行（云端 → 设备）](#六数据下行云端--设备)
7. [心跳与在线状态](#七心跳与在线状态)
8. [设备配置命令](#八设备配置命令)
9. [数据库设计](#九数据库设计)
10. [示例代码](#十示例代码)
11. [注意事项](#十一注意事项)

***

## 一、系统架构

```
┌─────────────┐     UART      ┌─────────────────┐    MQTT    ┌──────────────────┐
│   ARM MCU   │◄────────────►│  ESP32-C3 WiFi   │◄─────────►│  后端服务器      │
│ (逆变器控制) │   二进制帧协议  │  (透明转发+IP定位) │            │  (云端/APP)      │
│ BMS+MPPT    │              │                  │            │                  │
└─────────────┘              └─────────────────┘            └──────────────────┘
```

**数据流向**：

- ARM → ESP32：`UART 帧协议`（二进制，转义，XOR 校验）
- ESP32 → 云端：`MQTT 协议`（JSON 格式），ESP32 自动附加 `status` 心跳和 IP 定位
- 云端 → ARM：`MQTT → UART 帧协议`（ESP32 透明转发）

**ESP32 职责**：

1. 透传 ARM 数据（不解析 payload 内容，只做 SN 校验 + 主题路由）
2. 自动生成 `status` 心跳消息（在线状态 + RSSI + IP 定位）
3. 管理 WiFi 连接、MQTT 连接、LWT 遗嘱

***

## 二、UART 帧协议（ARM ↔ ESP32）

### 2.1 帧格式

```
┌────────┬────┬────────┬────────┬─────────────┬────────┐
│ 帧头    │ CMD │ 长度高  │ 长度低   │ 数据        │ XOR校验 │
│ 0xAA   │     │ LEN_H  │ LEN_L  │ DATA...     │        │
└────────┴────┴────────┴────────┴─────────────┴────────┘
```

| 字段  | 长度  | 说明               |
| --- | --- | ---------------- |
| 帧头  | 1字节 | 固定 `0xAA`        |
| CMD | 1字节 | 命令码              |
| 长度  | 2字节 | 数据长度（big-endian） |
| 数据  | N字节 | 命令数据             |
| XOR | 1字节 | 校验字节             |

### 2.2 转义规则

帧头 `0xAA` 和转义字节 `0x55` 在数据中出现时需要转义：

| 原字节    | 转义序列        |
| ------ | ----------- |
| `0xAA` | `0x55 0x01` |
| `0x55` | `0x55 0x00` |

> 转义只应用于帧头之后的所有字节，帧头的 `0xAA` 不转义。

### 2.3 XOR 校验

```
XOR = 0xAA ^ CMD ^ LEN_H ^ LEN_L ^ DATA[0] ^ DATA[1] ^ ... ^ DATA[N]
```

### 2.4 命令码

| CMD    | 名称             | 方向      | 说明                   |
| ------ | -------------- | ------- | -------------------- |
| `0x01` | SET\_BROKER    | ARM→ESP | 设置 MQTT 代理地址         |
| `0x02` | PUBLISH        | ARM→ESP | 发布 MQTT 消息（ARM 数据上报） |
| `0x03` | COMMAND\_RECV  | ESP→ARM | 收到云端控制命令             |
| `0x04` | COMMAND\_SEND  | ARM→ESP | 命令执行结果回复             |
| `0x05` | FACTORY\_RESET | ARM→ESP | 恢复出厂设置               |
| `0x06` | HEARTBEAT      | ESP→ARM | 心跳信号（60s）            |
| `0x08` | SET\_SN        | ARM→ESP | 设置设备序列号              |
| `0x09` | SET\_KEY       | ARM→ESP | 设置设备密钥               |
| `0x0A` | SET\_AP\_SSID  | ARM→ESP | 设置热点名称               |
| `0xFE` | ACK            | ESP→ARM | 命令应答成功               |
| `0xFF` | NACK           | ESP→ARM | 命令应答失败               |

***

## 三、MQTT 连接参数

| 参数            | 值                       | 说明                      |
| ------------- | ----------------------- | ----------------------- |
| 协议            | mqtts\://               | TLS 加密（端口 8883）         |
| 端口            | 8883                    | TLS 端口（默认）              |
| Keepalive     | 60s                     | 保活间隔                    |
| Client ID     | 设备 SN                   | 16 位 CS-SN-STD-001 V1.1 |
| Username      | `CSKJ-INV-DEVICE-6K2`   | 固定用户名                   |
| Password      | `CSKJINVDEVICE6K2`      | 固定密码                    |
| Clean Session | false                   | 非清理会话                   |
| 默认 Broker     | `jiuxiaoyw.online:8883` | 可通过 UART 或配网修改          |

***

## 四、主题格式

```
cs_inv/{设备SN}/{子主题}
```

示例：`cs_inv/H1CNA0013500001O/dac`

***

## 五、数据上行（设备 → 云端）

### 5.1 ARM 数据发布流程

ARM 通过 UART `CMD=0x02` 发送 JSON 到 ESP32，ESP32 透传到 MQTT：

**ARM → ESP32 帧格式**：

```
CMD=0x02
DATA={"topic":"data/ac","payload":"{\"voltage\":220.5,...}","sn":"H1CNA0013500001O"}
```

**ESP32 → 云端**：

```
主题: cs_inv/H1CNA0013500001O/data/ac
Payload: {"voltage":220.5,...}     ← 内层 payload 原样转发
```

### 5.2 上行主题总览

| 主题                         | QoS | Retain | 频率   | 来源       | 说明                  |
| -------------------------- | --- | ------ | ---- | -------- | ------------------- |
| `cs_inv/{sn}/status`       | 1   | true   | 60s  | ESP32 自动 | 在线状态 + RSSI + IP 定位 |
| `cs_inv/{sn}/info`         | 1   | false  | 连接时  | ARM      | 设备信息（上电一次）          |
| `cs_inv/{sn}/data/ac`      | 0   | false  | 5s   | ARM      | 交流输出                |
| `cs_inv/{sn}/data/battery` | 0   | false  | 5s   | ARM      | 电池 BMS              |
| `cs_inv/{sn}/data/pv`      | 0   | false  | 5s   | ARM      | 光伏 MPPT             |
| `cs_inv/{sn}/data/status`  | 0   | false  | 5s   | ARM      | 逆变器系统状态             |
| `cs_inv/{sn}/data/energy`  | 0   | false  | 60s  | ARM      | 能量统计                |
| `cs_inv/{sn}/data/cells`   | 0   | false  | 30s  | ARM      | 电芯详细数据              |
| `cs_inv/{sn}/data/alarm`   | 1   | false  | 事件触发 | ARM      | 告警/故障事件             |
| `cs_inv/{sn}/cmd/response` | 1   | false  | 按需   | ARM      | 控制命令执行结果            |

### 5.3 各主题 Payload 格式

> 完整字段定义见 `系统参数规范_48V离网逆变器.md`

#### status（ESP32 自动生成，非 ARM 上报）

```json
{
  "online": true,
  "rssi": -45,
  "location": {
    "ip": "223.5.5.5",
    "city": "Hangzhou"
  }
}
```

| 字段              | 类型          | 说明                   |
| --------------- | ----------- | -------------------- |
| `online`        | bool        | 设备在线状态               |
| `rssi`          | int         | WiFi 信号强度 (dBm)      |
| `location`      | object/null | IP 定位结果（仅 ip + city） |
| `location.ip`   | string      | 公网 IP                |
| `location.city` | string      | 城市（英文）               |

> 定位失败时 `location` 为 `null`。使用 ipapi.co 免费 API，缓存 1 小时，限速 1000 次/天。

#### info（ARM 上报，连接时一次）

```json
{
  "sn": "H1CNA0013500001O",
  "model": "CS1P3K-48",
  "manufacturer": "辰烁科技",
  "firmware_arm": "V1.0.0",
  "firmware_esp": "V1.0.0",
  "type": "off_grid",
  "phase": "single",
  "rated_power": 3000,
  "rated_voltage": 220,
  "rated_freq": 50,
  "battery_voltage": 48,
  "battery_types": ["LiFePO4", "NCM", "LeadAcid"],
  "mppt_count": 1,
  "pv_max_voltage": 150,
  "pv_max_power": 2000,
  "bms_count": 1,
  "cell_count": 16
}
```

#### data/ac（交流输出，5s）

```json
{
  "voltage": 220.5,
  "current": 8.52,
  "power": 1870.3,
  "apparent": 1875.6,
  "reactive": 120.5,
  "frequency": 50.02,
  "pf": 0.997,
  "load_percent": 62.4,
  "thd_v": 1.8,
  "thd_i": 2.5,
  "dc_injection": 15.0
}
```

#### data/battery（电池 BMS，5s）

```json
{
  "soc": 78.5,
  "soh": 96.2,
  "voltage": 51.2,
  "current": 25.5,
  "power": 1305.6,
  "capacity_remain": 78.5,
  "capacity_total": 100.0,
  "cycle_count": 152,
  "temp_max": 28.5,
  "temp_min": 25.0,
  "cell_volt_max": 3.35,
  "cell_volt_min": 3.28,
  "cell_volt_diff": 0.07,
  "charge_state": "charging",
  "battery_type": "LiFePO4",
  "protect_status1": 0,
  "protect_status2": 0
}
```

#### data/pv（光伏 MPPT，5s）

```json
{
  "pv_voltage": 85.3,
  "pv_current": 12.5,
  "pv_power": 1066.3,
  "mppt_state": "tracking"
}
```

#### data/status（逆变器系统状态，5s）

```json
{
  "state": "inverting",
  "fault_code": 0,
  "alarm_code": 0,
  "temp_inv": 48.5,
  "temp_mos": 55.2,
  "temp_ambient": 32.0,
  "dc_bus_voltage": 380.0,
  "fan_speed": 60,
  "efficiency": 94.6
}
```

#### data/energy（能量统计，60s）

```json
{
  "daily_pv": 8.56,
  "total_pv": 1250.3,
  "daily_charge": 7.80,
  "total_charge": 1100.5,
  "daily_discharge": 6.20,
  "total_discharge": 980.8,
  "daily_load": 6.00,
  "total_load": 950.2,
  "runtime_hours": 8640
}
```

#### data/cells（电芯详情，30s）

```json
{
  "cell_count": 16,
  "voltages": [3.32, 3.33, 3.31, 3.32, 3.35, 3.30, 3.32, 3.31, 3.33, 3.32, 3.31, 3.32, 3.34, 3.29, 3.32, 3.31],
  "temps": [26.5, 26.8, 26.2, 26.5, 27.0, 26.0, 26.5, 26.3, 26.8, 26.5, 26.2, 26.5, 26.9, 25.8, 26.5, 26.4],
  "charge_ah_total": 12580.3,
  "discharge_ah_total": 12450.6
}
```

#### data/alarm（告警事件，事件触发）

```json
{
  "event": "alarm",
  "timestamp": 1715000000,
  "source": "bms",
  "fault_code": 257,
  "fault_desc": "单体过压保护",
  "alarm_code": 0,
  "trigger": {
    "cell_no": 5,
    "cell_voltage": 3.65,
    "threshold": 3.60
  }
}
```

#### cmd/response（命令回复，按需）

```json
{
  "result": "ok",
  "cmd": "bms/charge_current",
  "message": "充电电流已设置为 50.0A",
  "timestamp": 1715000000
}
```

***

## 六、数据下行（云端 → 设备）

### 6.1 命令下发

云端通过 `cs_inv/{sn}/cmd` 下发命令，ESP32 透传到 ARM：

**云端 → ESP32 MQTT**：

```
主题: cs_inv/H1CNA0013500001O/cmd
Payload: {"topic":"ac_on","payload":""}
```

**ESP32 → ARM UART**：

```
CMD=0x03 (COMMAND_RECV)
DATA={"topic":"ac_on","payload":""}
```

### 6.2 支持的控制命令

#### 逆变器控制

| 命令                    | Payload         | 说明                   |
| --------------------- | --------------- | -------------------- |
| `ac_on`               | `""`            | 交流输出开启               |
| `ac_off`              | `""`            | 交流输出关闭               |
| `set_voltage`         | `{"value":220}` | 设定输出电压 (V)           |
| `set_freq`            | `{"value":50}`  | 设定输出频率 (Hz)          |
| `set_power_limit`     | `{"value":80}`  | 功率限制（额定功率百分比 0\~100） |
| `eco_mode`            | `{"value":1}`   | 节能模式：0=关, 1=开        |
| `restart`             | `""`            | 软重启                  |
| `set_report_interval` | `{"value":5}`   | 上报间隔 (秒)             |
| `query`               | `""`            | 立即上报全量数据             |

#### BMS 控制（ARM 转发到 Modbus）

| 命令                      | Payload          | BMS 寄存器 | 说明            |
| ----------------------- | ---------------- | ------- | ------------- |
| `bms/charge_enable`     | `{"value":1}`    | 0x1200  | 充放电使能         |
| `bms/charge_current`    | `{"value":500}`  | 0x1201  | 最大充电电流（×0.1A） |
| `bms/discharge_current` | `{"value":1000}` | 0x1202  | 最大放电电流（×0.1A） |
| `bms/charge_volt`       | `{"value":584}`  | 0x1203  | 充电截止电压（×0.1V） |
| `bms/discharge_volt`    | `{"value":430}`  | 0x1204  | 放电截止电压（×0.1V） |
| `bms/balance_enable`    | `{"value":1}`    | 0x1205  | 均衡使能          |
| `bms/balance_threshold` | `{"value":50}`   | 0x1206  | 均衡启动压差 (mV)   |

#### MPPT 控制

| 命令                 | Payload          | 说明          |
| ------------------ | ---------------- | ----------- |
| `mppt_on`          | `""`             | 启用 MPPT     |
| `mppt_off`         | `""`             | 禁用 MPPT     |
| `mppt_power_limit` | `{"value":1000}` | PV 功率限制 (W) |

### 6.3 命令回复

ARM 执行后通过 `CMD=0x04` 回复，ESP32 转发到 `cs_inv/{sn}/cmd/response`。

***

## 七、心跳与在线状态

### 7.1 ESP32 → ARM 心跳

```
CMD=0x06 (HEARTBEAT)
DATA=0x01
```

发送间隔：60s，表示 ESP32 在线。

### 7.2 ESP32 → 云端 status 心跳

ESP32 每 60s 自动发布到 `cs_inv/{sn}/status`（QoS 1, Retain true）：

```json
{
  "online": true,
  "rssi": -45,
  "location": {
    "ip": "223.5.5.5",
    "city": "Hangzhou"
  }
}
```

### 7.3 LWT 遗嘱

MQTT 连接时设置 LWT，设备异常断开时自动发布：

```
主题: cs_inv/{sn}/status
Payload: {"online":false}
Retain: true
```

后端通过监听 `cs_inv/+/status` 的 retained 消息判断设备在线/离线。

***

## 八、注意事项

1. **ESP32 是透传网关**：不解析 ARM 上报的 payload 内容，只做 SN 校验和主题路由。`status` 心跳是唯一由 ESP32 自身生成的消息。
2. **SN 校验**：ARM 通过 PUBLISH 或 SET\_SN 设置 SN 时，ESP32 会校验 CS-SN-STD-001 V1.1 格式，无效 SN 返回 NACK。SN 变更会触发 MQTT 重连。
3. **IP 定位**：WiFi 连接成功后自动请求 ipapi.co，结果缓存 1 小时。定位失败不影响正常功能，`location` 字段为 `null`。
4. **离网特性**：
   - 频率由逆变器自身产生，非电网同步
   - 电池电流正值=充电，负值=放电
   - 无并网/旁路模式
5. **安全建议**：
   - 生产环境使用 mqtts\:// (端口 8883)
   - 设备密钥加密存储
   - API 接口使用 JWT 认证
   - 敏感操作（开关机）需二次确认
6. **消息去重**：后端建议对相同 SN + topic 的消息做时间窗口去重。

