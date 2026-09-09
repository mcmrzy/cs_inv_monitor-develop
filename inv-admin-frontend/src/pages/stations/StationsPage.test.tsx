import { describe, it, expect } from 'vitest'
import { fireEvent, screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderAsAdmin } from '@/test/test-utils'
import StationsPage from './index'

// 注意：不要 mock @/utils/timezone —— 页面依赖其模块级 dayjs.extend(utc)
// jsdom 无 canvas：echarts 封装以占位 div 呈现
vi.mock('@/lib/echarts', () => ({
  default: () => <div data-testid="echarts-mock">chart</div>,
}))

/** 从统计卡片中找到标题对应的Statistic元素并断言其数值文本 */
function expectStatistic(title: string, value: string) {
  const stat = Array.from(document.querySelectorAll('.ant-statistic')).find((el) =>
    el.textContent?.includes(title),
  )
  expect(stat, `statistic ${title} should render`).toBeTruthy()
  expect(stat?.textContent).toContain(value)
}

describe('StationsPage', () => {
  it('renders title and summary cards from stations summary API', async () => {
    server.use(
      http.get('/api/v1/stations/summary', () =>
        HttpResponse.json({
          code: 0,
          message: 'success',
          data: { totalStations: 2, totalDevices: 15, onlineDevices: 12, todayGeneration: 100.5 },
        }),
      ),
    )

    renderAsAdmin(<StationsPage />)

    expect(screen.getByText('电站管理')).toBeInTheDocument()
    await waitFor(() => {
      expectStatistic('电站总数', '2')
      expectStatistic('设备总数', '15')
      expectStatistic('在线设备', '12')
    })
  })

  it('renders station table with mocked rows', async () => {
    renderAsAdmin(<StationsPage />)

    // ProTable 展示 MSW 返回的两条电站
    expect(await screen.findByText('测试电站A')).toBeInTheDocument()
    expect(screen.getByText('测试电站B')).toBeInTheDocument()
    expect(document.querySelector('.ant-table')).toBeInTheDocument()
  })

  it('renders status filter buttons with counts and search box', async () => {
    renderAsAdmin(<StationsPage />)

    // 工具栏按钮：全部 (2) / 正常 (0) / 故障 (0) / 离线 (2)
    expect(await screen.findByText(/全部 \(2\)/)).toBeInTheDocument()
    expect(screen.getByText(/正常 \(0\)/)).toBeInTheDocument()
    expect(screen.getByText(/故障 \(0\)/)).toBeInTheDocument()
    expect(screen.getByText(/离线 \(2\)/)).toBeInTheDocument()
    expect(screen.getByPlaceholderText('搜索电站名称或地址')).toBeInTheDocument()
  })

  it('filters table rows by search keyword', async () => {
    renderAsAdmin(<StationsPage />)

    expect(await screen.findByText('测试电站A')).toBeInTheDocument()
    fireEvent.change(screen.getByPlaceholderText('搜索电站名称或地址'), {
      target: { value: '测试电站A' },
    })

    await waitFor(() => {
      expect(screen.queryByText('测试电站B')).not.toBeInTheDocument()
    })
    expect(screen.getByText('测试电站A')).toBeInTheDocument()
  })

  it('opens detail drawer with info tab descriptions', async () => {
    renderAsAdmin(<StationsPage />)

    const detailLinks = await screen.findAllByText(/详情/)
    fireEvent.click(detailLinks[0])

    // Drawer 打开后展示电站信息 Descriptions（含电站名称字段值）
    const drawer = await waitFor(() => {
      const el = document.querySelector('.ant-drawer-open')
      expect(el).toBeInTheDocument()
      return el!
    })
    expect(drawer.textContent).toContain('电站信息')
    expect(drawer.textContent).toContain('测试电站A')
    // 详情抽屉包含 设备列表/发电统计/告警记录 三个附加 Tab
    expect(drawer.textContent).toContain('设备列表')
    expect(drawer.textContent).toContain('发电统计')
    expect(drawer.textContent).toContain('告警记录')
  })

  it('shows error alert when stations request fails', async () => {
    server.use(
      http.get('/api/v1/stations', () =>
        HttpResponse.json({ code: 500, message: 'boom' }, { status: 500 }),
      ),
    )

    renderAsAdmin(<StationsPage />)

    await waitFor(() => {
      expect(document.querySelector('.ant-alert-error')).toBeInTheDocument()
    })
    // 错误提示附带重试按钮
    expect(screen.getByText('重新加载')).toBeInTheDocument()
  })
})
