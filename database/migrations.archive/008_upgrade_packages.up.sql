-- =====================================================
-- Migration 008: OTA升级包架构重构
-- 新增 upgrade_packages + upgrade_package_items 表
-- 修改 device_upgrades 和 devices 表
-- =====================================================

-- 1. 升级包表
CREATE TABLE IF NOT EXISTS upgrade_packages (
    id           BIGSERIAL PRIMARY KEY,
    model        VARCHAR(100) NOT NULL,
    main_version VARCHAR(50) NOT NULL,
    changelog    TEXT NOT NULL DEFAULT '',
    is_force     BOOLEAN NOT NULL DEFAULT FALSE,
    status       SMALLINT NOT NULL DEFAULT 1,
    created_by   BIGINT,
    created_at   TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_package_model_version UNIQUE (model, main_version)
);

CREATE INDEX IF NOT EXISTS idx_pkg_model ON upgrade_packages(model);
CREATE INDEX IF NOT EXISTS idx_pkg_status ON upgrade_packages(status);
CREATE INDEX IF NOT EXISTS idx_pkg_created ON upgrade_packages(created_at DESC);

-- 2. 升级包明细表（关联芯片固件）
CREATE TABLE IF NOT EXISTS upgrade_package_items (
    id               BIGSERIAL PRIMARY KEY,
    package_id       BIGINT NOT NULL REFERENCES upgrade_packages(id) ON DELETE CASCADE,
    firmware_id      BIGINT NOT NULL REFERENCES firmware_versions(id),
    target_chip      VARCHAR(50) NOT NULL,
    firmware_version VARCHAR(50) NOT NULL,
    CONSTRAINT uq_pkg_firmware UNIQUE (package_id, firmware_id),
    CONSTRAINT uq_pkg_chip UNIQUE (package_id, target_chip)
);

CREATE INDEX IF NOT EXISTS idx_pkg_item_package ON upgrade_package_items(package_id);
CREATE INDEX IF NOT EXISTS idx_pkg_item_firmware ON upgrade_package_items(firmware_id);

-- 3. devices 表增加 main_version
ALTER TABLE devices ADD COLUMN IF NOT EXISTS main_version VARCHAR(50) DEFAULT '';

-- 4. device_upgrades 增加 upgrade_package_id
ALTER TABLE device_upgrades ADD COLUMN IF NOT EXISTS upgrade_package_id BIGINT;
CREATE INDEX IF NOT EXISTS idx_du_package_id ON device_upgrades(upgrade_package_id);

-- 替换唯一约束兼容旧数据
ALTER TABLE device_upgrades DROP CONSTRAINT IF EXISTS uq_device_firmware;
CREATE UNIQUE INDEX IF NOT EXISTS uq_du_device_firmware_package
    ON device_upgrades (device_sn, firmware_id, COALESCE(upgrade_package_id, 0));
