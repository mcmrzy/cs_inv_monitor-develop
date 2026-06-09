-- ============================================
-- 数据库清理迁移脚本 - 2026-05-28
-- 目标：删除过时表，统一数据架构
-- ============================================

-- 1. 删除确认无引用的旧表
DROP TABLE IF EXISTS device_minute_data CASCADE;
DROP TABLE IF EXISTS user_operation_logs CASCADE;
DROP TABLE IF EXISTS device_alarms CASCADE;
DROP TABLE IF EXISTS regions CASCADE;
DROP TABLE IF EXISTS device_params CASCADE;
DROP TABLE IF EXISTS device_shares CASCADE;
DROP TABLE IF EXISTS messages CASCADE;
DROP TABLE IF EXISTS user_notify_settings CASCADE;
DROP TABLE IF EXISTS ota_records CASCADE;

-- 2. 如果 device_realtime_data 存在，迁移最新数据到 device_telemetry，然后删除
DO $$
BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'device_realtime_data') THEN
        IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'device_telemetry') THEN
            EXECUTE $$
                INSERT INTO device_telemetry (device_sn, data, total_active_power, daily_energy, time)
                SELECT 
                    d.device_sn,
                    jsonb_build_object(
                        'pv1_voltage', d.pv1_voltage, 'pv1_current', d.pv1_current, 'pv1_power', d.pv1_power,
                        'pv2_voltage', d.pv2_voltage, 'pv2_current', d.pv2_current, 'pv2_power', d.pv2_power,
                        'battery_voltage', d.battery_voltage, 'battery_current', d.battery_current,
                        'battery_soc', d.battery_soc, 'battery_temp', d.battery_temp,
                        'grid_voltage', d.grid_voltage, 'grid_frequency', d.grid_frequency, 'grid_power', d.grid_power,
                        'output_voltage', d.output_voltage, 'output_current', d.output_current,
                        'output_power', d.output_power, 'power_factor', d.power_factor,
                        'board_temp', d.board_temp, 'tube_temp', d.tube_temp,
                        'fault_code', d.fault_code, 'fault_message', d.fault_message,
                        'run_mode', d.run_mode, 'wifi_signal', d.wifi_signal
                    ),
                    COALESCE(d.total_power, 0),
                    COALESCE(d.daily_power_yields, 0),
                    d.data_time
                FROM device_realtime_data d
                WHERE d.updated_at > NOW() - INTERVAL '1 hour'
                ON CONFLICT DO NOTHING
            $$;
            RAISE NOTICE 'Migrated realtime data to device_telemetry';
        END IF;
        DROP TABLE device_realtime_data CASCADE;
        RAISE NOTICE 'Dropped device_realtime_data';
    ELSE
        RAISE NOTICE 'device_realtime_data does not exist, skipping';
    END IF;
END $$;

-- 3. 删除旧的历史数据表（已被 TimescaleDB 连续聚合替代）
-- 注意：如果 TimescaleDB 连续聚合已正常运行，可以安全删除
DROP TABLE IF EXISTS device_hour_data CASCADE;
DROP TABLE IF EXISTS device_day_data CASCADE;
DROP TABLE IF EXISTS station_day_data CASCADE;

-- 4. 删除旧的视图（基于已删除的表）
DROP VIEW IF EXISTS v_station_realtime CASCADE;
DROP VIEW IF EXISTS v_user_devices CASCADE;

-- 5. 删除用户会话表（改用 JWT）
DROP TABLE IF EXISTS user_sessions CASCADE;

-- 6. 清理函数（更新以适配新架构）
CREATE OR REPLACE FUNCTION clean_expired_data()
RETURNS void AS $$
BEGIN
    -- 清理过期验证码
    DELETE FROM verification_codes WHERE expires_at < CURRENT_TIMESTAMP;
    
    -- 注意：分钟级/小时级数据已由 TimescaleDB 自动管理
    -- 原始遥测数据保留策略由 add_retention_policy 控制
END;
$$ LANGUAGE plpgsql;

-- 7. 统一 command_logs 表结构
-- 如果存在旧版 command_logs，备份后重建
DO $$
BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'command_logs') THEN
        -- 检查是否有旧结构（id, device_sn, cmd_type, params, operator_id, ip, created_at）
        IF EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'command_logs' AND column_name = 'cmd_type') THEN
            EXECUTE 'ALTER TABLE command_logs RENAME TO command_logs_old';
            RAISE NOTICE 'Renamed old command_logs to command_logs_old';
        ELSE
            RAISE NOTICE 'command_logs already has new structure, skipping rebuild';
        END IF;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS command_logs (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    command_name VARCHAR(50) NOT NULL,
    command_label VARCHAR(100) NOT NULL,
    params JSONB,
    req_id VARCHAR(50) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    result_message TEXT,
    executed_by BIGINT NOT NULL,
    ip_address VARCHAR(45),
    retry_count INTEGER DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_cmd_logs_sn ON command_logs(device_sn);
CREATE INDEX IF NOT EXISTS idx_cmd_logs_user ON command_logs(executed_by);
CREATE INDEX IF NOT EXISTS idx_cmd_logs_time ON command_logs(created_at);

-- 8. 清理冗余触发器（基于已删除的表，已安全跳过）
-- device_params 和 user_notify_settings 已在步骤 1 删除，触发器自动移除

-- 9. 确保 device_telemetry 超表已正确设置
-- 如果还没有创建超表，执行以下语句
-- SELECT create_hypertable('device_telemetry', 'time', if_not_exists => TRUE);

-- 10. 更新 system_configs（移除过时的配置项）
DELETE FROM system_configs WHERE config_key IN ('data_retention_days');
INSERT INTO system_configs (config_key, config_value, description) VALUES
('telemetry_retention_days', '90', '遥测数据保留天数（TimescaleDB 自动管理）')
ON CONFLICT (config_key) DO UPDATE SET config_value = EXCLUDED.config_value;

-- 完成
SELECT 'DATABASE_CLEANUP_COMPLETED' as result;
