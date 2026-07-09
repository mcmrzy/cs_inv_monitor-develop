import { describe, it, expect } from 'vitest'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { alertApi, notificationApi } from './alertApi'
import { mockAlerts, mockAlertStats, paginatedResponse } from '@/test/mocks/data'

describe('alertApi', () => {
  describe('list', () => {
    it('should fetch alarm list', async () => {
      const res = await alertApi.list({ page: 1 })
      const data = res.data?.data ?? res.data
      expect(data.items).toHaveLength(mockAlerts.length)
    })

    it('should filter by status', async () => {
      server.use(
        http.get('/api/v1/alarms', ({ request }) => {
          const url = new URL(request.url)
          const status = url.searchParams.get('status')
          const filtered = mockAlerts.filter((a) => Number(a.status) === Number(status))
          return HttpResponse.json({
            code: 0,
            data: paginatedResponse(filtered, filtered.length),
          })
        }),
      )

      const res = await alertApi.list({ status: 0 })
      const data = res.data?.data ?? res.data
      expect(data.items.length).toBeGreaterThan(0)
    })
  })

  describe('getStats', () => {
    it('should fetch alarm statistics', async () => {
      const res = await alertApi.getStats()
      const data = res.data?.data ?? res.data
      expect(data.total).toBe(mockAlertStats.total)
      expect(data.unhandled).toBe(mockAlertStats.unhandled)
      expect(data.handled).toBe(mockAlertStats.handled)
      expect(data.critical).toBe(mockAlertStats.critical)
    })
  })

  describe('handle (acknowledge)', () => {
    it('should acknowledge an alarm', async () => {
      const res = await alertApi.handle(201)
      expect(res.data.code).toBe(0)
    })
  })

  describe('ignore', () => {
    it('should ignore an alarm', async () => {
      const res = await alertApi.ignore(201)
      expect(res.data.code).toBe(0)
    })
  })

  describe('delete', () => {
    it('should delete an alarm', async () => {
      const res = await alertApi.delete(201)
      expect(res.data.code).toBe(0)
    })
  })

  describe('clearAll', () => {
    it('should clear all alarms', async () => {
      const res = await alertApi.clearAll()
      expect(res.data.code).toBe(0)
    })
  })
})

describe('notificationApi', () => {
  describe('list', () => {
    it('should fetch notification list', async () => {
      const res = await notificationApi.list({ page: 1 })
      const data = res.data?.data ?? res.data
      expect(data.items).toBeDefined()
    })
  })

  describe('getStats', () => {
    it('should fetch notification stats', async () => {
      const res = await notificationApi.getStats()
      const data = res.data?.data ?? res.data
      expect(data.total).toBe(3)
      expect(data.unread).toBe(1)
    })
  })

  describe('delete', () => {
    it('should delete a notification', async () => {
      server.use(
        http.delete('/api/v1/notifications/:id', () => {
          return HttpResponse.json({ code: 0, message: 'deleted' })
        }),
      )
      const res = await notificationApi.delete(1)
      expect(res.data.code).toBe(0)
    })
  })

  describe('clearAll', () => {
    it('should clear all notifications', async () => {
      server.use(
        http.delete('/api/v1/notifications/clear', () => {
          return HttpResponse.json({ code: 0, message: 'cleared' })
        }),
      )
      const res = await notificationApi.clearAll()
      expect(res.data.code).toBe(0)
    })
  })
})
