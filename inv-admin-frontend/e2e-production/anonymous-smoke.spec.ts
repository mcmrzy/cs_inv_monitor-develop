import { expect, test } from '@playwright/test'

const firmwareUrl = process.env.PRODUCTION_FIRMWARE_URL
  || 'https://download.jiuxiaoyw.online/firmware/CS-L10-6K2_1.5.0_1788860033746007357.bin'

test('login page renders without browser errors', async ({ page }) => {
  const errors: string[] = []
  page.on('console', (message) => {
    if (message.type() === 'error') errors.push(message.text())
  })

  const response = await page.goto('/login', { waitUntil: 'networkidle' })

  expect(response?.status()).toBe(200)
  await expect(page.locator('input[type="password"]')).toBeVisible()
  expect(errors).toEqual([])
})

test('protected pages redirect anonymous visitors to login', async ({ page }) => {
  for (const path of ['/dashboard', '/devices']) {
    await page.goto(path)
    await expect(page).toHaveURL(/\/login$/, { timeout: 5000 })
    await expect(page.locator('input[type="password"]')).toBeVisible()
  }
})

test('public download page can query the latest app version anonymously', async ({ page }) => {
  const checkResponse = page.waitForResponse((response) => (
    response.url().includes('/api/v1/ota/app/check')
  ))

  const navigation = await page.goto('/download', { waitUntil: 'domcontentloaded' })
  const apiResponse = await checkResponse

  expect(navigation?.status()).toBe(200)
  expect(apiResponse.status()).toBe(200)
  await expect(page).toHaveURL(/\/download$/)
  await expect(page.locator('body')).not.toBeEmpty()
})

test('production cache policy distinguishes HTML, hashed assets, and fixed assets', async ({ request }) => {
  const html = await request.get('/')
  expect(html.status()).toBe(200)
  expect(html.headers()['cache-control']).toContain('no-cache')
  expect(html.headers()['strict-transport-security']).toContain('max-age=31536000')
  expect(html.headers()['x-content-type-options']).toBe('nosniff')

  const body = await html.text()
  const assetPath = body.match(/src="(\/assets\/[^"]+\.js)"/)?.[1]
  expect(assetPath).toBeTruthy()

  const hashedAsset = await request.get(assetPath!)
  expect(hashedAsset.status()).toBe(200)
  expect(hashedAsset.headers()['cache-control']).toContain('max-age=31536000')
  expect(hashedAsset.headers()['cache-control']).toContain('immutable')

  const fixedAsset = await request.get('/images/login/login-bg-1.jpg')
  expect(fixedAsset.status()).toBe(200)
  expect(fixedAsset.headers()['cache-control']).toContain('max-age=86400')
  expect(fixedAsset.headers()['cache-control']).toContain('must-revalidate')
})

test('firmware download is a direct HTTP success with a stable content length', async ({ request }) => {
  const response = await request.get(firmwareUrl)

  expect(response.status()).toBe(200)
  expect(response.headers().location).toBeUndefined()
  expect(Number(response.headers()['content-length'])).toBeGreaterThan(0)
})
