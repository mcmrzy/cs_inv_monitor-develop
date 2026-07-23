import { describe, expect, it } from 'vitest'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { commandApi } from './commandApi'

describe('commandApi contracts', () => {
  it('loads executable templates from control capabilities', async () => {
    server.use(
      http.get('/api/v1/devices/by-sn/:sn/control-capabilities', ({ params }) =>
        HttpResponse.json({
          code: 0,
          data: [{
            command_code: 'restart',
            display_name: 'Restart',
            parameter_schema: { args: [] },
            risk_level: 3,
            requires_online: true,
            is_enabled: true,
            sn: params.sn,
          }],
        }),
      ),
    )

    const response = await commandApi.getTemplates('INV-001')
    expect(response.data.data[0]).toMatchObject({ command_code: 'restart', sn: 'INV-001' })
  })

  it('loads command history from the paginated history endpoint', async () => {
    server.use(
      http.get('/api/v1/devices/by-sn/:sn/commands/history', () =>
        HttpResponse.json({
          code: 0,
          data: { items: [{ id: 1, command_name: 'restart' }], total: 1 },
        }),
      ),
    )

    const response = await commandApi.getHistory('INV-001', { page: 1, page_size: 20 })
    expect(response.data.data.items).toHaveLength(1)
    expect(response.data.data.total).toBe(1)
  })
})
