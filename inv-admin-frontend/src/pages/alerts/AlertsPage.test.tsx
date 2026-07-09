import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderAsAdmin } from '@/test/test-utils'
import { mockAlerts, mockAlertStats, paginatedResponse } from '@/test/mocks/data'
import useAuthStore from '@/stores/authStore'
import AlertsPage from './index'

vi.mock('@/utils/timezone', () => ({
  formatInTimezone: (val: string) => val || '-',
}))

describe('AlertsPage', () => {
  beforeEach(() => {
    useAuthStore.getState().logout()
  })

  it('should render the alerts page', async () => {
    renderAsAdmin(<AlertsPage />)

    await waitFor(() => {
      expect(document.querySelector('.ant-typography')).toBeInTheDocument()
    })
  })

  it('should show alarm statistics cards', async () => {
    renderAsAdmin(<AlertsPage />)

    await waitFor(() => {
      // Statistics cards should be rendered
      const statCards = document.querySelectorAll('.ant-statistic')
      expect(statCards.length).toBeGreaterThan(0)
    })
  })

  it('should render alarm list with data', async () => {
    renderAsAdmin(<AlertsPage />)

    await waitFor(() => {
      expect(screen.getByText('INV20250001')).toBeInTheDocument()
    })
  })

  it('should show alarm status tags', async () => {
    renderAsAdmin(<AlertsPage />)

    await waitFor(() => {
      const tags = document.querySelectorAll('.ant-tag')
      expect(tags.length).toBeGreaterThan(0)
    })
  })

  it('should render filter controls', async () => {
    renderAsAdmin(<AlertsPage />)

    await waitFor(() => {
      const selects = document.querySelectorAll('.ant-select')
      expect(selects.length).toBeGreaterThan(0)
    })
  })

  it('should show tabs for all/alarm/notification', async () => {
    renderAsAdmin(<AlertsPage />)

    await waitFor(() => {
      const tabs = document.querySelectorAll('.ant-tabs-tab')
      expect(tabs.length).toBeGreaterThanOrEqual(3)
    })
  })

  it('should render refresh button', async () => {
    renderAsAdmin(<AlertsPage />)

    await waitFor(() => {
      const buttons = document.querySelectorAll('.ant-btn')
      const hasRefresh = Array.from(buttons).some(b => b.textContent?.includes('刷新'))
      expect(hasRefresh).toBe(true)
    })
  })

  it('should show clear all button', async () => {
    renderAsAdmin(<AlertsPage />)

    await waitFor(() => {
      const buttons = document.querySelectorAll('.ant-btn')
      const hasClear = Array.from(buttons).some(b => b.textContent?.includes('清除'))
      expect(hasClear).toBe(true)
    })
  })

  it('should handle empty alert list', async () => {
    server.use(
      http.get('/api/v1/alarms', () => {
        return HttpResponse.json({
          code: 0,
          data: paginatedResponse([], 0),
        })
      }),
    )

    renderAsAdmin(<AlertsPage />)

    await waitFor(() => {
      const empty = document.querySelector('.ant-empty')
      expect(empty).toBeInTheDocument()
    })
  })

  it('should show notification statistics', async () => {
    renderAsAdmin(<AlertsPage />)

    await waitFor(() => {
      // Notification stat should be visible
      const stats = document.querySelectorAll('.ant-statistic-content-value')
      expect(stats.length).toBeGreaterThan(0)
    })
  })

  it('should display fault messages in the table', async () => {
    renderAsAdmin(<AlertsPage />)

    await waitFor(() => {
      expect(screen.getByText('逆变器温度过高')).toBeInTheDocument()
    })
  })
})
