# 告警级别查询修复计划

## 问题描述
通知中心显示"设备故障"时，图标和颜色显示为绿色（正常），应该显示为红色（严重）。

## 根本原因
后端代码中查询严重告警时使用了错误的 `alarm_level` 值：
- **当前代码**: `alarm_level = 1` （提示/info）
- **正确值**: `alarm_level = 3` （严重/fault）

根据新的告警码定义：
- DB alarm_level: 1=提示(info), 2=警告(warning), 3=严重(fault)

## 需要修复的文件

### 1. inv_api_server/internal/handler/internal_handler.go

**位置 1**: 第 118 行 - 检查是否有未处理的严重告警
```go
// 错误代码
`SELECT COUNT(*) FROM alarms WHERE device_sn = $1 AND alarm_level = 1 AND status = 0`, req.SN,

// 修复后
`SELECT COUNT(*) FROM alarms WHERE device_sn = $1 AND alarm_level = 3 AND status = 0`, req.SN,
```

**位置 2**: 第 271 行 - 设备状态恢复逻辑
```go
// 错误代码
SELECT 1 FROM alarms WHERE alarms.device_sn = $1 AND alarms.alarm_level = 1 AND alarms.status = 0

// 修复后
SELECT 1 FROM alarms WHERE alarms.device_sn = $1 AND alarms.alarm_level = 3 AND alarms.status = 0
```

## 影响范围
- 设备上线时检查是否有未处理严重告警的逻辑
- 设备状态从故障恢复到在线的判断逻辑

## 验证步骤
1. 重启 inv-api-server 服务
2. 发送测试告警（code=1，应该是 fault/严重）
3. 查看通知中心，确认显示红色错误图标和"严重"标签
4. 点击查看详情，确认页面显示正确

## 注意事项
- 此修复只涉及后端 Go 代码
- Flutter 前端代码已经正确映射了 severity
- 数据库中的历史数据可能需要手动更新 alarm_level 字段（如果之前存储错误）
