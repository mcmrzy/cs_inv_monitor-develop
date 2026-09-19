import api from './api'

/* ═══════════ 设备调试（Debug Session）类型 ═══════════ */

export type DebugSessionStatus =
  | 'starting'
  | 'active'
  | 'stopping'
  | 'stopped'
  | 'expired'
  | 'interrupted'
  | 'failed'

export interface DebugSession {
  id: number
  device_sn: string
  status: DebugSessionStatus
  interval_seconds: number
  duration_seconds: number
  started_at: string
  expires_at: string
  stopped_at: string | null
  requested_by: number
  source: 'web' | 'app'
  start_task_id: string
  stop_task_id: string
  last_sample_at: string | null
  failure_reason: string
  created_at: string
  updated_at: string
}

export interface DebugSessionEnvelope {
  session: DebugSession | null
  device_online: boolean
  supported: boolean
  interval_seconds: number
}

export interface StartDebugSessionBody {
  /** 采集时长（秒），默认 3600，范围 300..14400 */
  duration_seconds?: number
  /** 幂等键（uuid） */
  request_id?: string
  source?: 'web'
}

export interface DebugSampleMetrics {
  pv1_voltage: number | null
  buck1_current: number | null
  pv2_voltage: number | null
  buck2_current: number | null
  battery_voltage: number | null
  battery_current: number | null
  dc_bus_voltage: number | null
  inv_current: number | null
  ac_voltage: number | null
  ac_current: number | null
}

export interface DebugSample {
  /** ISO UTC 时间 */
  time: string
  received_at: string | null
  quality_flags: number
  protocol_version: number
  metrics: DebugSampleMetrics
}

export interface DebugSamplesParams {
  session_id?: number
  window_minutes?: 15 | 30 | 60
  /** 不透明游标，空串 = 全量 */
  after?: string
  limit?: number
}

export interface DebugSamplesPage {
  /** 按 time 升序 */
  items: DebugSample[]
  /** 游标，空串 = 无更多 */
  next_cursor: string
  session: DebugSession | null
}

