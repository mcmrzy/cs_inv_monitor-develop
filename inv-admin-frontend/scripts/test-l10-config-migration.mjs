// Run against an isolated local PostgreSQL on port 25467. All fixture tables
// are TEMP and all changes are rolled back, including on assertion failure.
import assert from 'node:assert/strict'
import console from 'node:console'
import { readFile } from 'node:fs/promises'
import { URL } from 'node:url'
import { Client } from 'pg'

const migrationDir = new URL('../../database/migrations/', import.meta.url)
const oldSql = await readFile(new URL('096_add_csl10_6k2_v21.up.sql', migrationDir), 'utf8')
const seed = oldSql.match(/INSERT INTO device_config_schema\([\s\S]+?;/)?.[0]
assert.ok(seed, 'migration 096 config seed must exist')
const client = new Client({ host: '127.0.0.1', port: 25467, user: 'postgres', database: 'postgres' })
await client.connect()
try {
  await client.query('BEGIN')
  await client.query(`CREATE TEMP TABLE device_config_schema (
    param_key text PRIMARY KEY, group_code text, sub_group text, control_type text,
    scale numeric, unit text, min numeric, max numeric, enum_map jsonb, step numeric,
    confirmation_mode text, display_name_key text, sort_order integer, visibility jsonb, validation jsonb
  ); CREATE TEMP TABLE device_models(id integer PRIMARY KEY, model_code text);
  CREATE TEMP TABLE device_model_commands(model_id integer, command_code text, param_schema jsonb);
  INSERT INTO device_models VALUES (1,'CS-L10-6K2'),(2,'OTHER-MODEL')`)
  await client.query(seed)
  await client.query(`INSERT INTO device_model_commands
    SELECT m.id,s.param_key,jsonb_build_object('args',jsonb_build_array(
      jsonb_build_object('key','value','type','integer','min',0,'max',2,'enum',jsonb_build_array(0,1,2))))
    FROM device_models m CROSS JOIN device_config_schema s
    WHERE s.param_key IN ('set_output_priority','set_battery_type','set_ac_volt_range','set_charge_priority','set_ac_output_mode');
    INSERT INTO device_model_commands VALUES (1,'set_max_charge_current',
      '{"args":[{"key":"value","type":"number","min":0,"max":60}]}');
    CREATE TEMP TABLE schema_before AS SELECT * FROM device_config_schema;
    CREATE TEMP TABLE commands_before AS SELECT * FROM device_model_commands;`)

  const readSchema = async () => new Map((await client.query('SELECT * FROM device_config_schema')).rows.map(r => [r.param_key, r]))
  const old = await readSchema()
  assert.equal(old.get('set_battery_type').enum_map['1'], 'NCM', 'reproduce old incorrect AGM label')
  assert.equal(old.get('set_max_charge_current').max, '60', 'reproduce rejected 140A report')
  assert.equal(old.get('set_gen_start_voltage').validation.gte, 'set_gen_stop_voltage')

  await client.query(await readFile(new URL('134_l10_config_wire_contract.up.sql', migrationDir), 'utf8'))
  const schema = await readSchema()
  assert.deepEqual(schema.get('set_output_priority').enum_map, { 1: 'solar_first', 2: 'utility_first', 3: 'solar_battery_utility', 4: 'solar_utility_battery' })
  assert.deepEqual(schema.get('set_battery_type').enum_map, { 1: 'agm', 2: 'flooded', 3: 'lithium', 4: 'user_lead_acid', 5: 'user_lithium' })
  assert.deepEqual(schema.get('set_charge_priority').enum_map, { 1: 'solar_first', 2: 'solar_utility', 3: 'solar_only' })
  assert.deepEqual(schema.get('set_ac_volt_range').enum_map, { 1: 'appliance', 2: 'ups', 3: 'generator' })
  assert.deepEqual(schema.get('set_ac_output_mode').enum_map, { 1: 'ac_single_phase', 2: 'ac_parallel', 3: 'ac_three_phase_l1', 4: 'ac_three_phase_l2', 5: 'ac_three_phase_l3' })
  assert.equal(schema.get('set_max_charge_current').max, '140')
  assert.equal(schema.get('set_gen_start_voltage').validation.lte, 'set_gen_stop_voltage')
  assert.equal(schema.get('set_gen_stop_voltage').validation.gte, 'set_gen_start_voltage')
  assert.equal(schema.get('set_soc_back_utl').validation.lte, 'set_soc_back_bat')
  assert.equal(schema.get('set_soc_back_gen').validation.lte, 'set_soc_close_gen')
  assert.deepEqual(schema.get('set_equalize_enable').visibility.in, [2, 4])
  assert.equal(schema.get('set_equalize_enable').visibility.eq, 2, 'legacy clients retain their safe filter')
  const commands = (await client.query('SELECT * FROM device_model_commands')).rows
  assert.deepEqual(commands.find(c => c.model_id === 1 && c.command_code === 'set_battery_type').param_schema.args[0].enum, [1, 2, 3, 4, 5])
  assert.deepEqual(commands.find(c => c.model_id === 2 && c.command_code === 'set_battery_type').param_schema.args[0].enum, [0, 1, 2])
  assert.equal(commands.find(c => c.command_code === 'set_max_charge_current').param_schema.args[0].max, 140)

  const workflow = await readFile(new URL('../../.github/workflows/cd.yml', import.meta.url), 'utf8')
  const gate = workflow.match(/<<'L10_CONFIG_WIRE_SQL'\r?\n([\s\S]*?)\r?\n\s*L10_CONFIG_WIRE_SQL/)?.[1]
  assert.ok(gate, 'CD must verify the actual production migration')
  await client.query('CREATE TEMP TABLE schema_migrations(version integer); SAVEPOINT migration_gate')
  await assert.rejects(client.query(gate), /migration 134 was not applied/)
  await client.query('ROLLBACK TO SAVEPOINT migration_gate; INSERT INTO schema_migrations VALUES(134)')
  await client.query(gate)

  await client.query(await readFile(new URL('134_l10_config_wire_contract.down.sql', migrationDir), 'utf8'))
  const differences = await client.query(`SELECT * FROM (
    (SELECT * FROM device_config_schema EXCEPT SELECT * FROM schema_before)
    UNION ALL (SELECT * FROM schema_before EXCEPT SELECT * FROM device_config_schema)) diff`)
  assert.equal(differences.rowCount, 0, 'down restores the original config schema')
  const commandDiff = await client.query(`SELECT * FROM (
    (SELECT * FROM device_model_commands EXCEPT SELECT * FROM commands_before)
    UNION ALL (SELECT * FROM commands_before EXCEPT SELECT * FROM device_model_commands)) diff`)
  assert.equal(commandDiff.rowCount, 0, 'down restores command validation')
  console.log('PASS: actual migration 096 fixture -> 134 up, enums/ranges/constraints/model isolation -> 134 down')
} finally {
  await client.query('ROLLBACK')
  await client.end()
}
