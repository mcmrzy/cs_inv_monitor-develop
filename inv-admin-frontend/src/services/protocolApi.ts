import type { AxiosError } from 'axios'
import api from './api'
import type { ApiResponse, PaginatedResponse } from '@/types'

export interface ProtocolQueryParams {
  page?: number
  page_size?: number
  start_time?: string
  end_time?: string
}

export interface ParallelMachine {
  id: number
  sn: string
  role: 'master' | 'slave' | string
  phase: 'L1' | 'L2' | 'L3' | null
  power: number
  state: number
}

export interface ParallelState {
  has_parallel: boolean
  enabled: boolean
  station_id?: number
  master_sn?: string
  mode?: 'parallel' | 'three_phase' | 'standalone' | string
  count?: number
  total_rated_power?: number
  total_active_power?: number
  sync_state?: string
  machines?: ParallelMachine[]
  reported_at?: string
}

export interface ThreePhaseSample {
  event_time: string
  t: number
  received_at: string
  data_hash: string
  raw_envelope: unknown
  voltage_l1: number
  voltage_l2: number
  voltage_l3: number
  current_l1: number
  current_l2: number
  current_l3: number
  active_power_l1: number
  active_power_l2: number
  active_power_l3: number
  total_active_power: number
  line_voltage_l1l2: number
  line_voltage_l2l3: number
  line_voltage_l3l1: number
  frequency: number
  voltage_unbalance: number
  current_unbalance: number
}

export interface AlarmEvent {
  id: number
  device_sn: string
  station_id?: number
  source: number
  code: string
  level: number
  state: string
  active_at?: string
  recovered_at?: string
  event_time: string
  t: number
  received_at: string
  created_at: string
  data_hash: string
  raw_data: unknown
  raw_envelope: unknown
}

export interface AlarmSnapshot {
  id: number
  device_sn: string
  alarm_event_id: number
  snapshot_type: 'before' | 'after' | string
  ac_voltage: number | null
  ac_current: number | null
  ac_active_power: number | null
  ac_frequency: number | null
  battery_soc: number | null
  battery_voltage: number | null
  battery_current: number | null
  battery_temperature: number | null
  internal_temperature: number | null
  dc_bus_voltage: number | null
  work_state: number | null
  fault_code: number | null
  raw_snapshot: Record<string, unknown> | null
  captured_at: string
}

export interface AlarmEventDetail extends Omit<AlarmEvent, 'raw_data'> {
  topic: string
  snapshots: AlarmSnapshot[]
}

function unwrap<T>(response: { data: ApiResponse<T> }): T {
  if (response.data.code !== 0 || response.data.data === undefined) {
    throw new Error(response.data.message || '接口未返回有效数据')
  }
  return response.data.data
}

export function getApiErrorMessage(error: unknown): string {
  const axiosError = error as AxiosError<ApiResponse<unknown>>
  const status = axiosError.response?.status
  const businessCode = axiosError.response?.data?.code
  const message = axiosError.response?.data?.message || (error instanceof Error ? error.message : '')
  if (status === 403) return `无权访问该设备${message ? `：${message}` : ''}`
  if (status === 404) return `设备或接口不存在${message ? `：${message}` : ''}`
  if (status && status >= 500) return `服务端处理失败（HTTP ${status}）${message ? `：${message}` : ''}`
  if (businessCode !== undefined && businessCode !== 0) return `API ${businessCode}${message ? ` · ${message}` : ''}`
  if (status) return `HTTP ${status}${message ? ` · ${message}` : ''}`
  return message || '请求失败，请检查网络和服务状态'
}

export const protocolApi = {
  getParallelState: async (sn: string): Promise<ParallelState> =>
    unwrap(await api.get<ApiResponse<ParallelState>>(
      `/devices/${encodeURIComponent(sn)}/parallel-state`,
      { expectedDataShape: 'object' },
    )),

  getThreePhase: async (
    sn: string,
    params: ProtocolQueryParams = {},
  ): Promise<PaginatedResponse<ThreePhaseSample>> =>
    unwrap(await api.get<ApiResponse<PaginatedResponse<ThreePhaseSample>>>(
      `/devices/${encodeURIComponent(sn)}/three-phase`,
      { params, expectedDataShape: 'page' },
    )),

  getAlarmEvents: async (
    sn: string,
    params: ProtocolQueryParams = {},
  ): Promise<PaginatedResponse<AlarmEvent>> =>
    unwrap(await api.get<ApiResponse<PaginatedResponse<AlarmEvent>>>(
      `/devices/${encodeURIComponent(sn)}/alarm-events`,
      { params, expectedDataShape: 'page' },
    )),

  getAlarmEventDetail: async (id: number): Promise<AlarmEventDetail> =>
    unwrap(await api.get<ApiResponse<AlarmEventDetail>>(`/alarm-events/${id}`, { expectedDataShape: 'object' })),
}
