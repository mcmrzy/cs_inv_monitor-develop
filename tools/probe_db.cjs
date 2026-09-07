#!/usr/bin/env node
/** 临时探针：查询指定 SN 的遥测/错误/状态/设备行。 */
const { Client } = require('D:/CS_APP_PROJECT/cs_inv_monitor-develop/cs_inv_monitor-develop/inv-admin-frontend/node_modules/pg')

const SN = process.argv[2] || 'E2E-SN-MSCIU07M4NH'

async function main() {
  const c = new Client({ connectionString: 'postgres://testuser:testpass@127.0.0.1:15432/inv_test' })
  await c.connect()
  const tel = await c.query('SELECT COUNT(*)::int n, MAX(event_time) et FROM device_telemetry_3min WHERE device_sn=$1', [SN])
  const err = await c.query('SELECT error_code, COUNT(*)::int n FROM device_ingest_errors WHERE device_sn=$1 GROUP BY error_code', [SN])
  const lst = await c.query('SELECT * FROM device_latest_state WHERE device_sn=$1', [SN])
  const dev = await c.query('SELECT sn, created_at FROM devices WHERE sn=$1', [SN])
  const redisSn = await c.query("SELECT COUNT(*)::int n FROM device_telemetry_3min WHERE device_sn LIKE 'E2EMQTT%'")
  console.log('telemetry:', JSON.stringify(tel.rows))
  console.log('ingest_errors:', JSON.stringify(err.rows))
  console.log('latest_state:', JSON.stringify(lst.rows))
  console.log('device:', JSON.stringify(dev.rows))
  console.log('e2emqtt_total:', JSON.stringify(redisSn.rows))
  await c.end()
}

main().catch(e => { console.error('ERR', e.message); process.exit(1) })