export const deviceApi = {
  getDevices: (params: any) => api.get('/devices', { params, expectedDataShape: 'page' }),
  getDeviceBySn: (sn: string) => api.get(`/devices/by-sn/${sn}`, { expectedDataShape: 'object' }),
  createDevice: (data: any) => api.post('/devices', data),
  bindDevice: (sn: string, pin: string, stationId?: number) =>
    api.post('/devices/bind', { sn, pin, station_id: stationId }),
  updateDevice: (sn: string, data: any) => api.put(`/devices/by-sn/${sn}`, data),
  deleteDevice: (sn: string) => api.delete(`/devices/by-sn/${sn}`),
  unbindDevice: (sn: string) => api.post(`/devices/by-sn/${sn}/unbind`),
  addToStation: (sn: string, stationId: number) => api.post('/devices/add-to-station', { sn, station_id: stationId }),
  removeFromStation: (sn: string) => api.post(`/devices/by-sn/${sn}/remove-from-station`),
  requestUnbind: (sn: string, reason: string) => api.post(`/devices/by-sn/${sn}/request-unbind`, { reason }),
  getUnbindRequests: (params?: any) => api.get('/devices/unbind-requests', { params, expectedDataShape: 'page' }),
  approveUnbind: (id: number, comment?: string) => api.post(`/devices/unbind-requests/${id}/approve`, { comment }),
  rejectUnbind: (id: number, comment?: string) => api.post(`/devices/unbind-requests/${id}/reject`, { comment }),
  getLifecycleHistory: (sn: string, params?: any) => api.get(`/devices/by-sn/${sn}/lifecycle`, { params, expectedDataShape: 'page' }),
  importExcel: (file: File, installerId?: number) => {
    const formData = new FormData()
    formData.append('file', file)
    if (installerId) formData.append('installerId', String(installerId))
    return api.post('/devices/import-excel', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    })
  },
  getTelemetry: (sn: string, params?: any) => api.get(`/devices/by-sn/${sn}/telemetry`, { params, expectedDataShape: 'page' }),
  getRealtime: (sn: string) => api.get(`/devices/by-sn/${sn}/realtime`, { expectedDataShape: 'object' }),
  sendCommand: (sn: string, data: any) => api.post(`/devices/by-sn/${sn}/control`, data),
  getAll: () => api.get('/devices', { params: { page_size: 200 }, expectedDataShape: 'page' }),
  exportTelemetry: (sn: string, format: 'csv' | 'excel', params?: any) =>
    api.get(`/devices/by-sn/${sn}/telemetry/export${format === 'excel' ? '-excel' : ''}`, {
      params,
      responseType: 'blob',
    }),
  assignInstaller: (sn: string, installerId: number) => api.post(`/devices/by-sn/${sn}/assign-installer`, { installerId }),
  removeInstaller: (sn: string) => api.delete(`/devices/by-sn/${sn}/installer`),
  batchAssignInstaller: (deviceSns: string[], installerId: number) => api.post('/devices/batch-assign-installer', { deviceSns, installerId }),
  getControlCapabilities: (sn: string) => api.get(`/devices/by-sn/${sn}/control-capabilities`, { expectedDataShape: 'array' }),
  getControlState: (sn: string) => api.get(`/devices/by-sn/${sn}/control-state`, { expectedDataShape: 'object' }),
  getCommands: (sn: string, params?: any) => api.get(`/devices/by-sn/${sn}/commands`, { params, expectedDataShape: 'page' }),

  // ── V2.1 健康诊断 / 配置 schema（CS-L10-6K2）──
  getDiagnostics: (sn: string, params?: any) => api.get(`/devices/by-sn/${sn}/diagnostics`, { params, expectedDataShape: 'array' }),
  getHealthHistory: (sn: string, params?: any) => api.get(`/devices/by-sn/${sn}/health-history`, { params, expectedDataShape: 'array' }),
  getConfigSchema: (sn: string) => api.get(`/devices/by-sn/${sn}/config-schema`, { expectedDataShape: 'array' }),

  // ── 能源计划 ──
  getEnergySchedule: (sn: string) => api.get(`/devices/by-sn/${sn}/energy-schedule`, { expectedDataShape: 'object' }),
  updateEnergySchedule: (sn: string, data: any) => api.put(`/devices/by-sn/${sn}/energy-schedule`, data),

  // ── 电池配置 ──
  getBatteryProfiles: () => api.get('/battery-profiles', { expectedDataShape: 'array' }),
  getBatteryConfig: (sn: string) => api.get(`/devices/by-sn/${sn}/battery-config`, { expectedDataShape: 'object' }),
  updateBatteryConfig: (sn: string, data: any) => api.put(`/devices/by-sn/${sn}/battery-config`, data),

  // ── 控制覆盖 ──
  getControlOverrides: (sn: string) => api.get(`/devices/by-sn/${sn}/control-overrides`, { expectedDataShape: 'array' }),
  createControlOverride: (sn: string, data: any) => api.post(`/devices/by-sn/${sn}/control-overrides`, data),
  deleteControlOverride: (sn: string, id: string) => api.delete(`/devices/by-sn/${sn}/control-overrides/${id}`),

  // ── 设备调试（Debug Session）──
  /** 查询当前调试会话：{ session, device_online, supported, interval_seconds } */
  getDebugSession: (sn: string) => api.get(`/devices/by-sn/${sn}/debug-session`, { expectedDataShape: 'object' }),
  /** 开启调试会话：冲突/离线/超限时后端返回业务 code 409（拦截器抛错） */
  startDebugSession: (sn: string, body?: StartDebugSessionBody) =>
    api.post(`/devices/by-sn/${sn}/debug-session`, body),
  /** 停止调试会话（幂等） */
  stopDebugSession: (sn: string, id: number | string) => api.delete(`/devices/by-sn/${sn}/debug-session/${id}`),
  /** 拉取调试采样：{ items(按 time 升序), next_cursor(空串=无更多), session } */
  getDebugSamples: (sn: string, params?: DebugSamplesParams) =>
    api.get(`/devices/by-sn/${sn}/debug-samples`, { params, expectedDataShape: 'object' }),
}
