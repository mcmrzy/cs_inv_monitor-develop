-- 027: extend device_model_commands with fine-grained capability metadata and
-- register permission codes in role_permissions for RBAC enforcement.

-- =============================================================================
-- 1. Extend device_model_commands table with new capability columns
-- =============================================================================
ALTER TABLE device_model_commands
    ADD COLUMN IF NOT EXISTS config_domain VARCHAR(32),
    ADD COLUMN IF NOT EXISTS permission_code VARCHAR(64),
    ADD COLUMN IF NOT EXISTS operation_kind VARCHAR(20) DEFAULT 'persistent',
    ADD COLUMN IF NOT EXISTS requires_stopped BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS requires_bms_online BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS requires_group_master BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS confirmation_mode VARCHAR(20) DEFAULT 'none',
    ADD COLUMN IF NOT EXISTS ttl_seconds INTEGER,
    ADD COLUMN IF NOT EXISTS cooldown_seconds INTEGER,
    ADD COLUMN IF NOT EXISTS precondition_schema JSONB DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS ui_schema JSONB DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS min_firmware VARCHAR(32);

-- =============================================================================
-- 2. Widen risk_level CHECK constraint from 1..3 to 0..4
--    (0 = info-only / read, 4 = factory-reset)
-- =============================================================================
ALTER TABLE device_model_commands DROP CONSTRAINT IF EXISTS device_model_commands_risk_level_check;
ALTER TABLE device_model_commands ADD CONSTRAINT device_model_commands_risk_level_check
    CHECK (risk_level BETWEEN 0 AND 4);

-- =============================================================================
-- 3. Backfill config_domain and permission_code for existing commands
-- =============================================================================

-- AC on/off — disruptive output control
UPDATE device_model_commands SET
    config_domain = 'output',
    permission_code = 'device_control_disruptive'
WHERE command_code IN ('ac_on', 'ac_off');

-- Power limit — basic output control
UPDATE device_model_commands SET
    config_domain = 'output',
    permission_code = 'device_control_basic'
WHERE command_code = 'set_power_limit';

-- Battery charge/discharge limits and BMS parameters — battery configuration
UPDATE device_model_commands SET
    config_domain = 'battery',
    permission_code = 'device_configure_battery'
WHERE command_code IN (
    'set_charge_limit', 'set_discharge_limit',
    'bms_set_charge_current', 'bms_set_discharge_current',
    'bms_set_charge_voltage', 'bms_set_discharge_voltage',
    'bms_set_enable'
);

-- SOC window — basic battery control
UPDATE device_model_commands SET
    config_domain = 'battery',
    permission_code = 'device_control_basic'
WHERE command_code = 'set_soc_window';

-- Force charge/discharge — disruptive battery control
UPDATE device_model_commands SET
    config_domain = 'battery',
    permission_code = 'device_control_disruptive'
WHERE command_code IN ('force_charge', 'force_discharge');

-- Restart — disruptive service operation
UPDATE device_model_commands SET
    config_domain = 'service',
    permission_code = 'device_control_disruptive'
WHERE command_code = 'restart';

-- Query / read commands — basic service operations
UPDATE device_model_commands SET
    config_domain = 'service',
    permission_code = 'device_control_basic'
WHERE command_code IN ('query_config', 'query_telemetry', 'get_params');

-- Factory reset — factory-only service operation
UPDATE device_model_commands SET
    config_domain = 'service',
    permission_code = 'device_service_factory'
WHERE command_code = 'reset';

-- Parameter write / control / alarm / batch config — disruptive service operations
UPDATE device_model_commands SET
    config_domain = 'service',
    permission_code = 'device_control_disruptive'
WHERE command_code IN ('set_params', 'set_control', 'set_alarm', 'batch_config');

-- Parallel commands — parallel configuration
UPDATE device_model_commands SET
    config_domain = 'parallel',
    permission_code = 'device_configure_parallel'
WHERE command_code IN ('parallel_enable', 'parallel_set_role', 'parallel_set_phase', 'parallel_disable');

-- =============================================================================
-- 4. Partial index for enabled commands grouped by model + domain
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_dmc_model_domain
    ON device_model_commands(model_id, config_domain)
    WHERE is_enabled = true;

-- =============================================================================
-- 5. Register fine-grained permission codes in role_permissions
--
--    Permission code              → (resource, action)
--    device_control_basic         → (device_control, basic)
--    device_control_disruptive    → (device_control, disruptive)
--    device_configure_battery     → (device_configure, battery)
--    device_configure_ac_input    → (device_configure, ac_input)
--    device_configure_parallel    → (device_configure, parallel)
--    device_service_diagnostics   → (device_service, diagnostics)
--    device_service_factory       → (device_service, factory)
--    ota_control                  → (ota, control)
--
--    Role matrix (✓ = is_allowed):
--    | Permission                  | r1 | r2 | r3 | r4 | r5 |
--    | device_control_basic       |  ✓ |  ✓ |  ✓ |  ✓ |  ✓ |
--    | device_control_disruptive  |  ✓ |  ✓ |  ✓ |  ✓ |    |
--    | device_configure_battery   |  ✓ |    |    |  ✓ |    |
--    | device_configure_ac_input  |  ✓ |    |    |  ✓ |    |
--    | device_configure_parallel  |  ✓ |  ✓ |  ✓ |  ✓ |    |
--    | device_service_diagnostics |  ✓ |  ✓ |  ✓ |    |    |
--    | device_service_factory     |    |    |    |    |    |
--    | ota_control                |  ✓ |  ✓ |  ✓ |    |    |
-- =============================================================================

-- device_control_basic — allowed for all non-super-admin roles (1-5)
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
    (1, 'device_control', 'basic', true),
    (2, 'device_control', 'basic', true),
    (3, 'device_control', 'basic', true),
    (4, 'device_control', 'basic', true),
    (5, 'device_control', 'basic', true)
ON CONFLICT (role, resource, action) DO NOTHING;

-- device_control_disruptive — roles 1-4 only
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
    (1, 'device_control', 'disruptive', true),
    (2, 'device_control', 'disruptive', true),
    (3, 'device_control', 'disruptive', true),
    (4, 'device_control', 'disruptive', true)
ON CONFLICT (role, resource, action) DO NOTHING;

-- device_configure_battery — roles 1 and 4 only
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
    (1, 'device_configure', 'battery', true),
    (4, 'device_configure', 'battery', true)
ON CONFLICT (role, resource, action) DO NOTHING;

-- device_configure_ac_input — roles 1 and 4 only
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
    (1, 'device_configure', 'ac_input', true),
    (4, 'device_configure', 'ac_input', true)
ON CONFLICT (role, resource, action) DO NOTHING;

-- device_configure_parallel — roles 1-4 only
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
    (1, 'device_configure', 'parallel', true),
    (2, 'device_configure', 'parallel', true),
    (3, 'device_configure', 'parallel', true),
    (4, 'device_configure', 'parallel', true)
ON CONFLICT (role, resource, action) DO NOTHING;

-- device_service_diagnostics — roles 1-3 only
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
    (1, 'device_service', 'diagnostics', true),
    (2, 'device_service', 'diagnostics', true),
    (3, 'device_service', 'diagnostics', true)
ON CONFLICT (role, resource, action) DO NOTHING;

-- device_service_factory — no roles granted (super-admin only via code-level bypass)

-- ota_control — roles 1-3 only
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
    (1, 'ota', 'control', true),
    (2, 'ota', 'control', true),
    (3, 'ota', 'control', true)
ON CONFLICT (role, resource, action) DO NOTHING;
