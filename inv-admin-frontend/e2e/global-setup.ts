import { createClient } from 'redis'
import pg from 'pg'
import { createHmac } from 'node:crypto'
import { mkdirSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

/**
 * Global setup for Playwright E2E runs.
 *
 * Provisions an E2E account against the isolated test stack:
 * 1. Pre-writes the email verification code into the test Redis (:16379).
 * 2. Registers the account through the test gateway (:18888) email-register.
 * 3. Promotes the user to system admin in the test database (:15432) so the
 *    full navigation (dashboard, OTA, stations, monitoring, …) is visible.
 * 4. Binds two devices so list/detail journeys have real rows.
 * 5. Persists credentials + device S/Ns to ../e2e_evidence/e2e-account.json.
 */

const E2E_API = process.env.E2E_API_BASE || 'http://localhost:18888'
const REDIS_URL = process.env.E2E_REDIS_URL || 'redis://:testredispass@127.0.0.1:16379'
const PG_DSN = process.env.E2E_PG_DSN || 'postgres://testuser:testpass@127.0.0.1:15432/inv_test'
const PRODUCT_SECRET = process.env.E2E_PRODUCT_SECRET || 'CS_INV_L10_2026_SECRET'
// E2E 专用测试栈账号密码（与生产无关），CI/本地可用 E2E_TEST_PASSWORD 覆盖
const TEST_PASSWORD = process.env.E2E_TEST_PASSWORD || 'E2e@2026Pass'

// computeDevicePIN derives the 6-digit nameplate PIN (leading zeros preserved):
// HMAC-SHA256(secret, sn) first 3 bytes mod 1000000 — must stay in sync with
// business-api internal/service computeDevicePIN.
function computeDevicePIN(secret: string, sn: string): string {
  const d = createHmac('sha256', secret).update(sn).digest()
  const pin = ((d[0] << 16) | (d[1] << 8) | d[2]) % 1000000
  return String(pin).padStart(6, '0')
}

const EVIDENCE_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'e2e_evidence')

async function registerUser(email: string, phone: string, password: string, nickname: string): Promise<string> {
  const redis = createClient({ url: REDIS_URL })
  await redis.connect()
  try {
    await redis.set(`email:${email}:register`, '123456', { EX: 300 })
  } finally {
    await redis.disconnect()
  }

  const payload = {
    email,
    phone,
    password,
    code: '123456',
    nickname,
  }
  const res = await fetch(`${E2E_API}/api/v1/auth/email-register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
  const body = (await res.json()) as { code?: number; message?: string; data?: unknown }
  if (body.code !== 0) {
    throw new Error(`E2E account registration failed: ${body.code} ${body.message}`)
  }

  // Login to obtain a bearer token.
  const loginRes = await fetch(`${E2E_API}/api/v1/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ account: phone, password }),
  })
  const loginBody = (await loginRes.json()) as {
    code?: number
    data?: { access_token?: string; token?: string }
  }
  const token = loginBody?.data?.access_token ?? loginBody?.data?.token
  if (!token) {
    throw new Error(`E2E login failed: ${JSON.stringify(loginBody)}`)
  }
  return token
}

async function promoteToSystemAdmin(phone: string): Promise<void> {
  const pool = new pg.Pool({ connectionString: PG_DSN })
  try {
    await pool.query('UPDATE users SET is_system_admin = true WHERE phone = $1', [phone])
  } finally {
    await pool.end()
  }
}

/**
 * 清空测试栈的业务数据表，保证视觉基线与列表断言不随历史运行漂移：
 * 测试库是一次性资源（CI 每次全新起栈），残留行只会来自同一台开发机上
 * 之前的手动/测试运行。TRUNCATE CASCADE 会连带清掉引用这些表的事实数据
 * （遥测/告警明细等）。必须在注册账号之前执行。
 */
async function resetTestData(): Promise<void> {
  const pool = new pg.Pool({ connectionString: PG_DSN })
  try {
    await pool.query(`
      TRUNCATE user_device_rel, devices, stations, alarms,
               device_upgrades, firmware_versions, upgrade_tasks
      RESTART IDENTITY CASCADE
    `)
  } finally {
    await pool.end()
  }
}

async function bindDevice(token: string, sn: string): Promise<void> {
  const res = await fetch(`${E2E_API}/api/v1/devices/bind`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ sn, station_id: 0, pin: computeDevicePIN(PRODUCT_SECRET, sn) }),
  })
  const body = (await res.json()) as { code?: number; message?: string }
  if (body.code !== 0) {
    throw new Error(`bind device ${sn} failed: ${body.code} ${body.message}`)
  }
}

export default async function globalSetup(): Promise<void> {
  await resetTestData()

  const suffix = `${Date.now().toString(36)}${Math.floor(Math.random() * 0xffff).toString(36)}`
  const phone = `170${String(Date.now() % 100000000).padStart(8, '0')}`
  const email = `e2e_${suffix}@test.com`
  const password = TEST_PASSWORD

  console.log(`[e2e-setup] registering E2E account ${phone} / ${email}`)
  const token = await registerUser(email, phone, password, 'e2e-admin')
  await promoteToSystemAdmin(phone)

  const devices = ['E2E-SN-001', 'E2E-SN-002']
  for (const sn of devices) {
    await bindDevice(token, sn)
  }

  mkdirSync(EVIDENCE_DIR, { recursive: true })
  const account = { account: phone, phone, email, password, devices }
  writeFileSync(path.join(EVIDENCE_DIR, 'e2e-account.json'), JSON.stringify(account, null, 2))
  console.log(`[e2e-setup] E2E account ready: ${JSON.stringify(account)}`)
}
