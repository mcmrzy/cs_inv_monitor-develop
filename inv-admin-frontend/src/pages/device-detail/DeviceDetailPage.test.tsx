import { describe, it, expect } from 'vitest'
import { fireEvent, screen, waitFor } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { renderAsAdmin } from '@/test/test-utils'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import DeviceDetailPage from './index'

// 注意：不要 mock @/utils/timezone —— 页面依赖其模块级 dayjs.extend(utc)
// jsdom 无 canvas：echarts 封装以占位 div 呈现（能源中心功率曲线等）
vi.mock('@/lib/echarts', () => ({
  default: () => <div data-testid="echarts-mock">chart</div>,
}))

/** 通过内存路由渲染设备详情页（页面依赖 useParams 获取 sn） */
function renderDetail(sn?: string) {
  return renderAsAdmin(
    <MemoryRouter initialEntries={[sn ? `/devices/${sn}` : '/devices']}>
      <Routes>
        <Route path="/devices/:sn" element={<DeviceDetailPage />} />
        <Route path="/devices" element={<DeviceDetailPage />} />
      </Routes>
    </MemoryRouter>,
    { withRouter: false },
  )
}

describe('DeviceDetailPage', () => {
  it('renders page header with back button and device SN', async () => {
    renderDetail('INV20250001')

    expect(screen.getByText('设备详情')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /返\s*回/ })).toBeInTheDocument()
    await waitFor(() => {
      const snText = screen.getByText(/设备序列号/)
      expect(snText.textContent).toContain('INV20250001')
    })
  })

  it('renders all 12 device tabs', async () => {
    renderDetail('INV20250001')

    await waitFor(() => {
      expect(document.querySelectorAll('.ant-tabs-tab').length).toBe(12)
    })
    // 默认激活能源中心
    expect(document.querySelector('.ant-tabs-tab-active')?.textContent).toContain('能源中心')
  })

  it('renders energy center tab with realtime data', async () => {
    renderDetail('INV20250001')

    // /devices/by-sn/:sn/realtime 返回 ac.power=2200W，光伏卡片实时功率可见
    await waitFor(() => {
      expect(screen.getByText('光伏')).toBeInTheDocument()
    })
    expect(screen.getByText('电池')).toBeInTheDocument()
    expect(screen.getByText('负载')).toBeInTheDocument()
    expect(screen.getByText('电网')).toBeInTheDocument()
    expect(screen.getAllByText('实时功率').length).toBeGreaterThanOrEqual(1)
  })

  it('switches to BMS tab on click', async () => {
    renderDetail('INV20250001')

    await screen.findByText('光伏')
    fireEvent.click(screen.getByText('储能'))

    // BMS Tab 激活
    await waitFor(() => {
      expect(document.querySelector('.ant-tabs-tab-active')?.textContent).toContain('储能')
    })
  })

  it('shows the Modbus panel snapshot and opens remote settings for the exact device', async () => {
    const sn = 'PANEL-3KU-001'
    server.use(
      http.get('http://localhost:5173/api/v1/devices/by-sn/PANEL-3KU-001', () => HttpResponse.json({
        code: 0,
        data: { device: { sn, model: '3KU', status: 0 } },
      })),
      http.get('http://localhost:5173/api/v1/devices/by-sn/PANEL-3KU-001/realtime', () => HttpResponse.json({
        code: 0,
        data: {
          online: false,
          data_time: '2026-11-12T06:30:00Z',
          realtime: { pv_total_power: 1860, output_power: 1250, battery_soc: 72, grid_power: 0 },
        },
      })),
    )

    renderDetail(sn)
    expect(await screen.findByText('云端上次采样')).toBeInTheDocument()
    expect(screen.getByText('1.86 kW')).toBeInTheDocument()
    expect(screen.getByText('72%')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /远程设置/ })).toHaveAttribute('href', '/remote-settings?sn=PANEL-3KU-001')
    fireEvent.click(screen.getByRole('button', { name: /蓝牙设置/ }))
    expect(await screen.findByText(/手机连接.*PIN/)).toBeInTheDocument()
  })

  it('shows N/A fallback when sn param is missing', () => {
    renderDetail(undefined)

    const snText = screen.getByText(/设备序列号/)
    expect(snText.textContent).toContain('N/A')
    expect(screen.queryByText('设备详情')).not.toBeInTheDocument()
  })
})
