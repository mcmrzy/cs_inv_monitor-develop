import { chromium, expect } from '@playwright/test'
import { mkdir, writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'

const output = fileURLToPath(new URL('./design-previews/production/', import.meta.url))
await mkdir(output, { recursive: true })
const browser = await chromium.launch({ headless: true })
const context = await browser.newContext({ locale: 'zh-CN', timezoneId: 'Asia/Shanghai' })
const page = await context.newPage()
const errors = []
const expectedErrors = []
const checks = []
let scenario = 'normal'
let failRefresh = false
let expiration = Date.now() + 210000

function snapshot() {
  const cells = Array.from({ length: 16 }, (_, i) => 3295 + i)
  if (scenario === 'alarm') { cells[4] = 3498; cells[15] = null }
  return {
    layout: 0, bms_online: 1, battery_count: 1, voltage: 52.78, current: -8.4,
    soc: 72.6, soh: 97.8, soc_raw: 726, soh_raw: 978,
    capacity_remain: 43.56, capacity_full: 60, capacity_design: 64,
    warning_flag: scenario === 'alarm' ? 1 : 0,
    protection_flag: scenario === 'alarm' ? 1 : 0,
    status_fault_flag: 0x0a00, balance_status: 0x18,
    cell_voltages: cells, cell_temperatures: [null, null, null, null], cycle_count: 128,
    max_cell_voltage: scenario === 'alarm' ? 3498 : 3310, min_cell_voltage: 3295,
    max_cell_temp: null, min_cell_temp: null, mos_temp: -5.5, pcb_temp: 0, env_temp: 26.4,
    battery_mode: 2, battery_status: 1, system_mode: 0,
    total_chg_capacity_raw: 4294967295, total_dsg_capacity_raw: 129430,
    chg_request_current_raw: 3000, chg_request_voltage_raw: -32768, charging_voltage: null,
    raw_bytes: Array.from({ length: 100 }, (_, i) => i), age_ms: 800,
    updated_at: new Date().toISOString(), reported_at: new Date().toISOString(),
    expires_at: scenario === 'unknown' ? undefined : new Date(scenario === 'expired' ? Date.now() - 1000 : expiration).toISOString(),
  }
}

page.on('pageerror', e => errors.push(e.message))
page.on('console', e => {
  if (e.type() !== 'error') return
  if (failRefresh && /503|Local simulated outage|realtime/.test(e.text())) expectedErrors.push(e.text())
  else errors.push(e.text())
})
await context.addInitScript(() => {
  localStorage.setItem('auth-storage', JSON.stringify({ state: {
    token: 'local-browser-test-not-a-real-token', refreshToken: null, permissions: [], isAuthenticated: true,
    user: { id: 'local-ui-check', nickname: '本地验证', avatar: '', phone: '', email: '', status: 1, isSystemAdmin: true, timezone: 'Asia/Shanghai' },
  }, version: 0 }))
  localStorage.setItem('locale-storage', JSON.stringify({ state: { lang: 'zh' }, version: 0 }))
})
await context.route('**/api/v1/**', async route => {
  const path = new URL(route.request().url()).pathname
  if (failRefresh && path.endsWith('/realtime')) return route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ code: 503, message: 'Local simulated outage' }) })
  let data = { items: [], total: 0, page: 1, page_size: 100 }
  if (path.endsWith('/realtime')) data = {
    device_sn: 'CMD08-LOCAL', online: scenario !== 'inverter-stale', data_time: new Date(scenario === 'inverter-stale' ? Date.now() - 1200000 : Date.now()).toISOString(),
    realtime: { ...(scenario === 'absent' ? {} : { bms_summary: snapshot() }),
      bat: { battery_voltage: 49, battery_soc: 22, charge_power: 0 }, sys: { working_status: 1 } },
  }
  else if (path.endsWith('/devices/by-sn/CMD08-LOCAL')) data = { device: { sn: 'CMD08-LOCAL', alias: 'BMS 本地验证', model: 'CS-INV', status: 1, last_online_at: new Date().toISOString() } }
  else if (path.endsWith('/alerts/stats')) data = { total: 0, unhandled: 0, handled: 0, critical: 0 }
  await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ code: 0, message: 'success', data }) })
})

async function open(state, width, height, name) {
  scenario = state; failRefresh = false; expiration = Date.now() + (state === 'runtime-expiry' ? 8000 : 210000)
  await page.setViewportSize({ width, height })
  await page.goto('http://127.0.0.1:5177/devices/CMD08-LOCAL/detail')
  await page.getByRole('tab', { name: '储能', exact: true }).click()
  if (state !== 'absent') await page.getByTestId('cmd08-bms').waitFor()
  await page.evaluate(() => document.fonts.ready)
  await page.waitForTimeout(500)
  const overflow = await page.evaluate(() => {
    const root = document.querySelector('[data-testid="cmd08-bms"]')
    const bad = []
    for (const e of [document.body, root].filter(Boolean)) if (e.scrollWidth > e.clientWidth + 1) bad.push(`${e.tagName}:${e.scrollWidth}/${e.clientWidth}`)
    return bad
  })
  if (overflow.length) throw Error(`${name}: overflow ${overflow}`)
  await page.screenshot({ path: `${output}/${name}.png`, fullPage: true })
  checks.push(`${name}: rendered without horizontal overflow`)
}

