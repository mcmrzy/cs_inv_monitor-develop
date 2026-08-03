import { test, expect } from '@playwright/test'
import {
  loadAccount,
  login,
  loginAccountInput,
  loginPasswordInput,
  loginSubmitButton,
  openUserMenu,
  saveAuthStorage,
  injectAuthStorage,
  evidencePath,
} from './helpers'

/**
 * Authentication flows:
 * - unauthenticated access to a protected route → redirected to /login
 * - valid credentials → /dashboard (+ persisted session for later specs)
 * - logout from the user menu → back to /login
 * - wrong password → inline error alert, stays on /login
 *
 * NOTE: the wrong-password case is intentionally the LAST test so that a
 * possible 4032 (slider captcha) trigger cannot poison the successful logins.
 */
const acc = loadAccount()

test('未登录访问受保护路由重定向到 /login', async ({ page }) => {
  await page.goto('/devices')
  await expect(page).toHaveURL(/\/login/, { timeout: 15_000 })
  await page.screenshot({ path: evidencePath('e2e-redirect-login.png') })
})

test('有效凭据登录成功进入 /dashboard', async ({ page }) => {
  await login(page, acc)
  await expect(page).toHaveURL(/\/dashboard/, { timeout: 20_000 })
  await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
  await page.screenshot({ path: evidencePath('e2e-login-success.png'), fullPage: true })
  // Persist the session so subsequent specs (pages/lang) reuse it.
  await saveAuthStorage(page)
})

test('登出后回到 /login', async ({ page }) => {
  await injectAuthStorage(page)
  await page.goto('/dashboard')
  await expect(page).not.toHaveURL(/\/login/, { timeout: 20_000 })
  await openUserMenu(page)
  await page.getByText(/退出登录|Logout/).click()
  await expect(page).toHaveURL(/\/login/, { timeout: 15_000 })
  await page.screenshot({ path: evidencePath('e2e-logout.png') })
})

test('错误密码登录显示错误提示且停留在 /login', async ({ page }) => {
  await page.goto('/login')
  await loginAccountInput(page).fill(acc.account)
  await loginPasswordInput(page).fill('Wrong-Pass-2026!')
  await loginSubmitButton(page).click()
  await expect(async () => {
    // If the 4032 slider-captcha modal pops up, dismiss it first.
    const modal = page.locator('.ant-modal-content', {
      hasText: /安全验证|Security Verification/,
    })
    if (await modal.isVisible().catch(() => false)) {
      await page.keyboard.press('Escape')
      await expect(modal).toBeHidden()
    }
    await expect(page.locator('.ant-alert-error')).toBeVisible()
  }).toPass({ timeout: 20_000 })
  await expect(page).toHaveURL(/\/login/)
  await page.screenshot({ path: evidencePath('e2e-login-failed.png') })
})
