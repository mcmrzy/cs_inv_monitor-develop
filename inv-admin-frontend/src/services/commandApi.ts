import api from './api'

export const commandApi = {
  getTemplates: (sn: string) => api.get(`/devices/${sn}/control-capabilities`, { expectedDataShape: 'array' }),
  execute: (sn: string, data: { command: string; params: any }) =>
    api.post(`/devices/${sn}/control`, data),
  getHistory: (sn: string, params?: { page?: number; page_size?: number }) =>
    api.get(`/devices/${sn}/commands/history`, { params, expectedDataShape: 'page' }),
  batchControl: (data: { device_sns: string[]; command: string; params: any }) =>
    api.post('/devices/batch/control', data),
}
