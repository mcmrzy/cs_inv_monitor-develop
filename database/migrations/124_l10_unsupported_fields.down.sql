-- 124 反向迁移：CS-L10-6K2 未实现字段标记回滚（恢复 096 行为）。
-- 适用场景：厂家补齐 ARM 固件后（10 字段上报真实值），撤销字段能力门控与字段隐藏。
-- 幂等可重放：仅当对应键/值需要变更时才更新，重复执行影响 0 行。
-- 注意：诊断阈值（fan_speed_low_percent 等，096 写入）与 specifications 其它键保持不变。
-- 注意：allow_alarm_rule 按"注册时的原始集合"逐键恢复（不一律置 TRUE）——
--   原始为 TRUE 的 6 键：096 §5.3 的 inv_fan_speed / mppt_fan_speed / inv_current /
--     work_time_total / paired_socket，以及 091 §5 的 transformer_temperature；
--   原始为 FALSE 的 4 键：parallel_charge_current / pv_temperature / online_socket / on_socket。
--   show_realtime / show_history 在 091 §5 与 096 §5.3 均未显式赋值 → 采用建表默认 TRUE。

-- ============================================================
-- 1. 移除 diagnostics.unsupported_fields（其余 diagnostics 键保留）
-- ============================================================
UPDATE device_models
SET specifications = jsonb_set(
        specifications,
        '{diagnostics}',
        COALESCE(specifications->'diagnostics', '{}'::jsonb) - 'unsupported_fields'
    ),
    updated_at = NOW()
WHERE model_code = 'CS-L10-6K2'
  AND COALESCE(specifications->'diagnostics', '{}'::jsonb) ? 'unsupported_fields';

-- ============================================================
-- 2. 字段能力恢复（与 up 的 10 键一一对应）
-- ============================================================
-- 2.1 is_supported / is_visible / show_realtime / show_history 恢复为注册时取值（均为 TRUE）
UPDATE device_model_fields
SET is_supported  = TRUE,
    is_visible    = TRUE,
    show_realtime = TRUE,
    show_history  = TRUE,
    updated_at    = NOW()
WHERE model_id = (SELECT id FROM device_models WHERE model_code = 'CS-L10-6K2')
  AND field_key IN (
        'mppt_fan_speed',
        'inv_fan_speed',
        'parallel_charge_current',
        'work_time_total',
        'inv_current',
        'pv_temperature',
        'transformer_temperature',
        'paired_socket',
        'online_socket',
        'on_socket'
      )
  AND (is_supported IS DISTINCT FROM TRUE OR is_visible IS DISTINCT FROM TRUE
       OR show_realtime IS DISTINCT FROM TRUE OR show_history IS DISTINCT FROM TRUE);

-- 2.2 allow_alarm_rule：恢复原始 TRUE 集合（096 §5.3 的 5 键 + 091 §5 的 transformer_temperature）
UPDATE device_model_fields
SET allow_alarm_rule = TRUE,
    updated_at       = NOW()
WHERE model_id = (SELECT id FROM device_models WHERE model_code = 'CS-L10-6K2')
  AND field_key IN (
        'inv_fan_speed',
        'mppt_fan_speed',
        'inv_current',
        'work_time_total',
        'paired_socket',
        'transformer_temperature'
      )
  AND allow_alarm_rule IS DISTINCT FROM TRUE;

-- 2.3 allow_alarm_rule：其余 4 键原始为 FALSE（091 §5 / 096 §5.3 的 IN 列表未包含它们）
UPDATE device_model_fields
SET allow_alarm_rule = FALSE,
    updated_at       = NOW()
WHERE model_id = (SELECT id FROM device_models WHERE model_code = 'CS-L10-6K2')
  AND field_key IN (
        'parallel_charge_current',
        'pv_temperature',
        'online_socket',
        'on_socket'
      )
  AND allow_alarm_rule IS DISTINCT FROM FALSE;
