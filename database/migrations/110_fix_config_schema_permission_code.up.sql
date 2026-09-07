-- 110: 修正 device_config_schema.permission_code 的错误权限码
--
-- 迁移 096 将 permission_code 默认值定为 'device:control'（单数），但系统
-- 权限码体系（role_permission_grants / role_default_grants.go）使用的是
-- 'devices:control'（复数）。拼写不一致导致该码在所有角色的权限矩阵中
-- 均不存在：非系统管理员在远程参数设置页的全部参数被锁为只读（前端
-- canEdit 按 permission_code 判定），仅系统管理员凭 isSystemAdmin 直通。
--
-- 修正为 'devices:control'：四级角色（org_admin/agent/installer/customer）
-- 均持有该码，终端用户由此获得与自己设备远程参数的编辑能力（与 App 端
-- 对齐）；后续如需参数级差异化授权，可再按参数配置更细的权限码。

BEGIN;

ALTER TABLE device_config_schema
    ALTER COLUMN permission_code SET DEFAULT 'devices:control';

UPDATE device_config_schema
SET permission_code = 'devices:control'
WHERE permission_code = 'device:control';

COMMIT;
