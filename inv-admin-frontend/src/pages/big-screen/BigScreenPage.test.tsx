import { describe, it, expect, vi } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderAsAdmin } from '@/test/test-utils'
import BigScreenPage from './index'

// jsdom 无 canvas/WebGL：
// - @/lib/echarts 封装以占位 div 呈现（左栏状态饼图、趋势图）
// - RotatingGlobe 依赖 echarts-gl 的 WebGL 渲染，直接以占位 div 替代
vi.mock('@/lib/echarts', () => ({
  default: () => <div data-testid="echarts-mock">chart</div>,
}))
vi.mock('./components/RotatingGlobe', () => ({
  default: () => <div data-testid="globe-mock">globe</div>,
}))

describe('BigScreenPage', () => {
  it('renders header title, online rate badge and fullscreen button', async () => {
    renderAsAdmin(<BigScreenPage />)

    expect(screen.getByText('辰烁科技联网监控平台')).toBeInTheDocument()
    await waitFor(() => {
      // 头部徽标与中栏统计都使用「在线率」文案
      expect(screen.getAllByText(/在线率/).length).toBeGreaterThanOrEqual(2)
    })
    expect(document.querySelector('.bs-fullscreen-btn')).toBeInTheDocument()
    // 时钟与日期节点
    expect(document.querySelector('.bs-clock')).toBeInTheDocument()
    expect(document.querySelector('.bs-date')).toBeInTheDocument()
  })

  it('renders three-column skeleton with charts, globe placeholder and panels', async () => {
    renderAsAdmin(<BigScreenPage />)

    // 左栏面板
    expect(await screen.findByText('系统总览')).toBeInTheDocument()
    expect(screen.getByText('设备状态分布')).toBeInTheDocument()
    // 右栏面板
    expect(screen.getByText('实时告警')).toBeInTheDocument()
    expect(screen.getByText('电站省份分布')).toBeInTheDocument()
    // 中栏滚动信息与地球占位
    expect(screen.getByText('电站实时监控')).toBeInTheDocument()
    expect(screen.getByTestId('globe-mock')).toBeInTheDocument()
    // 左栏两张图表占位（状态饼图 + 发电趋势）
    await waitFor(() => {
      expect(screen.getAllByTestId('echarts-mock').length).toBeGreaterThanOrEqual(2)
    })
  })

  it('renders device stats, alarms and station ticker from APIs', async () => {
    server.use(
      http.get('/api/v1/dashboard/big-screen', () =>
        HttpResponse.json({
          code: 0,
          message: 'success',
          data: {
            deviceStats: { total: 100, online: 80, offline: 15, fault: 5 },
            todayEnergy: 1234.5,
            totalEnergy: 56789,
            recentAlarms: [
              { id: 1, device_sn: 'INV20250001', alarm_level: 3, fault_code: 'F01', fault_message: '逆变器过温', occurred_at: '2026-01-01 08:00:00' },
            ],
          },
        }),
      ),
      http.get('/api/v1/stations/summary', () =>
        HttpResponse.json({
          code: 0,
          message: 'success',
          data: {
            stations: [
              { station_id: 1, station_name: '大屏电站A', latitude: 23, longitude: 113, total_power: 500, online_count: 2, fault_count: 0, province: '广东' },
            ],
            summary: { totalStations: 1, totalDevices: 10, onlineDevices: 8, todayGeneration: 50, totalGeneration: 999, faultDevices: 0 },
          },
        }),
      ),
    )

    renderAsAdmin(<BigScreenPage />)

    // 左栏 KPI（设备总数 100 / 在线设备 80 / 故障设备 5）
    expect(await screen.findByText('100')).toBeInTheDocument()
    expect(screen.getByText('80')).toBeInTheDocument()
    expect(screen.getByText('5')).toBeInTheDocument()
    // 右栏实时告警列表
    expect(screen.getByText('INV20250001: 逆变器过温')).toBeInTheDocument()
    // 中栏今日发电数值
    expect(screen.getByText('1234.5')).toBeInTheDocument()
    // 底部电站轮播：电站名称 + 装机容量 + 总数（名称与其他文案混排，用正则匹配）
    await waitFor(() => {
      expect(screen.getAllByText(/大屏电站A/).length).toBeGreaterThanOrEqual(1)
    })
    expect(screen.getAllByText(/500 kW/).length).toBeGreaterThanOrEqual(1)
    // 省份分布聚合
    expect(screen.getByText('广东')).toBeInTheDocument()
  })

  it('shows empty placeholders when there is no station or alarm data', async () => {
    renderAsAdmin(<BigScreenPage />)

    // 默认 mock（data:{}）下右栏显示空态文案（省份列表与轮播共用空态文案）
    await waitFor(() => {
      expect(screen.getByText('暂无告警')).toBeInTheDocument()
    })
    expect(screen.getAllByText('暂无电站排名数据').length).toBeGreaterThanOrEqual(1)
  })

  it('shows error alert when big screen data request fails', async () => {
    server.use(
      http.get('/api/v1/dashboard/big-screen', () =>
        HttpResponse.json({ code: 500, message: 'boom' }, { status: 500 }),
      ),
    )

    renderAsAdmin(<BigScreenPage />)

    await waitFor(() => {
      expect(document.querySelector('.ant-alert-error')).toBeInTheDocument()
    })
  })
})
