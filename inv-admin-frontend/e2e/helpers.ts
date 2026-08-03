import { readFileSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { expect, type Page } from '@playwright/test'

/** Absolute path inside ../e2e_evidence (repo root evidence dir). */
export function evidencePath(name: string): string {
  return path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'e2e_evidence', name)
}

const AUTH_STORAGE_FILE = 'auth-storage.json'

/**
 * Persists the zustand `auth-storage` localStorage payload so later tests can
 * restore the session via injectAuthStorage() instead of logging in again.
 */
export async function saveAuthStorage(page: Page): Promise<void> {
  const raw = await page.evaluate(() => localStorage.getItem('auth-storage'))
  if (!raw) throw new Error('auth-storage not found in localStorage')
  writeFileSync(evidencePath(AUTH_STORAGE_FILE), raw, 'utf-8')
}

/** Injects the previously saved session into the page before any navigation. */
export async function injectAuthStorage(page: Page): Promise<void> {
  const raw = readFileSync(evidencePath(AUTH_STORAGE_FILE), 'utf-8')
  await page.addInitScript((s: string) => {
    localStorage.setItem('auth-storage', s)
  }, raw)
}

export interface E2EAccount {
  account: string
  phone: string
  email: string
  password: string
  devices: string[]
}

export function loadAccount(): E2EAccount {
  const p = path.resolve(
    path.dirname(fileURLToPath(import.meta.url)),
    '..',
    '..',
    'e2e_evidence',
    'e2e-account.json',
  )
  return JSON.parse(readFileSync(p, 'utf-8')) as E2EAccount
}

/** Locators for the login form (works in both zh and en). */
export const loginAccountInput = page => page.getByPlaceholder(/手机号 \/ 邮箱|Phone \/ Email/)
export const loginPasswordInput = page => page.getByPlaceholder(/密码|Password/)
export const loginSubmitButton = page => page.locator('button[type="submit"]')

/** Fills the login form and submits; waits until the app redirects away from /login. */
export async function login(page: Page, account: E2EAccount): Promise<void> {
  await page.goto('/login')
  await loginAccountInput(page).fill(account.account)
  await loginPasswordInput(page).fill(account.password)
  await loginSubmitButton(page).click()
  await expect(page).not.toHaveURL(/\/login/, { timeout: 30_000 })
}

/** Opens the top-right user dropdown menu. */
export async function openUserMenu(page: Page): Promise<void> {
  // ProLayout renders the avatar in the top-right corner; it is the only
  // visible Avatar inside the layout header.
  await page.locator('.ant-pro-global-header .ant-avatar').first().click()
}

/** Navigates to the given path already authenticated. */
export async function gotoAuthed(page: Page, url: string): Promise<void> {
  await page.goto(url)
  await expect(page).not.toHaveURL(/\/login/, { timeout: 20_000 })
}
