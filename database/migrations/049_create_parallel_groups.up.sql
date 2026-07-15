-- 049: Create parallel_groups table for parallel group configuration management.
--
-- A parallel group is a logical grouping of devices that are paralleled together
-- (e.g. multiple inverters sharing a single AC bus).  This table stores the
-- user-defined configuration; runtime state is tracked separately in
-- device_parallel_state (migration 039).

CREATE TABLE parallel_groups (
    id              BIGSERIAL PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    description     TEXT NOT NULL DEFAULT '',
    station_id      BIGINT REFERENCES stations(id) ON DELETE SET NULL,
    master_sn       VARCHAR(50) NOT NULL DEFAULT '',
    phase_config    VARCHAR(20) NOT NULL DEFAULT 'single_phase'
                    CHECK (phase_config IN ('single_phase', 'three_phase')),
    device_sns      JSONB NOT NULL DEFAULT '[]'::jsonb
                    CHECK (jsonb_typeof(device_sns) = 'array'),
    status          VARCHAR(20) NOT NULL DEFAULT 'synced'
                    CHECK (status IN ('synced', 'syncing', 'out_of_sync')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_parallel_groups_station ON parallel_groups(station_id);
CREATE INDEX idx_parallel_groups_name ON parallel_groups(name);

COMMENT ON TABLE parallel_groups IS '并联组配置表，管理逻辑分组的设备并联关系';
COMMENT ON COLUMN parallel_groups.device_sns IS '组成员设备 SN 列表 (JSONB array of strings)';
COMMENT ON COLUMN parallel_groups.phase_config IS '相配置: single_phase | three_phase';
COMMENT ON COLUMN parallel_groups.status IS '同步状态: synced | syncing | out_of_sync';
