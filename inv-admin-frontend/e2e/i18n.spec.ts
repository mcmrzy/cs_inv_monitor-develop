import { test, expect, type Page } from '@playwright/test'
import { gotoAuthed, openUserMenu } from './helpers'

/**
 * 语言切换矩阵：覆盖代表页面，验证「中文 → English → 中文」后
 * 侧边栏/页面标题/关键控件的文案随之切换。
 * 每个用例独立完成一次往返切换；storageState 中保存的是登录时的
 * localStorage 快照（zh-CN），因此用例之间不互相依赖。
 */

/** 布局内容区：用于区分「页面标题」与侧边栏菜单中的同名文案。 */
const content = (page: Page) => page.locator('.ant-pro-layout-content')

async function switchLang(page: Page, to: 'en' | 'zh'): Promise<void> {
  const item = page.getByText(to === 'en' ? 'English' : '中文', { exact: true })
  // 慢循环下头像点击可能落在页面水合完成前，下拉菜单未弹出导致目标项
  // 永不出现（soak 战役 c63/c83 两次 90s 超时）。改为「不可见就重新点
  // 头像」的自愈重试，直到菜单项可点。
  await expect(async () => {
    if (!(await item.isVisible().catch(() => false))) {
      await openUserMenu(page)
    }
    await item.click({ timeout: 3_000 })
  }).toPass({ timeout: 30_000 })
}

