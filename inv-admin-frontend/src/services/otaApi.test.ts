import { describe, it, expect } from 'vitest'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { otaApi } from './otaApi'
import { mockFirmwares, mockUpgradeTasks, paginatedResponse } from '@/test/mocks/data'

describe('otaApi', () => {
  describe('Firmware Management', () => {
    it('listFirmware should return firmware list', async () => {
      const res = await otaApi.listFirmware({ page: 1 })
      const data = res.data?.data ?? res.data
      expect(data.items).toHaveLength(mockFirmwares.length)
    })

    it('getAllFirmware should request with large page_size', async () => {
      server.use(
        http.get('/api/v1/firmwares', ({ request }) => {
          const url = new URL(request.url)
          return HttpResponse.json({
            code: 0,
            data: {
              items: mockFirmwares,
              total: mockFirmwares.length,
              page_size: url.searchParams.get('page_size'),
            },
          })
        }),
      )

      const res = await otaApi.getAllFirmware()
      expect(res.data.data.page_size).toBe('9999')
    })

    it('deleteFirmware should delete by id', async () => {
      const res = await otaApi.deleteFirmware(301)
      expect(res.data.code).toBe(0)
    })

    it('uploadFirmware should post form data', async () => {
      server.use(
        http.post('/api/v1/firmwares', ({ request }) => {
          const contentType = request.headers.get('content-type') || ''
          return HttpResponse.json({
            code: 0,
            data: { isMultipart: contentType.includes('multipart') },
          })
        }),
      )

      const formData = new FormData()
      formData.append('file', new Blob(['test']), 'firmware.bin')
      formData.append('model', 'CS-5K')
      formData.append('version', '1.4.0')

      const res = await otaApi.uploadFirmware(formData)
      expect(res.data.code).toBe(0)
    })
  })

  describe('Upgrade Task Management', () => {
    it('listTasks should return task list', async () => {
      const res = await otaApi.listTasks({ page: 1 })
      const data = res.data?.data ?? res.data
      expect(data.items).toHaveLength(mockUpgradeTasks.length)
    })

    it('createTask should create a new upgrade task', async () => {
      server.use(
        http.post('/api/v1/ota/tasks', async ({ request }) => {
          const body = (await request.json()) as any
          return HttpResponse.json({
            code: 0,
            data: { id: 402, ...body },
          })
        }),
      )

      const res = await otaApi.createTask({
        task_type: 'single',
        firmware_id: 301,
        device_sns: ['INV20250001'],
        execute_mode: 'immediate',
      })
      expect(res.data.code).toBe(0)
      expect(res.data.data.device_sns).toContain('INV20250001')
    })

    it('cancelTask should cancel a running task', async () => {
      server.use(
        http.post('/api/v1/ota/tasks/:id/cancel', () => {
          return HttpResponse.json({ code: 0, message: 'cancelled' })
        }),
      )

      const res = await otaApi.cancelTask(401)
      expect(res.data.code).toBe(0)
    })

    it('getTaskStats should return task statistics', async () => {
      const res = await otaApi.getTaskStats()
      const data = res.data?.data ?? res.data
      expect(data.total).toBe(5)
      expect(data.running).toBe(1)
      expect(data.completed).toBe(3)
    })
  })

  describe('Upgrade Dashboard', () => {
    it('getUpgradeDashboard should return dashboard data', async () => {
      server.use(
        http.get('/api/v1/ota/upgrades/dashboard', () => {
          return HttpResponse.json({
            code: 0,
            data: { items: [], total: 0 },
          })
        }),
      )

      const res = await otaApi.getUpgradeDashboard()
      expect(res.data.code).toBe(0)
    })
  })

  describe('Package Management', () => {
    it('listPackages should return package list', async () => {
      server.use(
        http.get('/api/v1/ota/packages', () => {
          return HttpResponse.json({
            code: 0,
            data: { items: [], total: 0 },
          })
        }),
      )

      const res = await otaApi.listPackages()
      expect(res.data.code).toBe(0)
    })

    it('createPackage should create a new package', async () => {
      server.use(
        http.post('/api/v1/ota/packages', async ({ request }) => {
          const body = (await request.json()) as any
          return HttpResponse.json({
            code: 0,
            data: { id: 501, ...body },
          })
        }),
      )

      const res = await otaApi.createPackage({
        model: 'CS-5K',
        firmware_ids: [301],
        changelog: 'Test package',
      })
      expect(res.data.code).toBe(0)
    })
  })
})
