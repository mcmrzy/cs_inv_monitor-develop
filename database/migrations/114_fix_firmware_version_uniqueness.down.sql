-- 回滚：恢复 UNIQUE(model, version) 全表约束。
-- 注意：若回滚前已存在「同型号不同芯片复用同一版本号」的启用行，
--       本回滚会因重复键失败，需先清理或改名这些行。
DROP INDEX IF EXISTS uq_firmware_versions_model_chip_version;

ALTER TABLE firmware_versions
    ADD CONSTRAINT firmware_versions_model_version_key UNIQUE (model, version);
