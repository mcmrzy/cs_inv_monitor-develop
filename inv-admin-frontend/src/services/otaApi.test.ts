import { describe, it, expect } from 'vitest'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import {
  otaApi,
  serializeUpgradeHistoryParams,
  createOtaIdempotencyKey,
} from './otaApi'
import { mockFirmwares, mockUpgradeTasks } from '@/test/mocks/data'

describe('otaApi', () => {
  describe('Firmware Management', () => {
    it('listFirmware should return firmware list', async () => {
      const res = await otaApi.listFirmware({ page: 1 })
      const data = res.data?.data ?? res.data
      expect(data).toHaveLength(mockFirmwares.length)
    })

    it('getAllFirmware should request with large page_size', async () => {
      let requestedPageSize: string | null = null
      server.use(
        http.get('/api/v1/ota/firmware', ({ request }) => {
          const url = new URL(request.url)
          requestedPageSize = url.searchParams.get('page_size')
          return HttpResponse.json({
            code: 0,
            data: mockFirmwares,
          })
        }),
      )

      await otaApi.getAllFirmware()
      expect(requestedPageSize).toBe('9999')
    })

    it('deleteFirmware should delete by id', async () => {
      const res = await otaApi.deleteFirmware(301)
      expect(res.data.code).toBe(0)
    })

    it('publishFirmware should post publish endpoint', async () => {
      server.use(
        http.post('/api/v1/ota/firmware/301/publish', () =>
          HttpResponse.json({ code: 0, message: 'success', data: { release_status: 'published' } }),
        ),
      )
      const res = await otaApi.publishFirmware(301)
      expect(res.data.code).toBe(0)
      expect(res.data.data.release_status).toBe('published')
    })

    it('disableFirmware should post disable endpoint', async () => {
      server.use(
        http.post('/api/v1/ota/firmware/301/disable', () =>
          HttpResponse.json({ code: 0, message: 'success', data: { release_status: 'disabled' } }),
        ),
      )
      const res = await otaApi.disableFirmware(301)
      expect(res.data.code).toBe(0)
      expect(res.data.data.release_status).toBe('disabled')
    })

    it('uploadFirmware should post form data', async () => {
      server.use(
        http.post('/api/v1/ota/firmware', ({ request }) => {
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

  describe('Independent module firmware APIs', () => {
    it('getFirmwareOverview requests device overview', async () => {
      server.use(
        http.get('/api/v1/ota/devices/INV20250001/firmware-overview', () =>
          HttpResponse.json({
            code: 0,
            data: {
              device_sn: 'INV20250001',
              device_model: 'SG-5K-D',
              is_online: true,
              modules: [
                {
                  target: 'arm',
                  current_version: '1.0.0',
                  latest_firmware_id: 301,
                  latest_version: '1.1.0',
                  version_state: 'outdated',
                  update_available: true,
                  changelog: 'fix',
                  published_at: '2026-01-01T00:00:00Z',
                },
              ],
            },
          }),
        ),
      )

      const res = await otaApi.getFirmwareOverview('INV20250001')
      const data = res.data?.data ?? res.data
      expect(data.modules[0].target).toBe('arm')
      expect(data.modules[0].update_available).toBe(true)
    })

    it('getFirmwareResources accepts the backend array envelope and serializes target_chip', async () => {
      let requestedChip: string | null = null
      server.use(
        http.get('/api/v1/ota/devices/INV20250001/firmware-resources', ({ request }) => {
          requestedChip = new URL(request.url).searchParams.get('target_chip')
          return HttpResponse.json({
            code: 0,
            data: [
              { id: 301, model: 'SG-5K-D', target_chip: 'arm', version: '1.1.0' },
            ],
          })
        }),
      )

      const res = await otaApi.getFirmwareResources('INV20250001', 'arm')
      expect(requestedChip).toBe('arm')
      expect(res.data.data).toEqual([
        { id: 301, model: 'SG-5K-D', target_chip: 'arm', version: '1.1.0' },
      ])
    })

    it('triggerFirmwareUpgrade posts device_sn + firmware_ids + idempotency_key', async () => {
      let body: any = null
      server.use(
        http.post('/api/v1/ota/trigger', async ({ request }) => {
          body = await request.json()
          return HttpResponse.json({
            code: 0,
            data: [{ task_id: 1, firmware_id: 301, target_chip: 'arm', version: '1.1.0', status: 'pending' }],
          })
        }),
      )

      const res = await otaApi.triggerFirmwareUpgrade({
        device_sn: 'INV20250001',
        firmware_ids: [301],
        idempotency_key: 'trigger-abc',
        force_reason: 'manual',
      })
      expect(res.data.code).toBe(0)
      expect(body.device_sn).toBe('INV20250001')
      expect(body.firmware_ids).toEqual([301])
      expect(body.idempotency_key).toBe('trigger-abc')
      expect(body.force_reason).toBe('manual')
    })

    it('rollbackFirmware posts firmware rollback payload', async () => {
      let body: any = null
      server.use(
        http.post('/api/v1/ota/firmware/rollback', async ({ request }) => {
          body = await request.json()
          return HttpResponse.json({ code: 0, data: [] })
        }),
      )

      const res = await otaApi.rollbackFirmware({
        device_sn: 'INV20250001',
        firmware_id: 301,
        idempotency_key: 'rollback-xyz',
      })
      expect(res.data.code).toBe(0)
      expect(body.device_sn).toBe('INV20250001')
      expect(body.firmware_id).toBe(301)
      expect(body.idempotency_key).toBe('rollback-xyz')
    })
  })

  describe('History filter serialization at API layer', () => {
    it('serializeUpgradeHistoryParams omits empty values', () => {
      expect(serializeUpgradeHistoryParams()).toEqual({})
      expect(
        serializeUpgradeHistoryParams({
          device_sn: '',
          target_chip: 'arm',
          status: '',
          start_time: undefined,
          end_time: '2026-01-02T00:00:00Z',
          page: 2,
          page_size: 20,
        }),
      ).toEqual({
        target_chip: 'arm',
        end_time: '2026-01-02T00:00:00Z',
        page: 2,
        page_size: 20,
      })
    })

    it('getDeviceUpgradeHistory serializes filters into query string', async () => {
      let requested: URLSearchParams | null = null
      server.use(
        http.get('/api/v1/ota/devices/INV20250001/history', ({ request }) => {
          requested = new URL(request.url).searchParams
          return HttpResponse.json({ code: 0, data: { items: [], total: 0 } })
        }),
      )

      await otaApi.getDeviceUpgradeHistory('INV20250001', {
        target_chip: 'esp',
        status: 'failed',
        start_time: '2026-01-01T00:00:00Z',
        end_time: '2026-01-02T00:00:00Z',
        page: 3,
        page_size: 15,
      })

      expect(requested).not.toBeNull()
      expect(requested!.get('target_chip')).toBe('esp')
      expect(requested!.get('status')).toBe('failed')
      expect(requested!.get('start_time')).toBe('2026-01-01T00:00:00Z')
      expect(requested!.get('end_time')).toBe('2026-01-02T00:00:00Z')
      expect(requested!.get('page')).toBe('3')
      expect(requested!.get('page_size')).toBe('15')
      expect(requested!.get('device_sn')).toBeNull()
    })

    it('listUpgradeHistory hits aggregated history endpoint', async () => {
      let requested: URLSearchParams | null = null
      server.use(
        http.get('/api/v1/ota/history', ({ request }) => {
          requested = new URL(request.url).searchParams
          return HttpResponse.json({ code: 0, data: { items: [], total: 0 } })
        }),
      )

      const res = await otaApi.listUpgradeHistory({
        device_sn: 'INV20250001',
        status: 'success',
        page: 1,
        page_size: 10,
      })
      expect(res.data.code).toBe(0)
      expect(requested!.get('device_sn')).toBe('INV20250001')
      expect(requested!.get('status')).toBe('success')
    })
  })

  describe('Upgrade Task Management', () => {
    it('listTasks should return task list', async () => {
      const res = await otaApi.listTasks({ page: 1 })
      const data = res.data?.data ?? res.data
      expect(data.items).toHaveLength(mockUpgradeTasks.length)
    })

    it('createTask should create a single-firmware upgrade task', async () => {
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

  describe('Legacy package write APIs are removed', () => {
    it('does not expose package create/push/install/rollback methods', () => {
      const api = otaApi as any
      expect(api.createPackage).toBeUndefined()
      expect(api.updatePackage).toBeUndefined()
      expect(api.deletePackage).toBeUndefined()
      expect(api.pushPackageUpgrade).toBeUndefined()
      expect(api.getPackageUpgradeDetails).toBeUndefined()
      expect(api.rollbackPackage).toBeUndefined()
      expect(api.publishPackage).toBeUndefined()
      expect(api.rollbackUpgrade).toBeUndefined()
      expect(api.listPackages).toBeUndefined()
      expect(api.getAvailablePackages).toBeUndefined()
    })
  })

  describe('Idempotency key helper', () => {
    it('createOtaIdempotencyKey produces unique prefixed keys', () => {
      const a = createOtaIdempotencyKey('trigger')
      const b = createOtaIdempotencyKey('trigger')
      expect(a.startsWith('trigger-')).toBe(true)
      expect(b.startsWith('trigger-')).toBe(true)
      expect(a).not.toBe(b)
    })
  })
})
