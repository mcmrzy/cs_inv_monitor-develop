import api from './api'

export const alertApi = {
  list: (params?: any) => api.get('/alarms', { params, expectedDataShape: 'page' }),
  getStats: () => api.get('/alarms/stats', { expectedDataShape: 'object' }),
  handle: (id: number) => api.post(`/alarms/${id}/acknowledge`),
  ignore: (id: number) => api.post(`/alarms/${id}/ignore`),
  delete: (id: number) => api.delete(`/alarms/${id}`),
  clearAll: () => api.delete('/alarms/clear'),
}

export const notificationApi = {
  list: (params?: any) => api.get('/notifications', { params, expectedDataShape: 'page' }),
  getStats: () => api.get('/notifications/stats', { expectedDataShape: 'object' }),
  delete: (id: number) => api.delete(`/notifications/${id}`),
  clearAll: () => api.delete('/notifications/clear'),
}
