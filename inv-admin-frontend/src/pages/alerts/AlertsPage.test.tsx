import { describe, it, expect, vi, beforeEach } from 'vitest'
import { fireEvent, screen, waitFor } from '@testing-library/react'
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

  it('loads selected event detail and renders telemetry or missing snapshots', async () => {
    server.use(
      http.get('/api/v1/devices/:sn/alarm-events', () => HttpResponse.json({
        code: 0,
        message: 'success',
        data: {
          items: [{ id: 41, device_sn: 'INV20250001', source: 1, code: 'ALM8', level: 2, state: 'active', event_time: '2026-07-14T10:00:00Z', received_at: '2026-07-14T10:00:01Z', data_hash: 'hash-41' }],
          total: 1, page: 1, page_size: 200,
        },
      })),
      http.get('/api/v1/alarm-events/41', () => HttpResponse.json({
        code: 0,
        message: 'success',
        data: {
          id: 41, device_sn: 'INV20250001', source: 1, code: 'ALM8', level: 2, state: 'active', topic: 'alarm',
          event_time: '2026-07-14T10:00:00Z', t: 1784023200, received_at: '2026-07-14T10:00:01Z', created_at: '2026-07-14T10:00:01Z', data_hash: 'hash-41', raw_envelope: {},
          snapshots: [
            { id: 91, device_sn: 'INV20250001', alarm_event_id: 41, snapshot_type: 'before', ac_voltage: 220.5, ac_current: 3.2, ac_active_power: 705.6, ac_frequency: 50, battery_soc: 80, battery_voltage: 51.2, battery_current: 2, battery_temperature: 25, internal_temperature: 40, dc_bus_voltage: 380, work_state: 1, fault_code: 8, raw_snapshot: {}, captured_at: '2026-07-14T10:00:00Z' },
            { id: 92, device_sn: 'INV20250001', alarm_event_id: 41, snapshot_type: 'after', raw_snapshot: { missing: true, reason: 'device_latest_state_not_found' }, captured_at: '2026-07-14T10:00:02Z' },
          ],
        },
      })),
    )

    renderAsAdmin(<AlertsPage />)
    const traceButton = await screen.findAllByText('事件追溯')
    fireEvent.click(traceButton[0])
    const eventCode = await screen.findByText('ALM8')
    fireEvent.click(eventCode.closest('tr')!)

    expect(await screen.findByText('220.5 V')).toBeInTheDocument()
    expect(screen.getByText('device_latest_state_not_found')).toBeInTheDocument()
  })

  it('shows alarm event detail access errors', async () => {
    server.use(
      http.get('/api/v1/devices/:sn/alarm-events', () => HttpResponse.json({
        code: 0, message: 'success',
        data: { items: [{ id: 41, device_sn: 'INV20250001', source: 1, code: 'ALM8', level: 2, state: 'active', event_time: '2026-07-14T10:00:00Z', received_at: '2026-07-14T10:00:01Z', data_hash: 'hash-41' }], total: 1, page: 1, page_size: 200 },
      })),
      http.get('/api/v1/alarm-events/41', () => HttpResponse.json({ code: 403, message: 'device access denied' }, { status: 403 })),
    )

    renderAsAdmin(<AlertsPage />)
    fireEvent.click((await screen.findAllByText('事件追溯'))[0])
    fireEvent.click((await screen.findByText('ALM8')).closest('tr')!)
    expect(await screen.findByText(/无权访问该设备/)).toBeInTheDocument()
  })
})
