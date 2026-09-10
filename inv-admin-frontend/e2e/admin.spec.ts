import { test, expect } from '@playwright/test'
import { gotoAuthed, loadAccount } from './helpers'

/**
 * 管理与配置类页面的骨架/控件/Tab 交互断言。
 * 会话来自 `setup` 项目 storageState（e2e-admin 超管），用例互不依赖。
 */
const acc = loadAccount()

/** 布局内容区：用于区分「页面标题」与侧边栏菜单中的同名文案。 */
const content = (page: import('@playwright/test').Page) => page.locator('.ant-pro-layout-content')

/** 断言页面未落入路由级错误边界（接口异常导致的白屏兜底）。 */
async function expectRendered(page: import('@playwright/test').Page): Promise<void> {
  await expect(content(page)).toBeVisible()
}

test.describe('用户管理 /users', () => {
  test('列表骨架：标题、表格列头与工具栏', async ({ page }) => {
    await gotoAuthed(page, '/users')
    await expectRendered(page)
    await expect(content(page).getByText('用户管理', { exact: true })).toBeVisible()
    for (const col of ['手机号', '邮箱', '昵称', '角色', '状态']) {
      await expect(page.locator('.ant-table-thead', { hasText: col })).toBeVisible()
    }
    await expect(page.getByRole('button', { name: /刷\s*新/ })).toBeVisible()
  })

  test('E2E 管理员账号出现在用户列表', async ({ page }) => {
    await gotoAuthed(page, '/users')
    const row = page.locator('.ant-table-row', { hasText: acc.phone }).first()
    await expect(row).toBeVisible({ timeout: 20_000 })
    await expect(row).toContainText('e2e-admin')
  })

  test('添加用户弹窗可打开并关闭', async ({ page }) => {
    await gotoAuthed(page, '/users')
    await page.getByRole('button', { name: '添加用户' }).click()
    const modal = page.locator('.ant-modal-content', { hasText: '添加用户' })
    await expect(modal).toBeVisible()
    await expect(modal.getByText('手机号', { exact: true }).first()).toBeVisible()
    await modal.getByRole('button', { name: /取 消|取消/ }).click()
    await expect(modal).toBeHidden({ timeout: 10_000 })
  })

  test('按手机号搜索可命中 E2E 账号', async ({ page }) => {
    await gotoAuthed(page, '/users')
    const search = page.getByPlaceholder('搜索手机号/邮箱/昵称')
    await expect(search).toBeVisible()
    await search.fill(acc.phone)
    await search.press('Enter')
    const row = page.locator('.ant-table-row', { hasText: acc.phone }).first()
    await expect(row).toBeVisible({ timeout: 20_000 })
    await search.clear()
    await search.press('Enter')
    await expect(page.locator('.ant-table-row', { hasText: acc.phone }).first()).toBeVisible({ timeout: 20_000 })
  })

  test('账号范围 Tab 与状态筛选下拉存在', async ({ page }) => {
    await gotoAuthed(page, '/users')
    await expect(page.locator('.ant-tabs-tab', { hasText: '全部用户' })).toBeVisible()
    await expect(page.locator('.ant-tabs-tab', { hasText: '系统管理员' })).toBeVisible()
    await expect(page.locator('.ant-select', { hasText: '状态筛选' }).first()).toBeVisible({ timeout: 15_000 })
  })
})

