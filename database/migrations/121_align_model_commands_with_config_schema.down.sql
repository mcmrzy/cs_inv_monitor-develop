-- 121 down: 删除本迁移为 CS-L10-6K2 从 device_config_schema 补入的命令。
-- 091/096 原生命令 display_name_key 为 commands.*，本迁移补入的为 config.*（与 schema 同源）。
-- model_id 回绑保留：无法可靠区分来源，解绑会直接破坏控制能力。
DELETE FROM device_model_commands c
USING device_models dm
WHERE c.model_id = dm.id
  AND dm.model_code = 'CS-L10-6K2'
  AND c.display_name_key IN (SELECT display_name_key FROM device_config_schema);
