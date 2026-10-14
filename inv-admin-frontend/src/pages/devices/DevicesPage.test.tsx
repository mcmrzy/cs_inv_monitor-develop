import { afterEach, describe, it, expect, vi } from 'vitest'
import { screen, waitFor, within } from '@testing-library/react'
import { renderAsAdmin } from '@/test/test-utils'
import { deviceApi } from '@/services/deviceApi'
import DevicesPage from './index'
import { buildBatchOtaDeepLink } from './index'

describe('DevicesPage', () => {
  afterEach(() => vi.restoreAllMocks())

  it('shows the current owner and distinguishes unbound devices from owners without a nickname', async () => {
    vi.spyOn(deviceApi, 'getDevices').mockResolvedValue({
      data: { code: 0, data: { items: [
        { sn: 'OWNER-NAMED', user_id: 41, owner: { nickname: '屋顶电站用户', phone: '13800000041' } },
        { sn: 'OWNER-PHONE', user_id: 42, owner: { nickname: '', phone: '13800000042' } },
        { sn: 'OWNER-ID', user_id: 43, owner: null },
        { sn: 'OWNER-UNBOUND', user_id: 0, owner: null },
      ], total: 4 } },
    } as any)
    renderAsAdmin(<DevicesPage />)

    await screen.findByText('OWNER-NAMED')
    expect(screen.getByRole('columnheader', { name: '当前归属人' })).toBeInTheDocument()
    for (const [sn, label] of [
      ['OWNER-NAMED', '屋顶电站用户'],
      ['OWNER-PHONE', '13800000042'],
      ['OWNER-ID', '用户 #43'],
      ['OWNER-UNBOUND', '未绑定'],
    ]) {
      const row = screen.getByText(sn).closest('tr')!
      expect(within(row).getByText(label)).toBeInTheDocument()
    }
  })

  it('builds batch OTA deep links that preserve the tasks tab', () => {
    expect(buildBatchOtaDeepLink(['INV20250001', 'INV/2'])).toBe(
      '/ota?tab=tasks&create=1&sns=INV20250001%2CINV%2F2',
    )
  })
  it('renders device table rows from the device list API', async () => {
    renderAsAdmin(<DevicesPage />)

    // MSW /devices 返回 mockDevices（INV20250001/2/3）
    expect(await screen.findByText('INV20250001')).toBeInTheDocument()
    await waitFor(() => {
      expect(screen.getByText('INV20250002')).toBeInTheDocument()
    })
  })

  it('renders toolbar actions', async () => {
    renderAsAdmin(<DevicesPage />)

    expect(await screen.findByText('添加设备')).toBeInTheDocument()
    expect(screen.getByText('绑定设备')).toBeInTheDocument()
  })

  it('renders search form controls', async () => {
    renderAsAdmin(<DevicesPage />)

    await waitFor(() => {
      expect(document.querySelectorAll('.ant-select').length).toBeGreaterThan(0)
    })
  })

  it('renders device status tags', async () => {
    renderAsAdmin(<DevicesPage />)

    await waitFor(() => {
      expect(document.querySelectorAll('.ant-tag').length).toBeGreaterThan(0)
    })
  })
})
