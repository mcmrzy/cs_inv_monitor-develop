import { describe, it, expect, beforeEach } from 'vitest'
import { fireEvent, waitFor, screen } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderAsAdmin } from '@/test/test-utils'
import { API_BASE } from '@/utils/urls'
import { stationHistoryPrefsKey } from '@/utils/stationHistoryPrefs'
import StationHistoryTab from './StationHistoryTab'

// jsdom 无 canvas：echarts 封装以占位 div 呈现
vi.mock('@/lib/echarts', () => ({
  default: () => <div data-testid="echarts-mock">chart</div>,
}))

const sampleRows = [
  { time: '2026-09-19T08:00:00+00:00', data_hash: 'h1', pv_total_power: 1200.5, battery_soc: 80 },
  { time: '2026-09-19T08:03:00+00:00', data_hash: 'h2', pv_total_power: 1300.5, battery_soc: 81 },
]

const telemetryRequests: string[] = []

function useTelemetryHandler() {
  server.use(
    http.get(`${API_BASE}/devices/by-sn/:sn/telemetry`, ({ request }) => {
      telemetryRequests.push(request.url)
      return HttpResponse.json({
        code: 0,
        message: 'success',
        data: { items: sampleRows, total: sampleRows.length, page: 1, page_size: 10 },
      })
    }),
  )
}

/** 只返回一台带型号的设备，用于验证「按型号记忆」 */
function useDevicesHandler(modelId: number) {
  server.use(
    http.get(`${API_BASE}/devices`, () =>
      HttpResponse.json({
        code: 0,
        message: 'success',
        data: {
          items: [{ id: '1', sn: 'INV20250001', model: 'SG-5K-D', model_id: modelId }],
          total: 1,
          page: 1,
          page_size: 20,
        },
      }),
    ),
  )
}

const lastTelemetryParams = () => new URL(telemetryRequests[telemetryRequests.length - 1]).searchParams

/** 表头在有固定列时会被 antd 复制一份，因此按表头单元格精确匹配 */
const tableHeaders = () =>
  Array.from(document.querySelectorAll('.ant-table-thead th')).map((th) => th.textContent ?? '')
const hasColumn = (label: string) => tableHeaders().some((text) => text.includes(label))

const openFieldPicker = () => {
  // 空态里的「选择字段」按钮（工具栏那个带字段计数）
  const button = screen.getAllByRole('button').find((el) => el.textContent?.trim() === '选择字段')
  expect(button, '空态应提供「选择字段」按钮').toBeTruthy()
  fireEvent.click(button as Element)
  return waitFor(() => {
    expect(document.querySelector('[data-field-key]')).toBeTruthy()
  })
}

const clickFieldCard = (fieldKey: string) => {
  const card = document.querySelector(`[data-field-key="${fieldKey}"]`)
  expect(card, `字段卡片 ${fieldKey} 应存在于选择面板`).toBeTruthy()
  fireEvent.click(card as Element)
}

