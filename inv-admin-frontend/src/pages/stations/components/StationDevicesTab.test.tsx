import { afterEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, screen, waitFor } from '@testing-library/react'
import { deviceApi } from '@/services/deviceApi'
import { renderAsAdmin } from '@/test/test-utils'
import StationDevicesTab from './StationDevicesTab'

describe('station device refresh', () => {
  afterEach(() => vi.restoreAllMocks())

  it('keeps genuine zero output and zero daily generation instead of using PV power or missing markers', async () => {
    vi.spyOn(deviceApi, 'getDevices').mockResolvedValue({
      data: { code: 0, data: { items: [{ id: '1', sn: 'ZERO-001', model: 'L10', status: 1 }] } },
    } as any)
    vi.spyOn(deviceApi, 'getRealtime').mockResolvedValue({
      data: { code: 0, data: { online: true, realtime: {
        ac_active_power: 0, pv_total_power: 1200, daily_pv: 0,
      } } },
    } as any)
    renderAsAdmin(<StationDevicesTab stationId={1} timezone="Asia/Shanghai" />)
    await screen.findByText('0 W')
    expect(screen.getByText('0.00 kWh')).toBeInTheDocument()
  })

  it('updates telemetry together with device cards on manual refresh', async () => {
    const getDevices = vi.spyOn(deviceApi, 'getDevices').mockResolvedValue({
      data: { code: 0, data: { items: [{ id: '1', sn: 'REFRESH-001', model: 'L10', status: 1 }] } },
    } as any)
    let power = 1200
    const getRealtime = vi.spyOn(deviceApi, 'getRealtime').mockImplementation(async () => ({
      data: { code: 0, data: { online: true, realtime: { output_power: power } } },
    } as any))
    renderAsAdmin(<StationDevicesTab stationId={1} timezone="Asia/Shanghai" />)
    await screen.findByText(/1200 W/)
    power = 2400
    fireEvent.click(screen.getByRole('button', { name: /刷新/ }))
    await screen.findByText(/2400 W/)
    await waitFor(() => {
      expect(getDevices).toHaveBeenCalledTimes(2)
      expect(getRealtime).toHaveBeenCalledTimes(2)
    })
  })
})
