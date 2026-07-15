import { describe, expect, it } from 'vitest'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { getApiErrorMessage, protocolApi } from './protocolApi'

describe('protocolApi', () => {
  it('loads the reported parallel state without using legacy groups', async () => {
    server.use(http.get('/api/v1/devices/:sn/parallel-state', ({ params }) =>
      HttpResponse.json({
        code: 0,
        message: 'success',
        data: {
          has_parallel: true,
          enabled: true,
          master_sn: params.sn,
          mode: 'three_phase',
          count: 3,
          sync_state: 'synced',
          machines: [{ id: 1, sn: params.sn, role: 'master', phase: 'L1', power: 1200, state: 1 }],
        },
      }),
    ))

    const state = await protocolApi.getParallelState('INV/01')
    expect(state.mode).toBe('three_phase')
    expect(state.machines?.[0].role).toBe('master')
  })

  it('loads paged three-phase 3-minute samples', async () => {
    server.use(http.get('/api/v1/devices/:sn/three-phase', ({ request }) => {
      const url = new URL(request.url)
      expect(url.searchParams.get('page_size')).toBe('500')
      return HttpResponse.json({
        code: 0,
        message: 'success',
        data: { items: [{ event_time: '2026-07-14T10:00:00Z', t: 1784023200, data_hash: 'abc', voltage_l1: 220 }], total: 1, page: 1, page_size: 500 },
      })
    }))

    const history = await protocolApi.getThreePhase('INV001', { page_size: 500 })
    expect(history.total).toBe(1)
    expect(history.items[0].voltage_l1).toBe(220)
  })

  it('loads alarm lifecycle and trace fields', async () => {
    server.use(http.get('/api/v1/devices/:sn/alarm-events', () => HttpResponse.json({
      code: 0,
      message: 'success',
      data: {
        items: [{ id: 8, device_sn: 'INV001', source: 1, code: '9', level: 2, state: 'active', event_time: '2026-07-14T10:00:00Z', received_at: '2026-07-14T10:00:01Z', data_hash: 'hash' }],
        total: 1, page: 1, page_size: 50,
      },
    })))

    const events = await protocolApi.getAlarmEvents('INV001')
    expect(events.items[0]).toMatchObject({ state: 'active', data_hash: 'hash' })
  })

  it('loads one alarm event with before/after snapshots', async () => {
    server.use(http.get('/api/v1/alarm-events/:id', ({ params }) => HttpResponse.json({
      code: 0,
      message: 'success',
      data: {
        id: Number(params.id),
        device_sn: 'INV001',
        source: 1,
        code: '8',
        level: 2,
        state: 'active',
        topic: 'alarm',
        event_time: '2026-07-14T10:00:00Z',
        t: 1784023200,
        received_at: '2026-07-14T10:00:01Z',
        created_at: '2026-07-14T10:00:01Z',
        data_hash: 'hash',
        raw_envelope: { t: 1784023200, v: 1, data: {} },
        snapshots: [
          { id: 91, device_sn: 'INV001', alarm_event_id: Number(params.id), snapshot_type: 'before', ac_voltage: 220.5, raw_snapshot: {}, captured_at: '2026-07-14T10:00:00Z' },
          { id: 92, device_sn: 'INV001', alarm_event_id: Number(params.id), snapshot_type: 'after', raw_snapshot: { missing: true, reason: 'device_latest_state_not_found' }, captured_at: '2026-07-14T10:00:02Z' },
        ],
      },
    })))

    const detail = await protocolApi.getAlarmEventDetail(41)
    expect(detail.id).toBe(41)
    expect(detail.snapshots[0]).toMatchObject({ snapshot_type: 'before', ac_voltage: 220.5 })
    expect(detail.snapshots[1].raw_snapshot).toMatchObject({ missing: true, reason: 'device_latest_state_not_found' })
  })

  it.each([
    [403, '无权访问'],
    [404, '不存在'],
    [500, 'HTTP 500'],
  ])('surfaces alarm detail HTTP %i errors', async (status, expected) => {
    server.use(http.get('/api/v1/alarm-events/:id', () =>
      HttpResponse.json({ code: status, message: `detail-${status}` }, { status }),
    ))

    try {
      await protocolApi.getAlarmEventDetail(41)
      expect.fail('request should fail')
    } catch (error) {
      expect(getApiErrorMessage(error)).toContain(expected)
    }
  })

  it('makes access-denied errors visible to callers', async () => {
    server.use(http.get('/api/v1/devices/:sn/parallel-state', () =>
      HttpResponse.json({ code: 403, message: 'device access denied' }, { status: 403 }),
    ))

    try {
      await protocolApi.getParallelState('OTHER')
      expect.fail('request should fail')
    } catch (error) {
      expect(getApiErrorMessage(error)).toContain('无权访问')
    }
  })
})
