import { test, expect } from '@playwright/test'
import { login, loadAccount, STORAGE_STATE } from './helpers'

/**
 * Playwright `setup` project: logs the E2E account in once and persists the
 * session as a storageState file. Browser projects declare a dependency on
 * this project and receive `use.storageState`, so no spec depends on another
 * spec having logged in first.
 */
test('认证准备：登录并保存 storageState', async ({ page }) => {
  await login(page, loadAccount())
  await expect(page).toHaveURL(/\/dashboard/, { timeout: 20_000 })
  await page.context().storageState({ path: STORAGE_STATE })
})
