import { describe, it, expect } from 'vitest'
import { fireEvent, screen } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderAsAdmin } from '@/test/test-utils'
import RuntimeErrorsTab from './RuntimeErrorsTab'

const snapshot = {
  checked_at: '2026-10-23T13:00:00Z', errors_status: 'ok', errors_5m: 6,
  events_retained: 6, limited: false, retention_hours: 24, capacity: 1000,
  groups: [{
    fingerprint: 'group1', service: 'business-api', method: 'GET', route: '/api/v1/stations/:id',
    status: 500, http_status: 500, kind: 'missing_column', sql_state: '42703',
    summary: 'Database column missing: l.ac_input_power', count: 6, duration_ms: 12,
    first_seen: '2026-10-23T12:58:00Z', last_seen: '2026-10-23T13:00:00Z',
    request_id: 'trace-test-123', occurred_at: '2026-10-23T13:00:00Z',
  }],
  schema: { status: 'degraded', checks: [{ table: 'device_latest_state', column: 'ac_input_power', expected_type: 'real', status: 'missing' }] },
}

describe('RuntimeErrorsTab', () => {
  it('shows the database fault, grouped count, request ID and actual missing column', async () => {
    server.use(http.get('/api/v1/admin/runtime-monitor', () => HttpResponse.json({ code: 0, data: snapshot })))
    renderAsAdmin(<RuntimeErrorsTab />)
    expect(await screen.findByText('Database column missing: l.ac_input_power')).toBeInTheDocument()
    expect(screen.getByText('/api/v1/stations/:id')).toBeInTheDocument()
    expect(screen.getByText('trace-test-123')).toBeInTheDocument()
    expect(screen.getByText('42703')).toBeInTheDocument()
    expect(screen.getByText('ac_input_power')).toBeInTheDocument()
    expect(screen.getByText('缺失')).toBeInTheDocument()
    fireEvent.change(screen.getByPlaceholderText('筛选接口、错误或追踪 ID'), { target: { value: 'other-route' } })
    expect(screen.queryByText('trace-test-123')).not.toBeInTheDocument()
  })

  it('shows unknown instead of a zero-error success when collection is unavailable', async () => {
    server.use(http.get('/api/v1/admin/runtime-monitor', () => HttpResponse.json({ code: 0, data: {
      ...snapshot, errors_status: 'unknown', errors_5m: null, events_retained: null, groups: [],
      schema: { status: 'unknown', checks: [] },
    } })))
    renderAsAdmin(<RuntimeErrorsTab />)
    expect(await screen.findByText('异常记录暂不可用，无法判断是否存在错误')).toBeInTheDocument()
    expect(screen.getByText('数据库结构检查不可用')).toBeInTheDocument()
    expect(screen.queryByText('暂无运行异常')).not.toBeInTheDocument()
  })

  it('keeps a failed refresh visible and offers retry', async () => {
    server.use(http.get('/api/v1/admin/runtime-monitor', () => HttpResponse.json({ code: 500, message: 'failed' }, { status: 500 })))
    renderAsAdmin(<RuntimeErrorsTab />)
    expect(await screen.findByText('无法读取运行监控，当前状态未知')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /刷 新|刷新/ })).toBeInTheDocument()
  })
})