describe('StationHistoryTab', () => {
  beforeEach(() => {
    telemetryRequests.length = 0
    localStorage.clear()
  })

  it('默认不选择任何字段，提示用户先添加字段', async () => {
    useTelemetryHandler()
    renderAsAdmin(<StationHistoryTab stationId={1} timezone="Asia/Shanghai" />)

    expect(await screen.findByText('尚未选择显示字段')).toBeInTheDocument()
    // 未选字段时不渲染数据表，避免只剩一列时间戳的“空表”
    expect(document.querySelector('.ant-table')).toBeNull()
    // 仍然查询了区间内的条数，用户能看到确实有数据
    await waitFor(() => expect(telemetryRequests.length).toBeGreaterThan(0))
    expect(await screen.findByText(/共 2 条/)).toBeInTheDocument()
    expect(lastTelemetryParams().get('granularity')).toBe('raw')
  })

  it('选择字段后显示对应列，并写入本地记忆', async () => {
    useTelemetryHandler()
    renderAsAdmin(<StationHistoryTab stationId={1} timezone="Asia/Shanghai" />)
    await screen.findByText(/共 2 条/)

    await openFieldPicker()
    clickFieldCard('pv_total_power')

    await waitFor(() => expect(document.querySelector('.ant-table')).toBeInTheDocument())
    expect(hasColumn('PV总功率 (W)')).toBe(true)
    expect(screen.queryByText('尚未选择显示字段')).not.toBeInTheDocument()

    // 记忆写入 localStorage（型号未知时用 default 作用域）
    await waitFor(() => {
      const raw = localStorage.getItem(stationHistoryPrefsKey('default'))
      expect(raw).toBeTruthy()
      expect(JSON.parse(raw as string).fields).toEqual(['pv_total_power'])
    })
  })

  it('重新打开页面时沿用记住的字段选择', async () => {
    localStorage.setItem(stationHistoryPrefsKey('default'), JSON.stringify({ fields: ['battery_soc'] }))
    useTelemetryHandler()

    renderAsAdmin(<StationHistoryTab stationId={1} timezone="Asia/Shanghai" />)

    await waitFor(() => expect(hasColumn('电池SOC (%)')).toBe(true))
    expect(screen.queryByText('尚未选择显示字段')).not.toBeInTheDocument()
  })

  it('切换数据粒度会带新粒度重新请求并回到第一页', async () => {
    localStorage.setItem(stationHistoryPrefsKey('default'), JSON.stringify({ fields: ['pv_total_power'] }))
    useTelemetryHandler()
    renderAsAdmin(<StationHistoryTab stationId={1} timezone="Asia/Shanghai" />)
    await waitFor(() => expect(hasColumn('PV总功率 (W)')).toBe(true))

    fireEvent.click(screen.getByText('按天'))

    await waitFor(() => expect(lastTelemetryParams().get('granularity')).toBe('day'))
    expect(lastTelemetryParams().get('page')).toBe('1')
  })

  it('选中字段后可生成曲线，按自动粒度请求所选字段', async () => {
    localStorage.setItem(stationHistoryPrefsKey('default'), JSON.stringify({ fields: ['pv_total_power'] }))
    useTelemetryHandler()
    renderAsAdmin(<StationHistoryTab stationId={1} timezone="Asia/Shanghai" />)
    await waitFor(() => expect(hasColumn('PV总功率 (W)')).toBe(true))

    fireEvent.click(screen.getByRole('button', { name: /生成曲线图/ }))

    expect(await screen.findByTestId('echarts-mock')).toBeInTheDocument()
    await waitFor(() => {
      const curveUrls = telemetryRequests.filter(
        (url) => new URL(url).searchParams.get('fields') === 'pv_total_power',
      )
      expect(curveUrls.length).toBeGreaterThan(0)
      const curve = new URL(curveUrls[curveUrls.length - 1]).searchParams
      // 默认区间是近 1 天 → 曲线用原始粒度，并按时间正序取点
      expect(curve.get('granularity')).toBe('raw')
      expect(curve.get('sort')).toBe('asc')
    })
  })

  it('未选字段时曲线按钮不可用', async () => {
    useTelemetryHandler()
    renderAsAdmin(<StationHistoryTab stationId={1} timezone="Asia/Shanghai" />)
    await screen.findByText(/共 2 条/)

    expect(screen.getByRole('button', { name: /生成曲线图/ })).toBeDisabled()
  })

  it('按型号记忆字段：切换型号后回到默认空选择', async () => {
    useDevicesHandler(101)
    useTelemetryHandler()
    localStorage.setItem(stationHistoryPrefsKey(101), JSON.stringify({ fields: ['battery_soc'] }))

    const view = renderAsAdmin(<StationHistoryTab stationId={1} timezone="Asia/Shanghai" />)
    await waitFor(() => expect(hasColumn('电池SOC (%)')).toBe(true))

    // 换一台不同型号的设备：不应沿用上一型号的字段
    view.unmount()
    useDevicesHandler(202)
    renderAsAdmin(<StationHistoryTab stationId={1} timezone="Asia/Shanghai" />)

    expect(await screen.findByText('尚未选择显示字段')).toBeInTheDocument()
    expect(hasColumn('电池SOC (%)')).toBe(false)
  })
})
