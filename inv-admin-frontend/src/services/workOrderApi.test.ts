import { describe, expect, it } from 'vitest'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { allowedWorkOrderStatuses, canMutateWorkOrder, workOrderApi } from './workOrderApi'

describe('workOrderApi business contract', () => {
  it('only exposes legal next states', () => {
    expect(allowedWorkOrderStatuses('open')).toEqual(['in_progress', 'closed'])
    expect(allowedWorkOrderStatuses('in_progress')).toEqual(['open', 'resolved', 'closed'])
    expect(allowedWorkOrderStatuses('resolved')).toEqual(['in_progress', 'closed'])
    expect(allowedWorkOrderStatuses('closed')).toEqual([])
  })

  it('matches installer and end-user operational ownership', () => {
    expect(canMutateWorkOrder('4', 4, { creatorId: 9, assigneeId: 4 })).toBe(true)
    expect(canMutateWorkOrder('4', 4, { creatorId: 9, assigneeId: 8 })).toBe(false)
    expect(canMutateWorkOrder('5', 5, { creatorId: 5, assigneeId: 4 })).toBe(true)
    expect(canMutateWorkOrder('5', 5, { creatorId: 9, assigneeId: 4 })).toBe(false)
  })

  it('sends optimistic version and idempotency key for a status command', async () => {
    let body: Record<string, unknown> = {}
    let idempotencyKey = ''
    server.use(http.patch('/api/v1/work-orders/:id/status', async ({ request }) => {
      body = await request.json() as Record<string, unknown>
      idempotencyKey = request.headers.get('Idempotency-Key') ?? ''
      return HttpResponse.json({ code: 0, data: { id: '7' } })
    }))

    await workOrderApi.updateStatus('7', 'in_progress', 3, 'status-7-v3')

    expect(body).toEqual({ status: 'in_progress', expectedVersion: 3 })
    expect(idempotencyKey).toBe('status-7-v3')
  })

  it('downloads an attachment through an internal identifier-only path', async () => {
    let requestedPath = ''
    server.use(http.get('/api/v1/work-orders/:orderId/attachments/:attachmentId', ({ request }) => {
      requestedPath = new URL(request.url).pathname
      return new HttpResponse(new Blob(['image']), { status: 200, headers: { 'Content-Type': 'image/png' } })
    }))

    await workOrderApi.downloadAttachment('7', '9')

    expect(requestedPath).toBe('/api/v1/work-orders/7/attachments/9')
  })
})
