import { describe, it, expect } from 'vitest'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { deviceApi } from './deviceApi'
import { mockDevices, paginatedResponse } from '@/test/mocks/data'

describe('deviceApi', () => {
  describe('getDevices', () => {
    it('should fetch device list with pagination', async () => {
      const res = await deviceApi.getDevices({ page: 1, pageSize: 20 })
      const data = res.data?.data ?? res.data
      expect(data.items).toHaveLength(mockDevices.length)
      expect(data.total).toBe(mockDevices.length)
    })

    it('should pass query parameters correctly', async () => {
      server.use(
        http.get('/api/v1/devices', ({ request }) => {
          const url = new URL(request.url)
          const keyword = url.searchParams.get('keyword')
          const status = url.searchParams.get('status')
          return HttpResponse.json({
            code: 0,
            data: paginatedResponse(
              mockDevices.filter((d) => d.status === status),
              1,
            ),
          })
        }),
      )

      const res = await deviceApi.getDevices({ keyword: 'INV', status: 'online' })
      const data = res.data?.data ?? res.data
      expect(data.items).toHaveLength(1)
      expect(data.items[0].status).toBe('online')
    })
  })

  describe('getDeviceBySn', () => {
    it('should fetch device by SN', async () => {
      const res = await deviceApi.getDeviceBySn('INV20250001')
      const data = res.data?.data ?? res.data
      expect(data.sn).toBe('INV20250001')
      expect(data.model).toBe('SG-5K-D')
    })

    it('should return 404 for non-existent SN', async () => {
      try {
        await deviceApi.getDeviceBySn('NONEXIST')
        expect.fail('should have thrown')
      } catch (err: any) {
        expect(err.response?.status).toBe(404)
      }
    })
  })

  describe('createDevice', () => {
    it('should create a new device', async () => {
      const res = await deviceApi.createDevice({
        sn: 'INV20250010',
        model: 'CS-5K',
        ratedPower: 5,
      })
      expect(res.data.code).toBe(0)
    })
  })

  describe('updateDevice', () => {
    it('should update device by SN', async () => {
      const res = await deviceApi.updateDevice('INV20250001', {
        model: 'CS-10K',
      })
      expect(res.data.code).toBe(0)
    })
  })

  describe('deleteDevice', () => {
    it('should delete device by SN', async () => {
      const res = await deviceApi.deleteDevice('INV20250001')
      expect(res.data.code).toBe(0)
    })
  })

  describe('getRealtime', () => {
    it('should fetch realtime telemetry data', async () => {
      const res = await deviceApi.getRealtime('INV20250001')
      const data = res.data?.data ?? res.data
      expect(data.ac).toBeDefined()
      expect(data.ac.voltage).toBe(220)
      expect(data.pv).toBeDefined()
      expect(data.battery).toBeDefined()
      expect(data.battery.soc).toBe(80)
      expect(data.online).toBeDefined()
    })
  })

  describe('getTelemetry', () => {
    it('should fetch telemetry history', async () => {
      const res = await deviceApi.getTelemetry('INV20250001', {
        startTime: '2026-07-01',
        endTime: '2026-07-02',
      })
      expect(res.data.code).toBe(0)
    })
  })

  describe('sendCommand', () => {
    it('should send control command to device', async () => {
      server.use(
        http.post('/api/v1/devices/:sn/control', async ({ request }) => {
          const body = (await request.json()) as any
          return HttpResponse.json({
            code: 0,
            data: { commandId: 1, status: 'queued', command: body.command },
          })
        }),
      )

      const res = await deviceApi.sendCommand('INV20250001', {
        command: 'set_power_limit',
        params: { value: 80 },
      })
      expect(res.data.code).toBe(0)
      expect(res.data.data.status).toBe('queued')
    })
  })

  describe('unbindDevice', () => {
    it('should unbind device', async () => {
      server.use(
        http.post('/api/v1/devices/:sn/unbind', () => {
          return HttpResponse.json({ code: 0, message: 'unbound' })
        }),
      )

      const res = await deviceApi.unbindDevice('INV20250001')
      expect(res.data.code).toBe(0)
    })
  })

  describe('getAll', () => {
    it('should fetch all devices with pageSize 200', async () => {
      server.use(
        http.get('/api/v1/devices', ({ request }) => {
          const url = new URL(request.url)
          const pageSize = url.searchParams.get('pageSize')
          return HttpResponse.json({
            code: 0,
            data: { items: mockDevices, total: mockDevices.length, requestedPageSize: pageSize },
          })
        }),
      )

      const res = await deviceApi.getAll()
      const data = res.data?.data ?? res.data
      expect(data.requestedPageSize).toBe('200')
    })
  })

  describe('batchAssignInstaller', () => {
    it('should batch assign installer to multiple devices', async () => {
      server.use(
        http.post('/api/v1/devices/batch-assign-installer', async ({ request }) => {
          const body = (await request.json()) as any
          return HttpResponse.json({
            code: 0,
            data: { updated: body.deviceSns.length },
          })
        }),
      )

      const res = await deviceApi.batchAssignInstaller(['INV20250001', 'INV20250002'], 3)
      expect(res.data.code).toBe(0)
    })
  })
})
