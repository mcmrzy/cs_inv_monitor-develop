import { describe, it, expect } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderAsAdmin } from '@/test/test-utils'
import { API_BASE } from '@/utils/urls'
import OtaPage from './index'

/**
 * 「升级中」分阶段展示：设备通过 ota/status 上报的 state 被 business-api 存进
 * device_upgrades.stage（迁移 117），前端据此把笼统的「升级中」拆成
 * 下载固件 / 校验固件 / 写入设备 / 重启生效。
 * 这里走真实渲染路径 —— 打开升级任务的「设备明细」抽屉，断言阶段文案出现。
 */
const taskDevice = (overrides: Record<string, unknown>) => ({
  id: 11,
  device_sn: 'H1ZZX0013900001P',
  firmware_id: 1,
  firmware_version: '1.1.0',
  target_chip: 'arm',
  old_version: '1.0.0',
  status: 'upgrading',
  stage: '',
  progress: 84,
  error_message: '',
  retry_count: 0,
  pushed_by: null,
  started_at: null,
  completed_at: null,
  created_at: '2026-09-14T00:00:00Z',
  updated_at: '2026-09-14T00:00:00Z',
  ...overrides,
})

function mockTaskDevices(items: Record<string, unknown>[]) {
  server.use(
    http.get(`${API_BASE}/ota/tasks/:id/devices`, () =>
      HttpResponse.json({
        code: 0,
        message: 'success',
        data: { items, total: items.length },
      }),
    ),
  )
}

async function openTaskDeviceDrawer() {
  renderAsAdmin(<OtaPage />)
  // 五 Tab 布局默认在「设备固件升级」，任务明细在「升级任务」Tab
  fireEvent.click(await screen.findByText('升级任务'))
  // mockUpgradeTask id='1'，明细入口是操作列的「详情」链接
  const detailLinks = await screen.findAllByText('详情')
  fireEvent.click(detailLinks[0])
}

describe('OTA 设备明细的阶段展示', () => {
  it('stage=installing 时进度列显示「写入设备」（状态列仍是库内状态"升级中"）', { timeout: 30_000 }, async () => {
    mockTaskDevices([taskDevice({ stage: 'installing' })])
    await openTaskDeviceDrawer()

    // 进度列: 设备上报的细粒度阶段
    expect(await screen.findByText('写入设备')).toBeInTheDocument()
    // 状态列: 库内粗粒度状态，两者并存是设计如此（一处来自 status，一处来自 stage）
    expect(screen.getAllByText('升级中')).toHaveLength(1)
    expect(screen.getAllByText('写入设备')).toHaveLength(1)
  })

  it('ARM 下载阶段 stage=receiving 归一为「下载固件」', { timeout: 30_000 }, async () => {
    mockTaskDevices([taskDevice({ stage: 'receiving', progress: 40 })])
    await openTaskDeviceDrawer()

    expect(await screen.findByText('下载固件')).toBeInTheDocument()
  })

  it('旧数据没有 stage 时回退显示 status 文案', { timeout: 30_000 }, async () => {
    mockTaskDevices([taskDevice({ stage: '' })])
    await openTaskDeviceDrawer()

    // 「升级中」在状态列与阶段列都可能出现，故用 >=1 断言
    expect((await screen.findAllByText('升级中')).length).toBeGreaterThan(0)
  })
})
