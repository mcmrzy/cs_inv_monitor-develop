-- 110 down: 回退 permission_code 至 096 迁移的原始默认值（'device:control'）。
-- 注意回退会重新锁死非系统管理员的远程参数编辑（原始缺陷状态）。

BEGIN;

ALTER TABLE device_config_schema
    ALTER COLUMN permission_code SET DEFAULT 'device:control';

UPDATE device_config_schema
SET permission_code = 'device:control'
WHERE permission_code = 'devices:control';

COMMIT;
