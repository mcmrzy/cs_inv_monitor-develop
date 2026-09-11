-- Migration 114: 修正 firmware_versions 唯一键（区分芯片、排除软删行）
--
-- 背景：firmware_versions 的 UNIQUE(model, version) 有两个缺陷：
--   1. 不含 target_chip —— 同一型号的 ARM/DSP/ESP 固件不允许使用相同版本号字符串，
--      但多芯片固件各自独立编号是正常情况，撞键属于误伤；
--   2. 约束覆盖软删行（status = 0）—— 删除固件后重新上传同一版本必然 23505。
--
-- 生产表现（2026-09-10 实测）：管理后台上传 ARM/DSP 固件返回 500「创建固件失败」。
-- 链路：前端按「型号 + 芯片」在启用固件里推算下一个版本号，ARM/DSP 没有启用固件
-- → 回退默认值 1.0.0 → INSERT (model, '1.0.0') 撞上历史遗留的已软删 ESP 1.0.0。
-- 与升级包软删占键（uq_package_model_version）属同一类问题。
--
-- 修法：改为「同型号 + 同芯片 + 同版本，且仅约束启用行」的部分唯一索引。
-- 效果：不同芯片可复用版本号；软删行不再阻塞重新上传；启用行仍不允许重复。
-- 幂等：DROP CONSTRAINT IF EXISTS / CREATE INDEX IF NOT EXISTS。
--
-- 前置：schema.sql 基线以 UNIQUE(model, version) 内联约束建表，PostgreSQL 自动
--       命名为 firmware_versions_model_version_key；旧库同名，故按名删除即可。
ALTER TABLE firmware_versions
    DROP CONSTRAINT IF EXISTS firmware_versions_model_version_key;

CREATE UNIQUE INDEX IF NOT EXISTS uq_firmware_versions_model_chip_version
    ON firmware_versions (model, target_chip, version)
    WHERE status = 1;
