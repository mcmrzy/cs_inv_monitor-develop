import { fireEvent, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { renderWithProviders } from '@/test/test-utils'
import ModbusPanelOverview, { isModbusPanelDevice } from './ModbusPanelOverview'

const mocks = vi.hoisted(() => ({ realtime: vi.fn() }))
vi.mock('@/services/deviceApi', () => ({ deviceApi: { getRealtime: mocks.realtime } }))

describe('Modbus panel parameter overview', () => {
  it('recognizes supported inverter codes and the panel firmware', () => {
    for (const model of ['PWR2KH12H1', '3KU', '6KU', '12KU']) {
      expect(isModbusPanelDevice({ reported_model: model })).toBe(true)
    }
    expect(isModbusPanelDevice({ firmware_esp: '0.4.34-modbus-full' })).toBe(true)
    expect(isModbusPanelDevice({ model: 'CS-L10-6K2' })).toBe(false)
  })

  it('preserves zero, shows missing readings, and links settings to this SN', async () => {
    mocks.realtime.mockResolvedValue({ data: { data: {
      online: true, data_time: new Date().toISOString(),
      realtime: { pv_total_power: 0, output_power: 1250, battery_soc: 72 },
    } } })
    renderWithProviders(<ModbusPanelOverview sn="PANEL-3KU" />)

    expect(await screen.findByText('云端实时')).toBeInTheDocument()
    expect(screen.getByText('0 W')).toBeInTheDocument()
    expect(screen.getAllByText('—').length).toBeGreaterThan(0)
    expect(screen.getByRole('link', { name: /远程设置/ }))
      .toHaveAttribute('href', '/remote-settings?sn=PANEL-3KU')
    fireEvent.click(screen.getByRole('button', { name: /蓝牙设置/ }))
    expect(screen.getByText('在手机 App 上连接设备')).toBeInTheDocument()
  })

  it('labels offline cached measurements as last samples', async () => {
    mocks.realtime.mockResolvedValue({ data: { data: {
      online: false, data_time: new Date().toISOString(),
      realtime: { pv_total_power: 1860 },
    } } })
    renderWithProviders(<ModbusPanelOverview sn="PANEL-OFFLINE" />)
    expect(await screen.findByText('云端上次采样')).toBeInTheDocument()
    expect(screen.queryByText('云端实时')).not.toBeInTheDocument()
  })
})
