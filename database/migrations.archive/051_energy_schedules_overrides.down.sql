-- 051_energy_schedules_overrides: 回滚能源计划与临时覆盖
DROP INDEX IF EXISTS idx_dco_sn_active;
DROP TABLE IF EXISTS device_control_overrides;
DROP TABLE IF EXISTS device_energy_schedules;
