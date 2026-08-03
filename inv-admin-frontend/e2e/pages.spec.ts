import { test, expect } from '@playwright/test'
import { injectAuthStorage, gotoAuthed, evidencePath, loadAccount } from './helpers'

/**
 * Core page smoke tests (already authenticated via injected session):
 * dashboard, device list → device detail navigation, alerts, OTA,
 * stations and monitoring.
 */
const acc = loadAccount()

test.beforeEach(async ({ page }) => {
  await injectAuthStorage(page)
})

test('仪表盘加载', async ({ page }) => {
  await gotoAuthed(page, '/dashboard')
  await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
  await page.screenshot({ path: evidencePath('e2e-page-dashboard.png'), fullPage: true })
})

test('设备列表展示绑定设备并可进入详情页', async ({ page }) => {
  await gotoAuthed(page, '/devices')
  const row = page
    .locator('.ant-table-row', { hasText: acc.devices[0] })
    .first()
  await expect(row).toBeVisible({ timeout: 20_000 })
  await page.screenshot({ path: evidencePath('e2e-page-devices.png'), fullPage: true })
  // S/N column is an <a> that opens the device detail drawer (not a route change)
  await row.locator('a').first().click()
  const drawer = page.locator('.ant-drawer-open')
  await expect(drawer).toBeVisible({ timeout: 15_000 })
  await expect(drawer).toContainText(acc.devices[0])
  await expect(page).toHaveURL(/\/devices$/, { timeout: 10_000 })
  await page.screenshot({ path: evidencePath('e2e-page-device-detail.png'), fullPage: true })
})

test('告警中心加载', async ({ page }) => {
  await gotoAuthed(page, '/alerts')
  await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
  await page.screenshot({ path: evidencePath('e2e-page-alerts.png'), fullPage: true })
})

test('OTA 升级页加载', async ({ page }) => {
  await gotoAuthed(page, '/ota')
  await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
  await page.screenshot({ path: evidencePath('e2e-page-ota.png'), fullPage: true })
})

test('电站管理加载', async ({ page }) => {
  await gotoAuthed(page, '/stations')
  await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
  await page.screenshot({ path: evidencePath('e2e-page-stations.png'), fullPage: true })
})

test('电站监控加载', async ({ page }) => {
  await gotoAuthed(page, '/monitoring')
  await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
  await page.screenshot({ path: evidencePath('e2e-page-monitoring.png'), fullPage: true })
})
