import { chromium } from '@playwright/test'
import { mkdir } from 'node:fs/promises'

const output = new URL('./design-previews/', import.meta.url).pathname.replace(/^\/([A-Z]:)/, '$1')
await mkdir(output, { recursive: true })
const browser = await chromium.launch({ headless: true })
const page = await browser.newPage()
const errors = []
page.on('pageerror', e => errors.push(e.message))
page.on('console', e => { if (e.type() === 'error') errors.push(e.text()) })
const checks = []

async function render(name, width, height, view, state = 'normal') {
  await page.setViewportSize({ width, height })
  await page.goto(`http://127.0.0.1:5177/bms-design.html?view=${view}&state=${state}`)
  await page.getByText('交互预览 · 模拟数据').waitFor()
  if (view !== 'web') await page.locator('.mobile-header').waitFor()
  if (view !== 'mobile' && state === 'normal') await page.locator('canvas').first().waitFor()
  await page.evaluate(() => document.fonts.ready)
  await page.waitForTimeout(600)
  const overflow = await page.evaluate(() => [...document.querySelectorAll('.mobile-main, .web-main, .preview-stage, body')]
    .filter(e => e.scrollWidth > e.clientWidth + 1).map(e => `${e.className || e.tagName}: ${e.scrollWidth}/${e.clientWidth}`))
  if (overflow.length) throw Error(`${name} overflow: ${overflow.join(', ')}`)
  await page.screenshot({ path: `${output}/${name}.png`, fullPage: true })
  checks.push(`${name}: no horizontal overflow`)
}

try {
  await render('desktop-compare', 1440, 1000, 'compare')
  const pixels = await page.locator('canvas').first().evaluate(canvas => {
    const ctx = canvas.getContext('2d')
    const bytes = ctx.getImageData(0, 0, canvas.width, canvas.height).data
    let colored = 0
    for (let i = 0; i < bytes.length; i += 4) if (bytes[i + 3] > 0 && Math.max(bytes[i], bytes[i + 1], bytes[i + 2]) - Math.min(bytes[i], bytes[i + 1], bytes[i + 2]) > 15) colored++
    return colored
  })
  if (pixels < 1000) throw Error(`Cell chart blank: ${pixels}`)
  checks.push(`cell chart: ${pixels} colored pixels`)
  await page.locator('.web-main').getByRole('button', { name: '单体 C05', exact: true }).click()
  await page.locator('.web-main .cell-selection').getByText('C05', { exact: true }).waitFor()
  if (!await page.locator('.web-main .cell-selection').getByText('3304 mV', { exact: true }).isVisible()) throw Error('Selected cell mismatch')
  await page.getByText('告警 / 保护', { exact: true }).click()
  await page.locator('.web-main .notice').getByText('单体过压保护', { exact: true }).waitFor()
  await page.locator('.web-main').getByRole('button', { name: '查看保护详情', exact: true }).click()
  await page.locator('.web-main').getByText('状态字与请求量', { exact: false }).click()
  await page.locator('.web-main').getByText('累计充电量 · 单位待确认', { exact: true }).waitFor()
  checks.push('alarm navigation and raw quantity disclosure: passed')
  await render('desktop-wide', 1920, 1080, 'web')
  await render('mobile-overview', 390, 844, 'mobile')
  await page.locator('.mobile-surface').getByRole('button', { name: '单体', exact: true }).click()
  await page.locator('canvas').waitFor()
  await page.getByRole('button', { name: '单体 C10', exact: true }).click()
  await page.locator('.cell-selection').getByText('3295 mV', { exact: true }).waitFor()
  await page.screenshot({ path: `${output}/mobile-cells.png`, fullPage: true })
  checks.push('mobile navigation and cell selection: passed')
  await page.getByText('告警 / 保护', { exact: true }).click()
  await page.screenshot({ path: `${output}/mobile-cells-alarm.png`, fullPage: true })
  await render('mobile-alarm', 390, 844, 'mobile', 'alarm')
  await render('mobile-expired', 390, 844, 'mobile', 'offline')
  if (await page.locator('.summary-band').innerText().then(t => /72\.6|52\.78|-8\.40/.test(t))) throw Error('Expired live metrics leaked')
  await page.locator('.mobile-surface').getByRole('button', { name: '诊断', exact: true }).click()
  await page.getByText('历史快照 · 非实时状态', { exact: true }).waitFor()
  await page.getByText('原始报文', { exact: false }).click()
  const payload = await page.locator('.raw-payload').innerText()
  if (payload.trim().split(/\s+/).length !== 100) throw Error('Incomplete raw bytes')
  await page.screenshot({ path: `${output}/mobile-diagnostics.png`, fullPage: true })
  checks.push('expired values masked and 100 historical raw bytes available: passed')
  await render('mobile-absent', 390, 844, 'mobile', 'absent')
  await render('mobile-narrow', 320, 720, 'mobile')
  await page.locator('.mobile-surface').getByRole('button', { name: '单体', exact: true }).click()
  await page.waitForTimeout(300)
  if (await page.locator('.mobile-main').evaluate(e => e.scrollWidth > e.clientWidth + 1)) throw Error('320 px cell view overflow')
  await page.screenshot({ path: `${output}/mobile-narrow-cells.png`, fullPage: true })
  await render('desktop-expired', 1440, 1000, 'web', 'offline')
  if (errors.length) throw Error(`Browser errors: ${errors.join('\n')}`)
  console.log(JSON.stringify({ checks, browserErrors: errors, screenshots: output }, null, 2))
} finally {
  await browser.close()
}
