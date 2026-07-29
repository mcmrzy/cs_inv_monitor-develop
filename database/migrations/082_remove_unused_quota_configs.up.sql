-- 删除未使用的系统配额配置
-- 这些配置存储在前端但后端从未使用，属于无效配置
DELETE FROM system_configs 
WHERE config_key IN (
    'maxDevicesPerTenant',
    'maxUsersPerTenant', 
    'maxAlertsPerDay',
    'maxOtaTasksPerMonth'
);
