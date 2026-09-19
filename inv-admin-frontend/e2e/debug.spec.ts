import { test, expect } from '@playwright/test'
import { gotoAuthed, evidencePath, loadAccount } from './helpers'

/**
 * 单设备调试模式（设备详情 → 调试 Tab）。
 * 仅验证入口与控制区渲染：不点击「开始」（测试账号设备不在线，
 * 后端会正确 409，但 e2e 只锁定 UI 存在性与可交互性）。
 */
const acc = loadAccount()

test('设备详情调试 Tab 渲染控制区与曲线区', async ({ page }) => {
  await gotoAuthed(page, '/devices')
  const row = page
    .locator('.ant-table-row', { hasText: acc.devices[0] })
    .first()
  await expect(row).toBeVisible({ timeout: 20_000 })
  await row.locator('a').first().click()
  await expect(page).toHaveURL(new RegExp(`/devices/${acc.devices[0]}/detail$`), { timeout: 10_000 })

  // 切到调试 Tab（中英文环境均可命中）
  const tab = page.locator('.ant-tabs-tab', { hasText: /调试|Debug/i }).first()
  await expect(tab).toBeVisible({ timeout: 15_000 })
  await tab.click()

  // 控制区：设备调试状态徽标（未开启/离线等）与开始按钮存在
  await expect(page.getByText(/未开启|Not started|离线|Offline/i).first()).toBeVisible({ timeout: 15_000 })
  await expect(
    page.getByRole('button', { name: /开启调试|开始|Start/i }).first()
  ).toBeVisible()
  // 曲线说明文案存在（MPPT 电流为 Buck 电流的测点提示）
  await expect(page.getByText(/Buck/i).first()).toBeVisible()

  await page.screenshot({ path: evidencePath('e2e-device-debug-tab.png'), fullPage: true })
})
