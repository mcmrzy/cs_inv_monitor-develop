import api from './api'

export const deviceApi = {
  getDevices: (params: any) => api.get('/devices', { params }),
  getDeviceBySn: (sn: string) => api.get(`/devices/${sn}`),
  createDevice: (data: any) => api.post('/devices', data),
  updateDevice: (sn: string, data: any) => api.put(`/devices/${sn}`, data),
  deleteDevice: (sn: string) => api.delete(`/devices/${sn}`),
  unbindDevice: (sn: string) => api.post(`/devices/${sn}/unbind`),
  addToStation: (sn: string, stationId: number) => api.post('/devices/add-to-station', { sn, station_id: stationId }),
  removeFromStation: (sn: string) => api.post(`/devices/${sn}/remove-from-station`),
  requestUnbind: (sn: string, reason: string) => api.post(`/devices/${sn}/request-unbind`, { reason }),
  getUnbindRequests: (params?: any) => api.get('/devices/unbind-requests', { params }),
  approveUnbind: (id: number, comment?: string) => api.post(`/devices/unbind-requests/${id}/approve`, { comment }),
  rejectUnbind: (id: number, comment?: string) => api.post(`/devices/unbind-requests/${id}/reject`, { comment }),
  getLifecycleHistory: (sn: string, params?: any) => api.get(`/devices/${sn}/lifecycle`, { params }),
  importExcel: (file: File, installerId?: number) => {
    const formData = new FormData()
    formData.append('file', file)
    if (installerId) formData.append('installerId', String(installerId))
    return api.post('/devices/import-excel', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    })
  },
  getTelemetry: (sn: string, params?: any) => api.get(`/devices/${sn}/telemetry`, { params }),
  getRealtime: (sn: string) => api.get(`/devices/${sn}/realtime`),
  sendCommand: (sn: string, data: any) => api.post(`/devices/${sn}/control`, data),
  getAll: () => api.get('/devices', { params: { page_size: 200 } }),
  exportTelemetry: (sn: string, format: 'csv' | 'excel', params?: any) =>
    api.get(`/devices/${sn}/telemetry/export${format === 'excel' ? '-excel' : ''}`, {
      params,
      responseType: 'blob',
    }),
  assignInstaller: (sn: string, installerId: number) => api.post(`/devices/${sn}/assign-installer`, { installerId }),
  removeInstaller: (sn: string) => api.delete(`/devices/${sn}/installer`),
  batchAssignInstaller: (deviceSns: string[], installerId: number) => api.post('/devices/batch-assign-installer', { deviceSns, installerId }),
  getControlCapabilities: (sn: string) => api.get(`/devices/${sn}/control-capabilities`),
  getControlState: (sn: string) => api.get(`/devices/${sn}/control-state`),
  getCommands: (sn: string, params?: any) => api.get(`/devices/${sn}/commands`, { params }),

  // ── 能源计划 ──
  getEnergySchedule: (sn: string) => api.get(`/devices/${sn}/energy-schedule`),
  updateEnergySchedule: (sn: string, data: any) => api.put(`/devices/${sn}/energy-schedule`, data),

  // ── 电池配置 ──
  getBatteryProfiles: () => api.get('/battery-profiles'),
  getBatteryConfig: (sn: string) => api.get(`/devices/${sn}/battery-config`),
  updateBatteryConfig: (sn: string, data: any) => api.put(`/devices/${sn}/battery-config`, data),

  // ── 控制覆盖 ──
  getControlOverrides: (sn: string) => api.get(`/devices/${sn}/control-overrides`),
  createControlOverride: (sn: string, data: any) => api.post(`/devices/${sn}/control-overrides`, data),
  deleteControlOverride: (sn: string, id: string) => api.delete(`/devices/${sn}/control-overrides/${id}`),
}
