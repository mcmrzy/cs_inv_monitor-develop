# Debug Session: alarm-not-displayed

## 状态: [FIXED - 待验证]

## 问题描述
设备端通过 UART/MQTT 持续发布 alarm 数据到主题 `cs_inv/H1CNA00135000014/data/alarm`，但前端监控界面没有任何告警信息显示。

## 假设验证结果

| # | 假设 | 结果 |
|---|------|------|
| H1 | `device_alarms` 表已被迁移脚本删除 | **确认** - migration_cleanup_20260528.sql L9 |
| H2 | 后端写 device_alarms、前端查 alarms，两张表独立 | **确认** - 完全独立的两张表 |
| H3 | Flutter alarmStream 无人监听 | **确认** - 定义但无订阅者 |
| H4 | WebSocket 不推送告警 | **确认** - ws_handler.go 仅推送遥测 |
| H5 | AlarmData.SN json:"-" 导致 SN 丢失 | **确认** - 新增发现，导致 POST 到 API 时 SN 为空 |

## 修复内容 (3 处)

### Fix 1: `inv_device_server/internal/model/device.go:117`
- `SN string \`json:"-"\`` → `SN string \`json:"sn"\`` 
- 原因：AlertConsumer 序列化 AlarmData 时 SN 被忽略，导致内部 API 收到空 SN

### Fix 2: `inv_api_server/internal/handler/internal_handler.go:426-487`
- 改为写入 `alarms` 表（前端查询的表）
- 新增：通过 device_sn 查找 user_id 和 station_id
- 新增：fault_code 映射 alarm_level 等级

### Fix 3: Flutter 端 `inv_app/lib/features/alarm/presentation/bloc/`
- `alarm_bloc.dart`: 新增 `mqttService` 依赖，订阅 `alarmStream`
- `alarm_event.dart`: 新增 `AlarmMqttReceived` 事件
- `service_locator.dart`: DI 注入 MQTTService 到 AlarmBloc

## 修复后数据流
```
设备 → MQTT → EMQX → Kafka → AlertConsumer → POST /api/v1/internal/device-alarm
                                                         ↓
                                                  INSERT INTO alarms ✓
                                                         ↓
                                              REST API GET /alarms ✓
                                                         ↓
                                                   前端显示 ✓

Flutter MQTT: alarmStream → AlarmBloc 自动刷新列表 ✓
```
