import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './e2e-production',
  outputDir: 'test-results/production',
  fullyParallel: false,
  forbidOnly: true,
  retries: 0,
  workers: 1,
  reporter: [['list']],
  use: {
    baseURL: process.env.PRODUCTION_BASE_URL || 'https://www.jiuxiaoyw.online',
    channel: process.env.PLAYWRIGHT_CHANNEL || 'chromium',
    headless: true,
    ignoreHTTPSErrors: false,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
    ...devices['Desktop Chrome'],
  },
})
