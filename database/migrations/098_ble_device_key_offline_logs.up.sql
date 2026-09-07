--
-- 背景：BLE 本地模式（App 通过蓝牙直连设备）：
--   1. devices 增加 device_key_hash —— 绑定设备时云端生成的 device_key 仅返回一次，
--      库中只存 SHA-256 摘要（设计文档 §4.1）。
--   2. device_offline_op_logs —— App 离线期间本地记录的操作日志，联网后批量上报，
--      (user_id, log_id) 唯一约束实现幂等（设计文档 §4.2）。
--
-- 幂等可重放：ADD COLUMN IF NOT EXISTS / CREATE TABLE IF NOT EXISTS / CREATE INDEX IF NOT EXISTS。

ALTER TABLE devices ADD COLUMN IF NOT EXISTS device_key_hash VARCHAR(64);

CREATE TABLE IF NOT EXISTS device_offline_op_logs (
    id BIGSERIAL PRIMARY KEY,
    log_id VARCHAR(64) NOT NULL,                 -- App 本地 UUID，同步幂等键
    user_id BIGINT NOT NULL,                     -- 同步时归属用户
    device_sn VARCHAR(50) NOT NULL,
    action VARCHAR(50) NOT NULL,                 -- bind/unbind/power_on/power_off/set_power/set_param/ota
    params JSONB DEFAULT '{}',
    result VARCHAR(50) DEFAULT 'ok',
    channel VARCHAR(10) DEFAULT 'ble',           -- cloud/ble
    op_time TIMESTAMPTZ NOT NULL,                -- App 上报的本地操作时间
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, log_id)
);

CREATE INDEX IF NOT EXISTS idx_offline_logs_user_time ON device_offline_op_logs(user_id, op_time DESC);
CREATE INDEX IF NOT EXISTS idx_offline_logs_sn ON device_offline_op_logs(device_sn);
