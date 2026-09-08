import { test, expect } from '@playwright/test'
import { gotoAuthed, openUserMenu, evidencePath } from './helpers'

/**
 * i18n: the side navigation must switch between Chinese and English labels
 * through the user menu language switcher. Session comes from the `setup`
 * project's storageState.
 */
test('语言切换：中文 → English 后导航文案变化并可切回', async ({ page }) => {
  await gotoAuthed(page, '/dashboard')

  // Default locale is zh-CN.
  // UX 改版后侧边栏按 4 个分组折叠，子项仅在所属分组展开后可见，先按需展开。
  const menu = page.locator('.ant-menu')
  const ensureGroupOpen = async (group: string, itemText: string) => {
    const item = menu.getByText(itemText, { exact: true })
    if (await item.isVisible().catch(() => false)) return
    // 分组标题可能是折叠子菜单或顶栏菜单项，页面级文本点击与 navigation.spec.ts 同策略
    await page.getByText(group, { exact: true }).first().click()
    await expect(item).toBeVisible({ timeout: 5_000 })
  }
  await ensureGroupOpen('资产管理', '设备管理')
  await ensureGroupOpen('设备运维', 'OTA升级')
  await expect(menu.getByText('设备管理', { exact: true })).toBeVisible()
  await expect(menu.getByText('OTA升级', { exact: true })).toBeVisible()

  // Switch to English via the user menu.
  await openUserMenu(page)
  await page.getByText('English', { exact: true }).click()
  await expect(menu.getByText('Devices', { exact: true })).toBeVisible({ timeout: 15_000 })
  await expect(menu.getByText('OTA Upgrade', { exact: true })).toBeVisible()
  await page.screenshot({ path: evidencePath('e2e-lang-en.png'), fullPage: true })

  // Switch back to Chinese.
  await openUserMenu(page)
  await page.getByText('中文', { exact: true }).click()
  await expect(menu.getByText('设备管理', { exact: true })).toBeVisible({ timeout: 15_000 })
  await page.screenshot({ path: evidencePath('e2e-lang-zh.png'), fullPage: true })
})
