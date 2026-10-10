import { act, cleanup, fireEvent, screen, within, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { renderAsAdmin } from '@/test/test-utils'
import { server } from '@/test/mocks/server'
import useLocaleStore from '@/stores/localeStore'
import BmsTab from './BmsTab'
import BmsSummaryView from './BmsSummaryView'
import { parseBmsSummary, SUMMARY_FIELDS } from './bmsSummary'

vi.mock('@/lib/echarts', () => ({ default: () => <div data-testid="cmd08-chart">chart</div> }))
const NOW = Date.parse('2026-10-08T08:00:00Z')
function snapshot(overrides: Record<string, unknown> = {}) {
  return { layout: 0, bms_online: 1, battery_count: 1, age_ms: 8000, soc_raw: 726, soh_raw: 978,
    soc: 72.6, soh: 97.8, voltage: 52.78, current: -8.4, cycle_count: 128,
    expires_at: new Date(NOW + 210000).toISOString(), updated_at: new Date(NOW - 8000).toISOString(), reported_at: new Date(NOW).toISOString(),
    capacity_remain: 43.56, capacity_full: 60, capacity_design: 64,
    warning_flag: 0, protection_flag: 0, status_fault_flag: (1 << 9) | (1 << 11), balance_status: 1 << 4,
    cell_voltages: Array.from({ length: 16 }, (_, i) => i === 15 ? null : 3295 + i),
    cell_temperatures: [null, null, null, null], max_cell_voltage: 3500, min_cell_voltage: 3295,
    max_cell_temp: null, min_cell_temp: null, mos_temp: -3.2, pcb_temp: 32.8, env_temp: 26.4,
    battery_mode: 2, battery_status: 1, system_mode: 0, charging_voltage: null,
    total_chg_capacity_raw: 4294967295, total_dsg_capacity_raw: 129430,
    chg_request_current_raw: 3000, chg_request_voltage_raw: -5600,
    raw_bytes: Array.from({ length: 100 }, (_, i) => i), ...overrides }
}
function view(overrides: Record<string, unknown> = {}, error?: unknown) {
  return renderAsAdmin(<BmsSummaryView summary={parseBmsSummary({ bms_summary: snapshot(overrides) })!} error={error} onRefresh={vi.fn()} />)
}
beforeEach(() => { vi.spyOn(Date, 'now').mockReturnValue(NOW); useLocaleStore.setState({ lang: 'zh' }) })
afterEach(() => { cleanup(); vi.restoreAllMocks(); useLocaleStore.setState({ lang: 'zh' }) })

describe('Production CMD08 BMS presentation', () => {
  it('shows populated layout 0 temperatures and charging voltage', () => {
    const { container } = view({ cell_temperatures: [-5, 0, 25, 30], max_cell_temp: 30, min_cell_temp: -5, charging_voltage: 56 })
    expect(container.querySelector('.cmd08-temperatures')).toHaveTextContent('-5')
    fireEvent.click(screen.getByRole('button', { name: '诊断详情' }))
    expect(container.querySelector('.cmd08-diagnostics')).toHaveTextContent('56 V')
    expect(container.querySelector('.cmd08-diagnostics')).toHaveTextContent('[-5,0,25,30]')
  })
  it('shows engineering values without re-scaling, all cells and keyboard selection', () => {
    view()
    expect(screen.getByTestId('cmd08-bms')).toHaveAttribute('data-availability', 'live')
    expect(screen.getByText('52.78')).toBeInTheDocument()
    expect(screen.getByText('-8.40')).toBeInTheDocument()
    expect(screen.getByText('43.560')).toBeInTheDocument()
    expect(screen.getByText('-3.2')).toBeInTheDocument()
    const button = screen.getByRole('button', { name: 'C05' })
    button.focus(); fireEvent.click(button)
    expect(button).toHaveFocus()
    expect(button).toHaveAttribute('aria-pressed', 'true')
    expect(screen.getByTestId('cmd08-selected-cell')).toHaveTextContent('C05')
    expect(screen.getByTestId('cmd08-selected-cell')).toHaveTextContent('均衡中')
    expect(screen.getByRole('button', { name: 'C16' })).toHaveTextContent('--')
    fireEvent.click(screen.getByRole('button', { name: '单体' }))
    expect(screen.queryByText('剩余电量')).not.toBeInTheDocument()
  })
  it.each([{ expires_at: new Date(NOW).toISOString() }, { expires_at: null }, { bms_online: 0 }])('masks current metrics but retains explicit historical diagnostics: %j', overrides => {
    const { container } = view(overrides)
    const current = container.querySelector('.cmd08-summary')!
    expect(current).not.toHaveTextContent('52.78')
    expect(current).not.toHaveTextContent('72.6')
    expect(container.querySelector('.cmd08-capacities')).not.toHaveTextContent('43.560')
    expect(screen.queryByTestId('cmd08-chart')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'C01' })).toHaveTextContent('--')
    expect(screen.getAllByText(/历史快照仅供诊断/).length).toBeGreaterThan(0)
    fireEvent.click(screen.getByRole('button', { name: '诊断详情' }))
    expect(container.querySelector('.cmd08-diagnostics')).toHaveTextContent('52.78 V')
  })
  it('expires while open even when refreshing fails', () => {
    vi.useFakeTimers({ now: NOW })
    try {
      const { container } = view({ expires_at: new Date(NOW + 1000).toISOString() }, new Error('network'))
      expect(screen.getByText(/刷新失败/)).toBeInTheDocument()
      expect(screen.getByTestId('cmd08-bms')).toHaveAttribute('data-availability', 'live')
      act(() => { vi.advanceTimersByTime(1000) })
      expect(screen.getByTestId('cmd08-bms')).toHaveAttribute('data-availability', 'expired')
      expect(container.querySelector('.cmd08-summary')).not.toHaveTextContent('52.78')
    } finally { vi.useRealTimers() }
  })
  it('retains all fields, uncertain quantities, metadata and 100 original bytes in diagnostics', () => {
    const { container } = view()
    fireEvent.click(screen.getByRole('button', { name: '诊断详情' }))
    const details = container.querySelector('.cmd08-diagnostics')!
    expect(details.querySelectorAll('dl > div')).toHaveLength(SUMMARY_FIELDS.length - 1)
    expect(details).toHaveTextContent('4294967295')
    expect(details).toHaveTextContent('-5600')
    expect(details).toHaveTextContent('0.1 A')
    expect(details).toHaveTextContent('上报极值与当前有效电芯计算结果不同')
    expect(details.querySelector('pre')!.textContent!.trim().split(' ')).toHaveLength(100)
    expect(details.querySelector('pre')).toHaveTextContent('60 61 62 63')
    expect(details).not.toHaveTextContent('deviceDetail.summary.')
  })
  it('never treats operating bits or unknown flags as healthy faults', () => {
    const { container } = view({ warning_flag: 1 << 6 })
    const status = container.querySelector('.cmd08-flags')!
    expect(status).toHaveTextContent('部分状态未确认')
    expect(status).toHaveTextContent('保留位 6')
    expect(status).toHaveTextContent('放电 MOS 开启')
    expect(status).not.toHaveTextContent('无活动项')
    expect(container.querySelector('.cmd08-notice')).toBeNull()
  })
  it('displays separate warning/protection/fault groups without legacy alarm levels', () => {
    const { container } = view({ warning_flag: 2, protection_flag: 64, status_fault_flag: 16 })
    const status = container.querySelector('.cmd08-flags')!
    expect(status).toHaveTextContent('单体欠压')
    expect(status).toHaveTextContent('短路')
    expect(status).toHaveTextContent('电芯故障')
    expect(status).not.toHaveTextContent('L1')
  })
  it('supports complete English labels and invariant Cxx selectors', () => {
    view(); act(() => { useLocaleStore.setState({ lang: 'en' }) })
    expect(screen.getByRole('button', { name: 'Overview' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Diagnostics' }))
    expect(screen.getByText('Raw requested charge voltage')).toBeInTheDocument()
    expect(screen.queryByText(/deviceDetail.summary./)).not.toBeInTheDocument()
  })
})
describe('BmsTab routing and legacy coexistence', () => {
  it('uses a valid BMS snapshot even if inverter envelope is offline/stale, ignoring legacy values', async () => {
    server.use(http.get('/api/v1/devices/by-sn/CMD08/realtime', () => HttpResponse.json({ code: 0, data: {
      online: false, data_time: '2000-01-01T00:00:00Z', realtime: { bms_summary: { data: snapshot() }, bms: { bms_online: 1, bms_soc: 99 } },
    } })))
    renderAsAdmin(<BmsTab sn="CMD08" />)
    await waitFor(() => expect(screen.getByTestId('cmd08-bms')).toHaveAttribute('data-availability', 'live'))
    expect(screen.getByText('52.78')).toBeInTheDocument()
    expect(screen.queryByText('99%')).not.toBeInTheDocument()
  })
  it('retains an expired CMD08 page instead of falling back to legacy BMS', async () => {
    server.use(http.get('/api/v1/devices/by-sn/CMD08/realtime', () => HttpResponse.json({ code: 0, data: {
      online: true, realtime: { bms_summary: snapshot({ expires_at: new Date(NOW).toISOString() }), bms: { bms_online: 1, bms_soc: 99 } },
    } })))
    renderAsAdmin(<BmsTab sn="CMD08" />)
    await waitFor(() => expect(screen.getByTestId('cmd08-bms')).toHaveAttribute('data-availability', 'expired'))
    expect(within(screen.getByTestId('cmd08-bms')).getByRole('button', { name: 'C01' })).toHaveTextContent('--')
  })
  it('shows an intentional missing snapshot state and refresh action', async () => {
    server.use(http.get('/api/v1/devices/by-sn/CMD08/realtime', () => HttpResponse.json({ code: 0, data: { realtime: {} } })))
    renderAsAdmin(<BmsTab sn="CMD08" />)
    expect(await screen.findByText('未接入 BMS')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '刷新 BMS' })).not.toBeDisabled()
  })
})
