import { test, expect } from '@playwright/test'
import { gotoAuthed, loadAccount } from './helpers'

/**
 * 路由矩阵：每个主路由一条用例，断言「页面骨架 + 关键控件」。
 * 会话来自 `setup` 项目的 storageState，用例之间互不依赖执行顺序。
 * 单测栈业务数据很少（仅 2 台绑定设备），因此以骨架/控件断言为主。
 */
const acc = loadAccount()

/** 布局内容区：用于区分「页面标题」与侧边栏菜单中的同名文案。 */
const content = (page: import('@playwright/test').Page) => page.locator('.ant-pro-layout-content')

test.describe('主路由矩阵', () => {
  test('/dashboard 仪表盘：概览卡片与排行/通知卡片渲染', async ({ page }) => {
    await gotoAuthed(page, '/dashboard')
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
    await expect(page.getByText('设备总数', { exact: true }).first()).toBeVisible()
    await expect(page.getByText('电站发电排行')).toBeVisible()
    await expect(page.getByText('最近通知')).toBeVisible()
  })

  test('/devices 设备列表：搜索框与添加/绑定按钮', async ({ page }) => {
    await gotoAuthed(page, '/devices')
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
    await expect(page.getByPlaceholder('搜索序列号、型号...')).toBeVisible()
    await expect(page.getByRole('button', { name: '添加设备' })).toBeVisible()
    await expect(page.getByRole('button', { name: '绑定设备' })).toBeVisible()
    await expect(page.locator('.ant-table').first()).toBeVisible()
  })

  test('/ota OTA 升级：升级任务/固件库/App版本管理 三个 Tab', async ({ page }) => {
    await gotoAuthed(page, '/ota')
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
    const tabs = page.locator('.ant-tabs-tab')
    await expect(tabs.filter({ hasText: '升级任务' })).toBeVisible()
    await expect(tabs.filter({ hasText: '固件库' })).toBeVisible()
    await expect(tabs.filter({ hasText: 'App版本管理' })).toBeVisible()
    await expect(page.locator('.ant-tabs-tab-active', { hasText: '升级任务' })).toBeVisible()
    await expect(page.getByRole('button', { name: '创建升级任务' })).toBeVisible()
  })

  test('/alerts 告警中心：三个 Tab 与筛选控件', async ({ page }) => {
    await gotoAuthed(page, '/alerts')
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
    await expect(page.locator('.ant-tabs-tab', { hasText: '全部' })).toBeVisible()
    await expect(page.locator('.ant-tabs-tab', { hasText: '告警' })).toBeVisible()
    await expect(page.locator('.ant-tabs-tab', { hasText: '通知' })).toBeVisible()
    await expect(page.getByRole('button', { name: /刷\s*新/ })).toBeVisible()
    await expect(page.locator('.ant-table').first()).toBeVisible()
  })

  test('/work-orders 工单管理：标题与创建按钮', async ({ page }) => {
    await gotoAuthed(page, '/work-orders')
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
    await expect(content(page).getByText('工单管理', { exact: true })).toBeVisible()
    await expect(page.getByRole('button', { name: '创建工单' })).toBeVisible()
    await expect(page.locator('.ant-table').first()).toBeVisible()
  })

  test('/users 用户管理：标题与添加用户按钮', async ({ page }) => {
    await gotoAuthed(page, '/users')
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
    await expect(content(page).getByText('用户管理', { exact: true })).toBeVisible()
    await expect(page.getByRole('button', { name: '添加用户' })).toBeVisible()
    await expect(page.locator('.ant-table').first()).toBeVisible()
  })

  test('/organizations 组织架构：标题与渠道管理 Tab', async ({ page }) => {
    await gotoAuthed(page, '/organizations')
    await expect(page).toHaveURL(/\/organizations/)
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
    await expect(content(page).getByRole('heading', { name: '组织架构' })).toBeVisible()
    await expect(page.locator('.ant-tabs-tab', { hasText: '渠道管理' })).toBeVisible()
    await expect(page.locator('.ant-tabs-tab-active', { hasText: '渠道管理' })).toBeVisible()
  })

  test('/stations 电站管理：标题与添加电站按钮', async ({ page }) => {
    await gotoAuthed(page, '/stations')
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
    await expect(content(page).getByText('电站管理', { exact: true })).toBeVisible()
    await expect(page.getByRole('button', { name: '添加电站' })).toBeVisible()
  })

  test('/models 型号与协议管理：标题与型号注册 Tab', async ({ page }) => {
    await gotoAuthed(page, '/models')
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
    await expect(page.getByText('型号与协议管理', { exact: true })).toBeVisible()
    await expect(page.locator('.ant-tabs-tab', { hasText: '型号注册' })).toBeVisible()
    await expect(page.getByRole('button', { name: '新增型号' })).toBeVisible()
  })

  test('/monitoring 电站监控：标题、汇总统计与搜索框', async ({ page }) => {
    await gotoAuthed(page, '/monitoring')
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
    await expect(content(page).getByText('电站监控', { exact: true })).toBeVisible()
    await expect(page.getByText('电站总数')).toBeVisible()
    await expect(page.getByPlaceholder('搜索电站名称或地址')).toBeVisible()
  })

  test('/remote-settings 远程设置：标题与未选设备空态', async ({ page }) => {
    await gotoAuthed(page, '/remote-settings')
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
    await expect(page.getByText('远程参数设置', { exact: true })).toBeVisible()
    await expect(page.getByText('请先选择设备')).toBeVisible()
  })

  test('/batch-settings 批量设置：标题与电站筛选卡片', async ({ page }) => {
    await gotoAuthed(page, '/batch-settings')
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
    await expect(content(page).getByText('批量设置', { exact: true })).toBeVisible()
    await expect(page.getByText('电站筛选')).toBeVisible()
    await expect(page.getByText('设备列表', { exact: true })).toBeVisible()
  })

  test('/operation-logs 操作记录：标题与查询控件', async ({ page }) => {
    await gotoAuthed(page, '/operation-logs')
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
    await expect(content(page).getByRole('heading', { name: '操作记录' })).toBeVisible()
    await expect(page.getByRole('button', { name: /查\s*询/ })).toBeVisible()
    await expect(page.getByText('日志类型', { exact: true })).toBeVisible()
  })

  test('/system/system-monitor 系统监控：系统健康 Tab 与资源卡片', async ({ page }) => {
    await gotoAuthed(page, '/system/system-monitor')
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
    await expect(page.locator('.ant-tabs-tab-active', { hasText: '系统健康' })).toBeVisible()
    await expect(page.getByText('CPU使用率')).toBeVisible()
    await expect(page.getByText('内存使用率')).toBeVisible()
  })

  test('/system/system-config 通知与文档配置：标题与两个 Tab', async ({ page }) => {
    await gotoAuthed(page, '/system/system-config')
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
    await expect(content(page).getByText('通知与文档配置', { exact: true })).toBeVisible()
    await expect(page.locator('.ant-tabs-tab', { hasText: '帮助文档配置' })).toBeVisible()
    await expect(page.locator('.ant-tabs-tab', { hasText: '邮件模板配置' })).toBeVisible()
  })

  test('/parallel 并机管理：标题与设备选择器', async ({ page }) => {
    await gotoAuthed(page, '/parallel')
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
    await expect(content(page).getByText('并机与三相遥测', { exact: true })).toBeVisible()
    // 进入页面后设备下拉会自动选中第一台绑定设备
    await expect(page.locator('.ant-select-selection-item', { hasText: 'E2E-SN-' })).toBeVisible()
    await expect(page.getByText('设备尚未上报并机状态')).toBeVisible()
  })
})

