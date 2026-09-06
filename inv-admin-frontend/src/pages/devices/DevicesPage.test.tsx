import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { renderAsAdmin } from '@/test/test-utils'
import DevicesPage from './index'

describe('DevicesPage', () => {
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
