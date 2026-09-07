import path from 'node:path'
import { defineConfig } from '@playwright/test'

// storageState 由 setup 项目写入仓库根 e2e_evidence/（与 global-setup 的账号
// 文件同目录，见 e2e/helpers.ts 的 STORAGE_STATE）。Playwright 以
// inv-admin-frontend 为 cwd 运行，故从 cwd 向上一级解析。
const STORAGE_STATE_PATH = path.resolve(process.cwd(), '..', 'e2e_evidence', 'auth-state.json')

/**
 * Playwright E2E configuration for the admin frontend.
 *
 * - Runs against the isolated test stack (deploy/docker-compose.test.yml):
 *   vite dev server on :5173 proxies /api to the test gateway :18888.
 * - Uses the system-installed Microsoft Edge channel locally (no browser
 *   download); CI sets PLAYWRIGHT_CHANNEL=chromium and installs it via
 *   `npx playwright install --with-deps chromium`.
 * - Evidence (reports, screenshots, traces) lands in ../e2e_evidence/.
 * - The `setup` project logs in once and persists a storageState; the browser
 *   project depends on it, so specs are order-independent. CI retries
 *   transient failures twice, locally zero to keep feedback honest.
 */
export default defineConfig({
  testDir: './e2e',
  globalSetup: './e2e/global-setup.ts',
  timeout: 90_000,
  expect: { timeout: 20_000 },
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 2 : 0,
  reporter: [
    ['list'],
    ['html', { open: 'never', outputFolder: '../e2e_evidence/playwright-report' }],
    ['json', { outputFile: '../e2e_evidence/playwright-results.json' }],
  ],
  use: {
    baseURL: 'http://localhost:5173',
    channel: process.env.PLAYWRIGHT_CHANNEL || 'msedge',
    headless: true,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
    locale: 'zh-CN',
  },
  projects: [
    {
      name: 'setup',
      testMatch: /auth\.setup\.ts/,
    },
    {
      name: 'chromium',
      testIgnore: [/auth\.setup\.ts/, /visual\.spec\.ts/],
      use: { storageState: STORAGE_STATE_PATH },
      dependencies: ['setup'],
    },
    {
      // 视觉回归项目：仅在本地生成/校验基线（截图含平台字体渲染，跨平台必炸）。
      // CI 只跑 setup+chromium 功能项目；Linux 基线种子待专门的 CI 任务补齐。
      name: 'visual',
      testMatch: /visual\.spec\.ts/,
      use: {
        storageState: STORAGE_STATE_PATH,
        viewport: { width: 1440, height: 900 },
      },
      dependencies: ['setup'],
    },
  ],
  outputDir: '../e2e_evidence/playwright-output',
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:5173',
    reuseExistingServer: false,
    timeout: 120_000,
    env: {
      VITE_PROXY_TARGET: 'http://localhost:18888',
    },
  },
})
