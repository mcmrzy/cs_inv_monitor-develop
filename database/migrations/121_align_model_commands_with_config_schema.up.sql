-- 121: 对齐型号控制命令与 config schema
-- 背景：远程设置 UI 读 device_config_schema（全局 42 键），下发校验读 device_model_commands（按 model_id）。
-- 若设备 model_id 为空、或型号命令表缺少 schema 键，会出现 UI 可见但 400 UNSUPPORTED_COMMAND。
-- 本迁移：1) 用 devices.model 回绑 model_id；2) 为 CS-L10-6K2 补齐 schema 中缺失且未禁用的写命令。

-- 1. 存量设备：model 文本能匹配型号编码时回绑 model_id
UPDATE devices d
SET model_id = dm.id, updated_at = NOW()
FROM device_models dm
WHERE d.model = dm.model_code
  AND d.model_id IS NULL
  AND dm.lifecycle_status != 'retired'
  AND d.deleted_at IS NULL;

-- 2. CS-L10-6K2：把 device_config_schema 中尚无命令记录的参数补进 device_model_commands
--    已有记录（含 is_enabled=false）不覆盖，避免覆盖运维手工禁用。
INSERT INTO device_model_commands(
    model_id, command_code, display_name_key, parameter_schema,
    timeout_seconds, risk_level, is_enabled, config_domain, operation_kind
)
SELECT
    dm.id,
    s.param_key,
    s.display_name_key,
    jsonb_build_object(
        'args', jsonb_build_array(
            CASE
                WHEN s.control_type = 'boolean' THEN
                    jsonb_build_object('key', 'value', 'type', 'boolean')
                WHEN s.control_type = 'enum' THEN
                    jsonb_build_object(
                        'key', 'value', 'type', 'integer',
                        'enum', (
                            SELECT jsonb_agg(k ORDER BY k::int)
                            FROM jsonb_object_keys(COALESCE(s.enum_map, '{}'::jsonb)) AS k
                        ),
                        'unit', COALESCE(s.unit, '')
                    )
                ELSE
                    jsonb_build_object(
                        'key', 'value', 'type', 'number',
                        'min', s.min, 'max', s.max,
                        'unit', COALESCE(s.unit, '')
                    )
            END
        )
    ),
    30,
    1,
    TRUE,
    s.group_code,
    'write'
FROM device_models dm
CROSS JOIN device_config_schema s
WHERE dm.model_code = 'CS-L10-6K2'
  AND NOT EXISTS (
    SELECT 1 FROM device_model_commands c
    WHERE c.model_id = dm.id AND c.command_code = s.param_key
  );
