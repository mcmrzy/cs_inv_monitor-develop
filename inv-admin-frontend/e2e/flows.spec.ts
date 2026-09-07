import { test, expect } from '@playwright/test'
import { gotoAuthed, login, loadAccount, openUserMenu } from './helpers'

/**
 * 跨页交互流：搜索、进详情、Tab 切换、弹窗开关、登出重登等。
 * 每个用例从 storageState 登录态开始，互不依赖执行顺序。
 */
const acc = loadAccount()

/** 布局内容区：用于区分「页面标题」与侧边栏菜单中的同名文案。 */
const content = (page: import('@playwright/test').Page) => page.locator('.ant-pro-layout-content')

test.describe('设备列表交互', () => {
  test('搜索 E2E-SN-001 命中绑定设备', async ({ page }) => {
    await gotoAuthed(page, '/devices')
    const search = page.getByPlaceholder('搜索序列号、型号...')
    await search.fill(acc.devices[0])
    await page.locator('.ant-input-search-button').click()
    const row = page.locator('.ant-table-row', { hasText: acc.devices[0] }).first()
    await expect(row).toBeVisible({ timeout: 20_000 })
  })

  test('搜索不存在的 SN 显示空态', async ({ page }) => {
    await gotoAuthed(page, '/devices')
    const search = page.getByPlaceholder('搜索序列号、型号...')
    await search.fill('NO-SUCH-SN-999')
    await page.locator('.ant-input-search-button').click()
    await expect(page.locator('.ant-empty').first()).toBeVisible({ timeout: 20_000 })
  })

  test('搜索结果进入详情并返回列表', async ({ page }) => {
    await gotoAuthed(page, '/devices')
    const search = page.getByPlaceholder('搜索序列号、型号...')
    await search.fill(acc.devices[0])
    await page.locator('.ant-input-search-button').click()
    const row = page.locator('.ant-table-row', { hasText: acc.devices[0] }).first()
    await expect(row).toBeVisible({ timeout: 20_000 })
    await row.locator('a').first().click()
    await expect(page).toHaveURL(new RegExp(`/devices/${acc.devices[0]}/detail$`), { timeout: 10_000 })
    await page.getByRole('button', { name: /返回|Back/i }).click()
    await expect(page).toHaveURL(/\/devices/, { timeout: 10_000 })
    await expect(search).toBeVisible()
  })

  test('两台绑定设备都在列表中', async ({ page }) => {
    await gotoAuthed(page, '/devices')
    await expect(page.locator('.ant-table-row', { hasText: acc.devices[0] }).first()).toBeVisible({ timeout: 20_000 })
    await expect(page.locator('.ant-table-row', { hasText: acc.devices[1] }).first()).toBeVisible()
  })

  test('绑定设备弹窗可打开并关闭', async ({ page }) => {
    await gotoAuthed(page, '/devices')
    await page.getByRole('button', { name: '绑定设备' }).click()
    const modal = page.locator('.ant-modal-content', { hasText: '绑定设备到我的账户' })
    await expect(modal).toBeVisible({ timeout: 15_000 })
    await modal.getByRole('button', { name: /取 消|取消/ }).click()
    await expect(modal).toBeHidden({ timeout: 10_000 })
  })

  test('在线状态筛选选「全部」后设备仍在列表', async ({ page }) => {
    await gotoAuthed(page, '/devices')
    await page.locator('.ant-select', { hasText: '在线状态' }).first().click()
    await page.locator('.ant-select-item-option', { hasText: '全部' }).first().click()
    await expect(page.locator('.ant-table-row', { hasText: acc.devices[0] }).first()).toBeVisible({ timeout: 20_000 })
    await expect(page.locator('.ant-table')).toBeVisible()
  })
})

test.describe('设备详情交互', () => {
  test('Tab 切换：能源中心 → 储能 → 设备信息', async ({ page }) => {
    await gotoAuthed(page, `/devices/${acc.devices[0]}/detail`)
    await expect(page.locator('.ant-tabs-tab-active', { hasText: '能源中心' })).toBeVisible({ timeout: 15_000 })
    await page.locator('.ant-tabs-tab', { hasText: '储能' }).click()
    await expect(page.locator('.ant-tabs-tab-active', { hasText: '储能' })).toBeVisible()
    await page.locator('.ant-tabs-tab', { hasText: '设备信息' }).click()
    await expect(page.locator('.ant-tabs-tab-active', { hasText: '设备信息' })).toBeVisible()
    await expect(page.locator('.ant-tabs-tabpane-active')).toBeVisible()
  })
})

