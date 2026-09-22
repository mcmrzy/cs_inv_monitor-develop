-- 125 反向迁移：CS-L10-6K2 V1 遗留死键隐藏回滚（恢复展示）。
-- 适用场景：ARM/DSP 将来实现了其中某些字段（或决定用 V1 键承接派生值），
-- 撤销字段能力门控与隐藏。幂等可重放：仅当值需要变更时才更新，重复执行影响 0 行。
-- 注意：allow_alarm_rule/show_realtime/show_history 在 091 §5 均未显式赋值
-- （建表默认 TRUE），allow_compare/default_chart 注册时即为 FALSE 且本迁移未动。

UPDATE device_model_fields
SET is_supported     = TRUE,
    is_visible       = TRUE,
    show_realtime    = TRUE,
    show_history     = TRUE,
    allow_alarm_rule = TRUE,
    updated_at       = NOW()
WHERE model_id = (SELECT id FROM device_models WHERE model_code = 'CS-L10-6K2')
  AND field_key IN (
        'pv1_current',
        'pv2_current',
        'mos_temperature',
        'alarm_code',
        'runtime_hours',
        'mppt_state',
        'pv1_power',
        'pv1_power_max',
        'pv1_voltage_max',
        'pv2_power',
        'pv2_power_max',
        'ac_power_factor',
        'ac_voltage_thd',
        'ambient_temperature',
        'efficiency',
        'fan_speed_percent',
        'system_mode'
      )
  AND (is_supported IS DISTINCT FROM TRUE OR is_visible IS DISTINCT FROM TRUE
       OR show_realtime IS DISTINCT FROM TRUE OR show_history IS DISTINCT FROM TRUE
       OR allow_alarm_rule IS DISTINCT FROM TRUE);