test.describe('重定向', () => {
  test('/ 根路径按角色重定向到默认路由', async ({ page }) => {
    // E2E 账号是系统管理员，默认路由固定为 /dashboard
    await gotoAuthed(page, '/')
    await expect(page).not.toHaveURL(/\/login/)
    await expect(page).toHaveURL(/\/dashboard/)
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
  })

  test('/admin 旧路径重定向到 /organizations', async ({ page }) => {
    await gotoAuthed(page, '/admin')
    await expect(page).toHaveURL(/\/organizations/)
    await expect(content(page).getByRole('heading', { name: '组织架构' })).toBeVisible()
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
  })
})

test.describe('全屏页面', () => {
  test('设备详情全屏页：返回按钮 + 11 个 Tab + 无侧边栏', async ({ page }) => {
    await gotoAuthed(page, `/devices/${acc.devices[0]}/detail`)
    await expect(page.getByRole('button', { name: /返回|Back/i })).toBeVisible({ timeout: 15_000 })
    await expect(page.getByText('设备详情', { exact: true })).toBeVisible()
    await expect(page.getByText(new RegExp(`设备序列号:\\s*${acc.devices[0]}`))).toBeVisible()
    await expect(page.locator('.ant-tabs-tab')).toHaveCount(11)
    await expect(page.locator('.ant-layout-sider')).toHaveCount(0)
    await expect(page.locator('.ant-menu')).toHaveCount(0)
  })

  test('设备详情全屏页（第二台设备）：SN 正确展示', async ({ page }) => {
    await gotoAuthed(page, `/devices/${acc.devices[1]}/detail`)
    await expect(page.getByRole('button', { name: /返回|Back/i })).toBeVisible({ timeout: 15_000 })
    await expect(page.getByText(new RegExp(`设备序列号:\\s*${acc.devices[1]}`))).toBeVisible()
    await expect(page.locator('.ant-tabs')).toBeVisible()
    await expect(page.locator('.ant-layout-sider')).toHaveCount(0)
  })

  test('设备详情返回导航：返回按钮回到来源列表', async ({ page }) => {
    await gotoAuthed(page, '/devices')
    const row = page.locator('.ant-table-row', { hasText: acc.devices[0] }).first()
    await expect(row).toBeVisible({ timeout: 20_000 })
    await row.locator('a').first().click()
    await expect(page).toHaveURL(new RegExp(`/devices/${acc.devices[0]}/detail$`), { timeout: 10_000 })
    await page.getByRole('button', { name: /返回|Back/i }).click()
    await expect(page).toHaveURL(/\/devices/, { timeout: 10_000 })
    await expect(page.getByPlaceholder('搜索序列号、型号...')).toBeVisible()
  })

  test('/big-screen 大屏页：标题与在线率徽标、无侧边栏', async ({ page }) => {
    await gotoAuthed(page, '/big-screen')
    await expect(page.locator('.bs-header-title')).toHaveText('辰烁科技联网监控平台')
    await expect(page.locator('.bs-online-badge')).toContainText('在线率')
    await expect(page.locator('.ant-layout-sider')).toHaveCount(0)
    await expect(page.locator('.ant-menu')).toHaveCount(0)
  })

  test('/download App 下载页：标题与下载按钮', async ({ page }) => {
    await gotoAuthed(page, '/download')
    await expect(page.getByText('辰烁光伏逆变', { exact: true })).toBeVisible()
    await expect(page.getByText('光伏电站智能监控平台')).toBeVisible()
    await expect(page.getByRole('button', { name: /下载 Android 安装包/ })).toBeVisible()
    await expect(page.locator('.ant-layout-sider')).toHaveCount(0)
  })

  test('/unauthorized 无权限页：403 提示与返回首页按钮', async ({ page }) => {
    await gotoAuthed(page, '/unauthorized')
    await expect(page.getByText('403', { exact: true })).toBeVisible()
    await expect(page.getByRole('button', { name: /返回首页|Back to Home/i })).toBeVisible()
  })
})