test.describe('组织架构 /organizations', () => {
  test('系统管理员可见三个 Tab', async ({ page }) => {
    await gotoAuthed(page, '/organizations')
    await expectRendered(page)
    await expect(page.locator('.ant-tabs-tab', { hasText: '渠道管理' })).toBeVisible()
    await expect(page.locator('.ant-tabs-tab', { hasText: '权限配置' })).toBeVisible()
    await expect(page.locator('.ant-tabs-tab', { hasText: 'API 权限总览' })).toBeVisible()
  })

  test('渠道管理为默认 Tab 且提供新建组织入口', async ({ page }) => {
    await gotoAuthed(page, '/organizations')
    await expect(page.locator('.ant-tabs-tab-active', { hasText: '渠道管理' })).toBeVisible()
    await expect(page.getByRole('button', { name: '新建组织' })).toBeVisible({ timeout: 15_000 })
  })

  test('切换到权限配置 Tab 显示组织/角色选择器', async ({ page }) => {
    await gotoAuthed(page, '/organizations')
    await page.locator('.ant-tabs-tab', { hasText: '权限配置' }).click()
    await expect(page.locator('.ant-tabs-tab-active', { hasText: '权限配置' })).toBeVisible()
    await expect(content(page).getByText('选择组织:', { exact: true })).toBeVisible({ timeout: 15_000 })
    await expect(content(page).getByText('请先选择一个组织，然后配置角色权限。')).toBeVisible()
  })

  test('切换到 API 权限总览 Tab 显示搜索框', async ({ page }) => {
    await gotoAuthed(page, '/organizations')
    await page.locator('.ant-tabs-tab', { hasText: 'API 权限总览' }).click()
    await expect(page.locator('.ant-tabs-tab-active', { hasText: 'API 权限总览' })).toBeVisible()
    await expect(page.getByText('API 权限总览').first()).toBeVisible({ timeout: 15_000 })
    await expect(page.getByPlaceholder('搜索 API 路径或描述')).toBeVisible()
  })
})

test.describe('操作记录 /operation-logs', () => {
  test('骨架：标题、日志类型筛选与查询按钮', async ({ page }) => {
    await gotoAuthed(page, '/operation-logs')
    await expectRendered(page)
    await expect(content(page).getByRole('heading', { name: '操作记录' })).toBeVisible()
    await expect(content(page).getByText('日志类型', { exact: true })).toBeVisible()
    await expect(page.getByText('时间范围', { exact: true })).toBeVisible()
    await expect(page.getByRole('button', { name: /查\s*询/ })).toBeVisible()
  })

  test('日志类型切换到告警日志', async ({ page }) => {
    await gotoAuthed(page, '/operation-logs')
    await page.locator('.ant-select-selection-item', { hasText: '全部' }).click()
    await page.locator('.ant-select-item-option', { hasText: '告警日志' }).click()
    await expect(page.locator('.ant-table').first()).toBeVisible({ timeout: 15_000 })
  })

  test('日志类型切换到命令日志', async ({ page }) => {
    await gotoAuthed(page, '/operation-logs')
    await page.locator('.ant-select-selection-item', { hasText: '全部' }).click()
    await page.locator('.ant-select-item-option', { hasText: '命令日志' }).click()
    await expect(page.locator('.ant-table').first()).toBeVisible({ timeout: 15_000 })
  })
})

test.describe('系统监控 /system/system-monitor', () => {
  test('系统健康 Tab：资源使用卡片', async ({ page }) => {
    await gotoAuthed(page, '/system/system-monitor')
    await expectRendered(page)
    await expect(page.locator('.ant-tabs-tab-active', { hasText: '系统健康' })).toBeVisible()
    await expect(page.getByText('CPU使用率')).toBeVisible()
    await expect(page.getByText('内存使用率')).toBeVisible()
  })

  test('数据管道 Tab：管道状态总览', async ({ page }) => {
    await gotoAuthed(page, '/system/system-monitor')
    await page.locator('.ant-tabs-tab', { hasText: '数据管道' }).click()
    await expect(page.locator('.ant-tabs-tab-active', { hasText: '数据管道' })).toBeVisible()
    await expect(page.getByText('管道状态总览')).toBeVisible({ timeout: 15_000 })
    await expect(page.getByText('整体状态', { exact: true })).toBeVisible()
  })

  test('运营统计 Tab：用户/邮件/推送统计', async ({ page }) => {
    await gotoAuthed(page, '/system/system-monitor')
    await page.locator('.ant-tabs-tab', { hasText: '运营统计' }).click()
    await expect(page.locator('.ant-tabs-tab-active', { hasText: '运营统计' })).toBeVisible()
    await expect(page.getByText('今日新增', { exact: true })).toBeVisible({ timeout: 15_000 })
    await expect(page.getByText('今日活跃', { exact: true })).toBeVisible()
  })

  test('系统日志 Tab：日志表格列头', async ({ page }) => {
    await gotoAuthed(page, '/system/system-monitor')
    await page.locator('.ant-tabs-tab', { hasText: '系统日志' }).click()
    await expect(page.locator('.ant-tabs-tab-active', { hasText: '系统日志' })).toBeVisible()
    await expect(page.locator('.ant-table-thead', { hasText: '时间' })).toBeVisible({ timeout: 15_000 })
    await expect(page.locator('.ant-table-thead', { hasText: '用户' })).toBeVisible()
  })
})

