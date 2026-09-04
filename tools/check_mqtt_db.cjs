#!/usr/bin/env node
/**
 * MQTT 端到端验证的数据库侧检查（阶段3）：
 * 读取 e2e_evidence/mqtt-e2e-result.json 中的 SN，查询
 * device_telemetry_3min / device_ingest_errors / device_latest_state / devices，
 * 输出 JSON 证据到 e2e_evidence/mqtt-e2e-db-check.json。
 */
const fs = require('node:fs')
const path = require('node:path')
const { Client } = require('D:/CS_APP_PROJECT/cs_inv_monitor-develop/cs_inv_monitor-develop/inv-admin-frontend/node_modules/pg')

const ROOT = path.resolve(__dirname, '..')
const RESULT = JSON.parse(fs.readFileSync(path.join(ROOT, 'e2e_evidence', 'mqtt-e2e-result.json'), 'utf-8'))
const SNS = RESULT.published.map(p => p.sn)

const DSN = process.env.E2E_PG_DSN || 'postgres://testuser:testpass@127.0.0.1:15432/inv_test'

async function main() {
  const client = new Client({ connectionString: DSN })
  await client.connect()

  const out = {
    checked_at: new Date().toISOString(),
    device_count: SNS.length,
    telemetry: {},
    ingest_errors: {},
    latest_state: {},
    registered_devices: {},
    alarms: {},
  }

  // 1) 遥测落库
  const tel = await client.query(
    `SELECT device_sn, COUNT(*) AS rows
       FROM device_telemetry_3min
      WHERE device_sn = ANY($1)
      GROUP BY device_sn ORDER BY device_sn`,
    [SNS],
  )
  for (const r of tel.rows) out.telemetry[r.device_sn] = Number(r.rows)

  // 2) 解析错误
  const err = await client.query(
    `SELECT device_sn, error_code, COUNT(*) AS rows
       FROM device_ingest_errors
      WHERE device_sn = ANY($1)
      GROUP BY device_sn, error_code ORDER BY device_sn`,
    [SNS],
  )
  for (const r of err.rows) out.ingest_errors[`${r.device_sn}(${r.error_code})`] = Number(r.rows)

  // 3) 最新状态
  const lst = await client.query(
    `SELECT device_sn, work_state, fault_code, ac_active_power, daily_pv_energy, event_time
       FROM device_latest_state
      WHERE device_sn = ANY($1)
      ORDER BY device_sn`,
    [SNS],
  )
  for (const r of lst.rows) out.latest_state[r.device_sn] = { ...r, event_time: String(r.event_time) }

  // 4) 设备注册情况（绑定 vs 未绑定）
  const reg = await client.query(`SELECT sn FROM devices WHERE sn = ANY($1)`, [SNS])
  for (const r of reg.rows) out.registered_devices[r.sn] = true

  // 5) 告警落库（alarm 消息产生后写入 device_alarm_events + device_alarm_snapshots + alarms 投影）
  const alarmSns = RESULT.alarm_devices || []
  if (alarmSns.length) {
    const alm = await client.query(
      `SELECT device_sn, COUNT(*) AS rows
         FROM device_alarm_events
        WHERE device_sn = ANY($1)
        GROUP BY device_sn ORDER BY device_sn`,
      [alarmSns],
    )
    for (const r of alm.rows) out.alarms[r.device_sn] = Number(r.rows)
    // 快照表与投影表计数
    for (const t of ['device_alarm_snapshots', 'alarms']) {
      const c = await client.query(
        `SELECT COUNT(*) AS rows FROM ${t} WHERE device_sn = ANY($1)`,
        [alarmSns],
      )
      out[`${t}_rows`] = Number(c.rows[0].rows)
    }
  }

  // 6) Redis 在线状态（device:heartbeat:{sn} / device:online_set）
  out.redis_online = {}
  try {
    const { createClient } = require('D:/CS_APP_PROJECT/cs_inv_monitor-develop/cs_inv_monitor-develop/inv-admin-frontend/node_modules/redis')
    const r = createClient({ url: 'redis://:testredispass@127.0.0.1:16379' })
    await r.connect()
    for (const sn of RESULT.bound_devices.slice(0, 2)) {
      out.redis_online[sn] = await r.exists(`device:heartbeat:${sn}`) > 0
    }
    out.redis_online.online_set_size = await r.sCard('device:online_set')
    await r.quit()
  } catch (e) {
    out.redis_online.error = e.message
  }

  await client.end()

  // 汇总统计
  const telCount = Object.values(out.telemetry).reduce((a, b) => a + b, 0)
  const errCount = Object.values(out.ingest_errors).reduce((a, b) => a + b, 0)
  out.summary = {
    telemetry_rows: telCount,
    ingest_errors: errCount,
    devices_with_telemetry: Object.keys(out.telemetry).length,
    devices_with_errors: Object.keys(out.ingest_errors).length,
    bound_devices_persisted: RESULT.bound_devices.filter(sn => out.telemetry[sn] > 0),
    bound_devices_missing: RESULT.bound_devices.filter(sn => !out.telemetry[sn]),
    alarm_rows: Object.values(out.alarms).reduce((a, b) => a + b, 0),
    alarm_devices: Object.keys(out.alarms),
  }

  const outFile = path.join(ROOT, 'e2e_evidence', 'mqtt-e2e-db-check.json')
  fs.writeFileSync(outFile, JSON.stringify(out, null, 2))
  console.log(JSON.stringify(out.summary, null, 2))
  console.log('evidence:', outFile)
}

main().catch(e => {
  console.error('DB check failed:', e.message)
  process.exit(1)
})
