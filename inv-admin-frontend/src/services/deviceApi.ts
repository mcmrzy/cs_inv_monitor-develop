import api from './api'

export const deviceApi = {
  getDevices: (params: any) => api.get('/devices', { params, expectedDataShape: 'page' }),
  getDeviceBySn: (sn: string) => api.get(`/devices/by-sn/${sn}`, { expectedDataShape: 'object' }),
  createDevice: (data: any) => api.post('/devices', data),
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
}
