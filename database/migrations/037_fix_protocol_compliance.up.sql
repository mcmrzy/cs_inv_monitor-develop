-- =====================================================
-- Migration 037: Fix protocol compliance issues (C-3, C-4)
-- =====================================================
-- C-3: PV field mapping error
--   Protocol defines pv[0]..pv[6] (7 fields), but migration 023
--   inserted 12 PV fields (pv[0]..pv[11]).
--   Migration 026 already fixed this by deleting ALL protocol fields
--   and re-inserting with the correct 7 PV fields. The statements
--   below are idempotent safety checks — they are no-ops if 026
--   has already been applied.
--
-- C-4: 4 commands missing from device_model_commands
--   set_soc_low, set_soc_high, parallel_sync_start, parallel_sync_stop
--   were defined in the protocol but never registered as model commands.
-- =====================================================

-- =====================================================
-- C-3: Ensure PV field mapping matches protocol (7 fields)
-- =====================================================
-- Protocol definition (heartbeat v1):
--   pv[0] = pv1_voltage   (V)   wire_type=float32   min=0    max=150
--   pv[1] = pv1_current   (A)   wire_type=float32   min=0    max=30
--   pv[2] = pv1_power     (W)   wire_type=float32   min=0    max=6200
--   pv[3] = pv2_voltage   (V)   wire_type=float32   min=0    max=150
--   pv[4] = pv2_current   (A)   wire_type=float32   min=0    max=30
--   pv[5] = pv2_power     (W)   wire_type=float32   min=0    max=6200
--   pv[6] = mppt_state          wire_type=uint8     min=0    max=2
--
-- Migration 026 already corrected the mapping by deleting ALL protocol
-- fields and re-inserting with the correct 7 PV fields. This migration
-- performs the same DELETE+INSERT for the PV group only, making it
-- fully idempotent and safe regardless of whether 026 ran.
-- Using individual UPDATEs would risk UNIQUE constraint violations on
-- (protocol_version_id, group_code, field_key) when swapping field_key
-- values between indices.

-- Delete ALL existing PV fields for heartbeat v1, then re-insert the
-- correct 7 fields matching the protocol definition.
DELETE FROM device_protocol_fields
WHERE protocol_version_id = (
    SELECT id FROM device_protocol_versions
    WHERE protocol_code = 'heartbeat' AND version = 1
)
AND group_code = 'pv';

WITH protocol AS (
    SELECT id FROM device_protocol_versions
    WHERE protocol_code = 'heartbeat' AND version = 1
), mapping(field_index, field_key, wire_type, minimum, maximum) AS (VALUES
    (0, 'pv1_voltage', 'float32', 0,    150),
    (1, 'pv1_current', 'float32', 0,    30),
    (2, 'pv1_power',   'float32', 0,    6200),
    (3, 'pv2_voltage', 'float32', 0,    150),
    (4, 'pv2_current', 'float32', 0,    30),
    (5, 'pv2_power',   'float32', 0,    6200),
    (6, 'mppt_state',  'uint8',   0,    2)
))
INSERT INTO device_protocol_fields (
    protocol_version_id, group_code, field_index,
    field_key, wire_type, minimum, maximum
)
SELECT protocol.id, 'pv', m.field_index, m.field_key,
       m.wire_type, m.minimum, m.maximum
FROM protocol CROSS JOIN mapping m;

-- =====================================================
-- C-4: Register 4 missing commands
-- =====================================================
-- The following commands are defined in the protocol but were not
-- registered in device_model_commands:
--   set_soc_low         — set discharge SOC floor
--   set_soc_high        — set charge SOC ceiling
--   parallel_sync_start — start parallel sync
--   parallel_sync_stop  — stop parallel sync
--
-- parameter_schema follows the existing {"args":[...]} convention
-- used by all commands in migration 023.
-- display_name_key follows the commands.xxx convention.

WITH commands(command_code, display_name_key, parameter_schema, timeout_seconds, risk_level) AS (VALUES
    ('set_soc_low',         'commands.set_soc_low',
     '{"args":[{"key":"soc_low","type":"integer","min":0,"max":100,"unit":"%"}]}'::jsonb,
     30, 2),
    ('set_soc_high',        'commands.set_soc_high',
     '{"args":[{"key":"soc_high","type":"integer","min":0,"max":100,"unit":"%"}]}'::jsonb,
     30, 2),
    ('parallel_sync_start', 'commands.parallel_sync_start',
     '{"args":[]}'::jsonb,
     60, 3),
    ('parallel_sync_stop',  'commands.parallel_sync_stop',
     '{"args":[]}'::jsonb,
     60, 3)
)
INSERT INTO device_model_commands (
    model_id, command_code, display_name_key,
    parameter_schema, timeout_seconds, risk_level
)
SELECT dm.id, c.command_code, c.display_name_key,
       c.parameter_schema, c.timeout_seconds, c.risk_level
FROM device_models dm
CROSS JOIN commands c
WHERE dm.model_code = 'CS-I10-6k2'
ON CONFLICT (model_id, command_code) DO NOTHING;
