/**
 * 设备调试 Tab（DebugTab）测试
 *
 * deviceApi 整体 mock（可控返回），echarts mock 捕获 option 断言 series 数量。
 * 覆盖：无会话开启、active 会话停止/倒计时/采样拉取/曲线渲染、选线增减。
 */
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, screen, waitFor } from '@testing-library/react'

const { chartOptions } = vi.hoisted(() => ({ chartOptions: [] as Record<string, any>[] }))

// jsdom 无 canvas：echarts 以占位 div 呈现，同时捕获 option 供断言 series 数量
vi.mock('@/lib/echarts', () => ({
  default: (props: { option?: Record<string, any> }) => {
    if (props?.option) chartOptions.push(props.option)
    return <div data-testid="echarts-mock">chart</div>
  },
}))

vi.mock('@/services/deviceApi', () => ({
  deviceApi: {
    getDebugSession: vi.fn(),
    startDebugSession: vi.fn(),
    stopDebugSession: vi.fn(),
    getDebugSamples: vi.fn(),
  },
}))

import { deviceApi } from '@/services/deviceApi'
import { renderWithProviders } from '@/test/test-utils'
import DebugTab from './DebugTab'

const mockedApi = vi.mocked(deviceApi, true)

const SN = 'INVDEBUG0001'
const SESSION_ID = 42

const ok = (data: unknown) => ({ data: { code: 0, message: 'success', data } })

const noSession = { session: null, device_online: true, supported: true, interval_seconds: 5 }

function buildActiveSession() {
  return {
    id: SESSION_ID,
    device_sn: SN,
    status: 'active' as const,
    interval_seconds: 5,
    duration_seconds: 3600,
    started_at: new Date(Date.now() - 5 * 60_000).toISOString(),
    // 55 分钟后到期 → 倒计时可见
    expires_at: new Date(Date.now() + 55 * 60_000).toISOString(),
    stopped_at: null,
    requested_by: 1,
    source: 'web' as const,
    start_task_id: 'task-start-1',
    stop_task_id: '',
    last_sample_at: new Date().toISOString(),
    failure_reason: '',
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  }
}

/** 采样点：默认勾选的四条线（电池电压/电流 + 交流电压/电流）有值；母线电压有值但默认不勾选 */
function buildSample(offsetSec: number) {
  return {
    time: new Date(Date.now() - 120_000 + offsetSec * 1000).toISOString(),
    received_at: null,
    quality_flags: 0,
    protocol_version: 2,
    metrics: {
      pv1_voltage: null,
      buck1_current: null,
      pv2_voltage: null,
      buck2_current: null,
      battery_voltage: 51.2,
      battery_current: 12.5,
      dc_bus_voltage: 380.0,
      inv_current: null,
      ac_voltage: 230.0,
      ac_current: 4.8,
    },
  }
}

const samplesPage = {
  items: [buildSample(0), buildSample(30)],
  next_cursor: 'cursor-1',
  session: null,
}

function mockActiveSession() {
  const session = buildActiveSession()
  mockedApi.getDebugSession.mockResolvedValue(
    ok({ session, device_online: true, supported: true, interval_seconds: 5 }) as any,
  )
  mockedApi.getDebugSamples.mockResolvedValue(ok(samplesPage) as any)
}

beforeEach(() => {
  vi.clearAllMocks()
  chartOptions.length = 0
})

describe('DebugTab', () => {
  it('无会话时显示「未开启」，点击开始调用 startDebugSession（含 duration/request_id/source）', async () => {
    mockedApi.getDebugSession.mockResolvedValue(ok(noSession) as any)

    renderWithProviders(<DebugTab sn={SN} />)

    expect(await screen.findByText('未开启')).toBeInTheDocument()
    // 会话不存在：不拉采样
    expect(mockedApi.getDebugSamples).not.toHaveBeenCalled()

    fireEvent.click(await screen.findByRole('button', { name: /开始调试/ }))

    await waitFor(() => expect(mockedApi.startDebugSession).toHaveBeenCalledTimes(1))
    const [calledSn, body] = mockedApi.startDebugSession.mock.calls[0]
    expect(calledSn).toBe(SN)
    expect(body).toMatchObject({ duration_seconds: 3600, source: 'web' })
    // request_id 为非空幂等键
    expect(typeof body?.request_id).toBe('string')
    expect(body?.request_id?.length ?? 0).toBeGreaterThan(0)
  })

  it('有 active 会话时显示停止按钮与倒计时，拉取采样并渲染 4 条默认曲线', async () => {
    mockActiveSession()

    renderWithProviders(<DebugTab sn={SN} />)

    expect(await screen.findByRole('button', { name: /停止调试/ })).toBeInTheDocument()
    expect(screen.getByText(/剩余时间/)).toBeInTheDocument()
    // 默认勾选：电池电压/电流 + 交流电压/电流
    expect(screen.getByRole('checkbox', { name: /电池电压/ })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: /电池电流/ })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: /交流电压/ })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: /交流电流/ })).toBeChecked()

    await waitFor(() => expect(mockedApi.getDebugSamples).toHaveBeenCalled())
    expect(screen.getByTestId('echarts-mock')).toBeInTheDocument()
    expect(chartOptions.length).toBeGreaterThan(0)
    expect(chartOptions[chartOptions.length - 1].series).toHaveLength(4)

    // 点击停止 → DELETE debug-session/:id
    fireEvent.click(screen.getByRole('button', { name: /停止调试/ }))
    await waitFor(() => expect(mockedApi.stopDebugSession).toHaveBeenCalledWith(SN, SESSION_ID))
  })

  it('勾选/取消一条电流线时 series 数量随之变化', async () => {
    mockActiveSession()

    renderWithProviders(<DebugTab sn={SN} />)

    await screen.findByTestId('echarts-mock')
    await waitFor(() => expect(chartOptions[chartOptions.length - 1].series).toHaveLength(4))

    // 取消勾选「电池电流」→ 3 条
    fireEvent.click(screen.getByRole('checkbox', { name: /电池电流/ }))
    await waitFor(() => expect(chartOptions[chartOptions.length - 1].series).toHaveLength(3))

    // 勾选「母线电压」（有数据）→ 4 条
    fireEvent.click(screen.getByRole('checkbox', { name: /母线电压/ }))
    await waitFor(() => expect(chartOptions[chartOptions.length - 1].series).toHaveLength(4))

    // 「全部清除」→ 无 series → 图表退化为空态
    fireEvent.click(screen.getByRole('button', { name: /全部清除/ }))
    await waitFor(() => expect(screen.queryByTestId('echarts-mock')).not.toBeInTheDocument())
  })
})