test.describe('侧边栏菜单点击导航', () => {
  const menuCases: Array<{ label: string; url: RegExp }> = [
    { label: '仪表盘', url: /\/dashboard/ },
    { label: '电站监控', url: /\/monitoring/ },
    { label: '电站管理', url: /\/stations/ },
    { label: '设备管理', url: /\/devices/ },
    { label: '型号管理', url: /\/models/ },
    { label: '并机管理', url: /\/parallel/ },
    { label: '远程设置', url: /\/remote-settings/ },
    { label: '批量设置', url: /\/batch-settings/ },
    { label: 'OTA升级', url: /\/ota/ },
    { label: '通知中心', url: /\/alerts/ },
    { label: '工单管理', url: /\/work-orders/ },
    { label: '组织架构', url: /\/organizations/ },
    { label: '用户管理', url: /\/users/ },
    { label: '操作记录', url: /\/operation-logs/ },
  ]

  for (const { label, url } of menuCases) {
    test(`侧边栏点击「${label}」跳转到对应路由`, async ({ page }) => {
      await gotoAuthed(page, '/dashboard')
      await expect(page.locator('.ant-menu')).toBeVisible()
      await page.locator('.ant-menu').getByText(label, { exact: true }).click()
      await expect(page).toHaveURL(url, { timeout: 10_000 })
      await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
    })
  }
})
