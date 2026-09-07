-- 回滚：重新插入系统配额配置
INSERT INTO system_configs (config_key, config_value, description) VALUES
('maxDevicesPerTenant', '500', '每租户最大设备数'),
('maxUsersPerTenant', '200', '每租户最大用户数'),
('maxAlertsPerDay', '1000', '每日最大告警数'),
('maxOtaTasksPerMonth', '50', '每月最大OTA任务数')
ON CONFLICT (config_key) DO NOTHING;
