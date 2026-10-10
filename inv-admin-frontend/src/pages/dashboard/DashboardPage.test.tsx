import { describe, it, expect, vi } from 'vitest'
import { act, screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { createTestQueryClient, renderAsAdmin } from '@/test/test-utils'
import useTimezoneStore from '@/stores/timezoneStore'
import DashboardPage from './index'

// jsdom 无 canvas：echarts 封装以占位 div 呈现，只断言图表实例数量与布局
vi.mock('@/lib/echarts', () => ({
  default: () => <div data-testid="echarts-mock">chart</div>,
}))

// 注意：不要 mock @/utils/timezone —— 它在模块级执行 dayjs.extend(utc)，
// mock 掉会让页面内 dayjs().tz() 因缺 utc 插件而崩溃

describe('DashboardPage', () => {
  it('requests the new current day after midnight without reopening the page', async () => {
    const previousTimezone = useTimezoneStore.getState().timezone
    useTimezoneStore.setState({ timezone: 'UTC' })
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.setSystemTime(new Date('2026-10-08T23:59:50Z'))
    const client = createTestQueryClient()
    const dates: string[] = []
    server.use(http.get('/api/v1/dashboard/energy-flow', ({ request }) => {
      dates.push(new URL(request.url).searchParams.get('date') ?? '')
      return HttpResponse.json({ code: 0, data: { date: dates[dates.length - 1], data: [] } })
    }))
    const page = renderAsAdmin(<DashboardPage />, { queryClient: client })
    try {
      await waitFor(() => expect(dates).toContain('2026-10-08'))
      vi.setSystemTime(new Date('2026-10-09T00:00:10Z'))
      await act(async () => { await client.invalidateQueries({ queryKey: ['dashboard', 'energyFlow'] }) })
      await waitFor(() => expect(dates[dates.length - 1]).toBe('2026-10-09'))
    } finally {
      page.unmount()
      client.clear()
      vi.useRealTimers()
      useTimezoneStore.setState({ timezone: previousTimezone })
    }
  })

  it('renders hero statistic cards with mock statistics values', async () => {
    renderAsAdmin(<DashboardPage />)

    // Hero 卡片标题与 mockDashboardStats 的数值（totalDevices=120）
    expect(await screen.findByText(/设备总数/)).toBeInTheDocument()
    await waitFor(() => {
      expect(screen.getByText('120')).toBeInTheDocument()
      expect(screen.getByText(/在线率/)).toBeInTheDocument()
    })
  })

  it('renders chart placeholders for trend/distribution sections', async () => {
    renderAsAdmin(<DashboardPage />)

    // 近30日趋势、设备状态、功率趋势、电量概览等图表位（jsdom 下为 mock 占位）
    await waitFor(() => {
      const charts = screen.getAllByTestId('echarts-mock')
      expect(charts.length).toBeGreaterThanOrEqual(1)
    })
    expect(screen.getByText(/近30日发电趋势/)).toBeInTheDocument()
  })

  it('renders station ranking section', async () => {
    renderAsAdmin(<DashboardPage />)

    await waitFor(() => {
      expect(screen.getByText(/电站发电排行/)).toBeInTheDocument()
    })
  })

  it('renders recent notifications section', async () => {
    renderAsAdmin(<DashboardPage />)

    await waitFor(() => {
      expect(screen.getByText(/最近通知/)).toBeInTheDocument()
    })
  })

  it('shows query error alert when statistics request fails', async () => {
    server.use(
      http.get('/api/v1/dashboard/statistics', () =>
        HttpResponse.json({ code: 500, message: 'boom' }, { status: 500 }),
      ),
    )

    renderAsAdmin(<DashboardPage />)

    await waitFor(() => {
      const alert = document.querySelector('.ant-alert-error')
      expect(alert).toBeInTheDocument()
    })
  })
})
