import api from './api'

export const alertApi = {
  getAlerts: (params?: any) => api.get('/alerts', { params }),
  acknowledge: (id: number) => api.post(`/alerts/${id}/acknowledge`),
  ignore: (id: number) => api.post(`/alerts/${id}/ignore`),
  list: (params?: any) => api.get('/alerts', { params }),
  getStats: () => api.get('/alerts/stats'),
  handle: (id: string) => api.post(`/alerts/${id}/acknowledge`),
}