test.describe('告警中心交互', () => {
  test('Tab 切换到「告警」后保留状态/级别筛选', async ({ page }) => {
    await gotoAuthed(page, '/alerts')
    await page.locator('.ant-tabs-tab', { hasText: '告警' }).click()
    await expect(page.locator('.ant-tabs-tab-active', { hasText: '告警' })).toBeVisible()
    await expect(page.locator('.ant-select', { hasText: '级别' }).first()).toBeVisible({ timeout: 15_000 })
    await expect(page.locator('.ant-table').first()).toBeVisible()
  })

  test('Tab 切换到「通知」出现通知类型筛选', async ({ page }) => {
    await gotoAuthed(page, '/alerts')
    await page.locator('.ant-tabs-tab', { hasText: '通知' }).click()
    await expect(page.locator('.ant-tabs-tab-active', { hasText: '通知' })).toBeVisible()
    await expect(page.locator('.ant-select', { hasText: '通知类型' }).first()).toBeVisible({ timeout: 15_000 })
  })
})

test.describe('OTA 升级交互', () => {
  test('固件库 Tab 显示上传固件入口', async ({ page }) => {
    await gotoAuthed(page, '/ota')
    await page.locator('.ant-tabs-tab', { hasText: '固件库' }).click()
    await expect(page.locator('.ant-tabs-tab-active', { hasText: '固件库' })).toBeVisible()
    await expect(page.getByRole('button', { name: '上传固件' })).toBeVisible({ timeout: 15_000 })
  })

  test('App版本管理 Tab 显示发布新版本入口', async ({ page }) => {
    await gotoAuthed(page, '/ota')
    await page.locator('.ant-tabs-tab', { hasText: 'App版本管理' }).click()
    await expect(page.locator('.ant-tabs-tab-active', { hasText: 'App版本管理' })).toBeVisible()
    await expect(page.getByRole('button', { name: '发布新版本' })).toBeVisible({ timeout: 15_000 })
  })

  test('创建升级任务向导弹窗可打开并关闭', async ({ page }) => {
    await gotoAuthed(page, '/ota')
    await page.getByRole('button', { name: '创建升级任务' }).click()
    const modal = page.locator('.ant-modal-content', { hasText: '创建升级任务' })
    await expect(modal).toBeVisible({ timeout: 15_000 })
    await expect(modal.locator('.ant-steps')).toBeVisible()
    await modal.getByRole('button', { name: /取 消|取消/ }).click()
    await expect(modal).toBeHidden({ timeout: 10_000 })
  })
})

test.describe('列表空态', () => {
  test('电站管理空态显示暂无数据', async ({ page }) => {
    await gotoAuthed(page, '/stations')
    await expect(page.getByText('电站管理', { exact: true })).toBeVisible()
    await expect(page.locator('.ant-empty', { hasText: '暂无数据' })).toBeVisible({ timeout: 20_000 })
  })

  test('工单管理空态：暂无数据 + 创建工单按钮', async ({ page }) => {
    await gotoAuthed(page, '/work-orders')
    await expect(content(page).getByText('工单管理', { exact: true })).toBeVisible()
    await expect(page.locator('.ant-empty', { hasText: '暂无数据' })).toBeVisible({ timeout: 20_000 })
    await expect(page.getByRole('button', { name: '创建工单' })).toBeVisible()
  })

  test('电站监控搜索不存在的电站显示空态', async ({ page }) => {
    await gotoAuthed(page, '/monitoring')
    const search = page.getByPlaceholder('搜索电站名称或地址')
    await expect(search).toBeVisible()
    await search.fill('ZZZ-不存在电站')
    await expect(page.locator('.ant-empty').first()).toBeVisible({ timeout: 15_000 })
  })
})

test.describe('认证与全局流', () => {
  test('登出后可用同一账号重新登录', async ({ page }) => {
    await gotoAuthed(page, '/dashboard')
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
    await openUserMenu(page)
    await page.getByText(/退出登录|Logout/).click()
    await expect(page).toHaveURL(/\/login/, { timeout: 15_000 })
    await login(page, acc)
    await expect(page).toHaveURL(/\/dashboard/, { timeout: 20_000 })
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
  })

  test('无权限页「返回首页」按钮跳转仪表盘', async ({ page }) => {
    await gotoAuthed(page, '/unauthorized')
    await page.getByRole('button', { name: /返回首页|Back to Home/i }).click()
    await expect(page).toHaveURL(/\/dashboard/, { timeout: 10_000 })
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
  })
})

test.describe('仪表盘交互', () => {
  test('发电趋势「昨天/今日」快捷按钮可切换', async ({ page }) => {
    await gotoAuthed(page, '/dashboard')
    const todayBtn = page.getByRole('button', { name: /今\s*日/ }).first()
    const yesterdayBtn = page.getByRole('button', { name: /昨\s*天/ }).first()
    await expect(todayBtn).toBeVisible()
    await expect(yesterdayBtn).toBeVisible()
    await yesterdayBtn.click()
    await expect(page).toHaveURL(/\/dashboard/)
    await todayBtn.click()
    await expect(page).toHaveURL(/\/dashboard/)
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
  })
})
