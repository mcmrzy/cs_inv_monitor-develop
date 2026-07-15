import { describe, expect, it } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderAsAdmin } from '@/test/test-utils'
import ParallelPage from './index'

describe('ParallelPage', () => {
  it('distinguishes a reported disabled state from missing data', async () => {
    server.use(http.get('/api/v1/devices/:sn/parallel-state', ({ params }) => HttpResponse.json({
      code: 0,
      message: 'success',
      data: {
        has_parallel: false,
        enabled: false,
        station_id: 12,
        master_sn: params.sn,
        mode: 'standalone',
        count: 0,
        sync_state: 'idle',
        machines: [],
        reported_at: '2026-07-14T10:00:00Z',
      },
    })))

    renderAsAdmin(<ParallelPage />)
    await waitFor(() => expect(screen.getByText('并机功能未启用')).toBeInTheDocument())
    expect(screen.queryByText('设备尚未上报并机状态')).not.toBeInTheDocument()
  })

  it('shows access errors instead of an empty state', async () => {
    server.use(http.get('/api/v1/devices/:sn/parallel-state', () =>
      HttpResponse.json({ code: 403, message: 'device access denied' }, { status: 403 }),
    ))

    renderAsAdmin(<ParallelPage />)
    await waitFor(() => expect(screen.getByText(/无权访问该设备/)).toBeInTheDocument())
    expect(screen.queryByText('设备尚未上报并机状态')).not.toBeInTheDocument()
  })
})
