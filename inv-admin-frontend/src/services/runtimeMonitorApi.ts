import api from './api'

export interface RuntimeErrorGroup {
  fingerprint: string
  service: string
  method: string
  route: string
  status: number
  http_status: number
  duration_ms: number
  kind: string
  sql_state?: string
  summary: string
  request_id: string
  count: number
  first_seen: string
  last_seen: string
}

export interface SchemaColumnCheck {
  table: string
  column: string
  expected_type: string
  actual_type?: string
  status: 'ok' | 'missing' | 'type_mismatch'
}

export interface RuntimeMonitorSnapshot {
  checked_at: string
  errors_status: 'ok' | 'unknown'
  errors_5m: number | null
  events_retained: number | null
  limited: boolean
  retention_hours: number
  capacity: number
  groups: RuntimeErrorGroup[]
  schema: { status: 'ok' | 'degraded' | 'unknown'; checks: SchemaColumnCheck[] }
}

export async function getRuntimeMonitor(): Promise<RuntimeMonitorSnapshot> {
  const result = await api.get<{ data: RuntimeMonitorSnapshot }>('/admin/runtime-monitor', { expectedDataShape: 'object' })
  return result.data.data
}
