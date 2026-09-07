-- 094_user_notify_prefs: 用户通知偏好表
-- 服务端存储用户通知设置，推送链路（JPush/邮件）发送前检查该表，
-- 使「我的-消息通知设置」页面的开关真正生效。
-- 字段与 App 端 notify_settings_page.dart 设置项一一对应。

CREATE TABLE IF NOT EXISTS user_notify_prefs (
    user_id BIGINT PRIMARY KEY REFERENCES users(id),
    push_enabled BOOLEAN NOT NULL DEFAULT true,          -- 通知总开关
    notify_online BOOLEAN NOT NULL DEFAULT true,         -- 设备上线通知
    notify_offline BOOLEAN NOT NULL DEFAULT true,        -- 设备离线通知
    notify_alarm BOOLEAN NOT NULL DEFAULT true,          -- 告警通知总开关
    notify_alarm_fatal BOOLEAN NOT NULL DEFAULT true,    -- 严重告警
    notify_alarm_warning BOOLEAN NOT NULL DEFAULT true,  -- 警告
    notify_alarm_info BOOLEAN NOT NULL DEFAULT true,     -- 提示
    notify_alarm_cleared BOOLEAN NOT NULL DEFAULT true,  -- 告警恢复通知
    notify_ota BOOLEAN NOT NULL DEFAULT true,            -- OTA 升级提醒
    notify_system BOOLEAN NOT NULL DEFAULT true,         -- 系统公告
    notify_daily BOOLEAN NOT NULL DEFAULT false,         -- 每日发电统计报告
    daily_report_time VARCHAR(5) NOT NULL DEFAULT '20:00', -- 报告推送时间（用户时区 HH:MM）
    email_enabled BOOLEAN NOT NULL DEFAULT false,        -- 邮件通知渠道
    dnd_enabled BOOLEAN NOT NULL DEFAULT false,          -- 免打扰模式
    dnd_start VARCHAR(5) NOT NULL DEFAULT '22:00',
    dnd_end VARCHAR(5) NOT NULL DEFAULT '07:00',
    alarm_break_dnd BOOLEAN NOT NULL DEFAULT true,       -- 严重告警不受免打扰影响
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE user_notify_prefs IS '用户通知偏好设置，推送前过滤依据';
