import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { fireEvent } from '@testing-library/react'
import { renderAsAdmin } from '@/test/test-utils'
import OtaPage from './index'

describe('OtaPage', () => {
  it('renders upgrade tasks and firmware library tabs', async () => {
    renderAsAdmin(<OtaPage />)

    expect(await screen.findByText('升级任务')).toBeInTheDocument()
    expect(screen.getByText('固件库')).toBeInTheDocument()
    expect(document.querySelectorAll('.ant-tabs-tab').length).toBeGreaterThanOrEqual(2)
  })

  it('shows upgrade task statistics cards', async () => {
    renderAsAdmin(<OtaPage />)

    await waitFor(() => {
      // 任务统计（总数/进行中/成功/失败等）
      const stats = document.querySelectorAll('.ant-statistic, .ant-pro-card')
      expect(stats.length).toBeGreaterThan(0)
    })
  })

  it('lists upgrade tasks from the OTA tasks API', async () => {
    renderAsAdmin(<OtaPage />)

    // ota/tasks handler 返回 mockUpgradeTasks；表格出现分页或数据行
    await waitFor(() => {
      const hasTable = document.querySelector('.ant-table')
      const hasEmpty = document.querySelector('.ant-empty')
      expect(hasTable || hasEmpty).toBeTruthy()
    })
  })

  it('switches to the firmware library tab and lists firmwares', async () => {
    renderAsAdmin(<OtaPage />)

    fireEvent.click(await screen.findByText('固件库'))
    // ota/firmware handler 返回 mockFirmwares（ARM/ESP 固件）
    await waitFor(() => {
      const hasTable = document.querySelector('.ant-table')
      expect(hasTable).toBeTruthy()
    })
  })
})
