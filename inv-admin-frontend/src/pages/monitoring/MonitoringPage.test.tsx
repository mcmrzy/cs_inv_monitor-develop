import { describe, it, expect } from 'vitest'
import { fireEvent, screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderAsAdmin } from '@/test/test-utils'
import MonitoringPage from './index'

// 注意：不要 mock @/utils/timezone —— 页面依赖其模块级 dayjs.extend(utc)

/** 从统计卡片中找到标题对应的Statistic元素并断言其数值文本 */
function expectStatistic(title: string, value: string) {
  const stat = Array.from(document.querySelectorAll('.ant-statistic')).find((el) =>
    el.textContent?.includes(title),
  )
  expect(stat, `statistic ${title} should render`).toBeTruthy()
  expect(stat?.textContent).toContain(value)
}

describe('MonitoringPage', () => {
  it('renders page title with summary statistics from stations summary API', async () => {
    // 注意：handlers.ts 中 /stations/:id 先于 /stations/summary 注册会截获该请求，
    // 这里显式覆盖以保证返回汇总对象
    server.use(
      http.get('/api/v1/stations/summary', () =>
        HttpResponse.json({
          code: 0,
          message: 'success',
          data: { totalStations: 2, totalDevices: 15, onlineDevices: 12, todayGeneration: 100.5 },
        }),
      ),
    )

    renderAsAdmin(<MonitoringPage />)

    // 页头标题 + 汇总统计
    expect(screen.getByText('电站监控')).toBeInTheDocument()
    await waitFor(() => {
      expectStatistic('电站总数', '2')
      expectStatistic('设备总数', '15')
      expectStatistic('在线设备', '12')
    })
  })

  it('renders station cards for every station returned by the API', async () => {
    renderAsAdmin(<MonitoringPage />)

    // MSW /stations 返回 测试电站A / 测试电站B，卡片显示设备数与状态标签
    expect(await screen.findByText('测试电站A')).toBeInTheDocument()
    expect(screen.getByText('测试电站B')).toBeInTheDocument()
    // 设备数统计（A=10, B=5）
    expect(screen.getByText('10')).toBeInTheDocument()
    expect(screen.getByText('5')).toBeInTheDocument()
  })

  it('renders status filter options with computed counts', async () => {
    renderAsAdmin(<MonitoringPage />)

    // 默认 mock 数据无在线设备 → 全部(2)/正常(0)/故障(0)/离线(2)
    await waitFor(() => {
      const segmentedText = document.querySelector('.ant-segmented')?.textContent ?? ''
      expect(segmentedText).toContain('全部 (2)')
      expect(segmentedText).toContain('正常 (0)')
      expect(segmentedText).toContain('故障 (0)')
      expect(segmentedText).toContain('离线 (2)')
      // 4 个筛选段
      expect(document.querySelectorAll('.ant-segmented-item').length).toBe(4)
    })
  })

  it('filters station cards by search keyword', async () => {
    renderAsAdmin(<MonitoringPage />)

    expect(await screen.findByText('测试电站A')).toBeInTheDocument()
    fireEvent.change(screen.getByPlaceholderText('搜索电站名称或地址'), {
      target: { value: '测试电站A' },
    })

    await waitFor(() => {
      expect(screen.queryByText('测试电站B')).not.toBeInTheDocument()
    })
    expect(screen.getByText('测试电站A')).toBeInTheDocument()
  })

  it('shows empty state when stations list is empty', async () => {
    server.use(
      http.get('/api/v1/stations', () =>
        HttpResponse.json({ code: 0, message: 'success', data: { items: [], total: 0 } }),
      ),
    )

    renderAsAdmin(<MonitoringPage />)

    await waitFor(() => {
      const empty = document.querySelector('.ant-empty')
      expect(empty).toBeInTheDocument()
      expect(empty?.textContent).toContain('暂无数据')
    })
    expect(screen.queryByText('测试电站A')).not.toBeInTheDocument()
  })
})
