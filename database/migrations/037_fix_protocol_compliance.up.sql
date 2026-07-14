-- =====================================================
-- Migration 037: Fix protocol compliance issues (C-3, C-4)
-- =====================================================

-- C-3: Ensure PV field mapping matches protocol (7 fields)
DELETE FROM device_protocol_fields
WHERE protocol_version_id = (
    SELECT id FROM device_protocol_versions
    WHERE protocol_code = 'heartbeat' AND version = 1
)
AND group_code = 'pv';

INSERT INTO device_protocol_fields (
    protocol_version_id, group_code, field_index,
    field_key, wire_type, minimum, maximum
)
SELECT p.id, 'pv', m.field_index, m.field_key,
       m.wire_type::varchar, m.minimum::numeric, m.maximum::numeric
FROM device_protocol_versions p
CROSS JOIN (
    VALUES
    (0::smallint, 'pv1_voltage'::varchar, 'float32'::varchar, 0::numeric, 150::numeric),
    (1::smallint, 'pv1_current'::varchar, 'float32'::varchar, 0::numeric, 30::numeric),
    (2::smallint, 'pv1_power'::varchar,   'float32'::varchar, 0::numeric, 6200::numeric),
    (3::smallint, 'pv2_voltage'::varchar, 'float32'::varchar, 0::numeric, 150::numeric),
    (4::smallint, 'pv2_current'::varchar, 'float32'::varchar, 0::numeric, 30::numeric),
    (5::smallint, 'pv2_power'::varchar,   'float32'::varchar, 0::numeric, 6200::numeric),
    (6::smallint, 'mppt_state'::varchar,  'uint8'::varchar,   0::numeric, 2::numeric)
) AS m(field_index, field_key, wire_type, minimum, maximum)
WHERE p.protocol_code = 'heartbeat' AND p.version = 1;

-- C-4: Register 4 missing commands
INSERT INTO device_model_commands (
    model_id, command_code, display_name_key,
    parameter_schema, timeout_seconds, risk_level
)
SELECT dm.id, c.command_code, c.display_name_key,
       c.parameter_schema, c.timeout_seconds, c.risk_level
FROM device_models dm
CROSS JOIN (
    VALUES
    ('set_soc_low'::varchar,         'commands.set_soc_low'::varchar,
     '{"args":[{"key":"soc_low","type":"integer","min":0,"max":100,"unit":"%"}]}'::jsonb,
     30::integer, 2::smallint),
    ('set_soc_high'::varchar,        'commands.set_soc_high'::varchar,
     '{"args":[{"key":"soc_high","type":"integer","min":0,"max":100,"unit":"%"}]}'::jsonb,
     30::integer, 2::smallint),
    ('parallel_sync_start'::varchar, 'commands.parallel_sync_start'::varchar,
     '{"args":[]}'::jsonb,
     60::integer, 3::smallint),
    ('parallel_sync_stop'::varchar,  'commands.parallel_sync_stop'::varchar,
     '{"args":[]}'::jsonb,
     60::integer, 3::smallint)
) AS c(command_code, display_name_key, parameter_schema, timeout_seconds, risk_level)
WHERE dm.model_code = 'CS-I10-6k2'
ON CONFLICT (model_id, command_code) DO NOTHING;
