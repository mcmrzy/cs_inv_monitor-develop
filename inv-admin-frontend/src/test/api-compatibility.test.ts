import { describe, it, expect } from 'vitest'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { otaApi } from '@/services/otaApi'
import { channelApi } from '@/services/channelApi'
import { deviceApi } from '@/services/deviceApi'
import { userApi } from '@/services/userApi'
import { alertApi } from '@/services/alertApi'
import { workOrderApi } from '@/services/workOrderApi'

describe('API Compatibility Tests', () => {
  describe('OTA Firmware Management - Path Verification', () => {
    it('listFirmware should call /ota/firmware', async () => {
      let requestPath = ''
      server.use(
        http.get('/api/v1/ota/firmware', ({ request }) => {
          requestPath = new URL(request.url).pathname
          return HttpResponse.json({ code: 0, data: [] })
        }),
      )
      await otaApi.listFirmware()
      expect(requestPath).toBe('/api/v1/ota/firmware')
    })

    it('deleteFirmware should call /ota/firmware/:id', async () => {
      let requestPath = ''
      server.use(
        http.delete('/api/v1/ota/firmware/:id', ({ request, params }) => {
          requestPath = `/api/v1/ota/firmware/${params.id}`
          return HttpResponse.json({ code: 0, message: 'deleted' })
        }),
      )
      await otaApi.deleteFirmware(301)
      expect(requestPath).toBe('/api/v1/ota/firmware/301')
    })
  })

  describe('Organization Member Management - Path Verification', () => {
    it('removeMember should call /members/memberships/:id/remove', async () => {
      let requestPath = ''
      server.use(
        http.delete('/api/v1/members/memberships/:id/remove', ({ params }) => {
          requestPath = `/api/v1/members/memberships/${params.id}/remove`
          return HttpResponse.json({ code: 0, message: 'removed' })
        }),
      )
      await channelApi.removeMember(1)
      expect(requestPath).toBe('/api/v1/members/memberships/1/remove')
    })

    it('updateMemberRole should call /members/memberships/:id/role', async () => {
      let requestPath = ''
      server.use(
        http.put('/api/v1/members/memberships/:id/role', ({ params }) => {
          requestPath = `/api/v1/members/memberships/${params.id}/role`
          return HttpResponse.json({ code: 0, message: 'updated' })
        }),
      )
      await channelApi.updateMemberRole(1, 'admin')
      expect(requestPath).toBe('/api/v1/members/memberships/1/role')
    })

    it('reactivateMember should call PATCH /members/memberships/:id/reactivate', async () => {
      let requestMethod = ''
      let requestPath = ''
      server.use(
        http.patch('/api/v1/members/memberships/:id/reactivate', ({ request, params }) => {
          requestMethod = request.method
          requestPath = `/api/v1/members/memberships/${params.id}/reactivate`
          return HttpResponse.json({ code: 0, data: { status: 'active' } })
        }),
      )
      await channelApi.reactivateMember(2)
      expect(requestMethod).toBe('PATCH')
      expect(requestPath).toBe('/api/v1/members/memberships/2/reactivate')
    })
  })

  describe('Organization Status Toggle - Method Verification', () => {
    it('toggleOrganization should use PATCH method', async () => {
      let requestMethod = ''
      server.use(
        http.patch('/api/v1/organizations/:id/status', ({ request }) => {
          requestMethod = request.method
          return HttpResponse.json({ code: 0, data: { status: 'disabled' } })
        }),
      )
      await channelApi.toggleOrganization(1)
      expect(requestMethod).toBe('PATCH')
    })
  })

  describe('Other API Functions - Regression Tests', () => {
    it('deviceApi should work correctly', async () => {
      server.use(
        http.get('/api/v1/devices', () => {
          return HttpResponse.json({
            code: 0,
            data: { items: [{ sn: 'INV001' }], total: 1, page: 1, page_size: 20 },
          })
        }),
      )
      const res = await deviceApi.getDevices({ page: 1 })
      expect(res.data.code).toBe(0)
    })

    it('userApi should work correctly', async () => {
      server.use(
        http.get('/api/v1/users', () => {
          return HttpResponse.json({
            code: 0,
            data: { items: [{ id: 1, email: 'test@test.com' }], total: 1, page: 1, page_size: 20 },
          })
        }),
      )
      const res = await userApi.list({ page: 1 })
      expect(res.data.code).toBe(0)
    })

    it('alertApi should work correctly', async () => {
      server.use(
        http.get('/api/v1/alarms', () => {
          return HttpResponse.json({
            code: 0,
            data: { items: [{ id: 1, level: 'warning' }], total: 1, page: 1, page_size: 20 },
          })
        }),
      )
      const res = await alertApi.list({ page: 1 })
      expect(res.data.code).toBe(0)
    })

    it('workOrderApi should work correctly', async () => {
      server.use(
        http.get('/api/v1/work-orders', () => {
          return HttpResponse.json({
            code: 0,
            data: { items: [{ id: '1', title: 'Test' }], total: 1, page: 1, page_size: 20 },
          })
        }),
      )
      const res = await workOrderApi.list({ page: 1 })
      expect(res.data.code).toBe(0)
    })
  })
})