test.describe('页面级语言切换', () => {
  test('仪表盘：统计卡片标题中英切换', async ({ page }) => {
    await gotoAuthed(page, '/dashboard')
    await expect(page.getByText('设备总数', { exact: true }).first()).toBeVisible()
    await expect(page.getByText('电站发电排行')).toBeVisible()

    await switchLang(page, 'en')
    await expect(page.getByText('Total Devices', { exact: true }).first()).toBeVisible({ timeout: 15_000 })
    await expect(page.getByText('Station Ranking')).toBeVisible()

    await switchLang(page, 'zh')
    await expect(page.getByText('设备总数', { exact: true }).first()).toBeVisible({ timeout: 15_000 })
  })

  test('设备列表：侧边栏菜单与搜索占位符切换', async ({ page }) => {
    await gotoAuthed(page, '/devices')
    const menu = page.locator('.ant-menu')
    await expect(menu.getByText('设备管理', { exact: true })).toBeVisible()
    await expect(page.getByPlaceholder('搜索序列号、型号...')).toBeVisible()

    await switchLang(page, 'en')
    await expect(menu.getByText('Devices', { exact: true })).toBeVisible({ timeout: 15_000 })
    await expect(page.getByPlaceholder('Search SN, model...')).toBeVisible()

    await switchLang(page, 'zh')
    await expect(menu.getByText('设备管理', { exact: true })).toBeVisible({ timeout: 15_000 })
  })

  test('OTA 升级：Tab 标签中英切换', async ({ page }) => {
    await gotoAuthed(page, '/ota')
    await expect(page.locator('.ant-tabs-tab', { hasText: '升级任务' })).toBeVisible()
    await expect(page.locator('.ant-tabs-tab', { hasText: '固件库' })).toBeVisible()

    await switchLang(page, 'en')
    await expect(page.locator('.ant-tabs-tab', { hasText: 'Upgrade Tasks' })).toBeVisible({ timeout: 15_000 })
    await expect(page.locator('.ant-tabs-tab', { hasText: 'Firmware Library' })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Create Upgrade Task' })).toBeVisible()

    await switchLang(page, 'zh')
    await expect(page.locator('.ant-tabs-tab', { hasText: '升级任务' })).toBeVisible({ timeout: 15_000 })
  })

  test('告警中心：Tab 标签中英切换', async ({ page }) => {
    await gotoAuthed(page, '/alerts')
    await expect(page.locator('.ant-tabs-tab', { hasText: '告警' })).toBeVisible()
    await expect(page.locator('.ant-tabs-tab', { hasText: '通知' })).toBeVisible()

    await switchLang(page, 'en')
    await expect(page.locator('.ant-tabs-tab', { hasText: 'Alarms' })).toBeVisible({ timeout: 15_000 })
    await expect(page.locator('.ant-tabs-tab', { hasText: 'Notifications' })).toBeVisible()

    await switchLang(page, 'zh')
    await expect(page.locator('.ant-tabs-tab', { hasText: '告警' })).toBeVisible({ timeout: 15_000 })
  })

  test('用户管理：页面标题中英切换', async ({ page }) => {
    await gotoAuthed(page, '/users')
    await expect(content(page).getByText('用户管理', { exact: true })).toBeVisible()

    await switchLang(page, 'en')
    await expect(content(page).getByText('User Management', { exact: true })).toBeVisible({ timeout: 15_000 })
    await expect(page.getByRole('button', { name: 'Add User' })).toBeVisible()

    await switchLang(page, 'zh')
    await expect(content(page).getByText('用户管理', { exact: true })).toBeVisible({ timeout: 15_000 })
  })

  test('电站管理：页面标题与按钮中英切换', async ({ page }) => {
    await gotoAuthed(page, '/stations')
    await expect(content(page).getByText('电站管理', { exact: true })).toBeVisible()

    await switchLang(page, 'en')
    await expect(content(page).getByText('Station Management', { exact: true })).toBeVisible({ timeout: 15_000 })
    await expect(page.getByRole('button', { name: 'Add Station' })).toBeVisible()

    await switchLang(page, 'zh')
    await expect(content(page).getByText('电站管理', { exact: true })).toBeVisible({ timeout: 15_000 })
  })

  test('组织架构：页面标题与 Tab 中英切换', async ({ page }) => {
    await gotoAuthed(page, '/organizations')
    await expect(content(page).getByRole('heading', { name: '组织架构' })).toBeVisible()

    await switchLang(page, 'en')
    await expect(content(page).getByRole('heading', { name: 'Organization' })).toBeVisible({ timeout: 15_000 })
    await expect(page.locator('.ant-tabs-tab', { hasText: 'Channel Management' })).toBeVisible()

    await switchLang(page, 'zh')
    await expect(content(page).getByRole('heading', { name: '组织架构' })).toBeVisible({ timeout: 15_000 })
  })

  test('操作记录：页面标题与查询按钮中英切换', async ({ page }) => {
    await gotoAuthed(page, '/operation-logs')
    await expect(content(page).getByRole('heading', { name: '操作记录' })).toBeVisible()

    await switchLang(page, 'en')
    await expect(content(page).getByRole('heading', { name: 'Operation Logs' })).toBeVisible({ timeout: 15_000 })
    await expect(page.getByRole('button', { name: 'Query' })).toBeVisible()

    await switchLang(page, 'zh')
    await expect(content(page).getByRole('heading', { name: '操作记录' })).toBeVisible({ timeout: 15_000 })
  })

  test('系统监控：Tab 标签中英切换', async ({ page }) => {
    await gotoAuthed(page, '/system/system-monitor')
    await expect(page.locator('.ant-tabs-tab-active', { hasText: '系统健康' })).toBeVisible()

    await switchLang(page, 'en')
    await expect(page.locator('.ant-tabs-tab', { hasText: 'System Health' })).toBeVisible({ timeout: 15_000 })
    await expect(page.locator('.ant-tabs-tab', { hasText: 'Data Pipeline' })).toBeVisible()

    await switchLang(page, 'zh')
    await expect(page.locator('.ant-tabs-tab', { hasText: '系统健康' })).toBeVisible({ timeout: 15_000 })
  })

  test('型号管理：页面标题与副标题中英切换', async ({ page }) => {
    await gotoAuthed(page, '/models')
    await expect(page.getByText('型号与协议管理', { exact: true })).toBeVisible()

    await switchLang(page, 'en')
    await expect(page.getByText('Model & Protocol Governance', { exact: true })).toBeVisible({ timeout: 15_000 })
    await expect(page.getByText('Manage model capabilities, standard fields, and released protocol versions')).toBeVisible()

    await switchLang(page, 'zh')
    await expect(page.getByText('型号与协议管理', { exact: true })).toBeVisible({ timeout: 15_000 })
  })
})
