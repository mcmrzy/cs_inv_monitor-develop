import { test, expect, type Locator, type Page } from '@playwright/test'
import { gotoAuthed } from './helpers'

/**
 * 视觉回归基线（界面美观稳定的防线）。
 *
 * - 仅在 visual 项目运行（固定 1440x900 视口；toHaveScreenshot 默认禁用 CSS
 *   动画/过渡并隐藏光标）。
 * - 基线按平台分文件存储（*-win32.png 等），本地生成：
 *     npx playwright test --project=visual --update-snapshots
 *   之后再跑同命令（不带 --update-snapshots）应全绿，否则页面存在不稳定元素，
 *   需要为该区域补 mask 或修掉闪烁源。
 * - mask 语义：只豁免「内容随日期/实时数据变化的画布与输入」区域；卡片框架、
 *   标题、布局骨架仍在比对范围内。
 */

/** dashboard：echarts canvas 的轴标签/渲染随日期滚动，日期选择器同理 */
function dashboardMasks(page: Page): Locator[] {
  return [page.locator('canvas'), page.locator('.ant-picker')]
}

const pages: Array<{
  name: string
  path: string
  masks?: (page: Page) => Locator[]
}> = [
  { name: '仪表盘', path: '/dashboard', masks: dashboardMasks },
  { name: '设备列表', path: '/devices' },
  { name: '告警中心', path: '/alerts' },
  { name: 'OTA 升级', path: '/ota' },
  { name: '电站管理', path: '/stations' },
  { name: '电站监控', path: '/monitoring' },
]

for (const { name, path, masks } of pages) {
  test(`视觉基线：${name}`, async ({ page }) => {
    await gotoAuthed(page, path)
    await expect(page.locator('.ant-pro-layout-content')).toBeVisible()
    // 等待路由内容真正挂载（避免截到 loading 骨架瞬间）
    await page.waitForLoadState('networkidle')
    await page.waitForTimeout(500)
    // maxDiffPixelRatio 0.02：吸收 antd 表格列宽测量 ±1px 抖动产生的文字
    // 反锯齿差（实测 ~1%）；真实的布局/样式回归通常远超 2%
    await expect(page).toHaveScreenshot(`${name}.png`, {
      fullPage: true,
      maxDiffPixelRatio: 0.02,
      ...(masks ? { mask: masks(page) } : {}),
    })
  })
}