try {
  await open('normal', 1440, 1000, 'web-normal')
  const bms = page.getByTestId('cmd08-bms')
  await expect(bms).toContainText('52.78')
  await expect(bms).toContainText('-8.40')
  await expect(bms).not.toContainText('49.00')
  const contrast = await page.locator('.cmd08-label').first().evaluate(label => {
    const color = getComputedStyle(label).color.match(/\d+/g).slice(0, 3).map(Number)
    const luminance = color.map(c => c / 255).map(c => c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) ** 2.4)
      .reduce((sum, c, i) => sum + c * [.2126, .7152, .0722][i], 0)
    return 1.05 / (luminance + .05)
  })
  if (contrast < 4.5) throw Error(`Small Web label contrast too low: ${contrast}`)
  checks.push(`small Web label contrast: ${contrast.toFixed(2)}:1`)
  await bms.getByRole('button', { name: 'C05', exact: true }).click()
  await expect(page.getByTestId('cmd08-selected-cell')).toContainText('3299')
  const colored = await bms.locator('canvas').first().evaluate(canvas => {
    const p = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data
    let n = 0
    for (let i = 0; i < p.length; i += 4) if (p[i + 3] > 0 && Math.max(p[i], p[i + 1], p[i + 2]) - Math.min(p[i], p[i + 1], p[i + 2]) > 15) n++
    return n
  })
  if (colored < 1000) throw Error('Production chart is blank')
  checks.push(`production chart: ${colored} colored pixels and selected cell matches`)
  await open('alarm', 1440, 1000, 'web-alarm')
  await expect(page.getByTestId('cmd08-bms')).toContainText('3498')
  await expect(page.getByTestId('cmd08-bms')).toContainText('单体过压')
  await open('expired', 1440, 1000, 'web-expired')
  await expect(page.locator('.cmd08-summary')).not.toContainText('52.78')
  await expect(page.locator('.cmd08-analysis')).not.toContainText('3498')
  await open('unknown', 1440, 1000, 'web-unknown')
  await expect(page.locator('.cmd08-summary')).not.toContainText('52.78')
  await open('absent', 1440, 1000, 'web-absent')
  await expect(page.getByTestId('cmd08-bms')).toHaveAttribute('data-availability', 'absent')
  await expect(page.getByTestId('cmd08-bms')).toContainText('未接入 BMS')
  await open('normal', 1920, 1080, 'web-wide')
  await open('normal', 390, 844, 'web-mobile')
  await open('normal', 320, 720, 'web-narrow')
  await open('inverter-stale', 1440, 1000, 'web-independent-bms')
  await expect(page.locator('.cmd08-summary')).toContainText('52.78')
  checks.push('BMS availability independent from stale/offline inverter envelope: passed')
  await open('runtime-expiry', 1440, 1000, 'web-before-expiry')
  await expect(page.locator('.cmd08-summary')).toContainText('52.78')
  failRefresh = true
  await page.getByTestId('cmd08-bms').getByRole('button', { name: '刷新 BMS', exact: true }).click()
  await expect(page.getByTestId('cmd08-bms')).toHaveAttribute('data-availability', 'expired', { timeout: 15000 })
  await expect(page.locator('.cmd08-summary')).not.toContainText('52.78')
  await page.screenshot({ path: `${output}/web-expiry-on-fetch-failure.png`, fullPage: true })
  checks.push('snapshot automatically expires after refresh failure: passed')
  failRefresh = false
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto('http://127.0.0.1:5177/bms-component-review.html')
  await expect(page.locator('.cmd08-summary')).toContainText('52.78')
  await page.locator('.component-review-toolbar').getByText('告警', { exact: true }).click()
  await expect(page.getByTestId('cmd08-bms')).toContainText('单体过压')
  await page.locator('.component-review-toolbar').getByText('过期', { exact: true }).click()
  await expect(page.getByTestId('cmd08-bms')).toHaveAttribute('data-availability', 'expired')
  await page.locator('.component-review-toolbar').getByText('未接入', { exact: true }).click()
  await expect(page.getByTestId('cmd08-bms')).toHaveAttribute('data-availability', 'absent')
  await page.locator('.component-review-toolbar').getByText('正常', { exact: true }).click()
  await page.locator('.component-review-toolbar').getByText('English', { exact: true }).click()
  await expect(page.getByTestId('cmd08-bms')).not.toContainText('deviceDetail.summary.')
  await expect(page.locator('.cmd08-summary')).toContainText('52.78')
  await page.screenshot({ path: `${output}/component-review-en-mobile.png`, fullPage: true })
  checks.push('isolated production component review state/language controls: passed')
  if (errors.length) throw Error(`Browser errors: ${errors.join('\n')}`)
  const result = { checks, browserErrors: errors, expectedRefreshErrors: expectedErrors.length, screenshots: output }
  await writeFile(`${output}/result.json`, JSON.stringify(result, null, 2))
  console.log(JSON.stringify(result, null, 2))
} finally {
  await browser.close()
}