test.describe('通知与文档 /system/system-config', () => {
  test('骨架：标题、三个 Tab 与默认系统公告面板', async ({ page }) => {
    await gotoAuthed(page, '/system/system-config')
    await expectRendered(page)
    await expect(content(page).getByText('通知与文档', { exact: true })).toBeVisible()
    await expect(page.locator('.ant-tabs-tab', { hasText: '通知' })).toBeVisible()
    await expect(page.locator('.ant-tabs-tab', { hasText: '帮助文档' })).toBeVisible()
    await expect(page.locator('.ant-tabs-tab', { hasText: '邮件模板' })).toBeVisible()
    // 默认 Tab 为「通知」：系统公告推送面板
    await expect(page.getByText('系统公告推送', { exact: true })).toBeVisible()
    await expect(page.getByPlaceholder('请输入公告标题')).toBeVisible()
  })

  test('系统公告推送：切换目标范围出现 ID 输入', async ({ page }) => {
    await gotoAuthed(page, '/system/system-config')
    await expect(page.getByText('系统公告推送', { exact: true })).toBeVisible({ timeout: 15_000 })
    // 默认目标为全部用户（超管）
    await expect(page.getByText('全部用户（仅超级管理员）', { exact: true })).toBeVisible()
    await page.locator('.ant-select', { hasText: '全部用户' }).click()
    await page.locator('.ant-select-item-option', { hasText: '指定用户' }).click()
    await expect(page.getByPlaceholder('请输入用户 ID')).toBeVisible()
  })

  test('帮助文档：客服电话与保存按钮', async ({ page }) => {
    await gotoAuthed(page, '/system/system-config')
    await page.locator('.ant-tabs-tab', { hasText: '帮助文档' }).click()
    await expect(page.getByText('客服电话', { exact: true }).first()).toBeVisible({ timeout: 15_000 })
    await expect(page.getByText('文档链接', { exact: true })).toBeVisible()
    await expect(page.getByRole('button', { name: /保 存|保存/ })).toBeVisible()
  })

  test('邮件模板：模板表格列头', async ({ page }) => {
    await gotoAuthed(page, '/system/system-config')
    await page.locator('.ant-tabs-tab', { hasText: '邮件模板' }).click()
    await expect(page.locator('.ant-tabs-tab-active', { hasText: '邮件模板' })).toBeVisible()
    await expect(page.getByText('模板类型', { exact: true })).toBeVisible({ timeout: 15_000 })
    await expect(page.getByText('邮件主题', { exact: true })).toBeVisible()
  })
})

test.describe('远程设置 /remote-settings', () => {
  test('标题、设备选择器与未选设备空态', async ({ page }) => {
    await gotoAuthed(page, '/remote-settings')
    await expectRendered(page)
    await expect(page.getByText('远程参数设置', { exact: true })).toBeVisible()
    await expect(page.getByText('远程配置逆变器运行参数，支持实时下发与生效')).toBeVisible()
    await expect(page.getByText('电站选择', { exact: true })).toBeVisible()
    await expect(page.getByText('设备选择', { exact: true })).toBeVisible()
    await expect(page.getByText('请先选择设备')).toBeVisible()
  })

  test('未选电站时设备选择器禁用', async ({ page }) => {
    await gotoAuthed(page, '/remote-settings')
    const deviceSelect = page.locator('.ant-select', { hasText: '请选择电站' })
    await expect(deviceSelect).toBeVisible({ timeout: 15_000 })
    await expect(deviceSelect).toHaveClass(/ant-select-disabled/)
  })
})

