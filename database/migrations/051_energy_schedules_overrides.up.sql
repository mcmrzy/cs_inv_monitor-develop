-- 051_energy_schedules_overrides: 能源计划与临时覆盖
CREATE TABLE IF NOT EXISTS device_energy_schedules (
    device_sn VARCHAR(50) PRIMARY KEY,
    timezone VARCHAR(64) NOT NULL DEFAULT 'Asia/Shanghai',
    revision BIGINT NOT NULL DEFAULT 0,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    periods JSONB NOT NULL DEFAULT '[]'::jsonb,
    updated_by BIGINT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS device_control_overrides (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    domain VARCHAR(32) NOT NULL,
    value JSONB NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    task_id UUID,
    created_by BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    active BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE INDEX IF NOT EXISTS idx_dco_sn_active ON device_control_overrides(device_sn, expires_at) WHERE active = TRUE;
