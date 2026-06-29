# 新型号设备接入指南

## 概述

系统支持通过后台管理页面配置不同型号设备的显示参数和控制命令，无需修改代码。

## 接入步骤

### 1. 创建设备型号

Admin 网页 → 型号管理 → 新建型号

| 字段 | 说明 | 示例 |
|------|------|------|
| 型号编码 | 唯一标识 | `CS-I10-6k2` |
| 型号名称 | 显示名称 | `CS-I10-6k2 48V离网逆变器` |
| 制造商 | 厂商名称 | `CS` |
| 分类 | 设备类型 | `inverter` / `battery` / `meter` / `hybrid` |
| 额定功率 | kW | `6.2` |

### 2. 配置字段（显示参数）

在型号详情页 → 字段管理 → 新增字段

| 字段 | 说明 | 示例 |
|------|------|------|
| field_key | 后端标识（需与 MQTT 数据的 key 对应） | `ac_voltage` |
| field_name | 显示名称 | `交流电压` |
| field_type | 数据类型 | `float` / `int` / `string` / `bool` |
| unit | 单位 | `V` / `A` / `W` / `kWh` / `%` |
| sort | 排序（越小越靠前） | `10` |
| is_show | 是否在前端显示 | `true` |
| group_name | 分组名称 | `交流参数` |
| parse_rule | 解析规则（数学表达式，x 为变量） | `x/1000` |

**分组建议：**
- `交流参数` — AC 相关字段
- `光伏参数` — PV 相关字段
- `电池参数` — Battery 相关字段
- `系统状态` — 状态/温度/效率等
- `能量统计` — 发电量/运行时间等
- `设备信息` — SN/型号/固件版本等

### 3. 配置控制命令

在字段管理中，将 `is_control` 设为 `true` 的字段会出现在控制页面。

| 字段 | 说明 | 示例 |
|------|------|------|
| field_key | 命令标识 | `ac_on` |
| field_name | 命令名称 | `开机` |
| is_control | 设为 true | `true` |
| control_params | 控制参数 JSON | 见下方 |

**control_params 示例：**

```json
// 简单开关命令
{"label": "开机", "confirm": true, "confirm_message": "确认开机？"}

// 带数值输入的命令
{"label": "设置功率限制", "input_type": "number", "min": 0, "max": 10000, "step": 100, "unit": "W"}

// 开关切换命令
{"label": "ECO模式", "input_type": "switch", "confirm": true}
```

### 4. 配置协议（MQTT 解析规则）

在型号详情页 → 协议管理 → 新增协议

| 字段 | 说明 | 示例 |
|------|------|------|
| topic_pattern | MQTT topic 模式 | `data/ac` |
| parse_type | 解析方式 | `json` / `modbus` / `custom` |
| parse_config | 解析配置 JSON | `{}` |
| is_active | 是否启用 | `true` |

**常用 topic 模式：**
- `data/ac` — 交流数据
- `data/pv` — 光伏数据
- `data/energy` — 能量统计
- `data/status` — 系统状态
- `data/battery` — 电池数据
- `data/info` — 设备信息
- `status` — 在线状态

### 5. 绑定设备到型号

在设备管理中，将设备的 `model_id` 关联到对应的型号。

### 6. 验证

- Admin 网页设备详情 → 应显示型号配置的字段
- 手机 App 设备详情 → 应按分组显示字段
- 控制页面 → 应显示配置的控制命令

## 数据流

```
设备 MQTT 上报 → mqtt-kafka-bridge → Kafka → inv_device_server
  ↓
  1. 查询设备 model_id
  2. 加载 model 的 fields + protocols
  3. 根据 topic 选择 protocol adapter
  4. 解析数据 + 应用 field mapping + parse_rule
  5. 存入 Redis + 调用 internal API 存入 PostgreSQL
  ↓
API Server
  ↓
  - 设备列表/详情返回 model_fields（含 group_name, control_params）
  - 控制命令校验 is_control 字段
  ↓
前端（Admin 网页 / 手机 App）
  ↓
  - 根据 model_fields 动态渲染
  - 按 group_name 分组显示
  - 控制命令根据 control_params 生成 UI
```

## 注意事项

1. `field_key` 必须与设备上报数据的 key 匹配（或通过 parse_rule 映射）
2. `group_name` 为空的字段会归入"其他"分组
3. `is_show=false` 的字段不会在前端显示，但数据仍会存储
4. `is_control=true` 的字段才会出现在控制页面
5. `parse_rule` 支持简单数学表达式：`x/1000`、`x*0.1+5` 等
