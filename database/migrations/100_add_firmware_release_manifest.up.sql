-- 100_add_firmware_release_manifest.up.sql
-- 恢复被归档迁移 058 (firmware_release_manifest) 引入的 firmware_versions 扩展列。
-- 部署库为旧 schema 基线 + 活跃迁移增量演进，058 归档后 security_version /
-- release_signature 列从未应用，导致升级包 items 查询（ota_repository.go 中
-- COALESCE(f.security_version,0) 等）SQL 报 "column does not exist" 并被静默
-- 跳过（err != nil 守卫），表现为主/管理后台固件库为空、升级包无法组装。
-- 幂等写法：已存在该列的库（完整 schema.sql 初始化）重复执行无副作用。
-- ADD CONSTRAINT 无 IF NOT EXISTS 语法，改用 DO 块判断（README 部署会重放全部迁移）。
ALTER TABLE firmware_versions
    ADD COLUMN IF NOT EXISTS security_version BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS release_signature VARCHAR(88) NOT NULL DEFAULT '';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'firmware_security_version_uint32'
    ) THEN
        ALTER TABLE firmware_versions
            ADD CONSTRAINT firmware_security_version_uint32
            CHECK (security_version >= 0 AND security_version <= 4294967295);
    END IF;
END
$$;