test.describe('批量设置 /batch-settings', () => {
  test('骨架：标题、电站筛选与设备列表卡片', async ({ page }) => {
    await gotoAuthed(page, '/batch-settings')
    await expectRendered(page)
    await expect(content(page).getByText('批量设置', { exact: true })).toBeVisible()
    await expect(page.getByText('电站筛选')).toBeVisible()
    await expect(page.getByText('设备列表', { exact: true })).toBeVisible()
    await expect(page.getByText('参数变更: 0 项')).toBeVisible()
  })

  test('设备列表展示两台绑定设备', async ({ page }) => {
    await gotoAuthed(page, '/batch-settings')
    await expect(page.locator('.ant-table-row', { hasText: acc.devices[0] }).first()).toBeVisible({ timeout: 20_000 })
    await expect(page.locator('.ant-table-row', { hasText: acc.devices[1] }).first()).toBeVisible()
    await expect(page.getByText(/已选 0 \/ 2/)).toBeVisible()
  })
})

test.describe('型号管理 /models', () => {
  test('骨架：标题、副标题与型号注册 Tab', async ({ page }) => {
    await gotoAuthed(page, '/models')
    await expectRendered(page)
    await expect(page.getByText('型号与协议管理', { exact: true })).toBeVisible()
    await expect(page.getByText('统一维护型号能力、标准字段和已发布协议版本')).toBeVisible()
    await expect(page.locator('.ant-tabs-tab', { hasText: '型号注册' })).toBeVisible()
  })

  test('型号注册 Tab：新增型号按钮与表格', async ({ page }) => {
    await gotoAuthed(page, '/models')
    await expect(page.locator('.ant-tabs-tab-active', { hasText: '型号注册' })).toBeVisible()
    await expect(page.getByRole('button', { name: '新增型号' })).toBeVisible({ timeout: 15_000 })
    await expect(page.locator('.ant-table').first()).toBeVisible()
  })

  test('新增型号弹窗可打开并关闭', async ({ page }) => {
    await gotoAuthed(page, '/models')
    await page.getByRole('button', { name: '新增型号' }).click()
    const modal = page.locator('.ant-modal-content').first()
    await expect(modal).toBeVisible({ timeout: 15_000 })
    await modal.getByRole('button', { name: /取 消|取消/ }).first().click()
    await expect(modal).toBeHidden({ timeout: 10_000 })
  })
})

test.describe('并机管理 /parallel', () => {
  test('骨架：标题、设备选择器与空态', async ({ page }) => {
    await gotoAuthed(page, '/parallel')
    await expectRendered(page)
    await expect(content(page).getByText('并机与三相遥测', { exact: true })).toBeVisible()
    // 设备下拉会自动选中第一台绑定设备
    await expect(page.locator('.ant-select-selection-item', { hasText: 'E2E-SN-' })).toBeVisible({ timeout: 15_000 })
    await expect(page.getByText('设备尚未上报并机状态')).toBeVisible()
  })

  test('切换设备下拉到指定设备 SN', async ({ page }) => {
    await gotoAuthed(page, '/parallel')
    // 等待自动选中完成后再打开下拉
    await expect(page.locator('.ant-select-selection-item', { hasText: 'E2E-SN-' })).toBeVisible({ timeout: 15_000 })
    await page.locator('.ant-select-selection-item', { hasText: 'E2E-SN-' }).click()
    const option = page.locator('.ant-select-item-option', { hasText: acc.devices[0] }).first()
    await expect(option).toBeVisible({ timeout: 15_000 })
    await option.click()
    await expect(page.locator('.ant-select-selection-item', { hasText: acc.devices[0] })).toBeVisible({ timeout: 15_000 })
  })
})
